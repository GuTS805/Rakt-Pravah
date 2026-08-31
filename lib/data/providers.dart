import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/location_service.dart';
import 'mock/mock_backend.dart';
import 'models/models.dart';

/// Single access point to the (mock) backend.
final backendProvider = Provider<MockBackend>((ref) => MockBackend.instance);

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

  MockBackend get _backend => ref.read(backendProvider);

  /// Called by the splash once startup work (config, session restore) is done.
  /// No session is persisted in the mock, so this resolves to unauthenticated.
  void finishStartup() {
    if (state.status == AuthStatus.unknown) {
      state = const AuthState(AuthStatus.unauthenticated);
    }
  }

  Future<void> login({required String phone}) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final user = UserProfile(
      id: 'user_me',
      name: 'Alok Sharma',
      bloodGroup: BloodGroup.oPos,
      phone: phone,
      email: 'alok@example.com',
      city: 'Bengaluru',
      lastDonation: DateTime.now().subtract(const Duration(days: 96)),
    );
    _backend.seedForUser(user);
    state = AuthState(AuthStatus.authenticated, user);
  }

  Future<void> register({
    required String name,
    required String phone,
    required BloodGroup bloodGroup,
    String? city,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final user = UserProfile(
      id: 'user_me',
      name: name,
      bloodGroup: bloodGroup,
      phone: phone,
      city: city,
    );
    _backend.seedForUser(user);
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
    final user = state.user;
    if (user == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final updated = UserProfile(
      id: user.id,
      name: name,
      bloodGroup: bloodGroup,
      phone: user.phone,
      email: user.email,
      city: city,
      lastDonation: user.lastDonation,
      isAdmin: user.isAdmin,
    );
    _backend.currentUser = updated;
    // Keep donor blood group in sync with the profile.
    await _backend.setDonorProfile(
        _backend.donorProfile.copyWith(bloodGroup: bloodGroup));
    state = AuthState(AuthStatus.authenticated, updated);
  }

  void logout() {
    _backend.reset();
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
// Invitations (donor opportunities)
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
    // Keep Donor Mode's location flag in sync with the real permission state.
    final backend = ref.read(backendProvider);
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
