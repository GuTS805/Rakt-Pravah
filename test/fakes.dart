import 'dart:async';

import 'package:geolocator/geolocator.dart' show LocationPermission;

import 'package:bloodlink/core/services/location_service.dart';
import 'package:bloodlink/data/backend.dart';
import 'package:bloodlink/data/models/models.dart';

/// Holds a current value and replays it to every new listener, so a widget
/// that subscribes after the fact still sees the present state instead of
/// waiting for the next change. Firestore snapshot streams behave this way;
/// a plain broadcast controller does not.
class _Replay<T> {
  _Replay(this._value);

  T _value;
  final _open = <StreamController<T>>[];

  T get value => _value;

  set value(T next) {
    _value = next;
    for (final c in List.of(_open)) {
      if (!c.isClosed) c.add(next);
    }
  }

  Stream<T> get stream {
    late final StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () => controller.add(_value),
      onCancel: () => _open.remove(controller),
    );
    _open.add(controller);
    return controller.stream;
  }
}

/// An in-memory [Backend] for tests: no Firebase, no network, no emulator.
/// Screens run against this exactly as they would against Firestore, and
/// tests drive it by mutating the seeded state or asserting on what the UI
/// asked it to do.
class FakeBackend implements Backend {
  FakeBackend({
    UserProfile? user,
    DonorProfile? donor,
    List<BloodRequest> requests = const [],
    List<Invitation> invitations = const [],
  }) : currentUser = user,
       _donor = _Replay(
         donor ??
             const DonorProfile(
               availability: DonorAvailability.off,
               bloodGroup: BloodGroup.oPos,
             ),
       ),
       _requests = _Replay(requests),
       _invitations = _Replay(invitations);

  @override
  UserProfile? currentUser;

  @override
  GeoPoint? myLocation;

  final _Replay<DonorProfile> _donor;
  final _Replay<List<BloodRequest>> _requests;
  final _Replay<List<Invitation>> _invitations;

  // --- What the UI asked us to do, for assertions ------------------------

  final List<DonorProfile> setDonorProfileCalls = [];
  final List<String> cancelledRequestIds = [];
  final List<String> fulfilledRequestIds = [];
  final List<String> withdrawnRequestIds = [];
  final List<String> extendedRequestIds = [];
  final List<(String, InvitationStatus)> invitationResponses = [];
  final List<String> sentVerificationEmails = [];
  final List<(String, GeoPoint)> liveLocationUpdates = [];
  final List<String> stoppedLiveLocationIds = [];
  final List<String> sentMessages = [];
  int createRequestCalls = 0;

  /// Makes the next accept lose the race, the way a real transaction does
  /// when another donor got there first.
  bool failNextInvitationResponse = false;

  // --- Test-side controls ------------------------------------------------

  void emitRequests(List<BloodRequest> next) => _requests.value = next;
  void emitInvitations(List<Invitation> next) => _invitations.value = next;
  void emitDonor(DonorProfile next) => _donor.value = next;

  // --- Backend -----------------------------------------------------------

  @override
  String get uid => currentUser?.id ?? 'fake-uid';

  @override
  DonorProfile get donorProfile => _donor.value;

  @override
  set donorProfile(DonorProfile value) => _donor.value = value;

  @override
  Stream<DonorProfile> get donorStream => _donor.stream;

  @override
  Future<DonorProfile> setDonorProfile(DonorProfile next) async {
    setDonorProfileCalls.add(next);
    _donor.value = next;
    return next;
  }

  @override
  Stream<List<BloodRequest>> get myRequestsStream => _requests.stream;

  @override
  Stream<List<Invitation>> get invitationsStream => _invitations.stream;

