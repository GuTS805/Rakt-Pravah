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

  @override
  String get uid => _auth.currentUser!.uid;

  @override
  UserProfile? currentUser;
  @override
  DonorProfile donorProfile = const DonorProfile(
    availability: DonorAvailability.off,
    bloodGroup: BloodGroup.oPos,
  );

  /// Best-effort current device location, kept in sync by
  /// DeviceLocationController so invitation distances can be computed
  /// without threading location through every call.
  @override
  GeoPoint? myLocation;

  Future<void> _ensureSignedIn() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
  }

  /// Restores a session already active on this device (survives restarts).
  /// Returns null if there's no local session or its profile is missing.
  @override
  Future<UserProfile?> restoreSession() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final doc = await _users.doc(user.uid).get();
    if (!doc.exists) return null;
    return _applyProfileDoc(doc.data()!);
  }

  /// Looks up an existing profile by phone number and, if found, adopts it
  /// onto this device's session. Returns null if no account has that phone.
  @override
  Future<UserProfile?> loginByPhone(String phone) async {
    await _ensureSignedIn();
    final query = await _users.where('phone', isEqualTo: phone).limit(1).get();
    if (query.docs.isEmpty) return null;
    final data = query.docs.first.data();
    await _users.doc(uid).set(data, fs.SetOptions(merge: true));
    return _applyProfileDoc(data);
  }

  @override
  Future<UserProfile> register({
    required String name,
    required String phone,
    required BloodGroup bloodGroup,
    required DateTime dateOfBirth,
    required Gender gender,
    required String country,
    required String state,
    required String city,
  }) async {
    await _ensureSignedIn();
    final data = <String, dynamic>{
      'name': name,
      'phone': phone,
      'bloodGroup': bloodGroup.label,
      'dateOfBirth': fs.Timestamp.fromDate(dateOfBirth),
      'gender': gender.name,
      'country': country,
      'state': state,
      'city': city,
      'email': null,
      'isAdmin': false,
      'lastDonation': null,
      'donor': _donorToMap(
        DonorProfile(
          availability: DonorAvailability.off,
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
    required String state,
    required String city,
  }) async {
    await _users.doc(uid).set({
      'name': name,
      'bloodGroup': bloodGroup.label,
      'dateOfBirth': fs.Timestamp.fromDate(dateOfBirth),
      'gender': gender.name,
      'country': country,
      'state': state,
      'city': city,
      // A nested map, not a 'donor.bloodGroup' key: set() treats dotted keys
      // as literal field names, so matching used to keep the old group.
      'donor': {'bloodGroup': bloodGroup.label},
    }, fs.SetOptions(merge: true));
    currentUser = UserProfile(
      id: uid,
      name: name,
      bloodGroup: bloodGroup,
      phone: currentUser!.phone,
      email: currentUser!.email,
      dateOfBirth: dateOfBirth,
      gender: gender,
      country: country,
      state: state,
      city: city,
      lastDonation: currentUser!.lastDonation,
      isAdmin: currentUser!.isAdmin,
    );
    donorProfile = donorProfile.copyWith(bloodGroup: bloodGroup);
  }

  // ---------------------------------------------------------------------
  // Operator sign-in. Only the admin console uses this: the mobile app runs
  // on anonymous auth and never asks for an email or a password. Operator
  // accounts are created in the Firebase console, and an existing admin
  // grants access from the Users page.
  // ---------------------------------------------------------------------
  @override
  Future<UserProfile> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final fb_auth.UserCredential credential;
    try {
      credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on fb_auth.FirebaseAuthException catch (e) {
      throw SignInFailure(switch (e.code) {
        'invalid-email' => 'That doesn\'t look like an email address.',
        'user-disabled' => 'This account has been disabled.',
        'too-many-requests' =>
          'Too many attempts. Wait a few minutes and try again.',
        'operation-not-allowed' =>
          'Email and password sign-in is switched off for this project.',
        // Firebase deliberately doesn't say which of the two was wrong, and
        // neither do we — that's what stops an attacker probing for emails.
        _ => 'Wrong email or password.',
      });
    }

    final doc = await _users.doc(credential.user!.uid).get();
    if (doc.exists) return _applyProfileDoc(doc.data()!);

    // An account created straight in the Firebase console has no profile
    // document yet. Give it one so the console has a name to show. isAdmin
    // starts false: only an existing admin can grant access.
    final data = <String, dynamic>{
      'name': email.split('@').first,
      'phone': '',
      'bloodGroup': BloodGroup.oPos.label,
      'email': email,
      'isAdmin': false,
      'lastDonation': null,
    };
    await _users.doc(uid).set(data, fs.SetOptions(merge: true));
    return _applyProfileDoc(data);
  }

  UserProfile _applyProfileDoc(Map<String, dynamic> data) {
    final user = UserProfile(
      id: uid,
      name: data['name'] as String,
      bloodGroup: BloodGroup.fromLabel(data['bloodGroup'] as String),
      phone: data['phone'] as String,
      email: data['email'] as String?,
      dateOfBirth: (data['dateOfBirth'] as fs.Timestamp?)?.toDate(),
      gender: Gender.values.asNameMap()[data['gender']],
      country: data['country'] as String?,
      state: data['state'] as String?,
      city: data['city'] as String?,
      lastDonation: (data['lastDonation'] as fs.Timestamp?)?.toDate(),
      isAdmin: data['isAdmin'] as bool? ?? false,
    );
    currentUser = user;
    donorProfile = _donorFromMap(
      (data['donor'] as Map?)?.cast<String, dynamic>(),
      user.bloodGroup,
    );
    return user;
  }

  @override
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
  @override
  Stream<DonorProfile> get donorStream =>
      _users.doc(uid).snapshots().map((doc) {
        // Keep the cache current too: invitationsStream and the location
        // controller both read it, and a stale copy would be written back.
        donorProfile = _donorFromMap(
          (doc.data()?['donor'] as Map?)?.cast<String, dynamic>(),
          currentUser?.bloodGroup ?? BloodGroup.oPos,
        );
        return donorProfile;
      });

  @override
  Future<DonorProfile> setDonorProfile(DonorProfile next) async {
    await _users.doc(uid).set({
      'donor': _donorToMap(next),
    }, fs.SetOptions(merge: true));
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
        availability: DonorAvailability.off,
        bloodGroup: fallbackGroup,
      );
    }
    return DonorProfile(
      availability: DonorAvailability.values.byNameOr(
        m['availability'] as String?,
        DonorAvailability.off,
      ),
      bloodGroup: m['bloodGroup'] == null
          ? fallbackGroup
          : BloodGroup.fromLabel(m['bloodGroup'] as String),
      notifyPush: m['notifyPush'] as bool? ?? true,
      notifyCritical: m['notifyCritical'] as bool? ?? false,
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
  }) async {
    final now = DateTime.now();
    final ref = _requests.doc();
    final data = <String, dynamic>{
      'requesterId': uid,
      'requesterName': currentUser!.name,
      'patientName': patientName,
      'patientBloodGroup': patientBloodGroup.label,
      'bloodGroups': bloodGroups.map((g) => g.label).toList(),
      'units': units,
      'urgency': urgency.name,
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
    };
    await ref.set(data);
    return _requestFromDoc(await ref.get());
  }

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
      tx.update(ref, {'status': status.name, 'timeline': timeline});
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
          'totalDonations': (donorMap['totalDonations'] as int? ?? 0) + 1,
          'lastDonation': fs.Timestamp.fromDate(DateTime.now()),
          'creditedRequestIds': [...credited, requestId],
        },
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
      final next = [
        ...donors,
        AcceptedDonor(id: uid, name: currentUser!.name, acceptedAt: now),
      ];
      // One donor gives one unit, so a request for several units keeps
      // searching until every unit has someone. Only the last acceptance
      // moves it into coordination.
      final full = next.length >= units;
      final timeline = List<Map<String, dynamic>>.from(
        (data['timeline'] as List?) ?? const [],
      );
      timeline.add(
        _eventToMap(
          RequestStatus.donorAccepted,
          now,
          units == 1
              ? '${currentUser!.name} accepted your request'
              : '${currentUser!.name} accepted — ${next.length} of $units units',
        ),
      );
      if (full) {
        timeline.add(
          _eventToMap(RequestStatus.coordinating, now, 'Coordination started'),
        );
      }
      tx.update(ref, {
        'status': full
            ? RequestStatus.coordinating.name
            : RequestStatus.searching.name,
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
  Future<void> updateLiveLocation(String requestId, GeoPoint point) =>
      _requests.doc(requestId).update({
        'donorLiveLocations.$uid': {
          'lat': point.lat,
          'lng': point.lng,
          'at': fs.Timestamp.fromDate(DateTime.now()),
        },
      });

  @override
  Future<void> stopLiveLocation(String requestId) => _requests
      .doc(requestId)
      .update({'donorLiveLocations.$uid': fs.FieldValue.delete()});

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
    );
  }

  Map<String, dynamic> _acceptedDonorToMap(AcceptedDonor d) => {
    'id': d.id,
    'name': d.name,
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
