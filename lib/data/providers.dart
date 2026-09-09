import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/location_service.dart';
import 'firebase/firebase_backend.dart';
import 'models/models.dart';

/// Single access point to the backend — Firebase (Firestore + Anonymous
/// Auth). Screens never talk to Firestore directly; everything goes through
/// this provider so the data layer stays swappable.
final backendProvider =
    Provider<FirebaseBackend>((ref) => FirebaseBackend.instance);

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------
enum AuthStatus { unknown, unauthenticated, needsOnboarding, authenticated }

class AuthState {
  const AuthState(this.status, [this.user]);
  final AuthStatus status;
  final UserProfile? user;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState(AuthStatus.unknown);

  FirebaseBackend get _backend => ref.read(backendProvider);

  /// Called by the splash once startup work is done. Restores a session
  /// already active on this device (Firebase Anonymous Auth persists
  /// locally), so a returning user skips straight past Login.
  Future<void> finishStartup() async {
    if (state.status != AuthStatus.unknown) return;
    final user = await _backend.restoreSession();
    state = user == null
        ? const AuthState(AuthStatus.unauthenticated)
        : AuthState(AuthStatus.authenticated, user);
  }

  /// Returns false if no account exists for that phone number — there is no
  /// account-recovery flow here (login only ever finds an existing profile
  /// by phone; it never fabricates one), so the caller must handle that.
  Future<bool> login({required String phone}) async {
    final user = await _backend.loginByPhone(phone);
    if (user == null) return false;
    state = AuthState(AuthStatus.authenticated, user);
    return true;
  }

  Future<void> register({
    required String name,
    required String phone,
    required BloodGroup bloodGroup,
    String? city,
  }) async {
    final user = await _backend.register(
      name: name,
      phone: phone,
      bloodGroup: bloodGroup,
      city: city,
    );
    state = AuthState(AuthStatus.needsOnboarding, user);
  }

  void completeOnboarding() {
    final user = state.user;
    if (user != null) state = AuthState(AuthStatus.authenticated, user);
  }

  Future<void> updateProfile({
    required String name,
    required BloodGroup bloodGroup,
    String? city,
  }) async {
    if (state.user == null) return;
    await _backend.updateProfile(name: name, bloodGroup: bloodGroup, city: city);
    state = AuthState(AuthStatus.authenticated, _backend.currentUser);
  }

  /// Sends the passwordless sign-in link — the user must already have a
  /// session (registered or restored) before verifying an email onto it.
  Future<void> sendEmailVerification(String email) =>
      _backend.sendVerificationEmailLink(email);

  bool isEmailVerificationLink(String link) =>
      _backend.isEmailSignInLink(link);

  /// Completes verification once the user taps the emailed link. Keeps
  /// whatever onboarding/authenticated status the user was already in —
  /// this only ever refreshes `emailVerified`, it doesn't change where they
  /// are in the signup flow.
  Future<void> completeEmailVerification({
    required String email,
    required String link,
  }) async {
    final user = await _backend.completeEmailLinkVerification(
        email: email, link: link);
    state = AuthState(state.status, user);
  }

