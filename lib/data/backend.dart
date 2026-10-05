import 'models/models.dart';

/// A sign-in that failed for a reason worth showing someone, already phrased
/// for them. Anything else is a bug and keeps its original exception.
class SignInFailure implements Exception {
  const SignInFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Everything the app is allowed to ask of its data layer.
///
/// Screens and providers depend on this, never on the Firebase implementation,
/// so the whole app can be driven by a fake in tests without a live project,
/// emulator, or network. `FirebaseBackend` is the production implementation;
/// `FakeBackend` in the test tree is the other one.
abstract class Backend {
  /// The signed-in user's id. Throws if called before a session exists —
  /// callers are expected to be past authentication.
  String get uid;

  /// The profile of the signed-in user, cached after the last read. Null
  /// before sign-in or after sign-out.
  UserProfile? get currentUser;
  set currentUser(UserProfile? value);

  /// Donor Mode state for the signed-in user, cached after the last read.
  DonorProfile get donorProfile;
  set donorProfile(DonorProfile value);

  /// Best-effort device position, kept in sync by the location controller so
  /// invitation distances can be computed without threading it through every
  /// call.
  GeoPoint? get myLocation;
  set myLocation(GeoPoint? value);

  // --- Session -----------------------------------------------------------

  /// Restores a session already active on this device. Null when there's no
  /// local session or its profile is missing.
  Future<UserProfile?> restoreSession();

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
  });

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
  });

  /// Sets, or with null removes, the signed-in user's profile photo: a small
  /// base64 JPEG kept on their profile. Requests made afterwards carry a copy.
  Future<void> setProfilePhoto(String? photo);

  /// Whether this account may ask for blood or donate right now. False only
  /// while the operators' approval switch is on and this account hasn't been
  /// approved yet; live, so approval takes effect without restarting the app.
  Stream<bool> get canActStream;

  Future<void> signOut();

  /// Signs in with an email and password. Throws [SignInFailure] when those
  /// don't match an account. Used by the app and by the operations console:
  /// one identity system, and the `isAdmin` flag on the returned profile is
  /// what decides whether the console lets someone in.
  Future<UserProfile> signInWithPassword({
    required String email,
    required String password,
  });

  /// Emails a password reset link. Silent about whether the address has an
  /// account, so this can't be used to find out who is registered.
  Future<void> sendPasswordReset(String email);

  /// Attaches an email and password to an account that doesn't have one, so
  /// it can be signed into again from anywhere. Keeps the same uid, and with
  /// it every request, donation and message the account already has.
  Future<UserProfile> addPasswordSignIn({
    required String email,
    required String password,
  });

  /// True while the signed-in account has no way back in: it exists only on
  /// this device until an email and password are attached.
  bool get isDeviceOnlyAccount;

  // --- Donor Mode --------------------------------------------------------

  Stream<DonorProfile> get donorStream;

  Future<DonorProfile> setDonorProfile(DonorProfile next);

  /// Records that the user donated blood today (or at [donatedAt]).
  /// Automatically turns Donor Mode OFF and starts the 3-month waiting period.
  Future<DonorProfile> recordDonation([DateTime? donatedAt]);

  /// Resets the donation cooldown (clears lastDonation and restores Donor Mode ON).
  Future<DonorProfile> resetDonationCooldown();

  /// Registers an FCM push-notification device token for this account.
  Future<void> registerFcmToken(String token);

  /// Unregisters an FCM device token (e.g. on logout or turning Donor Mode OFF).
  Future<void> unregisterFcmToken(String token);

  /// Live donation cooldown configuration from the platform settings.
  Stream<CooldownConfig> get cooldownConfigStream;

  /// Cached donation cooldown configuration.
  CooldownConfig get cooldownConfig;

  // --- Requests ----------------------------------------------------------

  Stream<List<BloodRequest>> get myRequestsStream;

  Stream<BloodRequest> requestStream(String id);

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
  });

  Future<void> cancelRequest(String id);

  Future<void> markFulfilled(String id);

  /// The patient's name, kept apart from the request itself so that only the
  /// requester and the donors who accepted can read it. Null when it isn't
  /// recorded, and an error when the caller isn't allowed to see it.
  Stream<String?> patientNameStream(String requestId);

  /// Gives a request that ran out of time another six hours.
  Future<void> extendRequest(String id);

  /// An accepted donor backs out. The request goes back to searching so
  /// another donor can pick it up, and this donor won't be offered it again.
  Future<void> withdrawFromRequest(String id);

  /// Live nearby matched donors for a request, ranked nearest distance first.
  Stream<List<MatchedDonor>> nearbyDonorsStream(String requestId);

  /// Expands the search radius for an open request and notifies matching donors.
  Future<void> expandSearchRadius(String requestId, double newRadiusKm);

  // --- Invitations (the donor side of a request) -------------------------

  Stream<List<Invitation>> get invitationsStream;

  /// Marks an invitation as viewed by the signed-in donor.
  Future<void> markInvitationViewed(String requestId);

  /// Accepting is a race: only the first donor wins, and the loser gets an
  /// error rather than a silent no-op.
  Future<void> respondToInvitation(String id, InvitationStatus status);

  // --- Coordination ------------------------------------------------------

  Stream<List<ChatMessage>> chatStream(String requestId);

  Future<ChatMessage> sendMessage(String requestId, String text);

  Future<void> updateLiveLocation(
    String requestId,
    GeoPoint point, {
    DonorTransitStatus transitStatus = DonorTransitStatus.onTheWay,
    double? headingDegrees,
    bool isRequester = false,
  });

  Future<void> updateDonorTransitStatus(
    String requestId,
    DonorTransitStatus status,
  );

  Future<void> stopLiveLocation(String requestId, {bool isRequester = false});
}