  @override
  Stream<BloodRequest> requestStream(String id) =>
      _requests.stream.map((all) => all.firstWhere((r) => r.id == id));

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
    createRequestCalls++;
    final created = BloodRequest(
      id: 'req-$createRequestCalls',
      requesterId: uid,
      requesterName: currentUser?.name ?? 'Tester',
      patientName: patientName,
      patientBloodGroup: patientBloodGroup,
      bloodGroups: bloodGroups,
      units: units,
      urgency: urgency,
      status: RequestStatus.searching,
      createdAt: DateTime.now(),
      destination: destination,
      requestLocationLabel: requestLocationLabel,
      requestLocation: requestLocation,
    );
    _requests.value = [..._requests.value, created];
    return created;
  }

  @override
  Future<void> cancelRequest(String id) async => cancelledRequestIds.add(id);

  @override
  Future<void> markFulfilled(String id) async => fulfilledRequestIds.add(id);

  @override
  Future<void> withdrawFromRequest(String id) async =>
      withdrawnRequestIds.add(id);

  @override
  Future<void> extendRequest(String id) async => extendedRequestIds.add(id);

  @override
  Future<void> respondToInvitation(String id, InvitationStatus status) async {
    if (failNextInvitationResponse) {
      failNextInvitationResponse = false;
      throw StateError('another donor accepted first');
    }
    invitationResponses.add((id, status));
    _invitations.value = [
      for (final i in _invitations.value)
        if (i.id == id) i.copyWith(status: status) else i,
    ];
  }

  @override
  Stream<List<ChatMessage>> chatStream(String requestId) =>
      Stream.value(const []);

  @override
  Future<ChatMessage> sendMessage(String requestId, String text) async {
    sentMessages.add(text);
    return ChatMessage(
      id: 'msg-${sentMessages.length}',
      requestId: requestId,
      senderId: uid,
      senderName: currentUser?.name ?? 'Tester',
      text: text,
      sentAt: DateTime.now(),
    );
  }

  @override
  Future<void> updateLiveLocation(String requestId, GeoPoint point) async =>
      liveLocationUpdates.add((requestId, point));

  @override
  Future<void> stopLiveLocation(String requestId) async =>
      stoppedLiveLocationIds.add(requestId);

  @override
  Future<void> sendVerificationEmailLink(String email) async =>
      sentVerificationEmails.add(email);

  @override
  bool isEmailSignInLink(String link) => link.contains('mode=signIn');

  @override
  Future<UserProfile> completeEmailLinkVerification({
    required String email,
    required String link,
  }) async {
    final user = currentUser!;
    final signedIn = UserProfile(
      id: user.id,
      name: user.name,
      bloodGroup: user.bloodGroup,
      phone: user.phone,
      email: email,
      dateOfBirth: user.dateOfBirth,
      gender: user.gender,
      country: user.country,
      state: user.state,
      city: user.city,
      lastDonation: user.lastDonation,
      isAdmin: user.isAdmin,
    );
    currentUser = signedIn;
    return signedIn;
  }

  @override
  Future<UserProfile?> restoreSession() async => currentUser;

  @override
  Future<UserProfile?> loginByPhone(String phone) async =>
      currentUser?.phone == phone ? currentUser : null;

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
    final user = UserProfile(
      id: 'fake-uid',
      name: name,
      bloodGroup: bloodGroup,
      phone: phone,
      dateOfBirth: dateOfBirth,
      gender: gender,
      country: country,
      state: state,
      city: city,
    );
    currentUser = user;
    return user;
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
    final user = currentUser!;
    currentUser = UserProfile(
      id: user.id,
      name: name,
      bloodGroup: bloodGroup,
      phone: user.phone,
      email: user.email,
      dateOfBirth: dateOfBirth,
      gender: gender,
      country: country,
      state: state,
      city: city,
      lastDonation: user.lastDonation,
      isAdmin: user.isAdmin,
    );
  }

  @override
  Future<void> signOut() async => currentUser = null;
}

/// Location without the platform. Real [LocationService] calls Geolocator
/// statics, which have no implementation in a widget test — this returns a
/// canned result instead so screens that ask for location still build.
class FakeLocationService implements LocationService {
  FakeLocationService({this.result = const LocationDenied()});

  final LocationResult result;
  int requestCalls = 0;

  @override
  Future<LocationResult> requestAndGetLocation() async {
    requestCalls++;
    return result;
  }

  @override
  Future<LocationResult> getLocationIfPermitted() async => result;

  @override
  Future<GeoPoint?> forwardGeocode(String address) async => null;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> openLocationSettings() async {}

  @override
  Future<LocationPermission> checkPermission() async =>
      result is LocationGranted
      ? LocationPermission.whileInUse
      : LocationPermission.denied;
}