  Future<void> logout() async {
    await _backend.signOut();
    state = const AuthState(AuthStatus.unauthenticated);
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

final currentUserProvider = Provider<UserProfile?>(
    (ref) => ref.watch(authControllerProvider).user);

// ---------------------------------------------------------------------------
// Theme mode
// ---------------------------------------------------------------------------
final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;
  void set(ThemeMode mode) => state = mode;
  void toggle() => state =
      state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
}

// ---------------------------------------------------------------------------
// Donor Mode
// ---------------------------------------------------------------------------
final donorProfileProvider = StreamProvider<DonorProfile>((ref) {
  final backend = ref.watch(backendProvider);
  return backend.donorStream;
});

/// Synchronous view of donor state with the seeded default as fallback.
final donorProfileValueProvider = Provider<DonorProfile>((ref) {
  final backend = ref.watch(backendProvider);
  return ref.watch(donorProfileProvider).maybeWhen(
        data: (d) => d,
        orElse: () => backend.donorProfile,
      );
});

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------
final myRequestsProvider = StreamProvider<List<BloodRequest>>((ref) {
  final backend = ref.watch(backendProvider);
  return backend.myRequestsStream;
});

/// Live stream of a single request (auto-updating tracking screen).
final requestProvider =
    StreamProvider.family<BloodRequest, String>((ref, id) {
  final backend = ref.watch(backendProvider);
  return backend.requestStream(id);
});

/// The user's currently active request, if any (drives the Home dashboard).
final activeRequestProvider = Provider<BloodRequest?>((ref) {
  final requests = ref.watch(myRequestsProvider).valueOrNull ?? const [];
  for (final r in requests) {
    if (r.status.isActive) return r;
  }
  return null;
});

// ---------------------------------------------------------------------------
// Invitations (donor opportunities) — derived live from compatible open
// requests via Firestore queries (spec §23), not a scripted mock.
// ---------------------------------------------------------------------------
final invitationsProvider = StreamProvider<List<Invitation>>((ref) {
  final backend = ref.watch(backendProvider);
  return backend.invitationsStream;
});

/// Pending invitations only — what a donor is asked to act on now.
final pendingInvitationsProvider = Provider<List<Invitation>>((ref) {
  final all = ref.watch(invitationsProvider).valueOrNull ?? const [];
  return all.where((i) => i.status == InvitationStatus.pending).toList();
});

/// The invitation the user has accepted, if any — drives the "active donation"
/// card on Home and the donor coordination entry point.
final acceptedInvitationProvider = Provider<Invitation?>((ref) {
  final all = ref.watch(invitationsProvider).valueOrNull ?? const [];
  for (final i in all) {
    if (i.status == InvitationStatus.accepted) return i;
  }
  return null;
});

// ---------------------------------------------------------------------------
// Device location (real GPS + permission — not demo data)
// ---------------------------------------------------------------------------
final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

enum DeviceLocationStatus { unknown, requesting, granted, denied, deniedForever, serviceDisabled }

class DeviceLocationState {
  const DeviceLocationState({
    this.status = DeviceLocationStatus.unknown,
    this.point,
    this.label,
  });

  final DeviceLocationStatus status;
  final GeoPoint? point;
  final String? label;

  bool get isGranted => status == DeviceLocationStatus.granted && point != null;

  DeviceLocationState copyWith(
          {DeviceLocationStatus? status, GeoPoint? point, String? label}) =>
      DeviceLocationState(
        status: status ?? this.status,
        point: point ?? this.point,
        label: label ?? this.label,
      );
}

/// Real device location state. Backed entirely by the OS location permission
/// and GPS/network position via [LocationService] — nothing here is mocked.
class DeviceLocationController extends Notifier<DeviceLocationState> {
  @override
  DeviceLocationState build() => const DeviceLocationState();

  LocationService get _service => ref.read(locationServiceProvider);

  /// Silently checks current permission/position without prompting, so the UI
  /// can reflect real state on first load without surprising the user with a
  /// system dialog.
  Future<void> refreshSilently() async {
    final result = await _service.getLocationIfPermitted();
    _apply(result);
  }

  /// Prompts the OS permission dialog (if not yet decided) and fetches the
  /// real position on success.
  Future<DeviceLocationState> request() async {
    state = state.copyWith(status: DeviceLocationStatus.requesting);
    final result = await _service.requestAndGetLocation();
    _apply(result);
    return state;
  }

  void _apply(LocationResult result) {
    state = switch (result) {
      LocationGranted(:final point, :final label) => DeviceLocationState(
          status: DeviceLocationStatus.granted, point: point, label: label),
      LocationDenied() =>
        state.copyWith(status: DeviceLocationStatus.denied),
      LocationDeniedForever() =>
        state.copyWith(status: DeviceLocationStatus.deniedForever),
      LocationServiceDisabled() =>
        state.copyWith(status: DeviceLocationStatus.serviceDisabled),
    };
    // Keep Donor Mode's location flag, and the backend's cached position used
    // to compute invitation distances, in sync with the real permission state.
    final backend = ref.read(backendProvider);
    backend.myLocation = state.point;
    if (backend.currentUser != null) {
      backend.setDonorProfile(
          backend.donorProfile.copyWith(locationGranted: state.isGranted));
    }
  }
}

final deviceLocationProvider =
    NotifierProvider<DeviceLocationController, DeviceLocationState>(
        DeviceLocationController.new);

// ---------------------------------------------------------------------------
// Chat
// ---------------------------------------------------------------------------
final chatProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, requestId) {
  final backend = ref.watch(backendProvider);
  return backend.chatStream(requestId);
});
