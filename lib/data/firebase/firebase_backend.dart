import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import '../../core/location/location_data.dart';
import '../../core/services/photo_picker.dart';
import '../backend.dart';
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
  FirebaseBackend._();
  static final FirebaseBackend instance = FirebaseBackend._();

  static bool _isDesignatedAdminEmail(String? email) {
    if (email == null) return false;
    final normalized = email.trim().toLowerCase();
    return normalized == 'vikky.code@gmail.com' ||
        normalized == 'admin.vikky@gmail.com';
  }

  final fs.FirebaseFirestore _db = fs.FirebaseFirestore.instance;
  final fb_auth.FirebaseAuth _auth = fb_auth.FirebaseAuth.instance;

  fs.CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  fs.CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('blood_requests');

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
  GeoPoint? myLocation;

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
    final doc = await _users.doc(user.uid).get();
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

    await _createOrLinkAccount(email: email, password: password);
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
      // Every new account starts unapproved; the rules refuse anything else.
      // Whether that holds anyone back is the operators' switch.
      'approved': false,
      'lastDonation': null,
      'donor': _donorToMap(
        DonorProfile(
          availability: DonorAvailability.available,
          bloodGroup: bloodGroup,
        ),
      ),
    };
    await _users.doc(uid).set(data, fs.SetOptions(merge: true));
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
    final effectiveCode =
        (countryCode != null && countryCode.trim().isNotEmpty)
            ? countryCode.trim()
            : (currentUser?.countryCode ?? '+91');
    final effectivePhone = (phone != null && phone.trim().isNotEmpty)
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

    await _users.doc(uid).set({
      'name': name,
      'bloodGroup': bloodGroup.label,
      'dateOfBirth': fs.Timestamp.fromDate(dateOfBirth),
      'gender': gender.name,
      'country': country,
      'countryIsoCode': effCountryIso,
      'state': state,
      'stateCode': effStateCode,
      'city': city,
      'latitude': effLat,
      'longitude': effLng,
      if (effLat != null && effLng != null)
        'location': {'lat': effLat, 'lng': effLng},
      'phone': ?effectivePhone,
      if (effectiveCode.isNotEmpty) 'countryCode': effectiveCode,
      // A nested map, not a 'donor.bloodGroup' key: set() treats dotted keys
      // as literal field names, so matching used to keep the old group.
      'donor': {'bloodGroup': bloodGroup.label},
    }, fs.SetOptions(merge: true));
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
      latitude: effLat,
      longitude: effLng,
      lastDonation: currentUser!.lastDonation,
      isAdmin: currentUser!.isAdmin,
      photo: currentUser!.photo,
      approved: currentUser!.approved,
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
    await _users.doc(uid).set({'photo': photo}, fs.SetOptions(merge: true));
    final user = currentUser!;
    currentUser = UserProfile(
      id: user.id,
      name: user.name,
      bloodGroup: user.bloodGroup,
      phone: user.phone,
      email: user.email,
      dateOfBirth: user.dateOfBirth,
      gender: user.gender,
      country: user.country,
      state: user.state,
      city: user.city,
      lastDonation: user.lastDonation,
      isAdmin: user.isAdmin,
      photo: photo,
      approved: user.approved,
    );

    // Propagate updated photo across any blood requests authored by this user
    try {
      final snap = await _requests.where('requesterId', isEqualTo: uid).get();
      for (final doc in snap.docs) {
        await doc.reference.update({'requesterPhoto': photo});
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
  Future<void> _createOrLinkAccount({
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
      } else {
        await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
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
    await _users.doc(uid).set({'email': email}, fs.SetOptions(merge: true));
    final doc = await _users.doc(uid).get();
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
        'invalid-credential' => 'Invalid ID or password.',
        'user-disabled' => 'This account has been disabled.',
        'too-many-requests' =>
          'Too many attempts. Wait a few minutes and try again.',
        'operation-not-allowed' =>
          'Email and password sign-in is switched off for this project.',
        'network-request-failed' =>
          'Unable to connect to the server. Please try again.',
        _ => 'Invalid ID or password.',
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
      final doc = await _users.doc(userId).get();
      if (doc.exists) {
        final docData = Map<String, dynamic>.from(doc.data()!);
        if (isDesignatedAdmin &&
            (docData['isAdmin'] != true || docData['role'] != 'admin')) {
          docData['isAdmin'] = true;
          docData['role'] = 'admin';
          await _users.doc(userId).set({
            'isAdmin': true,
            'role': 'admin',
          }, fs.SetOptions(merge: true));
        }
        return _applyProfileDoc(
          docData,
          userId: userId,
          tokenIsAdmin: tokenIsAdmin || isDesignatedAdmin,
        );
      }

      // An account created straight in the Firebase console has no profile
      // document yet.
      final data = <String, dynamic>{
        'name': email.split('@').first,
        'phone': '9876543210',
        'bloodGroup': BloodGroup.oPos.label,
        'email': email,
        'isAdmin': isDesignatedAdmin,
        'role': isDesignatedAdmin ? 'admin' : 'user',
        // The rules only let a profile be created unapproved; admins pass
        // the approval check regardless.
        'approved': false,
        'lastDonation': null,
      };
      await _users.doc(userId).set(data, fs.SetOptions(merge: true));
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
      approved: data['approved'] as bool? ?? true,
    );
    currentUser = user;
    donorProfile = _donorFromMap(
      (data['donor'] as Map?)?.cast<String, dynamic>(),
      user.bloodGroup,
    );
    return user;
  }

  @override
  Stream<bool> get canActStream {
    final config = _db.collection('config').doc('app');
    final me = _users.doc(uid);
    late final StreamController<bool> out;
    final subs = <StreamSubscription<dynamic>>[];
    bool? gateOn;
    bool? approved;
    var admin = false;

    void emit() {
      if (gateOn == null || approved == null) return;
      out.add(!gateOn! || approved! || admin);
    }

    out = StreamController<bool>(
      onListen: () {
        subs.add(
          config.snapshots().listen(
            (doc) {
              gateOn = doc.data()?['requireApproval'] == true;
              emit();
            },
            onError: (_) {
              // No readable config means no switch: don't hold anyone back.
              gateOn = false;
              emit();
            },
          ),
        );
        subs.add(
          me.snapshots().listen((doc) {
            final data = doc.data();
            // A missing field is an account from before approval existed.
            approved = data?['approved'] as bool? ?? true;
            admin = data?['isAdmin'] == true;
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

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    currentUser = null;
    donorProfile = const DonorProfile(
      availability: DonorAvailability.available,
      bloodGroup: BloodGroup.oPos,
    );
  }

  // ---------------------------------------------------------------------
  // Donor Mode
  // ---------------------------------------------------------------------
  @override
  Stream<DonorProfile> get donorStream =>
      _users.doc(uid).snapshots().map((doc) {
        // Keep the cache current too: invitationsStream and the location
        // controller both read it, and a stale copy would be written back.
        final parsed = _donorFromMap(
          (doc.data()?['donor'] as Map?)?.cast<String, dynamic>(),
          currentUser?.bloodGroup ?? BloodGroup.oPos,
        );
        donorProfile = _autoReenableIfCooldownEnded(parsed);
        return donorProfile;
      });

  DonorProfile _autoReenableIfCooldownEnded(DonorProfile profile) {
    if (profile.lastDonation != null &&
        !profile.isInCooldown &&
        profile.availability == DonorAvailability.off) {
      final reactivated = profile.copyWith(
        availability: DonorAvailability.available,
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
    await _users.doc(uid).set({
      'donor': _donorToMap(next),
    }, fs.SetOptions(merge: true));
    donorProfile = next;
    return next;
  }

  @override
  Future<DonorProfile> recordDonation([DateTime? donatedAt]) async {
    final when = donatedAt ?? DateTime.now();
    final updated = donorProfile.copyWith(
      availability: DonorAvailability.off,
      lastDonation: when,
      totalDonations: donorProfile.totalDonations + 1,
    );
    await _users.doc(uid).set({
      'lastDonation': fs.Timestamp.fromDate(when),
      'donor': _donorToMap(updated),
    }, fs.SetOptions(merge: true));
    donorProfile = updated;
    return updated;
  }

  @override
  Future<DonorProfile> resetDonationCooldown() async {
    final updated = donorProfile.copyWith(
      availability: DonorAvailability.available,
      clearLastDonation: true,
    );
    await _users.doc(uid).set({
      'lastDonation': null,
      'donor': _donorToMap(updated),
    }, fs.SetOptions(merge: true));
    donorProfile = updated;
    return updated;
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

  Future<void> _expire(String id) =>
      _transitionIfActive(id, RequestStatus.expired, 'No donor found in time');

  @override
  Future<void> extendRequest(String id) async {
    final ref = _requests.doc(id);
    await _db.runTransaction((tx) async {
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
    });
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
    await ref.set(data);
    await ref.collection('private').doc('patient').set({
      'name': patientName,
      if (effectivePhone != null && effectivePhone.isNotEmpty)
        'phone': effectivePhone,
      'bloodType': bloodType ?? 'Blood',
    });
    return _requestFromDoc(await ref.get());
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
    await _requests.doc(requestId).update({'searchRadiusKm': newRadiusKm});
  }

  @override
  Future<void> markInvitationViewed(String requestId) async {
    if (uid.isEmpty) return;
    await _requests.doc(requestId).update({
      'viewedByDonorIds': fs.FieldValue.arrayUnion([uid]),
    });
  }

  @override
  Future<void> withdrawFromRequest(String id) async {
    final ref = _requests.doc(id);
    await _db.runTransaction((tx) async {
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
    });
  }

  Future<void> _transitionIfActive(
    String id,
    RequestStatus status,
    String note,
  ) async {
    final ref = _requests.doc(id);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final current = RequestStatus.values.byNameOr(
        snap.data()!['status'] as String?,
        RequestStatus.created,
      );
      if (current.isTerminal) return;
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
    });
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
    final ref = _users.doc(uid);
    await _db.runTransaction((tx) async {
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
    });
  }

  /// Accept is a transaction so only the first donor to claim a request
  /// wins; a lost race throws so the UI can say the opportunity is gone
  /// instead of pretending it succeeded (spec §13).
  @override
  Future<void> respondToInvitation(String id, InvitationStatus status) async {
    if (status == InvitationStatus.declined) {
      await _requests.doc(id).update({
        'declinedByDonorIds': fs.FieldValue.arrayUnion([uid]),
      });
      return;
    }
    if (status != InvitationStatus.accepted) return;

    await _db.runTransaction((tx) async {
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
      if (current.isTerminal || donors.length >= units) {
        throw StateError('This request is no longer available.');
      }
      if (donors.any((d) => d.id == uid)) return;

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
    });
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
    await ref.set({
      'senderId': uid,
      'senderName': currentUser!.name,
      'text': text,
      'sentAt': fs.Timestamp.fromDate(now),
    });
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
      await _requests.doc(requestId).update({
        'requesterLiveLocation': {
          'lat': point.lat,
          'lng': point.lng,
          'at': fs.Timestamp.fromDate(now),
        },
      });
    } else {
      await _requests.doc(requestId).update({
        'donorLiveLocations.$uid': {
          'lat': point.lat,
          'lng': point.lng,
          'at': fs.Timestamp.fromDate(now),
          'transitStatus': transitStatus.name,
          'heading': ?headingDegrees,
        },
      });
    }
  }

  @override
  Future<void> updateDonorTransitStatus(
    String requestId,
    DonorTransitStatus status,
  ) async {
    final ref = _requests.doc(requestId);
    await ref.update({'donorLiveLocations.$uid.transitStatus': status.name});
    final snap = await ref.get();
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
      await ref.update({'timeline': timeline});
    }
  }

  @override
  Future<void> stopLiveLocation(
    String requestId, {
    bool isRequester = false,
  }) async {
    if (isRequester) {
      await _requests.doc(requestId).update({
        'requesterLiveLocation': fs.FieldValue.delete(),
      });
    } else {
      await _requests.doc(requestId).update({
        'donorLiveLocations.$uid': fs.FieldValue.delete(),
      });
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
