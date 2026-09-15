import 'models/models.dart';

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

  /// Adopts an existing profile found by phone number. Null when no account
  /// has that number — there is no account-creation fallback here.
  Future<UserProfile?> loginByPhone(String phone);

  Future<UserProfile> register({
    required String name,
    required String phone,
    required BloodGroup bloodGroup,
    String? city,
  });

  Future<void> updateProfile({
    required String name,
    required BloodGroup bloodGroup,
    String? city,
  });

  Future<void> signOut();

  // --- Email verification ------------------------------------------------

  Future<void> sendVerificationEmailLink(String email);

  bool isEmailSignInLink(String link);

  /// Completes verification for a link the user opened, attaching the proven
  /// email to their account.
  Future<UserProfile> completeEmailLinkVerification({
    required String email,
    required String link,
  });

  // --- Donor Mode --------------------------------------------------------

  Stream<DonorProfile> get donorStream;

  Future<DonorProfile> setDonorProfile(DonorProfile next);

  // --- Requests ----------------------------------------------------------

  Stream<List<BloodRequest>> get myRequestsStream;

  Stream<BloodRequest> requestStream(String id);

  Future<BloodRequest> createRequest({
    required List<BloodGroup> bloodGroups,
    required int units,
    required Urgency urgency,
    required String requestLocationLabel,
    required Destination destination,
    GeoPoint? requestLocation,
  });

  Future<void> cancelRequest(String id);

  Future<void> markFulfilled(String id);

  // --- Invitations (the donor side of a request) -------------------------

  Stream<List<Invitation>> get invitationsStream;

  /// Accepting is a race: only the first donor wins, and the loser gets an
  /// error rather than a silent no-op.
  Future<void> respondToInvitation(String id, InvitationStatus status);

  // --- Coordination ------------------------------------------------------

  Stream<List<ChatMessage>> chatStream(String requestId);

  Future<ChatMessage> sendMessage(String requestId, String text);

  Future<void> updateLiveLocation(String requestId, GeoPoint point);

  Future<void> stopLiveLocation(String requestId);
}
