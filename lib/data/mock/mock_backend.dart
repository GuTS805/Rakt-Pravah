import 'dart:async';
import 'dart:math';

import '../models/models.dart';

/// In-memory stand-in for the real FastAPI + PostGIS backend.
///
/// It deliberately mimics backend behavior the UI must react to:
///  - a request moves CREATED -> SEARCHING on its own,
///  - donors are "contacted" progressively in widening waves,
///  - a donor eventually accepts, flipping the request to DONOR_ACCEPTED ->
///    COORDINATING, and the requester's screen updates live via the stream.
///
/// The backend — not any local toggle — remains the source of truth. Every
/// screen listens to these streams and reconciles. Swapping to the real API
/// means reimplementing this class against HTTP + WebSockets; the models and
/// stream shapes stay identical.
class MockBackend {
  MockBackend._();
  static final MockBackend instance = MockBackend._();

  final _rng = Random();

  // ---- Session / profile ------------------------------------------------
  UserProfile? currentUser;

  DonorProfile donorProfile = const DonorProfile(
    availability: DonorAvailability.off,
    bloodGroup: BloodGroup.oPos,
    totalDonations: 4,
  );
  final _donorController = StreamController<DonorProfile>.broadcast();
  Stream<DonorProfile> get donorStream => _donorController.stream;

  // ---- Requests ---------------------------------------------------------
  final Map<String, BloodRequest> _requests = {};
  final _requestsController = StreamController<List<BloodRequest>>.broadcast();
  final Map<String, StreamController<BloodRequest>> _requestControllers = {};
  final Map<String, Timer> _requestTimers = {};

  Stream<List<BloodRequest>> get myRequestsStream =>
      _requestsController.stream;

