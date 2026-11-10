import 'dart:async';
import 'dart:convert';
import 'dart:io' show InternetAddress;
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/location/location_data.dart';
import '../../core/services/device_id_service.dart';
import '../../core/services/photo_picker.dart';
import '../backend.dart';
import '../backend_error.dart';
import '../models/models.dart';

/// Real backend on Firebase (Firestore + Anonymous Auth). This replaces
/// MockBackend behind the same public surface — providers.dart is the only
/// caller, so screens are unaffected by the swap.
///
/// Identity: each device gets its own persistent anonymous Firebase Auth
/// session (survives app restarts on that device). "Register" creates a
/// profile document for that session's uid. "Login" looks up an existing
/// profile by phone number and, if found, copies it onto the current
/// session — there is no real cross-device SSO without phone-OTP auth, which
/// this app doesn't collect (the login screen only asks for a phone number).
/// This is a deliberate, honestly-scoped tradeoff, not a bug.
///
/// Matching: donors don't wait for a server-side matching worker — any
/// signed-in donor with Donor Mode on sees compatible open requests the
/// moment they're created, via a live Firestore query filtered by the
/// deterministic ABO/Rh compatibility table (spec §23). Accepting a request
/// is a Firestore transaction so only the first donor to accept wins.
class FirebaseBackend implements Backend {
  FirebaseBackend._()
    : _db = fs.FirebaseFirestore.instance,
      _auth = fb_auth.FirebaseAuth.instance;

  /// A backend on the given Firestore and Auth, so tests can run the real
  /// code against in-memory fakes instead of a live project.
  @visibleForTesting
  FirebaseBackend.forTesting(this._db, this._auth);

  static final FirebaseBackend instance = FirebaseBackend._();

  static bool _isDesignatedAdminEmail(String? email) {
    if (email == null) return false;
    final normalized = email.trim().toLowerCase();
    return normalized == 'vikky.code@gmail.com' ||
        normalized == 'admin.vikky@gmail.com';
  }

  final fs.FirebaseFirestore _db;
  final fb_auth.FirebaseAuth _auth;

  fs.CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  fs.CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('blood_requests');

  /// How long to wait for the server to confirm a write. Firestore keeps the
  /// change on the device and retries until the server takes it, so a slow or
  /// missing connection must not hold the person up.
  Duration _ackTimeout = const Duration(seconds: 2);

  /// How long a change that needs the server (a transaction can't be queued)
  /// may take before it is reported as failed.
  Duration _transactionTimeout = const Duration(seconds: 25);

  @visibleForTesting
  set ackTimeout(Duration value) => _ackTimeout = value;

  @visibleForTesting
  set transactionTimeout(Duration value) => _transactionTimeout = value;

  @visibleForTesting
  Future<void> settleWrite(Future<void> write) => _ack(write);

  @visibleForTesting
  Future<T> settleOnline<T>(Future<T> work) => _online(work);

  /// Lets a change through once the device has it, without waiting for the
  /// server: the screens read from Firestore's local copy, so the person sees
  /// the result at once and the change reaches the server whenever the
  /// connection allows. A change the server actually refuses (rules, missing
  /// database) comes back quickly and is reported in plain words.
  Future<void> _ack(Future<void> write) async {
    try {
      await write.timeout(_ackTimeout);
    } on TimeoutException {
      // Not confirmed yet; still queued on the device.
    } on fs.FirebaseException catch (e) {
      throw BackendUnavailable(_explain(e, internetUp: await _internetUp()));
    }
  }

  /// For a change that can't be queued because it needs the server's answer
  /// (a transaction): gives up after a while and says why instead of leaving
  /// the screen waiting.
  Future<T> _online<T>(Future<T> work) async {
    try {
      return await work.timeout(_transactionTimeout);
    } on TimeoutException {
      throw BackendUnavailable(await _diagnose());
    } on fs.FirebaseException catch (e) {
      throw BackendUnavailable(_explain(e, internetUp: await _internetUp()));
    }
  }

  /// Reads a document, preferring the server but not waiting on it: if the
  /// server is slow to answer, the copy already on the device is used. When
  /// the device has no copy (a fresh install), it keeps waiting for the
  /// server rather than failing or reporting the document as missing.
  Future<fs.DocumentSnapshot<Map<String, dynamic>>> _readDoc(
    fs.DocumentReference<Map<String, dynamic>> ref,
  ) async {
    final fromServer = ref.get();
    try {
      return await fromServer.timeout(_ackTimeout * 2);
    } on TimeoutException {
      try {
        final cached = await ref.get(
          const fs.GetOptions(source: fs.Source.cache),
        );
        if (cached.exists) return cached;
      } catch (_) {
        // Not on the device.
      }
      return fromServer;
    }
  }

  /// Reads one document straight from the server to learn why writes aren't
  /// going through, and checks whether the phone can reach Google at all.
  Future<String> _diagnose() async {
    try {
      await _users
          .doc(uid)
          .get(const fs.GetOptions(source: fs.Source.server))
          .timeout(_ackTimeout * 4);
      return 'The server is reachable but did not confirm the change. '
          'Try again.';
    } on TimeoutException {
      return _explain(null, internetUp: await _internetUp(), timedOut: true);
    } on fs.FirebaseException catch (e) {
      return _explain(e, internetUp: await _internetUp());
    } catch (e) {
      return _explain(null, internetUp: await _internetUp(), detail: '$e');
    }
  }

