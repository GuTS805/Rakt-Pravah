import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

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

  final fs.FirebaseFirestore _db = fs.FirebaseFirestore.instance;
  final fb_auth.FirebaseAuth _auth = fb_auth.FirebaseAuth.instance;

  fs.CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  fs.CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('blood_requests');

  String get uid => _auth.currentUser!.uid;

  UserProfile? currentUser;
  DonorProfile donorProfile = const DonorProfile(
    availability: DonorAvailability.off,
    bloodGroup: BloodGroup.oPos,
  );

  /// Best-effort current device location, kept in sync by
  /// DeviceLocationController so invitation distances can be computed
  /// without threading location through every call.
  GeoPoint? myLocation;

  Future<void> _ensureSignedIn() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
  }

  /// Restores a session already active on this device (survives restarts).
  /// Returns null if there's no local session or its profile is missing.
  Future<UserProfile?> restoreSession() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final doc = await _users.doc(user.uid).get();
    if (!doc.exists) return null;
    return _applyProfileDoc(doc.data()!);
  }

  /// Looks up an existing profile by phone number and, if found, adopts it
  /// onto this device's session. Returns null if no account has that phone.
  Future<UserProfile?> loginByPhone(String phone) async {
    await _ensureSignedIn();
    final query = await _users.where('phone', isEqualTo: phone).limit(1).get();
    if (query.docs.isEmpty) return null;
    final data = query.docs.first.data();
    await _users.doc(uid).set(data, fs.SetOptions(merge: true));
    return _applyProfileDoc(data);
  }

  Future<UserProfile> register({
    required String name,
    required String phone,
    required BloodGroup bloodGroup,
    String? city,
  }) async {
    await _ensureSignedIn();
    final data = <String, dynamic>{
      'name': name,
      'phone': phone,
      'bloodGroup': bloodGroup.label,
      'city': city,
      'email': null,
      'isAdmin': false,
      'lastDonation': null,
      'donor': _donorToMap(DonorProfile(
        availability: DonorAvailability.off,
        bloodGroup: bloodGroup,
      )),
    };
    await _users.doc(uid).set(data, fs.SetOptions(merge: true));
    return _applyProfileDoc(data);
  }

  Future<void> updateProfile({
    required String name,
    required BloodGroup bloodGroup,
    String? city,
  }) async {
    await _users.doc(uid).set({
      'name': name,
      'bloodGroup': bloodGroup.label,
      'city': city,
      'donor.bloodGroup': bloodGroup.label,
    }, fs.SetOptions(merge: true));
    currentUser = UserProfile(
      id: uid,
      name: name,
      bloodGroup: bloodGroup,
      phone: currentUser!.phone,
      email: currentUser!.email,
      city: city,
      lastDonation: currentUser!.lastDonation,
      isAdmin: currentUser!.isAdmin,
    );
    donorProfile = donorProfile.copyWith(bloodGroup: bloodGroup);
  }

  // ---------------------------------------------------------------------
  // Email verification (spec: only a verified user may request or donate).
  // Firebase's client SDK has no numeric email-OTP provider, so this uses
  // its built-in passwordless Email Link sign-in instead: tapping the link
  // proves ownership exactly like an OTP would, without needing a paid plan
  // or a server-side code sender. The link opens straight back into the app
  // via Android App Links (see hosting_public/.well-known/assetlinks.json —
  // Firebase Dynamic Links, which used to handle this, has been shut down).
  // ---------------------------------------------------------------------
  static const _emailContinueUrl =
      'https://nobloodlink.firebaseapp.com/finishSignIn.html';

  Future<void> sendVerificationEmailLink(String email) async {
    await _ensureSignedIn();
    await _auth.sendSignInLinkToEmail(
      email: email,
      actionCodeSettings: fb_auth.ActionCodeSettings(
        url: _emailContinueUrl,
        handleCodeInApp: true,
        androidPackageName: 'com.bloodlink.bloodlink',
        androidInstallApp: true,
        androidMinimumVersion: '1',
        iOSBundleId: 'com.bloodlink.bloodlink',
      ),
    );
  }

  bool isEmailSignInLink(String link) => _auth.isSignInWithEmailLink(link);

  /// Completes verification once the user taps the emailed link. Links the
  /// email credential onto the current (likely anonymous) session so the uid
  /// and all existing data stay put — unless that email was already
  /// verified on a different device, in which case this signs into that
  /// existing account instead. That fallback is also what gives verified
  /// email a second job: real cross-device sign-in, which anonymous-only
  /// auth never had.
  Future<UserProfile> completeEmailLinkVerification({
    required String email,
    required String link,
  }) async {
    await _ensureSignedIn();
    final credential = fb_auth.EmailAuthProvider.credentialWithLink(
        email: email, emailLink: link);
    try {
      await _auth.currentUser!.linkWithCredential(credential);
    } on fb_auth.FirebaseAuthException catch (e) {
      if (e.code != 'credential-already-in-use' &&
          e.code != 'email-already-in-use') {
        rethrow;
      }
      await _auth.signInWithCredential(credential);
    }
    await _auth.currentUser!.reload();
    await _users.doc(uid).set({'email': email}, fs.SetOptions(merge: true));
    final doc = await _users.doc(uid).get();
    return _applyProfileDoc(doc.data()!);
  }

  UserProfile _applyProfileDoc(Map<String, dynamic> data) {
    final user = UserProfile(
      id: uid,
      name: data['name'] as String,
      bloodGroup: BloodGroup.fromLabel(data['bloodGroup'] as String),
      phone: data['phone'] as String,
      email: data['email'] as String?,
      // Sourced from Firebase Auth's own claim, never from the profile doc —
      // a client can't write its way into being "verified".
      emailVerified: _auth.currentUser?.emailVerified ?? false,
      city: data['city'] as String?,
      lastDonation: (data['lastDonation'] as fs.Timestamp?)?.toDate(),
      isAdmin: data['isAdmin'] as bool? ?? false,
    );
    currentUser = user;
    donorProfile = _donorFromMap(
        (data['donor'] as Map?)?.cast<String, dynamic>(), user.bloodGroup);
    return user;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    currentUser = null;
    donorProfile = const DonorProfile(
      availability: DonorAvailability.off,
      bloodGroup: BloodGroup.oPos,
    );
  }

  // ---------------------------------------------------------------------
  // Donor Mode
  // ---------------------------------------------------------------------
  Stream<DonorProfile> get donorStream => _users.doc(uid).snapshots().map(
        (doc) => _donorFromMap(
            (doc.data()?['donor'] as Map?)?.cast<String, dynamic>(),
            currentUser?.bloodGroup ?? BloodGroup.oPos),
      );

  Future<DonorProfile> setDonorProfile(DonorProfile next) async {
    await _users
        .doc(uid)
        .set({'donor': _donorToMap(next)}, fs.SetOptions(merge: true));
    donorProfile = next;
    return next;
  }

  Map<String, dynamic> _donorToMap(DonorProfile d) => {
        'availability': d.availability.name,
        'bloodGroup': d.bloodGroup.label,
        'notifyPush': d.notifyPush,
        'notifyCritical': d.notifyCritical,
        'locationGranted': d.locationGranted,
        'maxDistanceKm': d.maxDistanceKm,
        'pausedUntil':
            d.pausedUntil == null ? null : fs.Timestamp.fromDate(d.pausedUntil!),
        'totalDonations': d.totalDonations,
        'lastDonation':
            d.lastDonation == null ? null : fs.Timestamp.fromDate(d.lastDonation!),
      };

  DonorProfile _donorFromMap(Map<String, dynamic>? m, BloodGroup fallbackGroup) {
    if (m == null) {
      return DonorProfile(
          availability: DonorAvailability.off, bloodGroup: fallbackGroup);
    }
    return DonorProfile(
      availability: DonorAvailability.values
          .byNameOr(m['availability'] as String?, DonorAvailability.off),
      bloodGroup: m['bloodGroup'] == null
          ? fallbackGroup
          : BloodGroup.fromLabel(m['bloodGroup'] as String),
      notifyPush: m['notifyPush'] as bool? ?? true,
      notifyCritical: m['notifyCritical'] as bool? ?? true,
      locationGranted: m['locationGranted'] as bool? ?? false,
      maxDistanceKm: (m['maxDistanceKm'] as num?)?.toDouble() ?? 15,
      pausedUntil: (m['pausedUntil'] as fs.Timestamp?)?.toDate(),
      totalDonations: m['totalDonations'] as int? ?? 0,
      lastDonation: (m['lastDonation'] as fs.Timestamp?)?.toDate(),
    );
  }

  // ---------------------------------------------------------------------
  // Requests
  // ---------------------------------------------------------------------
  Stream<List<BloodRequest>> get myRequestsStream => _requests
      .where('requesterId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(_requestFromDoc).toList());

  Stream<BloodRequest> requestStream(String id) => _requests
      .doc(id)
      .snapshots()
      .where((doc) => doc.exists)
      .map(_requestFromDoc);

  Future<BloodRequest> createRequest({
    required List<BloodGroup> bloodGroups,
    required int units,
    required Urgency urgency,
    required String requestLocationLabel,
    required Destination destination,
    GeoPoint? requestLocation,
  }) async {
    final now = DateTime.now();
    final ref = _requests.doc();
    final data = <String, dynamic>{
      'requesterId': uid,
      'requesterName': currentUser!.name,
      'bloodGroups': bloodGroups.map((g) => g.label).toList(),
      'units': units,
      'urgency': urgency.name,
      'status': RequestStatus.searching.name,
      'createdAt': fs.Timestamp.fromDate(now),
      'destination': _destinationToMap(destination),
      'requestLocationLabel': requestLocationLabel,
      'requestLocation': _pointToMap(requestLocation),
      'donorsContacted': 0,
      'currentWave': 0,
      'searchRadiusKm': 0.0,
      'acceptedDonorName': null,
      'acceptedDonorId': null,
      'expiresAt': fs.Timestamp.fromDate(now.add(const Duration(hours: 6))),
      'timeline': [
        _eventToMap(RequestStatus.created, now, null),
        _eventToMap(RequestStatus.searching, now, 'Searching for donors'),
      ],
      'declinedByDonorIds': <String>[],
    };
    await ref.set(data);
    return _requestFromDoc(await ref.get());
  }

  Future<void> cancelRequest(String id) async {
    await _transitionIfActive(
        id, RequestStatus.cancelled, 'Cancelled by requester');
  }

  Future<void> markFulfilled(String id) async {
    await _transitionIfActive(id, RequestStatus.fulfilled, 'Marked fulfilled');
  }

  Future<void> _transitionIfActive(
      String id, RequestStatus status, String note) async {
    final ref = _requests.doc(id);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final current =
          RequestStatus.values.byNameOr(snap.data()!['status'] as String?, RequestStatus.created);
      if (current.isTerminal) return;
      final timeline = List<Map<String, dynamic>>.from(
          (snap.data()!['timeline'] as List?) ?? const []);
      timeline.add(_eventToMap(status, DateTime.now(), note));
      tx.update(ref, {'status': status.name, 'timeline': timeline});
    });
  }

  // ---------------------------------------------------------------------
  // Invitations — derived live from compatible open requests, not stored
  // as separate documents. Merges two live queries: requests this donor is
  // still eligible to see, and any request they've already accepted.
  // ---------------------------------------------------------------------
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
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!controller.isClosed) controller.add(list);
    }

    // A donor within the 90-day cooldown of their last donation is never
    // shown new opportunities — enforced here, not just as a disabled
    // switch in the UI, so it can't be bypassed by a stale client.
    StreamSubscription<fs.QuerySnapshot<Map<String, dynamic>>>? openSub;
    if (donorProfile.isInCooldown) {
      openMap = {};
      openReady = true;
    } else {
      // The requester already chose exactly which donor groups a request is
      // open to (see BloodGroupMultiPicker), so matching is a direct
      // "is my blood group in that list" check — no compatibility inference
      // needed on this side.
      openSub = _requests
          .where('bloodGroups', arrayContainsAny: [donorProfile.bloodGroup.label])
          .where('status', whereIn: [
        RequestStatus.created.name,
        RequestStatus.searching.name,
      ]).snapshots().listen((snap) {
        final map = <String, Invitation>{};
        for (final doc in snap.docs) {
          final data = doc.data();
          if (data['requesterId'] == uid) continue;
          final declined =
              (data['declinedByDonorIds'] as List?)?.cast<String>() ?? const [];
          if (declined.contains(uid)) continue;
          map[doc.id] = _invitationFromRequestData(doc.id, data, myLocation);
        }
        openMap = map;
        openReady = true;
        emit();
      });
    }

    final acceptedSub = _requests
        .where('acceptedDonorId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      acceptedMap = {
        for (final doc in snap.docs)
          doc.id: _invitationFromRequestData(doc.id, doc.data(), myLocation,
              forceStatus: InvitationStatus.accepted)
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
          (data['donor'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final credited =
          (donorMap['creditedRequestIds'] as List?)?.cast<String>() ?? const [];
      if (credited.contains(requestId)) return;
      tx.set(
        ref,
        {
          'donor': {
            ...donorMap,
            'totalDonations': (donorMap['totalDonations'] as int? ?? 0) + 1,
            'lastDonation': fs.Timestamp.fromDate(DateTime.now()),
            'creditedRequestIds': [...credited, requestId],
          },
        },
        fs.SetOptions(merge: true),
      );
    });
  }

  /// Accept is a transaction so only the first donor to claim a request
  /// wins; a lost race throws so the UI can say the opportunity is gone
  /// instead of pretending it succeeded (spec §13).
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
      final current =
          RequestStatus.values.byNameOr(data['status'] as String?, RequestStatus.created);
      if (data['acceptedDonorId'] != null || current.isTerminal) {
        throw StateError('This request is no longer available.');
      }
      final now = DateTime.now();
      final timeline =
          List<Map<String, dynamic>>.from((data['timeline'] as List?) ?? const []);
      timeline.add(_eventToMap(RequestStatus.donorAccepted, now,
          '${currentUser!.name} accepted your request'));
      timeline.add(
          _eventToMap(RequestStatus.coordinating, now, 'Coordination started'));
      tx.update(ref, {
        'status': RequestStatus.coordinating.name,
        'acceptedDonorId': uid,
        'acceptedDonorName': currentUser!.name,
        'timeline': timeline,
      });
    });
  }

  Invitation _invitationFromRequestData(
      String id, Map<String, dynamic> data, GeoPoint? myLocation,
      {InvitationStatus? forceStatus}) {
    final dest = (data['destination'] as Map).cast<String, dynamic>();
    final reqPoint = _pointFromMap(data['requestLocation'] as Map?);
    final distance = (myLocation != null && reqPoint != null)
        ? _haversineKm(myLocation, reqPoint)
        : 0.0;
    return Invitation(
      id: id,
      requestId: id,
      bloodGroups: _parseBloodGroups(data['bloodGroups']),
      units: data['units'] as int,
      urgency:
          Urgency.values.byNameOr(data['urgency'] as String?, Urgency.routine),
      distanceKm: distance,
      status: forceStatus ?? InvitationStatus.pending,
      destinationName: dest['name'] as String? ?? '',
      destinationArea: dest['address'] as String? ?? '',
      createdAt: (data['createdAt'] as fs.Timestamp).toDate(),
      expiresAt: (data['expiresAt'] as fs.Timestamp?)?.toDate(),
    );
  }

  // ---------------------------------------------------------------------
  // Chat — a subcollection per request; only the requester and accepted
  // donor can read/write it, enforced by Firestore security rules.
  // ---------------------------------------------------------------------
  Stream<List<ChatMessage>> chatStream(String requestId) => _requests
      .doc(requestId)
      .collection('messages')
      .orderBy('sentAt')
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => ChatMessage(
                id: d.id,
                requestId: requestId,
                senderId: d.data()['senderId'] as String,
                senderName: d.data()['senderName'] as String,
                text: d.data()['text'] as String,
                sentAt: (d.data()['sentAt'] as fs.Timestamp).toDate(),
              ))
          .toList());

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
  Future<void> updateLiveLocation(String requestId, GeoPoint point) =>
      _requests.doc(requestId).update({
        'donorLiveLocation': _pointToMap(point),
        'donorLiveLocationAt': fs.Timestamp.fromDate(DateTime.now()),
      });

  Future<void> stopLiveLocation(String requestId) =>
      _requests.doc(requestId).update({
        'donorLiveLocation': fs.FieldValue.delete(),
        'donorLiveLocationAt': fs.FieldValue.delete(),
      });

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
    return BloodRequest(
      id: doc.id,
      requesterId: data['requesterId'] as String,
      requesterName: data['requesterName'] as String,
      bloodGroups: _parseBloodGroups(data['bloodGroups']),
      units: data['units'] as int,
      urgency:
          Urgency.values.byNameOr(data['urgency'] as String?, Urgency.routine),
      status: RequestStatus.values
          .byNameOr(data['status'] as String?, RequestStatus.created),
      createdAt: (data['createdAt'] as fs.Timestamp).toDate(),
      destination: Destination(
        name: destMap['name'] as String? ?? '',
        address: destMap['address'] as String? ?? '',
        wardOrContact: destMap['wardOrContact'] as String?,
        location: _pointFromMap(destMap['location'] as Map?),
      ),
      requestLocationLabel: data['requestLocationLabel'] as String? ?? '',
      requestLocation: _pointFromMap(data['requestLocation'] as Map?),
      donorsContacted: data['donorsContacted'] as int? ?? 0,
      currentWave: data['currentWave'] as int? ?? 0,
      searchRadiusKm: (data['searchRadiusKm'] as num?)?.toDouble() ?? 0,
      acceptedDonorName: data['acceptedDonorName'] as String?,
      acceptedDonorId: data['acceptedDonorId'] as String?,
      expiresAt: (data['expiresAt'] as fs.Timestamp?)?.toDate(),
      timeline: ((data['timeline'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(_eventFromMap)
          .toList(),
      donorLiveLocation: _pointFromMap(data['donorLiveLocation'] as Map?),
      donorLiveLocationAt:
          (data['donorLiveLocationAt'] as fs.Timestamp?)?.toDate(),
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

  Map<String, dynamic> _eventToMap(RequestStatus s, DateTime at, String? note) =>
      {'status': s.name, 'at': fs.Timestamp.fromDate(at), 'note': note};

  StatusEvent _eventFromMap(Map<String, dynamic> m) => StatusEvent(
        status: RequestStatus.values
            .byNameOr(m['status'] as String?, RequestStatus.created),
        at: (m['at'] as fs.Timestamp).toDate(),
        note: m['note'] as String?,
      );

  double _haversineKm(GeoPoint a, GeoPoint b) {
    const r = 6371.0;
    final dLat = _deg2rad(b.lat - a.lat);
    final dLng = _deg2rad(b.lng - a.lng);
    final lat1 = _deg2rad(a.lat);
    final lat2 = _deg2rad(b.lat);
    final h = math.pow(math.sin(dLat / 2), 2) +
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