  List<BloodRequest> get myRequestsSnapshot {
    final list = _requests.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Stream<BloodRequest> requestStream(String id) {
    final c = _requestControllers.putIfAbsent(
        id, () => StreamController<BloodRequest>.broadcast());
    // Emit the current snapshot on subscribe so screens render immediately.
    scheduleMicrotask(() {
      final r = _requests[id];
      if (r != null && c.hasListener) c.add(r);
    });
    return c.stream;
  }

  BloodRequest? request(String id) => _requests[id];

  // ---- Invitations (donor side) ----------------------------------------
  final Map<String, Invitation> _invitations = {};
  final _invitationsController = StreamController<List<Invitation>>.broadcast();

  Stream<List<Invitation>> get invitationsStream =>
      _invitationsController.stream;

  List<Invitation> get invitationsSnapshot {
    final list = _invitations.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  // ---- Chat -------------------------------------------------------------
  final Map<String, List<ChatMessage>> _chats = {};
  final Map<String, StreamController<List<ChatMessage>>> _chatControllers = {};

  Stream<List<ChatMessage>> chatStream(String requestId) {
    final c = _chatControllers.putIfAbsent(
        requestId, () => StreamController<List<ChatMessage>>.broadcast());
    scheduleMicrotask(() => c.add(List.of(_chats[requestId] ?? const [])));
    return c.stream;
  }

  // =======================================================================
  // Seeding
  // =======================================================================
  void seedForUser(UserProfile user) {
    currentUser = user;
    if (_seeded) return;
    _seeded = true;

    donorProfile = donorProfile.copyWith(bloodGroup: user.bloodGroup);

    // A couple of past requests so history isn't empty.
    final past = BloodRequest(
      id: 'req_past_1',
      requesterId: user.id,
      requesterName: user.name,
      bloodGroup: BloodGroup.oPos,
      units: 2,
      urgency: Urgency.urgent,
      status: RequestStatus.fulfilled,
      createdAt: DateTime.now().subtract(const Duration(days: 12)),
      destination: const Destination(
        name: 'City General Hospital',
        address: 'MG Road, Bengaluru',
        wardOrContact: 'Ward 3B',
      ),
      requestLocationLabel: 'MG Road, Bengaluru',
      donorsContacted: 7,
      acceptedDonorName: 'Rahul M.',
      acceptedDonorId: 'donor_x',
      timeline: [
        StatusEvent(
            status: RequestStatus.created,
            at: DateTime.now().subtract(const Duration(days: 12, minutes: 40))),
        StatusEvent(
            status: RequestStatus.fulfilled,
            at: DateTime.now().subtract(const Duration(days: 12))),
      ],
    );
    _requests[past.id] = past;
    _emitRequests();

    // Seed some donor opportunities (visible once Donor Mode is on).
    _seedInvitations();
  }

  bool _seeded = false;

  void _seedInvitations() {
    final samples = [
      Invitation(
        id: 'inv_1',
        requestId: 'req_remote_1',
        bloodGroup: BloodGroup.oPos,
        units: 2,
        urgency: Urgency.critical,
        distanceKm: 3.2,
        status: InvitationStatus.pending,
        destinationName: 'City General Hospital',
        destinationArea: 'Indiranagar',
        createdAt: DateTime.now().subtract(const Duration(minutes: 6)),
        expiresAt: DateTime.now().add(const Duration(minutes: 24)),
      ),
      Invitation(
        id: 'inv_2',
        requestId: 'req_remote_2',
        bloodGroup: BloodGroup.oNeg,
        units: 1,
        urgency: Urgency.urgent,
        distanceKm: 7.8,
        status: InvitationStatus.pending,
        destinationName: 'St. John\'s Medical',
        destinationArea: 'Koramangala',
        createdAt: DateTime.now().subtract(const Duration(minutes: 18)),
        expiresAt: DateTime.now().add(const Duration(minutes: 42)),
      ),
    ];
    for (final i in samples) {
      _invitations[i.id] = i;
    }
    _emitInvitations();
  }

  // =======================================================================
  // Donor Mode
  // =======================================================================
  Future<DonorProfile> setDonorProfile(DonorProfile next) async {
    await _latency();
    donorProfile = next;
    _donorController.add(donorProfile);
    return donorProfile;
  }

  // =======================================================================
  // Requests
  // =======================================================================
  Future<BloodRequest> createRequest({
    required BloodGroup bloodGroup,
    required int units,
    required Urgency urgency,
    required String requestLocationLabel,
    required Destination destination,
    GeoPoint? requestLocation,
  }) async {
    await _latency();
    final user = currentUser!;
    final id = 'req_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();
    final req = BloodRequest(
      id: id,
      requesterId: user.id,
      requesterName: user.name,
      bloodGroup: bloodGroup,
      units: units,
      urgency: urgency,
      status: RequestStatus.created,
      createdAt: now,
      destination: destination,
      requestLocationLabel: requestLocationLabel,
      requestLocation: requestLocation,
      searchRadiusKm: 5,
      expiresAt: now.add(const Duration(hours: 6)),
      timeline: [StatusEvent(status: RequestStatus.created, at: now)],
    );
    _requests[id] = req;
    _emitRequests();
    _emitRequest(req);
    _driveLifecycle(id);
    return req;
  }

  Future<void> cancelRequest(String id) async {
    await _latency();
    final req = _requests[id];
    if (req == null || req.status.isTerminal) return;
    _requestTimers.remove(id)?.cancel();
    _transition(id, RequestStatus.cancelled, note: 'Cancelled by requester');
  }

  Future<void> markFulfilled(String id) async {
    await _latency();
    final req = _requests[id];
    if (req == null || req.status.isTerminal) return;
    _requestTimers.remove(id)?.cancel();
    _transition(id, RequestStatus.fulfilled, note: 'Marked fulfilled');
  }

  /// Scripted progression that mimics the backend matching worker so the
  /// tracking screen updates live in a demo without a server.
  void _driveLifecycle(String id) {
    // CREATED -> SEARCHING
    _requestTimers[id] = Timer(const Duration(milliseconds: 1400), () {
      _transition(id, RequestStatus.searching, note: 'Searching for donors');
      _runWaves(id, contacted: 0, wave: 1);
    });
  }

  void _runWaves(String id, {required int contacted, required int wave}) {
    final req = _requests[id];
    if (req == null || req.status != RequestStatus.searching) return;

    final added = 1 + _rng.nextInt(3);
    final nextContacted = contacted + added;
    final radius = (4 + wave * 3).toDouble();

    _requests[id] = req.copyWith(
      donorsContacted: nextContacted,
      currentWave: wave,
      searchRadiusKm: radius,
    );
    _emitRequest(_requests[id]!);
    _emitRequests();

    // A donor accepts once enough donors have been contacted.
    if (nextContacted >= 4 + _rng.nextInt(2)) {
      _requestTimers[id] =
          Timer(const Duration(milliseconds: 2600), () => _donorAccepts(id));
      return;
    }

    _requestTimers[id] = Timer(
      Duration(milliseconds: 2200 + _rng.nextInt(1600)),
      () => _runWaves(id, contacted: nextContacted, wave: wave + 1),
    );
  }

  void _donorAccepts(String id) {
    final req = _requests[id];
    if (req == null || req.status != RequestStatus.searching) return;
    _requests[id] = req.copyWith(
      acceptedDonorName: 'Aisha K.',
      acceptedDonorId: 'donor_aisha',
    );
    _transition(id, RequestStatus.donorAccepted,
        note: 'Aisha K. accepted your request');
    // Coordination opens shortly after acceptance.
    _requestTimers[id] = Timer(const Duration(milliseconds: 1600), () {
      _transition(id, RequestStatus.coordinating,
          note: 'Coordination started');
      _seedCoordinationMessage(id);
    });
  }

  void _seedCoordinationMessage(String id) {
    final req = _requests[id];
    if (req == null) return;
    final msg = ChatMessage(
      id: 'm_${DateTime.now().millisecondsSinceEpoch}',
      requestId: id,
      senderId: req.acceptedDonorId ?? 'donor',
      senderName: req.acceptedDonorName ?? 'Donor',
      text: 'Hi, I can donate. On my way to ${req.destination.name}.',
      sentAt: DateTime.now(),
    );
    _chats.putIfAbsent(id, () => []).add(msg);
    _emitChat(id);
  }

  void _transition(String id, RequestStatus status, {String? note}) {
    final req = _requests[id];
    if (req == null) return;
    final events = List<StatusEvent>.of(req.timeline)
      ..add(StatusEvent(status: status, at: DateTime.now(), note: note));
    _requests[id] = req.copyWith(status: status, timeline: events);
    _emitRequest(_requests[id]!);
    _emitRequests();
  }

  // =======================================================================
  // Invitations
  // =======================================================================
  Future<void> respondToInvitation(String id, InvitationStatus status) async {
    await _latency();
    final inv = _invitations[id];
    if (inv == null) return;
    _invitations[id] = inv.copyWith(status: status);
    _emitInvitations();

    // Accepting opens a coordination context. Synthesize the request the donor
    // is now helping with, so the coordination + chat routes work end-to-end.
    if (status == InvitationStatus.accepted) {
      _createCoordinationForAcceptedInvitation(inv);
    }
  }

  void _createCoordinationForAcceptedInvitation(Invitation inv) {
    final user = currentUser!;
    final now = DateTime.now();
    final req = BloodRequest(
      id: inv.requestId,
      requesterId: 'requester_remote',
      requesterName: 'Requester',
      bloodGroup: inv.bloodGroup,
      units: inv.units,
      urgency: inv.urgency,
      status: RequestStatus.coordinating,
      createdAt: inv.createdAt,
      destination: Destination(
        name: inv.destinationName,
        address: inv.destinationArea,
      ),
      requestLocationLabel: inv.destinationArea,
      acceptedDonorName: user.name,
      acceptedDonorId: user.id,
      donorsContacted: 1,
      timeline: [
        StatusEvent(status: RequestStatus.created, at: inv.createdAt),
        StatusEvent(
            status: RequestStatus.searching,
            at: inv.createdAt.add(const Duration(minutes: 1))),
        StatusEvent(
            status: RequestStatus.donorAccepted,
            at: now,
            note: 'You accepted this request'),
        StatusEvent(
            status: RequestStatus.coordinating,
            at: now,
            note: 'Coordination started'),
      ],
    );
    _requests[req.id] = req;
    _emitRequest(req);
    _emitRequests();

    final msg = ChatMessage(
      id: 'm_${now.millisecondsSinceEpoch}',
      requestId: req.id,
      senderId: 'requester_remote',
      senderName: 'Requester',
      text:
          'Thank you so much for accepting. We\'re at ${inv.destinationName}.',
      sentAt: now,
    );
    _chats.putIfAbsent(req.id, () => []).add(msg);
    _emitChat(req.id);
  }

  Invitation? invitation(String id) => _invitations[id];

  // =======================================================================
  // Chat
  // =======================================================================
  Future<ChatMessage> sendMessage(String requestId, String text) async {
    final user = currentUser!;
    final optimistic = ChatMessage(
      id: 'local_${DateTime.now().microsecondsSinceEpoch}',
      requestId: requestId,
      senderId: user.id,
      senderName: user.name,
      text: text,
      sentAt: DateTime.now(),
      pending: true,
    );
    _chats.putIfAbsent(requestId, () => []).add(optimistic);
    _emitChat(requestId);

    await _latency();
    final list = _chats[requestId]!;
    final idx = list.indexWhere((m) => m.id == optimistic.id);
    if (idx != -1) list[idx] = optimistic.copyWith(pending: false);
    _emitChat(requestId);
    return list[idx];
  }

  // =======================================================================
  // Emit helpers
  // =======================================================================
  void _emitRequests() => _requestsController.add(myRequestsSnapshot);
  void _emitRequest(BloodRequest r) => _requestControllers[r.id]?.add(r);
  void _emitInvitations() =>
      _invitationsController.add(invitationsSnapshot);
  void _emitChat(String requestId) => _chatControllers[requestId]
      ?.add(List.of(_chats[requestId] ?? const []));

  Future<void> _latency() =>
      Future<void>.delayed(Duration(milliseconds: 350 + _rng.nextInt(400)));

  /// Reset for logout.
  void reset() {
    for (final t in _requestTimers.values) {
      t.cancel();
    }
    _requestTimers.clear();
    _requests.clear();
    _invitations.clear();
    _chats.clear();
    currentUser = null;
    _seeded = false;
    donorProfile = const DonorProfile(
      availability: DonorAvailability.off,
      bloodGroup: BloodGroup.oPos,
      totalDonations: 4,
    );
  }
}
