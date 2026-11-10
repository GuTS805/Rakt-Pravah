import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart' show LocationPermission;

import 'package:rakt_pravah/core/services/location_service.dart';
import 'package:rakt_pravah/core/services/photo_picker.dart';
import 'package:rakt_pravah/data/backend.dart';
import 'package:rakt_pravah/data/models/models.dart';

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
  final _Replay<bool> _canAct = _Replay(true);

  // --- What the UI asked us to do, for assertions ------------------------

  final List<DonorProfile> setDonorProfileCalls = [];
  final List<String> cancelledRequestIds = [];
  final List<String> fulfilledRequestIds = [];
  final List<String> withdrawnRequestIds = [];
  final List<String> extendedRequestIds = [];
  final List<(String, InvitationStatus)> invitationResponses = [];
  final Map<String, String> passwords = {};
  final Map<String, UserProfile> registeredUsers = {};
  bool sessionExpired = false;
  final List<String> passwordResetEmails = [];
  final Map<String, String> patientNames = {};
  final List<(String, GeoPoint)> liveLocationUpdates = [];
  final List<String> stoppedLiveLocationIds = [];
  final List<String> sentMessages = [];
  final List<String> viewedInvitationRequestIds = [];
  final List<(String, double)> expandedRadiusCalls = [];
  List<MatchedDonor>? customMatchedDonors;

  /// Makes the nearby donor list fail, as it does for a requester when the
  /// rules keep donor profiles private.
  Object? nearbyDonorsError;
  int createRequestCalls = 0;

  /// Makes the next accept lose the race, the way a real transaction does
  /// when another donor got there first.
  bool failNextInvitationResponse = false;

  /// Thrown (once) by the next respondToInvitation, whatever it is.
  Object? invitationResponseError;

  // --- Test-side controls ------------------------------------------------

  void emitRequests(List<BloodRequest> next) => _requests.value = next;
  void emitInvitations(List<Invitation> next) => _invitations.value = next;
  void emitDonor(DonorProfile next) => _donor.value = next;

  /// Flips whether the account may act, as verifying its phone would.
  void emitCanAct(bool next) => _canAct.value = next;

  /// Numbers a code was texted to, in order.
  final List<String> phoneCodesSentTo = [];

  /// The code the fake SMS carries.
  String phoneCode = '123456';

  /// Thrown (once) by the next sendPhoneCode.
  Object? sendPhoneCodeError;

  /// The next sendPhoneCode verifies without a code, as Android can.
  bool verifyWithoutCode = false;

  /// The password deleteAccount accepts.
  String accountPassword = 'secret123';

  /// True once the account has been deleted.
  bool accountDeleted = false;

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
  Future<DonorProfile> recordDonation([DateTime? donatedAt]) async {
    final when = donatedAt ?? DateTime.now();
    final isCooldownOn = cooldownConfig.enabled;
    final updated = donorProfile.copyWith(
      availability: isCooldownOn ? DonorAvailability.off : donorProfile.availability,
      lastDonation: when,
      totalDonations: donorProfile.totalDonations + 1,
      cooldownConfig: cooldownConfig,
    );
    setDonorProfileCalls.add(updated);
    _donor.value = updated;
    return updated;
  }

  @override
  Future<DonorProfile> resetDonationCooldown() async {
    final updated = donorProfile.copyWith(
      availability: DonorAvailability.available,
      clearLastDonation: true,
      totalDonations: donorProfile.totalDonations > 0
          ? donorProfile.totalDonations - 1
          : 0,
    );
    setDonorProfileCalls.add(updated);
    _donor.value = updated;
    return updated;
  }

  final List<String> registeredFcmTokens = [];
  final List<String> unregisteredFcmTokens = [];

  @override
  Future<void> registerFcmToken(String token) async {
    registeredFcmTokens.add(token);
  }

  @override
  Future<void> unregisterFcmToken(String token) async {
    unregisteredFcmTokens.add(token);
  }

  final _cooldownConfig = _Replay(const CooldownConfig());

  @override
  CooldownConfig get cooldownConfig => _cooldownConfig.value;

  @override
  Stream<CooldownConfig> get cooldownConfigStream => _cooldownConfig.stream;

  void emitCooldownConfig(CooldownConfig config) {
    _cooldownConfig.value = config;
    var updated = _donor.value.copyWith(cooldownConfig: config);
    if (!config.enabled &&
        updated.availability == DonorAvailability.off &&
        updated.lastDonation != null) {
      updated = updated.copyWith(availability: DonorAvailability.available);
    } else if (config.enabled &&
        updated.isInCooldown &&
        updated.availability != DonorAvailability.off) {
      updated = updated.copyWith(availability: DonorAvailability.off);
    }
    _donor.value = updated;
    donorProfile = updated;
  }

  @override
  Stream<List<BloodRequest>> get myRequestsStream => _requests.stream;

  /// How many times the invitation query was (re)built.
  int invitationsStreamReads = 0;

  @override
  Stream<List<Invitation>> get invitationsStream {
    invitationsStreamReads++;
    return _invitations.stream;
  }

  @override
  Stream<String?> patientNameStream(String id) =>
      Stream.value(patientNames[id]);

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
    String? bloodType,
    String? phoneCountryCode,
    String? phone,
    DateTime? requiredDate,
    String? notes,
    String? city,
    String? state,
  }) async {
    createRequestCalls++;
    patientNames['req-$createRequestCalls'] = patientName;
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

    final created = BloodRequest(
      id: 'req-$createRequestCalls',
      requesterId: uid,
      requesterName: currentUser?.name ?? 'Tester',
      requesterPhoto: currentUser?.photo,
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
      bloodType: bloodType ?? 'Blood',
      phoneCountryCode: effectivePhoneCountryCode,
      phone: effectivePhone,
      requiredDate: requiredDate,
      notes: notes,
    );
    _requests.value = [..._requests.value, created];
    return created;
  }

  @override
  Future<void> cancelRequest(String id) async {
    cancelledRequestIds.add(id);
    _requests.value = [
      for (final r in _requests.value)
        if (r.id == id)
          r.copyWith(
            status: RequestStatus.cancelled,
            donorLiveLocations: const {},
            requesterLiveLocation: null,
          )
        else
          r,
    ];
  }

  @override
  Future<void> markFulfilled(String id) async {
    fulfilledRequestIds.add(id);
    _requests.value = [
      for (final r in _requests.value)
        if (r.id == id)
          r.copyWith(
            status: RequestStatus.fulfilled,
            donorLiveLocations: const {},
            requesterLiveLocation: null,
          )
        else
          r,
    ];
  }

  @override
  Future<void> withdrawFromRequest(String id) async =>
      withdrawnRequestIds.add(id);

  @override
  Future<void> extendRequest(String id) async => extendedRequestIds.add(id);

  @override
  Stream<List<MatchedDonor>> nearbyDonorsStream(String requestId) {
    if (nearbyDonorsError != null) return Stream.error(nearbyDonorsError!);
    if (customMatchedDonors != null) {
      return Stream.value(customMatchedDonors!);
    }
    final req = _requests.value.where((r) => r.id == requestId).firstOrNull;
    final maxRadius = req?.searchRadiusKm ?? 25.0;

    final defaults = [
      MatchedDonor(
        id: 'donor-1',
        name: 'Aarav Sharma',
        bloodGroup: BloodGroup.oPos,
        distanceKm: 1.2,
        status: (req?.acceptedDonorIds.contains('donor-1') ?? false)
            ? DonorRequestInteractionStatus.accepted
            : DonorRequestInteractionStatus.notified,
        phone: '+91 98765 43210',
        notifiedAt: DateTime.now().subtract(const Duration(minutes: 15)),
      ),
      MatchedDonor(
        id: 'donor-2',
        name: 'Priya Patel',
        bloodGroup: BloodGroup.oPos,
        distanceKm: 2.8,
        status: (req?.acceptedDonorIds.contains('donor-2') ?? false)
            ? DonorRequestInteractionStatus.accepted
            : (req?.viewedByDonorIds.contains('donor-2') ?? false)
            ? DonorRequestInteractionStatus.viewed
            : DonorRequestInteractionStatus.notified,
        phone: '+91 98765 43211',
        notifiedAt: DateTime.now().subtract(const Duration(minutes: 12)),
      ),
      MatchedDonor(
        id: 'donor-3',
        name: 'Rahul Verma',
        bloodGroup: BloodGroup.aPos,
        distanceKm: 5.4,
        status: DonorRequestInteractionStatus.notified,
        phone: '+91 98765 43212',
        notifiedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      ),
      MatchedDonor(
        id: 'donor-4',
        name: 'Ananya Rao',
        bloodGroup: BloodGroup.oNeg,
        distanceKm: 9.7,
        status: DonorRequestInteractionStatus.notified,
        phone: '+91 98765 43213',
        notifiedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
      MatchedDonor(
        id: 'donor-5',
        name: 'Vikram Singh',
        bloodGroup: BloodGroup.bPos,
        distanceKm: 18.5,
        status: DonorRequestInteractionStatus.notified,
        phone: '+91 98765 43214',
        notifiedAt: DateTime.now().subtract(const Duration(minutes: 2)),
      ),
    ];

    // Filter by radius and sort nearest first
    final filtered = defaults.where((d) => d.distanceKm <= maxRadius).toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return Stream.value(filtered);
  }

  @override
  Future<void> markInvitationViewed(String requestId) async {
    viewedInvitationRequestIds.add(requestId);
    _requests.value = [
      for (final r in _requests.value)
        if (r.id == requestId && !r.viewedByDonorIds.contains(uid))
          r.copyWith(viewedByDonorIds: [...r.viewedByDonorIds, uid])
        else
          r,
    ];
  }

  @override
  Future<void> expandSearchRadius(String requestId, double newRadiusKm) async {
    expandedRadiusCalls.add((requestId, newRadiusKm));
    _requests.value = [
      for (final r in _requests.value)
        if (r.id == requestId) r.copyWith(searchRadiusKm: newRadiusKm) else r,
    ];
  }

  @override
  Future<void> respondToInvitation(String id, InvitationStatus status) async {
    final error = invitationResponseError;
    if (error != null) {
      invitationResponseError = null;
      throw error;
    }
    if (failNextInvitationResponse) {
      failNextInvitationResponse = false;
      throw StateError('another donor accepted first');
    }
    invitationResponses.add((id, status));
    _invitations.value = [
      for (final i in _invitations.value)
        if (i.id == id) i.copyWith(status: status) else i,
    ];
    if (status == InvitationStatus.accepted) {
      final inv = _invitations.value.where((i) => i.id == id).firstOrNull;
      final targetReqId = inv?.requestId ?? id;
      _requests.value = [
        for (final r in _requests.value)
          if (r.id == targetReqId)
            r.copyWith(
              status: RequestStatus.donorAccepted,
              acceptedDonors: [
                ...r.acceptedDonors,
                AcceptedDonor(
                  id: uid,
                  name: currentUser?.name ?? 'Donor',
                  bloodGroup: currentUser?.bloodGroup ?? BloodGroup.aPos,
                  bloodType: r.bloodType,
                  phone: currentUser?.phone,
                  distanceKm: inv?.distanceKm ?? 2.4,
                  location: myLocation,
                  status: 'Accepted',
                  transitStatus: DonorTransitStatus.accepted,
                  isVerified: true,
                  isDonorModeOn: true,
                  acceptedAt: DateTime.now(),
                ),
              ],
              timeline: [
                ...r.timeline,
                StatusEvent(
                  status: RequestStatus.donorAccepted,
                  at: DateTime.now(),
                  note:
                      '${currentUser?.name ?? "Donor"} accepted your blood request',
                ),
              ],
            )
          else
            r,
      ];
    }
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
  Future<void> updateLiveLocation(
    String requestId,
    GeoPoint point, {
    DonorTransitStatus? transitStatus,
    double? headingDegrees,
    bool isRequester = false,
  }) async {
    liveLocationUpdates.add((requestId, point));
    final previous = _requests.value
        .where((r) => r.id == requestId)
        .firstOrNull
        ?.donorLiveLocations[uid]
        ?.transitStatus;
    final ping = DonorPing(
      point: point,
      at: DateTime.now(),
      transitStatus:
          transitStatus ?? previous ?? DonorTransitStatus.accepted,
      headingDegrees: headingDegrees,
    );
    _requests.value = [
      for (final r in _requests.value)
        if (r.id == requestId)
          isRequester
              ? r.copyWith(requesterLiveLocation: ping)
              : r.copyWith(
                  donorLiveLocations: {...r.donorLiveLocations, uid: ping},
                )
        else
          r,
    ];
  }

  @override
  Future<void> updateDonorTransitStatus(
    String requestId,
    DonorTransitStatus status,
  ) async {
    _requests.value = [
      for (final r in _requests.value)
        if (r.id == requestId)
          r.copyWith(
            donorLiveLocations: {
              for (final entry in r.donorLiveLocations.entries)
                entry.key: DonorPing(
                  point: entry.value.point,
                  at: entry.value.at,
                  transitStatus: entry.key == uid
                      ? status
                      : entry.value.transitStatus,
                  headingDegrees: entry.value.headingDegrees,
                ),
            },
          )
        else
          r,
    ];
  }

  @override
  Future<void> stopLiveLocation(
    String requestId, {
    bool isRequester = false,
  }) async {
    stoppedLiveLocationIds.add(requestId);
    _requests.value = [
      for (final r in _requests.value)
        if (r.id == requestId)
          isRequester
              ? r.copyWith(requesterLiveLocation: null)
              : r.copyWith(
                  donorLiveLocations: {
                    for (final entry in r.donorLiveLocations.entries)
                      if (entry.key != uid) entry.key: entry.value,
                  },
                )
        else
          r,
    ];
  }

  @override
  Future<UserProfile> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (registeredUsers.isNotEmpty &&
        !registeredUsers.containsKey(email) &&
        !passwords.containsKey(email)) {
      throw const SignInFailure('Wrong email or password.');
    }
    if (passwords.containsKey(email) && passwords[email] != password) {
      throw const SignInFailure('Wrong email or password.');
    }
    if (!passwords.containsKey(email) && currentUser == null) {
      throw const SignInFailure('Wrong email or password.');
    }
    final user =
        registeredUsers[email] ??
        currentUser ??
        UserProfile(
          id: 'fake-uid',
          name: email.split('@').first,
          bloodGroup: BloodGroup.oPos,
          phone: '',
        );
    final signedIn = user.copyWith(email: email);
    currentUser = signedIn;
    return signedIn;
  }

  @override
  Future<UserProfile?> restoreSession() async =>
      sessionExpired ? null : currentUser;

  /// Set to make the next password reset fail.
  Object? passwordResetError;

  @override
  Future<void> sendPasswordReset(String email) async {
    final error = passwordResetError;
    if (error != null) throw error;
    passwordResetEmails.add(email);
  }

  @override
  bool get isDeviceOnlyAccount => currentUser?.email == null;

  @override
  Future<UserProfile> addPasswordSignIn({
    required String email,
    required String password,
  }) async {
    passwords[email] = password;
    return signInWithPassword(email: email, password: password);
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
    final phoneError = PhoneUtils.validate(cleanCode, cleanPhone);
    if (phoneError != null) {
      throw ArgumentError(phoneError);
    }

    passwords[email] = password;
    final user = UserProfile(
      id: 'fake-uid-${registeredUsers.length + 1}',
      name: name,
      bloodGroup: bloodGroup,
      phone: cleanPhone,
      countryCode: cleanCode,
      countryIsoCode: countryIsoCode ?? 'IN',
      email: email,
      dateOfBirth: dateOfBirth,
      gender: gender,
      country: country,
      state: state,
      stateCode: stateCode,
      city: city,
      latitude: latitude,
      longitude: longitude,
      isAdmin: false,
    );
    registeredUsers[email] = user;
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
    String? countryIsoCode,
    required String state,
    String? stateCode,
    required String city,
    double? latitude,
    double? longitude,
    String? phone,
    String? countryCode,
  }) async {
    final user = currentUser!;
    final effectiveCode =
        (countryCode != null && countryCode.trim().isNotEmpty)
            ? countryCode.trim()
            : user.countryCode;
    final effectivePhone = (phone != null && phone.trim().isNotEmpty)
        ? PhoneUtils.cleanDigits(phone)
        : user.phone;

    if (effectivePhone.isNotEmpty) {
      final phoneError = PhoneUtils.validate(effectiveCode, effectivePhone);
      if (phoneError != null) {
        throw ArgumentError(phoneError);
      }
    }

    currentUser = UserProfile(
      id: user.id,
      name: name,
      bloodGroup: bloodGroup,
      phone: effectivePhone,
      countryCode: effectiveCode,
      countryIsoCode: countryIsoCode ?? user.countryIsoCode ?? 'IN',
      email: user.email,
      dateOfBirth: dateOfBirth,
      gender: gender,
      country: country,
      state: state,
      stateCode: stateCode ?? user.stateCode,
      city: city,
      latitude: latitude ?? user.latitude,
      longitude: longitude ?? user.longitude,
      lastDonation: user.lastDonation,
      isAdmin: user.isAdmin,
      photo: user.photo,
      phoneVerified: user.phoneVerified,
    );
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
      phoneVerified: user.phoneVerified,
    );

    final currentRequests = _requests.value;
    final updated = [
      for (final r in currentRequests)
        if (r.requesterId == user.id)
          r.copyWith(requesterPhoto: photo)
        else
          r,
    ];
    _requests.value = updated;
  }

  @override
  Stream<bool> get canActStream => _canAct.stream;

  @override
  Future<PhoneCodeSent?> sendPhoneCode(
    String phoneNumber, {
    PhoneCodeSent? resend,
  }) async {
    final error = sendPhoneCodeError;
    if (error != null) {
      sendPhoneCodeError = null;
      throw error;
    }
    phoneCodesSentTo.add(phoneNumber);
    if (verifyWithoutCode) {
      _verify(phoneNumber);
      return null;
    }
    return PhoneCodeSent(
      phoneNumber: phoneNumber,
      verificationId: 'verification-${phoneCodesSentTo.length}',
      resendToken: phoneCodesSentTo.length,
    );
  }

  @override
  Future<UserProfile> confirmPhoneCode(PhoneCodeSent sent, String code) async {
    if (code != phoneCode) {
      throw const PhoneVerificationFailure(
        'That code is wrong. Check the SMS and try again.',
      );
    }
    return _verify(sent.phoneNumber);
  }

  UserProfile _verify(String phoneNumber) {
    final parsed = PhoneUtils.parse(phoneNumber);
    final user = currentUser!.copyWith(
      countryCode: parsed.countryCode,
      phone: parsed.phone,
      phoneVerified: true,
    );
    currentUser = user;
    _canAct.value = true;
    return user;
  }

  @override
  Future<void> signOut() async => currentUser = null;

  /// Reports filed, as (detail, requestId, userId).
  final List<(String, String?, String?)> reports = [];

  @override
  Future<void> fileReport({
    required String detail,
    String? requestId,
    String? userId,
  }) async => reports.add((detail, requestId, userId));

  @override
  Future<void> deleteAccount({String? password}) async {
    if (!isDeviceOnlyAccount && password != accountPassword) {
      throw const AccountDeletionFailure('That password is wrong.');
    }
    accountDeleted = true;
    currentUser = null;
  }
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

/// Camera and gallery without a device: hands back whatever [next] holds, and
/// remembers which source it was asked for.
class FakePhotoPicker implements PhotoPicker {
  String? next;
  final asked = <PhotoSource>[];

  @override
  Future<String?> pick(PhotoSource source) async {
    asked.add(source);
    return next;
  }
}