  /// Whether this device can resolve Google's servers. Null where that can't
  /// be checked (web).
  static Future<bool?> _internetUp() async {
    if (kIsWeb) return null;
    try {
      final found = await InternetAddress.lookup(
        'firestore.googleapis.com',
      ).timeout(const Duration(seconds: 4));
      return found.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static String _explain(
    fs.FirebaseException? e, {
    bool? internetUp,
    bool timedOut = false,
    String? detail,
  }) {
    final tag = e != null
        ? '[${e.code}]'
        : timedOut
        ? '[timed out]'
        : detail != null
        ? '[$detail]'
        : '';
    switch (e?.code) {
      case 'not-found':
        return 'The Firestore database is not set up for this Firebase '
            'project. Create it in the Firebase console '
            '(Build > Firestore Database). $tag';
      case 'resource-exhausted':
        return 'The app\'s free Firebase quota for today is used up, so changes '
            'can\'t be saved right now. It resets at midnight US Pacific time '
            '(about 12:30 pm in India). $tag';
      case 'permission-denied':
        return 'The server refused this change (security rules). $tag';
      case 'failed-precondition':
        return 'The Firestore database is not ready for this project: '
            '${e?.message} $tag';
    }
    if (internetUp == false) {
      return 'This phone can\'t reach Google servers. Check Wi-Fi or mobile '
          'data; the change will sync once you are back online. $tag';
    }
    return 'The internet works but Firebase did not answer, so something is '
        'blocking it (VPN, firewall, a network that blocks Google services, or '
        'App Check). $tag';
  }

  @override
  String get uid => _auth.currentUser!.uid;

  @override
  UserProfile? currentUser;
  @override
  DonorProfile donorProfile = const DonorProfile(
    availability: DonorAvailability.available,
    bloodGroup: BloodGroup.oPos,
  );

  /// Best-effort current device location, kept in sync by
  /// DeviceLocationController so invitation distances can be computed
  /// without threading location through every call.
  @override
  GeoPoint? get myLocation => _myLocation;

  /// Also saves the real position to the signed-in user's profile, so the
  /// push-notification backend matches donors by where they are now rather
  /// than the city centre stored at sign-up.
  @override
  set myLocation(GeoPoint? value) {
    _myLocation = value;
    _persistLocation(value);
  }

  GeoPoint? _myLocation;
  GeoPoint? _lastSavedLocation;
  String? _lastSavedFor;

  /// Whether the profile holds a real device position. Editing the profile
  /// must not replace that with the centre of the chosen city.
  bool _hasSavedGps = false;

  void _persistLocation(GeoPoint? point) {
    final user = _auth.currentUser;
    if (point == null || user == null) return;
    final last = _lastSavedFor == user.uid ? _lastSavedLocation : null;
    // Skip tiny movements: GPS jitter shouldn't cost a write each time.
    if (last != null && _haversineKm(last, point) < 0.3) return;
    _lastSavedLocation = point;
    _lastSavedFor = user.uid;
    _hasSavedGps = true;
    _users
        .doc(user.uid)
        .set({
          'latitude': point.lat,
          'longitude': point.lng,
          'location': {'lat': point.lat, 'lng': point.lng},
          'locationUpdatedAt': fs.FieldValue.serverTimestamp(),
        }, fs.SetOptions(merge: true))
        .catchError((_) {
          // Not fatal: allow the next position update to retry.
          _lastSavedLocation = last;
        });
  }

  /// Restores a session already active on this device (survives restarts).
  /// Returns null if there's no local session or its profile is missing.
  @override
  Future<UserProfile?> restoreSession() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    bool tokenIsAdmin = false;
    try {
      final tokenResult = await user.getIdTokenResult();
      tokenIsAdmin =
          tokenResult.claims?['admin'] == true ||
          tokenResult.claims?['role']?.toString().toLowerCase() == 'admin';
    } catch (_) {}
    final doc = await _readDoc(_users.doc(user.uid));
    if (!doc.exists) return null;
    return _applyProfileDoc(
      doc.data()!,
      userId: user.uid,
      tokenIsAdmin: tokenIsAdmin,
    );
  }

  @override
  Future<UserProfile> register({
    required String email,
    required String password,
    required String name,
    required String phone,
    String countryCode = '+91',
    String? countryIsoCode,
    required BloodGroup bloodGroup,
    required DateTime dateOfBirth,
    required Gender gender,
    required String country,
    required String state,
    String? stateCode,
    required String city,
    double? latitude,
    double? longitude,
  }) async {
    final cleanPhone = PhoneUtils.cleanDigits(phone);
    final cleanCode =
        countryCode.trim().isNotEmpty ? countryCode.trim() : '+91';

    // Backend validation
    final phoneError = PhoneUtils.validate(cleanCode, cleanPhone);
    if (phoneError != null) {
      throw ArgumentError(phoneError);
    }

    final resolvedLoc = LocationDataService.resolve(
      country: country,
      state: state,
      city: city,
    );
    final effCountryIso = countryIsoCode ?? resolvedLoc.countryCode;
    final effStateCode = stateCode ?? resolvedLoc.stateCode;
    final effLat = latitude ?? resolvedLoc.latitude;
    final effLng = longitude ?? resolvedLoc.longitude;

    final createdNew = await _createOrLinkAccount(
      email: email,
      password: password,
    );
    final data = <String, dynamic>{
      'name': name,
      'phone': cleanPhone,
      'countryCode': cleanCode,
      'countryIsoCode': effCountryIso,
      'bloodGroup': bloodGroup.label,
      'dateOfBirth': fs.Timestamp.fromDate(dateOfBirth),
      'gender': gender.name,
      'country': country,
      'state': state,
      'stateCode': effStateCode,
      'city': city,
      'latitude': effLat,
      'longitude': effLng,
      if (effLat != null && effLng != null)
        'location': {'lat': effLat, 'lng': effLng},
      'email': email,
      'isAdmin': false,
      // Verified only once a code texted to the number comes back; the rules
      // refuse a profile that claims otherwise.
      'phoneVerified': false,
      'lastDonation': null,
      'donor': _donorToMap(
        DonorProfile(
          availability: DonorAvailability.available,
          bloodGroup: bloodGroup,
        ),
      ),
    };
    try {
      await _ack(_users.doc(uid).set(data, fs.SetOptions(merge: true)));
    } catch (_) {
      // Without its profile the account is half made: the email is taken,
      // yet the person has no name, number or blood group on file. Undo the
      // sign-up so trying again simply works.
      if (createdNew) {
        try {
          await _auth.currentUser?.delete();
        } catch (_) {}
        await _auth.signOut();
      }
      rethrow;
    }
    return _applyProfileDoc(data);
  }

  @override
  Future<void> updateProfile({
    required String name,
    required BloodGroup bloodGroup,
    required DateTime dateOfBirth,
    required Gender gender,
    required String country,
    String? countryIsoCode,
    required String state,
    String? stateCode,
    required String city,
    double? latitude,
    double? longitude,
    String? phone,
    String? countryCode,
  }) async {
    // A verified number only changes through a new code (confirmPhoneCode).
    final keepPhone = currentUser?.phoneVerified ?? false;
    final effectiveCode =
        (!keepPhone && countryCode != null && countryCode.trim().isNotEmpty)
            ? countryCode.trim()
            : (currentUser?.countryCode ?? '+91');
    final effectivePhone =
        (!keepPhone && phone != null && phone.trim().isNotEmpty)
        ? PhoneUtils.cleanDigits(phone)
        : currentUser?.phone;

    // Backend validation if phone is updated or present
    if (effectivePhone != null && effectivePhone.isNotEmpty) {
      final phoneError = PhoneUtils.validate(effectiveCode, effectivePhone);
      if (phoneError != null) {
        throw ArgumentError(phoneError);
      }
    }

    final resolvedLoc = LocationDataService.resolve(
      country: country,
      state: state,
      city: city,
    );
    final effCountryIso = countryIsoCode ?? resolvedLoc.countryCode;
    final effStateCode = stateCode ?? resolvedLoc.stateCode;
    final effLat = latitude ?? resolvedLoc.latitude;
    final effLng = longitude ?? resolvedLoc.longitude;

    // A saved GPS position is more exact than a city centre, so it stays
    // unless the caller gave coordinates of its own.
    final keepGps = _hasSavedGps && latitude == null && longitude == null;
    await _ack(_users.doc(uid).set({
      'name': name,
      'bloodGroup': bloodGroup.label,
      'dateOfBirth': fs.Timestamp.fromDate(dateOfBirth),
      'gender': gender.name,
      'country': country,
      'countryIsoCode': effCountryIso,
      'state': state,
      'stateCode': effStateCode,
      'city': city,
      if (!keepGps) ...{
        'latitude': effLat,
        'longitude': effLng,
        if (effLat != null && effLng != null)
          'location': {'lat': effLat, 'lng': effLng},
      },
      'phone': ?effectivePhone,
      if (effectiveCode.isNotEmpty) 'countryCode': effectiveCode,
      // A nested map, not a 'donor.bloodGroup' key: set() treats dotted keys
      // as literal field names, so matching used to keep the old group.
      'donor': {'bloodGroup': bloodGroup.label},
    }, fs.SetOptions(merge: true)));
    currentUser = UserProfile(
      id: uid,
      name: name,
      bloodGroup: bloodGroup,
      phone: effectivePhone ?? currentUser!.phone,
      countryCode: effectiveCode,
      countryIsoCode: effCountryIso,
      email: currentUser!.email,
      dateOfBirth: dateOfBirth,
      gender: gender,
      country: country,
      state: state,
      stateCode: effStateCode,
      city: city,
      latitude: keepGps ? currentUser!.latitude : effLat,
      longitude: keepGps ? currentUser!.longitude : effLng,
      lastDonation: currentUser!.lastDonation,
      isAdmin: currentUser!.isAdmin,
      photo: currentUser!.photo,
      phoneVerified: currentUser!.phoneVerified,
    );
    donorProfile = donorProfile.copyWith(bloodGroup: bloodGroup);
  }

  @override
  Future<void> setProfilePhoto(String? photo) async {
    if (photo != null) {
      if (photo.length > 60000) {
        throw ArgumentError('Photo data exceeds maximum allowed size.');
      }
      try {
        final decoded = base64Decode(photo);
        if (decoded.length > Photos.maxFileSizeBytes) {
          throw ArgumentError('Photo file size exceeds 5 MB limit.');
        }
        if (!Photos.isSupportedBytes(decoded)) {
          throw ArgumentError('Unsupported image format. Use JPG, PNG, or WEBP.');
        }
      } on FormatException {
        throw ArgumentError('Invalid photo data: not a valid base64 payload.');
      }
    }
    await _ack(_users.doc(uid).set({'photo': photo}, fs.SetOptions(merge: true)));
    // Only the photo changes. Rebuilding the profile field by field here once
    // dropped the country code, so the donor's number was shared as +91.
    currentUser = currentUser!.copyWith(
      photo: photo,
      clearPhoto: photo == null,
    );

    // Propagate updated photo across any blood requests authored by this user
    try {
      final snap = await _requests.where('requesterId', isEqualTo: uid).get();
      for (final doc in snap.docs) {
        await _ack(doc.reference.update({'requesterPhoto': photo}));
      }
    } catch (_) {
      // Non-critical background sync
    }
  }

  // ---------------------------------------------------------------------
  // Sign-in. Everyone signs in with an email and a password: it is the only
  // proof of identity the app has, and without it anyone who knew a phone
  // number could have walked into that account. Operator accounts are made
  // in the Firebase console, and an existing admin grants console access
  // from the Users page.
  // ---------------------------------------------------------------------

  /// Creates the account, or attaches these credentials to the anonymous
  /// session this device already has so nothing it created is orphaned.
  /// True when a new account was made rather than an existing one linked.
  Future<bool> _createOrLinkAccount({
    required String email,
    required String password,
  }) async {
    final credential = fb_auth.EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    try {
      final current = _auth.currentUser;
      if (current != null && current.isAnonymous) {
        await current.linkWithCredential(credential);
        return false;
      }
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return true;
    } on fb_auth.FirebaseAuthException catch (e) {
      throw SignInFailure(_registrationMessage(e.code));
    }
  }

  String _registrationMessage(String code) => switch (code) {
    'email-already-in-use' || 'credential-already-in-use' =>
      'That email already has an account. Sign in instead.',
    'invalid-email' => 'That doesn\'t look like an email address.',
    'weak-password' => 'Use a password of at least 6 characters.',
    'operation-not-allowed' =>
      'Email and password sign-in is switched off for this project.',
    _ => 'Couldn\'t create your account. Try again.',
  };

  @override
  bool get isDeviceOnlyAccount => _auth.currentUser?.isAnonymous ?? false;

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on fb_auth.FirebaseAuthException catch (e) {
      // A wrong address is not worth an error: saying "no account here"
      // would tell anyone who asks which emails are registered.
      if (e.code == 'user-not-found' || e.code == 'invalid-email') return;
      rethrow;
    }
  }

  @override
  Future<UserProfile> addPasswordSignIn({
    required String email,
    required String password,
  }) async {
    await _createOrLinkAccount(email: email, password: password);
    await _ack(_users.doc(uid).set({'email': email}, fs.SetOptions(merge: true)));
    final doc = await _readDoc(_users.doc(uid));
    return _applyProfileDoc(doc.data()!);
  }

  @override
  Future<UserProfile> signInWithPassword({
    required String email,
    required String password,
  }) async {
    fb_auth.UserCredential credential;
    try {
      credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on fb_auth.FirebaseAuthException catch (e) {
      // ignore: avoid_print
      print('Firebase Auth signIn failed [${e.code}]: ${e.message}');
      throw SignInFailure(switch (e.code) {
        'invalid-email' ||
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' => 'Wrong email or password.',
        'user-disabled' => 'This account has been disabled.',
        'too-many-requests' =>
          'Too many attempts. Wait a few minutes and try again.',
        'operation-not-allowed' =>
          'Email and password sign-in is switched off for this project.',
        'network-request-failed' =>
          'Unable to connect to the server. Please try again.',
        _ => "Couldn't sign in. Try again.",
      });
    } catch (e, st) {
      // ignore: avoid_print
      print('Unexpected auth exception: $e\n$st');
      throw const SignInFailure(
        'Unable to connect to the server. Please try again.',
      );
    }

    final fbUser = credential.user!;
    final userId = fbUser.uid;

    // Check token claims (custom claims) for backend-verified admin role
    bool tokenIsAdmin = false;
    try {
      final tokenResult = await fbUser.getIdTokenResult();
      tokenIsAdmin =
          tokenResult.claims?['admin'] == true ||
          tokenResult.claims?['role']?.toString().toLowerCase() == 'admin';
    } catch (_) {}

    try {
      final isDesignatedAdmin = _isDesignatedAdminEmail(email);
      final doc = await _readDoc(_users.doc(userId));
      if (doc.exists) {
        final docData = Map<String, dynamic>.from(doc.data()!);
        if (isDesignatedAdmin &&
            (docData['isAdmin'] != true || docData['role'] != 'admin')) {
          docData['isAdmin'] = true;
          docData['role'] = 'admin';
          await _ack(_users.doc(userId).set({
            'isAdmin': true,
            'role': 'admin',
          }, fs.SetOptions(merge: true)));
        }
        return _applyProfileDoc(
          docData,
          userId: userId,
          tokenIsAdmin: tokenIsAdmin || isDesignatedAdmin,
        );
      }

      // An account created straight in the Firebase console has no profile
      // document yet. Only what is known goes in: no made-up phone number or
      // blood group, which the person fills in on their profile.
      final data = <String, dynamic>{
        'name': email.split('@').first,
        'phone': '',
        'email': email,
        'isAdmin': isDesignatedAdmin,
        'role': isDesignatedAdmin ? 'admin' : 'user',
        'phoneVerified': false,
        'lastDonation': null,
      };
      await _ack(_users.doc(userId).set(data, fs.SetOptions(merge: true)));
      return _applyProfileDoc(
        data,
        userId: userId,
        tokenIsAdmin: tokenIsAdmin || isDesignatedAdmin,
      );
    } catch (e) {
      // ignore: avoid_print
      print('Firestore profile fetch/create error: $e');
      final isDesignatedAdmin = _isDesignatedAdminEmail(email);
      final fallbackProfile = UserProfile(
        id: userId,
        name: email.split('@').first,
        bloodGroup: BloodGroup.oPos,
        phone: '',
        email: email,
        isAdmin: tokenIsAdmin || isDesignatedAdmin,
      );
      currentUser = fallbackProfile;
      return fallbackProfile;
    }
  }

  UserProfile _applyProfileDoc(
    Map<String, dynamic> data, {
    String? userId,
    bool tokenIsAdmin = false,
  }) {
    final email = data['email'] as String?;
    final roleStr = data['role'] as String?;
    final isDesignatedAdmin = _isDesignatedAdminEmail(email);
    final isAdminFromDb =
        (data['isAdmin'] as bool? ?? false) ||
        (roleStr?.toLowerCase() == 'admin');
    final isAdmin = tokenIsAdmin || isAdminFromDb || isDesignatedAdmin;

    final rawPhone = (data['phone'] as String?) ?? '';
    final rawCode = data['countryCode'] as String?;
    final (countryCode: parsedCode, phone: parsedPhone) = rawCode != null
        ? (countryCode: rawCode, phone: PhoneUtils.cleanDigits(rawPhone))
        : PhoneUtils.parse(rawPhone);

    final locMap = data['location'] as Map?;
    final lat = (data['latitude'] as num?)?.toDouble() ??
        (locMap?['lat'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble() ??
        (locMap?['lng'] as num?)?.toDouble();

    final user = UserProfile(
      id:
          userId ??
          _auth.currentUser?.uid ??
          (data['id'] as String? ?? 'user_id'),
      name: (data['name'] as String?)?.isNotEmpty == true
          ? (data['name'] as String)
          : (email?.split('@').first ?? 'User'),
      bloodGroup: data['bloodGroup'] != null
          ? BloodGroup.values.firstWhere(
              (g) => g.label == data['bloodGroup'],
              orElse: () => BloodGroup.oPos,
            )
          : BloodGroup.oPos,
      phone: parsedPhone.isNotEmpty ? parsedPhone : rawPhone,
      countryCode: parsedCode,
      countryIsoCode: data['countryIsoCode'] as String? ?? 'IN',
      email: email,
      dateOfBirth: (data['dateOfBirth'] as fs.Timestamp?)?.toDate(),
      gender: data['gender'] != null
          ? Gender.values.asNameMap()[data['gender']]
          : null,
      country: data['country'] as String?,
      state: data['state'] as String?,
      stateCode: data['stateCode'] as String?,
      city: data['city'] as String?,
      latitude: lat,
      longitude: lng,
      lastDonation: (data['lastDonation'] as fs.Timestamp?)?.toDate(),
      isAdmin: isAdmin,
      photo: data['photo'] as String?,
      phoneVerified: _hasVerifiedPhone,
    );
    currentUser = user;
    _hasSavedGps = data['locationUpdatedAt'] != null;
    donorProfile = _donorFromMap(
      (data['donor'] as Map?)?.cast<String, dynamic>(),
      user.bloodGroup,
    );
    return user;
  }

  /// Whether the signed-in account has a phone number confirmed by SMS. The
  /// sign-in token carries it, which is what the security rules check.
  bool get _hasVerifiedPhone =>
      _auth.currentUser?.phoneNumber?.isNotEmpty ?? false;

  @override
  Stream<bool> get canActStream {
    final me = _users.doc(uid);
    late final StreamController<bool> out;
    final subs = <StreamSubscription<dynamic>>[];
    bool? verified;
    bool? admin;
    var active = true;

    void emit() {
      if (verified == null || admin == null) return;
      out.add(
        admin! || (currentUser?.isAdmin ?? false) || (verified! && active),
      );
    }

    out = StreamController<bool>(
      onListen: () {
        subs.add(
          _auth.userChanges().listen((user) {
            verified = user?.phoneNumber?.isNotEmpty ?? false;
            emit();
          }, onError: out.addError),
        );
        subs.add(
          me.snapshots().listen((doc) {
            final data = doc.data();
            admin =
                data?['isAdmin'] == true ||
                data?['role'] == 'admin' ||
                _isDesignatedAdminEmail(data?['email'] as String?);
            // An operator can switch an account off from the console.
            active = data?['isActive'] != false && data?['disabled'] != true;
            emit();
          }, onError: out.addError),
        );
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return out.stream;
  }

  // ---------------------------------------------------------------------
  // Phone verification. The number is linked to the account in Firebase
  // Auth, so it is in every sign-in token from then on: the rules let only
  // such accounts request blood or donate, and one number can belong to one
  // account only.
  // ---------------------------------------------------------------------

  @override
  Future<PhoneCodeSent?> sendPhoneCode(
    String phoneNumber, {
    PhoneCodeSent? resend,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const PhoneVerificationFailure('Sign in again, then try.');
    }

    if (kIsWeb) {
      if (_hasVerifiedPhone) {
        throw const PhoneVerificationFailure(
          'Change your number from the Rakt Pravah phone app.',
        );
      }
      try {
        final result = await user.linkWithPhoneNumber(phoneNumber);
        return PhoneCodeSent(
          phoneNumber: phoneNumber,
          verificationId: result.verificationId,
          confirm: (code) => result.confirm(code),
        );
      } on fb_auth.FirebaseAuthException catch (e) {
        throw PhoneVerificationFailure(_phoneMessage(e.code));
      }
    }

    final sent = Completer<PhoneCodeSent?>();
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        forceResendingToken: resend?.resendToken,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) async {
          // Android read the SMS itself, possibly after the code screen is
          // already up. The screen hears about it through canActStream.
          try {
            await _usePhoneCredential(credential);
            if (!sent.isCompleted) sent.complete(null);
          } catch (e) {
            if (!sent.isCompleted) sent.completeError(e);
          }
        },
        verificationFailed: (e) {
          if (!sent.isCompleted) {
            sent.completeError(PhoneVerificationFailure(_phoneMessage(e.code)));
          }
        },
        codeSent: (verificationId, resendToken) {
          if (!sent.isCompleted) {
            sent.complete(
              PhoneCodeSent(
                phoneNumber: phoneNumber,
                verificationId: verificationId,
                resendToken: resendToken,
              ),
            );
          }
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } on fb_auth.FirebaseAuthException catch (e) {
      throw PhoneVerificationFailure(_phoneMessage(e.code));
    }
    return sent.future;
  }

  @override
  Future<UserProfile> confirmPhoneCode(PhoneCodeSent sent, String code) async {
    // Android may have confirmed it on its own while the code was typed.
    if (_auth.currentUser?.phoneNumber == sent.phoneNumber) return _savePhone();

    final confirm = sent.confirm;
    if (confirm != null) {
      try {
        await confirm(code.trim());
      } on fb_auth.FirebaseAuthException catch (e) {
        throw PhoneVerificationFailure(_phoneMessage(e.code));
      }
      await _auth.currentUser!.getIdToken(true);
      return _savePhone();
    }

    return _usePhoneCredential(
      fb_auth.PhoneAuthProvider.credential(
        verificationId: sent.verificationId,
        smsCode: code.trim(),
      ),
    );
  }

  /// Makes the number in [credential] this account's phone: links it the
  /// first time, replaces it on a change of number.
  Future<UserProfile> _usePhoneCredential(
    fb_auth.PhoneAuthCredential credential,
  ) async {
    final user = _auth.currentUser!;
    try {
      if (_hasVerifiedPhone) {
        await user.updatePhoneNumber(credential);
      } else {
        await user.linkWithCredential(credential);
      }
    } on fb_auth.FirebaseAuthException catch (e) {
      throw PhoneVerificationFailure(_phoneMessage(e.code));
    }
    // The rules read the number from the sign-in token, so fetch one that
    // carries it before writing anything that depends on it.
    await _auth.currentUser!.getIdToken(true);
    return _savePhone();
  }

  /// Copies the verified number onto the profile, where the app shows it.
  Future<UserProfile> _savePhone() async {
    final parsed = PhoneUtils.parse(_auth.currentUser!.phoneNumber);
    await _ack(
      _users.doc(uid).set({
        'countryCode': parsed.countryCode,
        'phone': parsed.phone,
        'phoneVerified': true,
      }, fs.SetOptions(merge: true)),
    );
    final user = currentUser!.copyWith(
      countryCode: parsed.countryCode,
      phone: parsed.phone,
      phoneVerified: true,
    );
    currentUser = user;
    return user;
  }

  String _phoneMessage(String code) => switch (code) {
    'invalid-phone-number' || 'missing-phone-number' =>
      'That phone number doesn\'t look right. Check it and try again.',
    'invalid-verification-code' || 'missing-verification-code' =>
      'That code is wrong. Check the SMS and try again.',
    'session-expired' || 'code-expired' || 'invalid-verification-id' =>
      'That code has expired. Send a new one.',
    'credential-already-in-use' ||
    'account-exists-with-different-credential' =>
      'This number is already verified on another account.',
    'provider-already-linked' =>
      'This account already has a verified number.',
    'too-many-requests' => 'Too many attempts. Wait a while and try again.',
    'quota-exceeded' => 'No more codes can be sent today. Try again tomorrow.',
    'operation-not-allowed' || 'billing-not-enabled' =>
      'Phone verification isn\'t switched on for this app yet.',
    'app-not-authorized' ||
    'invalid-app-credential' ||
    'missing-client-identifier' ||
    'captcha-check-failed' =>
      'This copy of the app can\'t send codes. Install the official app.',
    'network-request-failed' =>
      'No internet connection. Check it and try again.',
    'requires-recent-login' => 'Sign out and sign in again, then try.',
    _ => 'Couldn\'t verify the number. Try again. [$code]',
  };

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    _forgetSession();
  }

  @override
  Future<void> fileReport({
    required String detail,
    String? requestId,
    String? userId,
  }) async {
    await _online(_db.collection('reports').add({
      'reporterId': uid,
      'reporterName': currentUser?.name,
      'reason': userId != null
          ? 'A person'
          : (requestId != null ? 'A request' : 'Problem report'),
      'detail': detail,
      'targetRequestId': ?requestId,
      'targetUserId': ?userId,
      'status': 'open',
      'createdAt': fs.Timestamp.now(),
    }));
  }

  void _forgetSession() {
    currentUser = null;
    donorProfile = const DonorProfile(
      availability: DonorAvailability.available,
      bloodGroup: BloodGroup.oPos,
    );
  }

  @override
  Future<void> deleteAccount({String? password}) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final me = user.uid;

    // Firebase only deletes a sign-in that was used recently, and this is
    // also the moment to be sure it's really them.
    if (!user.isAnonymous) {
      final email = user.email;
      if (email == null || password == null || password.isEmpty) {
        throw const AccountDeletionFailure('Enter your password.');
      }
      try {
        await user.reauthenticateWithCredential(
          fb_auth.EmailAuthProvider.credential(email: email, password: password),
        );
      } on fb_auth.FirebaseAuthException catch (e) {
        throw AccountDeletionFailure(switch (e.code) {
          'wrong-password' ||
          'invalid-credential' ||
          'user-mismatch' => 'That password is wrong.',
          'too-many-requests' =>
            'Too many attempts. Wait a few minutes and try again.',
          'network-request-failed' =>
            'No internet connection. Connect and try again.',
          _ => 'Couldn\'t confirm your password. Try again. [${e.code}]',
        });
      }
    }

    try {
      // Requests they made: closed if still open, and their name, photo and
      // number taken off. The record stays for the donors who answered it.
      final mine = await _online(
        _requests.where('requesterId', isEqualTo: me).get(),
      );
      for (final doc in mine.docs) {
        await _transitionIfActive(
          doc.id,
          RequestStatus.cancelled,
          'Cancelled: the requester deleted their account',
        );
        await _online(doc.reference.update({
          'requesterName': 'Deleted account',
          'requesterPhoto': null,
          'phone': fs.FieldValue.delete(),
          'phoneCountryCode': fs.FieldValue.delete(),
          'fullPhoneNumber': fs.FieldValue.delete(),
          'notes': fs.FieldValue.delete(),
        }));
        await _online(doc.reference.collection('private').doc('patient').set({
          'name': 'Deleted account',
          'phone': fs.FieldValue.delete(),
        }, fs.SetOptions(merge: true)));
      }

      // Requests they accepted as a donor and haven't finished go back to
      // searching, so the patient isn't left waiting on someone who's gone.
      final accepted = await _online(
        _requests.where('acceptedDonorIds', arrayContains: me).get(),
      );
      for (final doc in accepted.docs) {
        await withdrawFromRequest(doc.id);
      }

      final devices = await _online(
        _db.collection('push_devices').where('user_id', isEqualTo: me).get(),
      );
      for (final doc in devices.docs) {
        await _online(doc.reference.delete());
      }
      for (final sub in ['devices', 'fcm_tokens']) {
        final docs = await _online(_users.doc(me).collection(sub).get());
        for (final doc in docs.docs) {
          await _online(doc.reference.delete());
        }
      }
      await _online(_users.doc(me).delete());

      await user.delete();
      await _auth.signOut();
    } on BackendUnavailable catch (e) {
      throw AccountDeletionFailure(
        'Couldn\'t finish deleting your account. ${e.message}',
      );
    } on fb_auth.FirebaseAuthException catch (e) {
      throw AccountDeletionFailure(
        'Couldn\'t finish deleting your account. Try again. [${e.code}]',
      );
    }
    _forgetSession();
  }

  CooldownConfig _cooldownConfig = const CooldownConfig();

  @override
  CooldownConfig get cooldownConfig => _cooldownConfig;

  @override
  Stream<CooldownConfig> get cooldownConfigStream async* {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('rakt_cooldown_enabled');
      final days = prefs.getInt('rakt_cooldown_days');
      if (enabled != null || days != null) {
        _cooldownConfig = CooldownConfig(
          enabled: enabled ?? true,
          durationDays: days ?? 90,
        );
        yield _cooldownConfig;
      }
    } catch (_) {}

    yield* _db
        .collection('config')
        .doc('app')
        .snapshots()
        .map((doc) {
          if (doc.exists && doc.data() != null) {
            _cooldownConfig = CooldownConfig.fromMap(doc.data());
            SharedPreferences.getInstance().then((p) {
              p.setBool('rakt_cooldown_enabled', _cooldownConfig.enabled);
              p.setInt('rakt_cooldown_days', _cooldownConfig.durationDays);
            }).catchError((_) {});
          }
          return _cooldownConfig;
        })
        .handleError((_) {});
  }

  // ---------------------------------------------------------------------
  // Donor Mode
  // ---------------------------------------------------------------------
  @override
  Stream<DonorProfile> get donorStream {
    // Admins are not donors. Return a permanently-off, immutable profile
    // so the Donate tab (if ever visible) shows nothing useful.
    if (currentUser?.isAdmin == true) {
      return Stream.value(
        DonorProfile(
          availability: DonorAvailability.off,
          bloodGroup: currentUser?.bloodGroup ?? BloodGroup.oPos,
        ),
      );
    }
    final configDoc = _db.collection('config').doc('app');
    final userDoc = _users.doc(uid);
    late final StreamController<DonorProfile> controller;
    final subs = <StreamSubscription<dynamic>>[];
    Map<String, dynamic>? lastUserMap;
    var userLoaded = false;

    void emit() {
      if (!userLoaded && currentUser == null) return;
      final parsed = _donorFromMap(
        (lastUserMap?['donor'] as Map?)?.cast<String, dynamic>(),
        currentUser?.bloodGroup ?? BloodGroup.oPos,
      );
      donorProfile = _autoReenableIfCooldownEnded(parsed);
      if (!controller.isClosed) controller.add(donorProfile);
    }

    controller = StreamController<DonorProfile>(
      onListen: () {
        subs.add(
          configDoc.snapshots().listen(
            (doc) {
              _cooldownConfig = CooldownConfig.fromMap(doc.data());
              emit();
            },
            onError: (_) {
              _cooldownConfig = const CooldownConfig();
              emit();
            },
          ),
        );
        subs.add(
          userDoc.snapshots().listen(
            (doc) {
              userLoaded = true;
              lastUserMap = doc.data();
              emit();
            },
            onError: controller.addError,
          ),
        );
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }

  DonorProfile _autoReenableIfCooldownEnded(DonorProfile profile) {
    if (profile.cooldownConfig.enabled && profile.isInCooldown) {
      if (profile.availability != DonorAvailability.off) {
        final disabled = profile.copyWith(
          availability: DonorAvailability.off,
          cooldownConfig: _cooldownConfig,
        );
        _users.doc(uid).set({
          'donor': _donorToMap(disabled),
        }, fs.SetOptions(merge: true)).ignore();
        return disabled;
      }
      return profile;
    }

    if (profile.lastDonation != null &&
        !profile.isInCooldown &&
        profile.availability == DonorAvailability.off) {
      final reactivated = profile.copyWith(
        availability: DonorAvailability.available,
        cooldownConfig: _cooldownConfig,
      );
      _users.doc(uid).set({
        'donor': _donorToMap(reactivated),
      }, fs.SetOptions(merge: true)).ignore();
      return reactivated;
    }
    return profile;
  }

  @override
  Future<DonorProfile> setDonorProfile(DonorProfile next) async {
    // Admins are not donors — silently discard any attempt to change donor state.
    if (currentUser?.isAdmin == true) return donorProfile;
    final withConfig = next.copyWith(cooldownConfig: _cooldownConfig);
    await _ack(_users.doc(uid).set({
      'donor': _donorToMap(withConfig),
    }, fs.SetOptions(merge: true)));
    donorProfile = withConfig;
    return withConfig;
  }

  @override
  Future<DonorProfile> recordDonation([DateTime? donatedAt]) async {
    // Admins cannot donate blood.
    if (currentUser?.isAdmin == true) return donorProfile;
    final when = donatedAt ?? DateTime.now();
    final isCooldownOn = _cooldownConfig.enabled;
    final updated = donorProfile.copyWith(
      availability: isCooldownOn
          ? DonorAvailability.off
          : donorProfile.availability,
      lastDonation: when,
      totalDonations: donorProfile.totalDonations + 1,
      cooldownConfig: _cooldownConfig,
    );
    await _ack(_users.doc(uid).set({
      'lastDonation': fs.Timestamp.fromDate(when),
      'donor': _donorToMap(updated),
    }, fs.SetOptions(merge: true)));
    donorProfile = updated;
    return updated;
  }

  @override
  Future<DonorProfile> resetDonationCooldown() async {
    final updated = donorProfile.copyWith(
      availability: DonorAvailability.available,
      clearLastDonation: true,
      totalDonations: math.max(0, donorProfile.totalDonations - 1),
      cooldownConfig: _cooldownConfig,
    );
    await _ack(_users.doc(uid).set({
      'lastDonation': null,
      'donor': _donorToMap(updated),
    }, fs.SetOptions(merge: true)));
    donorProfile = updated;
    return updated;
  }

  @override
  Future<void> registerFcmToken(String token) async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) return;
    final deviceId = await DeviceIdService.instance.getDeviceId();
    final sanitizedKey = token.replaceAll(RegExp(r'[/.\#$\[\]]'), '_');
    final platform = kIsWeb
        ? 'web'
        : (defaultTargetPlatform == TargetPlatform.android
            ? 'android'
            : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'other'));
    final now = fs.Timestamp.now();

    // 1. Maintain quick access list on the user's primary profile doc
    await _ack(_users.doc(currentUid).set({
      'fcmTokenList': fs.FieldValue.arrayUnion([token]),
      'fcmTokens': {
        sanitizedKey: {
          'token': token,
          'platform': platform,
          'device_id': deviceId,
          'updatedAt': now,
        }
      }
    }, fs.SetOptions(merge: true)));

    // 2. Store push-device information in dedicated collection
    final deviceData = {
      'user_id': currentUid,
      'device_id': deviceId,
      'platform': platform,
      'push_token': token,
      'is_active': true,
      'last_seen': now,
      'updated_at': now,
    };

    final deviceDocRef = _db.collection('push_devices').doc(deviceId);
    fs.DocumentSnapshot<Map<String, dynamic>>? existing;
    try {
      existing = await _readDoc(deviceDocRef);
    } catch (_) {
      existing = null;
    }
    if (existing == null || !existing.exists) {
      deviceData['created_at'] = now;
    }
    await _ack(deviceDocRef.set(deviceData, fs.SetOptions(merge: true)));

    // Also mirror into user's devices subcollection
    await _users
        .doc(currentUid)
        .collection('devices')
        .doc(deviceId)
        .set(deviceData, fs.SetOptions(merge: true));
  }

  @override
  Future<void> unregisterFcmToken(String token) async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) return;
    final deviceId = await DeviceIdService.instance.getDeviceId();
    final sanitizedKey = token.replaceAll(RegExp(r'[/.\#$\[\]]'), '_');
    final now = fs.Timestamp.now();

    await _ack(_users.doc(currentUid).update({
      'fcmTokenList': fs.FieldValue.arrayRemove([token]),
      'fcmTokens.$sanitizedKey': fs.FieldValue.delete(),
    }).catchError((_) {}));

    final deactivation = {
      'is_active': false,
      'updated_at': now,
    };

    await _db
        .collection('push_devices')
        .doc(deviceId)
        .set(deactivation, fs.SetOptions(merge: true))
        .catchError((_) {});

    await _users
        .doc(currentUid)
        .collection('devices')
        .doc(deviceId)
        .set(deactivation, fs.SetOptions(merge: true))
        .catchError((_) {});
  }

  Map<String, dynamic> _donorToMap(DonorProfile d) => {
    'availability': d.availability.name,
    'bloodGroup': d.bloodGroup.label,
    'notifyPush': d.notifyPush,
    'notifyCritical': d.notifyCritical,
    'locationGranted': d.locationGranted,
    'maxDistanceKm': d.maxDistanceKm,
    'pausedUntil': d.pausedUntil == null
        ? null
        : fs.Timestamp.fromDate(d.pausedUntil!),
    'totalDonations': d.totalDonations,
    'lastDonation': d.lastDonation == null
        ? null
        : fs.Timestamp.fromDate(d.lastDonation!),
  };

  DonorProfile _donorFromMap(
    Map<String, dynamic>? m,
    BloodGroup fallbackGroup,
  ) {
    if (m == null) {
      return DonorProfile(
        availability: DonorAvailability.available,
        bloodGroup: fallbackGroup,
        cooldownConfig: _cooldownConfig,
      );
    }
    return DonorProfile(
      availability: DonorAvailability.values.byNameOr(
        m['availability'] as String?,
        DonorAvailability.available,
      ),
      bloodGroup: m['bloodGroup'] == null
          ? fallbackGroup
          : BloodGroup.fromLabel(m['bloodGroup'] as String),
      notifyPush: m['notifyPush'] as bool? ?? true,
      notifyCritical: m['notifyCritical'] as bool? ?? false,
      locationGranted: m['locationGranted'] as bool? ?? false,
      maxDistanceKm: (m['maxDistanceKm'] as num?)?.toDouble() ?? 30,
      pausedUntil: (m['pausedUntil'] as fs.Timestamp?)?.toDate(),
      totalDonations: m['totalDonations'] as int? ?? 0,
      lastDonation: (m['lastDonation'] as fs.Timestamp?)?.toDate(),
      cooldownConfig: _cooldownConfig,
    );
  }

  // ---------------------------------------------------------------------
  // Requests
  // ---------------------------------------------------------------------
  @override
  Stream<List<BloodRequest>> get myRequestsStream => _requests
      .where('requesterId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) {
        final requests = snap.docs.map(_requestFromDoc).toList();
        // Nothing runs server-side to close requests that ran out of time,
        // so the requester's own app does it: they're the only one whose
        // security rules allow the write, and the only one who needs to see
        // the result. Fire-and-forget, the stream reports the new status.
        for (final request in requests) {
          if (request.hasExpiredBy()) unawaited(_expire(request.id));
        }
        return requests;
      });

  Future<void> _expire(String id) => _transitionIfActive(
    id,
    RequestStatus.expired,
    'No donor found in time',
    // Checked again inside the transaction: a donor may have accepted, or
    // the request been extended, since the snapshot that looked expired.
    stillApplies: (request) => request.hasExpiredBy(),
  );

  @override
  Future<void> extendRequest(String id) async {
    final ref = _requests.doc(id);
    await _online(_db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data()!['requesterId'] != uid) return;
      final now = DateTime.now();
      final timeline = List<Map<String, dynamic>>.from(
        (snap.data()!['timeline'] as List?) ?? const [],
      );
      timeline.add(
        _eventToMap(RequestStatus.searching, now, 'Searching again'),
      );
      tx.update(ref, {
        'status': RequestStatus.searching.name,
        'expiresAt': fs.Timestamp.fromDate(now.add(const Duration(hours: 6))),
        'timeline': timeline,
      });
    }));
  }

  @override
  Stream<BloodRequest> requestStream(String id) => _requests
      .doc(id)
      .snapshots()
      .where((doc) => doc.exists)
      .map(_requestFromDoc);

  @override
  Future<BloodRequest> createRequest({
    required String patientName,
    required BloodGroup patientBloodGroup,
    required List<BloodGroup> bloodGroups,
    required int units,
    required Urgency urgency,
    required String requestLocationLabel,
    required Destination destination,
    GeoPoint? requestLocation,
    String? bloodType,
    String? phoneCountryCode,
    String? phone,
    DateTime? requiredDate,
    String? notes,
  }) async {
    final now = DateTime.now();
    final ref = _requests.doc();
    String? effectivePhone;
    String effectivePhoneCountryCode = phoneCountryCode ?? '+91';

    if (phone != null && phone.trim().isNotEmpty) {
      if (phone.trim().startsWith('+')) {
        final parsed = PhoneUtils.parse(phone);
        effectivePhoneCountryCode = phoneCountryCode ?? parsed.countryCode;
        effectivePhone = parsed.phone;
      } else {
        effectivePhone = PhoneUtils.cleanDigits(phone);
      }
    } else if (currentUser?.phone != null &&
        currentUser!.phone.trim().isNotEmpty) {
      final parsed = PhoneUtils.parse(currentUser!.phone);
      effectivePhoneCountryCode = currentUser!.countryCode.isNotEmpty
          ? currentUser!.countryCode
          : parsed.countryCode;
      effectivePhone = parsed.phone;
    }

    if (effectivePhone != null && effectivePhone.isNotEmpty) {
      final err =
          PhoneUtils.validate(effectivePhoneCountryCode, effectivePhone);
      if (err != null) {
        throw ArgumentError(err);
      }
    }

    final data = <String, dynamic>{
      'requesterId': uid,
      'requesterName': currentUser!.name,
      // Profiles aren't readable by other users, so the photo the card shows
      // is a copy taken now. Requests made before a photo was added have none.
      'requesterPhoto': currentUser!.photo,
      // The patient's name is not in here: every signed-in user can read
      // these documents, because that's how donors find requests at all. It
      // lives in the private subcollection written below instead.
      'patientBloodGroup': patientBloodGroup.label,
      'bloodGroups': bloodGroups.map((g) => g.label).toList(),
      'units': units,
      'urgency': urgency.name,
      'bloodType': bloodType ?? 'Blood',
      if (effectivePhone != null && effectivePhone.isNotEmpty) ...{
        'phone': effectivePhone,
        'phoneCountryCode': effectivePhoneCountryCode,
        'fullPhoneNumber': PhoneUtils.toInternational(
          effectivePhone,
          countryCode: effectivePhoneCountryCode,
        ),
      },
      if (requiredDate != null)
        'requiredDate': fs.Timestamp.fromDate(requiredDate),
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'status': RequestStatus.searching.name,
      'createdAt': fs.Timestamp.fromDate(now),
      'destination': _destinationToMap(destination),
      'requestLocationLabel': requestLocationLabel,
      'requestLocation': _pointToMap(requestLocation),
      // The requester's saved home area, used to match donors when neither
      // side has usable coordinates.
      'city': currentUser?.city,
      'state': currentUser?.state,
      'donorsContacted': 0,
      'currentWave': 0,
      'searchRadiusKm': 0.0,
      'acceptedDonors': <Map<String, dynamic>>[],
      'acceptedDonorIds': <String>[],
      'expiresAt': fs.Timestamp.fromDate(now.add(const Duration(hours: 6))),
      'timeline': [
        _eventToMap(RequestStatus.created, now, null),
        _eventToMap(RequestStatus.searching, now, 'Searching for donors'),
      ],
      'declinedByDonorIds': <String>[],
      'viewedByDonorIds': <String>[],
    };
    await _ack(ref.set(data));
    await _ack(ref.collection('private').doc('patient').set({
      'name': patientName,
      if (effectivePhone != null && effectivePhone.isNotEmpty)
        'phone': effectivePhone,
      'bloodType': bloodType ?? 'Blood',
    }));
    // The server may not have it yet; the device already does.
    return _requestFromDoc(
      await ref.get(const fs.GetOptions(source: fs.Source.cache)),
    );
  }

  @override
  Stream<String?> patientNameStream(String requestId) => _requests
      .doc(requestId)
      .collection('private')
      .doc('patient')
      .snapshots()
      .map((doc) => doc.data()?['name'] as String?);

  @override
  Future<void> cancelRequest(String id) async {
    await _transitionIfActive(
      id,
      RequestStatus.cancelled,
      'Cancelled by requester',
    );
  }

  @override
  Future<void> markFulfilled(String id) async {
    await _transitionIfActive(id, RequestStatus.fulfilled, 'Marked fulfilled');
  }

  @override
  Stream<List<MatchedDonor>> nearbyDonorsStream(String requestId) {
    final controller = StreamController<List<MatchedDonor>>.broadcast();
    BloodRequest? currentRequest;
    List<fs.DocumentSnapshot<Map<String, dynamic>>>? userDocs;

    void emit() {
      if (currentRequest == null || userDocs == null) return;
      final req = currentRequest!;
      var destPoint = req.destination.location ?? req.requestLocation;
      if (destPoint == null) {
        final resolved = LocationDataService.resolve(
          country: 'India',
          city: req.requestLocationLabel,
        );
        if (resolved.hasCoordinates) {
          destPoint = GeoPoint(resolved.latitude!, resolved.longitude!);
        }
      }
      final searchRadius = req.searchRadiusKm > 0 ? req.searchRadiusKm : 25.0;
      final acceptedMap = {for (final d in req.acceptedDonors) d.id: d};
      final declinedIds = req.declinedByDonorIds.toSet();
      final viewedIds = req.viewedByDonorIds.toSet();

      final List<MatchedDonor> results = [];

      for (final doc in userDocs!) {
        final donorId = doc.id;
        if (donorId == req.requesterId) continue;
        if (declinedIds.contains(donorId)) continue;

        final data = doc.data() ?? {};
        // Admins are excluded from donor matching entirely.
        if (data['isAdmin'] == true) continue;
        final donorMap = (data['donor'] as Map?)?.cast<String, dynamic>();
        final bloodGroupStr =
            data['bloodGroup'] as String? ?? donorMap?['bloodGroup'] as String?;
        if (bloodGroupStr == null) continue;
        final bloodGroup = BloodGroup.fromLabel(bloodGroupStr);

        final profile = _donorFromMap(donorMap, bloodGroup);
        final isAccepted = acceptedMap.containsKey(donorId);

        if (!isAccepted) {
          if (!profile.isOn || profile.isInCooldown) continue;
        }

        final isCompatible =
            req.bloodGroups.contains(bloodGroup) ||
            (req.patientBloodGroup != null &&
                donorsCompatibleWith(req.patientBloodGroup!)
                    .contains(bloodGroup));
        if (!isCompatible && !isAccepted) continue;

        var donorLocation = _pointFromMap(data['location'] as Map?);
        if (donorLocation == null && data['city'] != null) {
          final resolved = LocationDataService.resolve(
            country: data['country'] as String? ?? 'India',
            state: data['state'] as String?,
            city: data['city'] as String?,
          );
          if (resolved.hasCoordinates) {
            donorLocation = GeoPoint(resolved.latitude!, resolved.longitude!);
          }
        }
        double? distance;
        if (donorLocation != null && destPoint != null) {
          distance = _haversineKm(donorLocation, destPoint);
        } else if (donorId == uid && myLocation != null && destPoint != null) {
          distance = _haversineKm(myLocation!, destPoint);
        }

        if (distance != null && distance > searchRadius && !isAccepted) {
          continue;
        }

        final DonorRequestInteractionStatus status;
        if (isAccepted) {
          status = DonorRequestInteractionStatus.accepted;
        } else if (viewedIds.contains(donorId)) {
          status = DonorRequestInteractionStatus.viewed;
        } else {
          status = DonorRequestInteractionStatus.notified;
        }

        results.add(
          MatchedDonor(
            id: donorId,
            name: data['name'] as String? ?? 'Donor',
            bloodGroup: bloodGroup,
            distanceKm: distance ?? 0.0,
            status: status,
            phone: data['phone'] as String?,
            phoneCountryCode: data['countryCode'] as String?,
            location: donorLocation,
            notifiedAt: req.createdAt,
            isEligible: !profile.isInCooldown,
            isDonorModeOn: profile.isOn,
          ),
        );
      }

      results.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

      if (!controller.isClosed) {
        controller.add(results);
      }
    }

    final reqSub = requestStream(requestId).listen((req) {
      currentRequest = req;
      emit();
    }, onError: controller.addError);

    final usersSub = _users.snapshots().listen((snap) {
      userDocs = snap.docs;
      emit();
    }, onError: controller.addError);

    controller.onCancel = () {
      reqSub.cancel();
      usersSub.cancel();
    };

    return controller.stream;
  }

  @override
  Future<void> expandSearchRadius(String requestId, double newRadiusKm) async {
    await _ack(_requests.doc(requestId).update({'searchRadiusKm': newRadiusKm}));
  }

  @override
  Future<void> markInvitationViewed(String requestId) async {
    if (uid.isEmpty) return;
    await _ack(_requests.doc(requestId).update({
      'viewedByDonorIds': fs.FieldValue.arrayUnion([uid]),
    }));
  }

  @override
  Future<void> withdrawFromRequest(String id) async {
    final ref = _requests.doc(id);
    await _online(_db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data()!;
      final current = RequestStatus.values.byNameOr(
        data['status'] as String?,
        RequestStatus.created,
      );
      final donors = _acceptedDonorsFromData(data);
      if (!donors.any((d) => d.id == uid) || current.isTerminal) return;
      final remaining = donors.where((d) => d.id != uid).toList();
      final timeline = List<Map<String, dynamic>>.from(
        (data['timeline'] as List?) ?? const [],
      );
      timeline.add(
        _eventToMap(
          RequestStatus.searching,
          DateTime.now(),
          '${currentUser?.name ?? 'A donor'} can\'t make it. Searching again',
        ),
      );
      tx.update(ref, {
        // Back to searching: the patient still needs this unit, and another
        // donor can take it.
        'status': RequestStatus.searching.name,
        'acceptedDonors': remaining.map(_acceptedDonorToMap).toList(),
        'acceptedDonorIds': remaining.map((d) => d.id).toList(),
        'timeline': timeline,
        'declinedByDonorIds': fs.FieldValue.arrayUnion([uid]),
        'donorLiveLocations.$uid': fs.FieldValue.delete(),
      });
    }));
  }

  Future<void> _transitionIfActive(
    String id,
    RequestStatus status,
    String note, {
    bool Function(BloodRequest current)? stillApplies,
  }) async {
    final ref = _requests.doc(id);
    await _online(_db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final current = RequestStatus.values.byNameOr(
        snap.data()!['status'] as String?,
        RequestStatus.created,
      );
      if (current.isTerminal) return;
      if (stillApplies != null && !stillApplies(_requestFromDoc(snap))) return;
      final timeline = List<Map<String, dynamic>>.from(
        (snap.data()!['timeline'] as List?) ?? const [],
      );
      timeline.add(_eventToMap(status, DateTime.now(), note));
      tx.update(ref, {
        'status': status.name,
        'timeline': timeline,
        'donorLiveLocations': <String, dynamic>{},
        'requesterLiveLocation': fs.FieldValue.delete(),
      });
    }));
  }

  // ---------------------------------------------------------------------
  // Invitations — derived live from compatible open requests, not stored
  // as separate documents. Merges two live queries: requests this donor is
  // still eligible to see, and any request they've already accepted.
  // ---------------------------------------------------------------------
  @override
  Stream<List<Invitation>> get invitationsStream {
    final controller = StreamController<List<Invitation>>.broadcast();
    Map<String, Invitation> openMap = {};
    Map<String, Invitation> acceptedMap = {};
    var openReady = false, acceptedReady = false;

    void emit() {
      if (!openReady || !acceptedReady) return;
      final combined = <String, Invitation>{}
        ..addAll(openMap)
        ..addAll(acceptedMap);
      final list = combined.values.toList()
        ..sort((a, b) {
          // Closest first when distances are known; a donor can only help
          // someone they can actually reach in time.
          final da = a.distanceKm, db = b.distanceKm;
          if (da != null && db != null && da != db) return da.compareTo(db);
          if (da == null && db != null) return 1;
          if (da != null && db == null) return -1;
          return b.createdAt.compareTo(a.createdAt);
        });
      if (!controller.isClosed) controller.add(list);
    }

    // Admins are not donors and must never see or receive blood-request invitations.
    if (currentUser?.isAdmin == true) {
      return Stream.value(const []);
    }

    // New opportunities only reach a donor who has Donor Mode on and isn't
    // within the 90-day cooldown of their last donation. Enforced here, not
    // just in the UI, so Donor Mode off really means no requests. Requests
    // they already accepted (below) keep showing either way.
    StreamSubscription<fs.QuerySnapshot<Map<String, dynamic>>>? openSub;
    if (!donorProfile.isOn || donorProfile.isInCooldown) {
      openMap = {};
      openReady = true;
    } else {
      // The requester already chose exactly which donor groups a request is
      // open to (see BloodGroupMultiPicker), so matching is a direct
      // "is my blood group in that list" check — no compatibility inference
      // needed on this side.
      openSub = _requests
          .where(
            'bloodGroups',
            arrayContainsAny: [donorProfile.bloodGroup.label],
          )
          .where(
            'status',
            whereIn: [RequestStatus.created.name, RequestStatus.searching.name],
          )
          .snapshots()
          .listen((snap) {
            final map = <String, Invitation>{};
            for (final doc in snap.docs) {
              final data = doc.data();
              if (data['requesterId'] == uid) continue;
              final declined =
                  (data['declinedByDonorIds'] as List?)?.cast<String>() ??
                  const [];
              if (declined.contains(uid)) continue;
              final invitation = _invitationFromRequestData(
                doc.id,
                data,
                myLocation,
              );
              // Nobody sweeps expired requests server-side, so an old one
              // would otherwise sit in every donor's list indefinitely.
              if (invitation.isExpired) continue;
              // Every unit already has a donor.
              if ((invitation.unitsRemaining ?? 1) <= 0) continue;
              if (!_isNearby(invitation, data)) continue;
              map[doc.id] = invitation;
            }
            openMap = map;
            openReady = true;
            emit();
          });
    }

    final acceptedSub = _requests
        .where('acceptedDonorIds', arrayContains: uid)
        .snapshots()
        .listen((snap) {
          acceptedMap = {
            for (final doc in snap.docs)
              doc.id: _invitationFromRequestData(
                doc.id,
                doc.data(),
                myLocation,
                forceStatus: InvitationStatus.accepted,
              ),
          };
          acceptedReady = true;
          emit();
          for (final doc in snap.docs) {
            if (doc.data()['status'] == RequestStatus.fulfilled.name) {
              _creditDonationIfNeeded(doc.id);
            }
          }
        });

    controller.onCancel = () {
      openSub?.cancel();
      acceptedSub.cancel();
    };
    return controller.stream;
  }

  /// Records a completed donation exactly once per request, even across
  /// app restarts — a Firestore transaction checks the donor's own
  /// `creditedRequestIds` list before crediting, since re-emitted snapshots
  /// would otherwise double-count every time this listener fires. This is
  /// what starts the real 90-day donation cooldown (spec: donors shouldn't
  /// be matched again too soon after giving blood).
  Future<void> _creditDonationIfNeeded(String requestId) async {
    // Admins cannot have donations credited to them.
    if (currentUser?.isAdmin == true) return;
    final ref = _users.doc(uid);
    await _online(_db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? <String, dynamic>{};
      final donorMap =
          (data['donor'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final credited =
          (donorMap['creditedRequestIds'] as List?)?.cast<String>() ?? const [];
      if (credited.contains(requestId)) return;
      tx.set(ref, {
        'donor': {
          ...donorMap,
          'availability': DonorAvailability.off.name,
          'totalDonations': (donorMap['totalDonations'] as int? ?? 0) + 1,
          'lastDonation': fs.Timestamp.fromDate(DateTime.now()),
          'creditedRequestIds': [...credited, requestId],
        },
        'lastDonation': fs.Timestamp.fromDate(DateTime.now()),
      }, fs.SetOptions(merge: true));
    }));
  }

  /// Accept is a transaction so only the first donor to claim a request
  /// wins; a lost race throws so the UI can say the opportunity is gone
  /// instead of pretending it succeeded (spec §13).
  @override
  Future<void> respondToInvitation(String id, InvitationStatus status) async {
    if (status == InvitationStatus.declined) {
      await _ack(_requests.doc(id).update({
        'declinedByDonorIds': fs.FieldValue.arrayUnion([uid]),
      }));
      return;
    }
    if (status != InvitationStatus.accepted) return;

    try {
      await _acceptTransaction(id);
    } on BackendUnavailable {
      // The answer may simply have been slow: the claim can still commit
      // after we stopped waiting, so look before calling it a failure.
      if (await _isOnAcceptedList(id)) return;
      rethrow;
    }
  }

  Future<bool> _isOnAcceptedList(String requestId) async {
    try {
      final snap = await _readDoc(_requests.doc(requestId));
      final ids = (snap.data()?['acceptedDonorIds'] as List?) ?? const [];
      return ids.contains(uid);
    } catch (_) {
      return false;
    }
  }

  Future<void> _acceptTransaction(String id) async {
    // Admins cannot accept blood requests as donors.
    if (currentUser?.isAdmin == true) {
      throw StateError('Admin accounts cannot accept blood requests as donors.');
    }
    await _online(_db.runTransaction((tx) async {
      final ref = _requests.doc(id);
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw StateError('This request is no longer available.');
      }
      final data = snap.data()!;
      final current = RequestStatus.values.byNameOr(
        data['status'] as String?,
        RequestStatus.created,
      );
      final units = data['units'] as int? ?? 1;
      final donors = _acceptedDonorsFromData(data);
      // Already on the list (a retry after a slow answer): nothing to do. This
      // has to come before the capacity check, which a full request would fail.
      if (donors.any((d) => d.id == uid)) return;
      if (current.isTerminal || donors.length >= units) {
        throw StateError('This request is no longer available.');
      }

      final now = DateTime.now();
      final destPoint =
          _pointFromMap((data['destination'] as Map?)?['location'] as Map?) ??
          _pointFromMap(data['requestLocation'] as Map?);
      double? dist;
      if (myLocation != null && destPoint != null) {
        dist = _haversineKm(myLocation!, destPoint);
      }
      final next = [
        ...donors,
        AcceptedDonor(
          id: uid,
          name: currentUser!.name,
          bloodGroup: currentUser!.bloodGroup,
          bloodType: data['bloodType'] as String? ?? 'Blood',
          phone: currentUser!.phone,
          phoneCountryCode: currentUser!.countryCode,
          distanceKm: dist,
          location: myLocation,
          status: 'Accepted',
          transitStatus: DonorTransitStatus.accepted,
          isVerified: true,
          isDonorModeOn: donorProfile.isOn,
          acceptedAt: now,
          photoUrl: currentUser!.photo,
        ),
      ];
      final timeline = List<Map<String, dynamic>>.from(
        (data['timeline'] as List?) ?? const [],
      );
      timeline.add(
        _eventToMap(
          RequestStatus.donorAccepted,
          now,
          '${currentUser!.name} accepted your blood request',
        ),
      );
      tx.update(ref, {
        'status': RequestStatus.donorAccepted.name,
        'acceptedDonors': next.map(_acceptedDonorToMap).toList(),
        'acceptedDonorIds': next.map((d) => d.id).toList(),
        'timeline': timeline,
      });
    }));
  }

  /// Whether a request is close enough to show this donor. Distance decides
  /// it when both positions are known; otherwise it falls back to the saved
  /// home state, so a donor in Kerala isn't shown a request from Lucknow
  /// just because nobody's GPS was on.
  bool _isNearby(Invitation invitation, Map<String, dynamic> data) {
    final km = invitation.distanceKm;
    if (km != null) return km <= donorProfile.maxDistanceKm;
    final requestState = (data['state'] as String?)?.trim().toLowerCase();
    final myState = currentUser?.state?.trim().toLowerCase();
    if (requestState == null ||
        requestState.isEmpty ||
        myState == null ||
        myState.isEmpty) {
      // Not enough information to rule it out — better a donor sees it and
      // decides than a patient goes unseen.
      return true;
    }
    return requestState == myState;
  }

  Invitation _invitationFromRequestData(
    String id,
    Map<String, dynamic> data,
    GeoPoint? myLocation, {
    InvitationStatus? forceStatus,
  }) {
    final dest = (data['destination'] as Map).cast<String, dynamic>();
    // The donor travels to the hospital, not to wherever the requester
    // happened to be, so that's the distance that matters to them.
    final target =
        _pointFromMap(dest['location'] as Map?) ??
        _pointFromMap(data['requestLocation'] as Map?);
    final distance = (myLocation != null && target != null)
        ? _haversineKm(myLocation, target)
        : null;
    final patientGroup = data['patientBloodGroup'] as String?;
    final units = data['units'] as int? ?? 1;
    final pledged = _acceptedDonorsFromData(data).length;
    return Invitation(
      id: id,
      requestId: id,
      requesterId: data['requesterId'] as String? ?? '',
      requesterName: data['requesterName'] as String? ?? 'Someone',
      requesterPhoto: data['requesterPhoto'] as String?,
      bloodGroups: _parseBloodGroups(data['bloodGroups']),
      units: data['units'] as int,
      urgency: Urgency.values.byNameOr(
        data['urgency'] as String?,
        Urgency.routine,
      ),
      distanceKm: distance,
      status: forceStatus ?? InvitationStatus.pending,
      destinationName: dest['name'] as String? ?? '',
      destinationArea: dest['address'] as String? ?? '',
      createdAt: (data['createdAt'] as fs.Timestamp).toDate(),
      expiresAt: (data['expiresAt'] as fs.Timestamp?)?.toDate(),
      patientBloodGroup: patientGroup == null
          ? null
          : BloodGroup.fromLabel(patientGroup),
      requestStatus: RequestStatus.values.byNameOr(
        data['status'] as String?,
        RequestStatus.created,
      ),
      unitsRemaining: units - pledged < 0 ? 0 : units - pledged,
    );
  }

  // ---------------------------------------------------------------------
  // Chat — a subcollection per request; only the requester and accepted
  // donor can read/write it, enforced by Firestore security rules.
  // ---------------------------------------------------------------------
  @override
  Stream<List<ChatMessage>> chatStream(String requestId) => _requests
      .doc(requestId)
      .collection('messages')
      .orderBy('sentAt')
      .snapshots()
      .map(
        (snap) => snap.docs
            .map(
              (d) => ChatMessage(
                id: d.id,
                requestId: requestId,
                senderId: d.data()['senderId'] as String,
                senderName: d.data()['senderName'] as String,
                text: d.data()['text'] as String,
                sentAt: (d.data()['sentAt'] as fs.Timestamp).toDate(),
              ),
            )
            .toList(),
      );

  @override
  Future<ChatMessage> sendMessage(String requestId, String text) async {
    final now = DateTime.now();
    final ref = _requests.doc(requestId).collection('messages').doc();
    await _ack(ref.set({
      'senderId': uid,
      'senderName': currentUser!.name,
      'text': text,
      'sentAt': fs.Timestamp.fromDate(now),
    }));
    return ChatMessage(
      id: ref.id,
      requestId: requestId,
      senderId: uid,
      senderName: currentUser!.name,
      text: text,
      sentAt: now,
    );
  }

  // ---------------------------------------------------------------------
  // Live location — the accepted donor's real position while they've
  // explicitly chosen to share it (spec §19). Security rules restrict this
  // write to exactly these two fields on a request the caller is the
  // accepted donor of; nothing else on the document can change this way.
  // ---------------------------------------------------------------------
  @override
  Future<void> updateLiveLocation(
    String requestId,
    GeoPoint point, {
    DonorTransitStatus transitStatus = DonorTransitStatus.onTheWay,
    double? headingDegrees,
    bool isRequester = false,
  }) async {
    final now = DateTime.now();
    if (isRequester) {
      await _ack(_requests.doc(requestId).update({
        'requesterLiveLocation': {
          'lat': point.lat,
          'lng': point.lng,
          'at': fs.Timestamp.fromDate(now),
        },
      }));
    } else {
      await _ack(_requests.doc(requestId).update({
        'donorLiveLocations.$uid': {
          'lat': point.lat,
          'lng': point.lng,
          'at': fs.Timestamp.fromDate(now),
          'transitStatus': transitStatus.name,
          'heading': ?headingDegrees,
        },
      }));
    }
  }

  @override
  Future<void> updateDonorTransitStatus(
    String requestId,
    DonorTransitStatus status,
  ) async {
    final ref = _requests.doc(requestId);
    await _ack(ref.update({'donorLiveLocations.$uid.transitStatus': status.name}));
    final snap = await _readDoc(ref);
    if (snap.exists) {
      final timeline = List<Map<String, dynamic>>.from(
        (snap.data()!['timeline'] as List?) ?? const [],
      );
      timeline.add(
        _eventToMap(
          RequestStatus.coordinating,
          DateTime.now(),
          'Donor status: ${status.label}',
        ),
      );
      await _ack(ref.update({'timeline': timeline}));
    }
  }

  @override
  Future<void> stopLiveLocation(
    String requestId, {
    bool isRequester = false,
  }) async {
    if (isRequester) {
      await _ack(_requests.doc(requestId).update({
        'requesterLiveLocation': fs.FieldValue.delete(),
      }));
    } else {
      await _ack(_requests.doc(requestId).update({
        'donorLiveLocations.$uid': fs.FieldValue.delete(),
      }));
    }
  }

  // ---------------------------------------------------------------------
  // Serialization helpers
  // ---------------------------------------------------------------------
  List<BloodGroup> _parseBloodGroups(dynamic raw) {
    final labels = (raw as List?)?.cast<String>() ?? const [];
    return labels.map(BloodGroup.fromLabel).toList();
  }

  BloodRequest _requestFromDoc(fs.DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final destMap = (data['destination'] as Map).cast<String, dynamic>();
    final patientGroup = data['patientBloodGroup'] as String?;
    return BloodRequest(
      id: doc.id,
      requesterId: data['requesterId'] as String,
      requesterName: data['requesterName'] as String,
      requesterPhoto: data['requesterPhoto'] as String?,
      // Only requests created before the name moved still carry it here.
      patientName: data['patientName'] as String?,
      patientBloodGroup: patientGroup == null
          ? null
          : BloodGroup.fromLabel(patientGroup),
      bloodGroups: _parseBloodGroups(data['bloodGroups']),
      units: data['units'] as int,
      urgency: Urgency.values.byNameOr(
        data['urgency'] as String?,
        Urgency.routine,
      ),
      status: RequestStatus.values.byNameOr(
        data['status'] as String?,
        RequestStatus.created,
      ),
      createdAt: (data['createdAt'] as fs.Timestamp).toDate(),
      destination: Destination(
        name: destMap['name'] as String? ?? '',
        address: destMap['address'] as String? ?? '',
        wardOrContact: destMap['wardOrContact'] as String?,
        location: _pointFromMap(destMap['location'] as Map?),
      ),
      requestLocationLabel: data['requestLocationLabel'] as String? ?? '',
      requestLocation: _pointFromMap(data['requestLocation'] as Map?),
      bloodType: (data['bloodType'] as String?) ?? 'Blood',
      phoneCountryCode: data['phoneCountryCode'] as String? ?? '+91',
      phone: (data['phone'] as String?) ?? (data['patientPhone'] as String?),
      requiredDate: (data['requiredDate'] as fs.Timestamp?)?.toDate(),
      notes: data['notes'] as String?,
      donorsContacted: data['donorsContacted'] as int? ?? 0,
      currentWave: data['currentWave'] as int? ?? 0,
      searchRadiusKm: (data['searchRadiusKm'] as num?)?.toDouble() ?? 0,
      acceptedDonors: _acceptedDonorsFromData(data),
      expiresAt: (data['expiresAt'] as fs.Timestamp?)?.toDate(),
      timeline: ((data['timeline'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(_eventFromMap)
          .toList(),
      donorLiveLocations: _liveLocationsFromData(data),
      requesterLiveLocation: _requesterLiveLocationFromData(data),
      declinedByDonorIds:
          (data['declinedByDonorIds'] as List?)?.cast<String>() ?? const [],
      viewedByDonorIds:
          (data['viewedByDonorIds'] as List?)?.cast<String>() ?? const [],
    );
  }

  Map<String, dynamic> _acceptedDonorToMap(AcceptedDonor d) => {
    'id': d.id,
    'name': d.name,
    'bloodGroup': d.bloodGroup?.label,
    'bloodType': d.bloodType,
    'photoUrl': d.photoUrl,
    'phone': d.phone,
    'phoneCountryCode': d.phoneCountryCode,
    'distanceKm': d.distanceKm,
    'location': _pointToMap(d.location),
    'status': d.status,
    'transitStatus': d.transitStatus.name,
    'isVerified': d.isVerified,
    'isDonorModeOn': d.isDonorModeOn,
    'at': fs.Timestamp.fromDate(d.acceptedAt),
  };

  /// Reads the donor list, falling back to the single `acceptedDonorId` that
  /// requests created before multi-donor matching still carry.
  List<AcceptedDonor> _acceptedDonorsFromData(Map<String, dynamic> data) {
    final raw = (data['acceptedDonors'] as List?)?.cast<Map>();
    if (raw != null && raw.isNotEmpty) {
      return [
        for (final m in raw)
          AcceptedDonor(
            id: m['id'] as String,
            name: m['name'] as String? ?? 'Donor',
            bloodGroup: m['bloodGroup'] != null
                ? BloodGroup.fromLabel(m['bloodGroup'] as String)
                : null,
            bloodType: m['bloodType'] as String? ?? 'Blood',
            photoUrl: m['photoUrl'] as String?,
            phone: m['phone'] as String?,
            phoneCountryCode: m['phoneCountryCode'] as String?,
            distanceKm: (m['distanceKm'] as num?)?.toDouble(),
            location: _pointFromMap(m['location'] as Map?),
            status: m['status'] as String? ?? 'Accepted',
            transitStatus: DonorTransitStatus.values.byNameOr(
              m['transitStatus'] as String?,
              DonorTransitStatus.accepted,
            ),
            isVerified: m['isVerified'] as bool? ?? true,
            isDonorModeOn: m['isDonorModeOn'] as bool? ?? true,
            acceptedAt: (m['at'] as fs.Timestamp?)?.toDate() ?? DateTime.now(),
          ),
      ];
    }
    final legacyId = data['acceptedDonorId'] as String?;
    if (legacyId == null) return const [];
    return [
      AcceptedDonor(
        id: legacyId,
        name: data['acceptedDonorName'] as String? ?? 'Donor',
        acceptedAt:
            (data['createdAt'] as fs.Timestamp?)?.toDate() ?? DateTime.now(),
      ),
    ];
  }

  Map<String, DonorPing> _liveLocationsFromData(Map<String, dynamic> data) {
    final raw = (data['donorLiveLocations'] as Map?)?.cast<String, dynamic>();
    if (raw != null) {
      return {
        for (final entry in raw.entries)
          if (_pointFromMap(entry.value as Map?) case final point?)
            entry.key: DonorPing(
              point: point,
              at:
                  ((entry.value as Map)['at'] as fs.Timestamp?)?.toDate() ??
                  DateTime.now(),
              transitStatus: DonorTransitStatus.values.byNameOr(
                (entry.value as Map)['transitStatus'] as String?,
                DonorTransitStatus.onTheWay,
              ),
              headingDegrees: ((entry.value as Map)['heading'] as num?)
                  ?.toDouble(),
            ),
      };
    }
    // Legacy single-donor shape.
    final point = _pointFromMap(data['donorLiveLocation'] as Map?);
    final donorId = data['acceptedDonorId'] as String?;
    if (point == null || donorId == null) return const {};
    return {
      donorId: DonorPing(
        point: point,
        at:
            (data['donorLiveLocationAt'] as fs.Timestamp?)?.toDate() ??
            DateTime.now(),
      ),
    };
  }

  DonorPing? _requesterLiveLocationFromData(Map<String, dynamic> data) {
    final raw = data['requesterLiveLocation'] as Map?;
    if (raw == null) return null;
    final point = _pointFromMap(raw);
    if (point == null) return null;
    return DonorPing(
      point: point,
      at: (raw['at'] as fs.Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> _destinationToMap(Destination d) => {
    'name': d.name,
    'address': d.address,
    'wardOrContact': d.wardOrContact,
    'location': _pointToMap(d.location),
  };

  Map<String, dynamic>? _pointToMap(GeoPoint? p) =>
      p == null ? null : {'lat': p.lat, 'lng': p.lng};

  GeoPoint? _pointFromMap(Map? m) => m == null
      ? null
      : GeoPoint((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());

  Map<String, dynamic> _eventToMap(
    RequestStatus s,
    DateTime at,
    String? note,
  ) => {'status': s.name, 'at': fs.Timestamp.fromDate(at), 'note': note};

  StatusEvent _eventFromMap(Map<String, dynamic> m) => StatusEvent(
    status: RequestStatus.values.byNameOr(
      m['status'] as String?,
      RequestStatus.created,
    ),
    at: (m['at'] as fs.Timestamp).toDate(),
    note: m['note'] as String?,
  );

  double _haversineKm(GeoPoint a, GeoPoint b) {
    const r = 6371.0;
    final dLat = _deg2rad(b.lat - a.lat);
    final dLng = _deg2rad(b.lng - a.lng);
    final lat1 = _deg2rad(a.lat);
    final lat2 = _deg2rad(b.lat);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.pow(math.sin(dLng / 2), 2) * math.cos(lat1) * math.cos(lat2);
    return r * 2 * math.asin(math.sqrt(h));
  }

  double _deg2rad(double d) => d * (math.pi / 180.0);
}

extension _ByNameOr<T extends Enum> on List<T> {
  T byNameOr(String? name, T fallback) {
    if (name == null) return fallback;
    for (final v in this) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}
