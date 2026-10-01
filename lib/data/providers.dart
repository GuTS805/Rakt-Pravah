import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/location_service.dart';
import '../core/services/photo_picker.dart';
import 'backend.dart';
import 'firebase/firebase_backend.dart';
import 'models/models.dart';

/// Single access point to the backend. Screens never talk to Firestore
/// directly; everything goes through this provider, typed to the [Backend]
/// interface rather than the Firebase implementation, so tests can override
/// it with a fake and drive real screens without a live project.
final backendProvider = Provider<Backend>((ref) => FirebaseBackend.instance);

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

  Backend get _backend => ref.read(backendProvider);

  /// Called by the splash once startup work is done. Restores a session
  /// already active on this device (Firebase Anonymous Auth persists
  /// locally), so a returning user skips straight past Login.
  Future<void> finishStartup() async {
    if (state.status != AuthStatus.unknown) return;
    try {
      final user = await _backend.restoreSession();
      state = user == null
          ? const AuthState(AuthStatus.unauthenticated)
          : AuthState(AuthStatus.authenticated, user);
    } catch (_) {
      state = const AuthState(AuthStatus.unauthenticated);
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String name,
    required String phone,
    required BloodGroup bloodGroup,
    required DateTime dateOfBirth,
    required Gender gender,
    required String country,
    required String state,
    required String city,
  }) async {
    final user = await _backend.register(
      email: email,
      password: password,
      name: name,
      phone: phone,
      bloodGroup: bloodGroup,
      dateOfBirth: dateOfBirth,
      gender: gender,
      country: country,
      state: state,
      city: city,
    );
    this.state = AuthState(AuthStatus.needsOnboarding, user);
  }

  void completeOnboarding() {
    final user = state.user;
    if (user != null) state = AuthState(AuthStatus.authenticated, user);
  }

  Future<void> updateProfile({
    required String name,
    required BloodGroup bloodGroup,
    required DateTime dateOfBirth,
    required Gender gender,
    required String country,
    required String state,
    required String city,
  }) async {
    if (this.state.user == null) return;
    await _backend.updateProfile(
      name: name,
      bloodGroup: bloodGroup,
      dateOfBirth: dateOfBirth,
      gender: gender,
      country: country,
      state: state,
      city: city,
    );
    this.state = AuthState(AuthStatus.authenticated, _backend.currentUser);
  }

  /// Sets, or with null removes, the profile photo.
  Future<void> setPhoto(String? photo) async {
    if (state.user == null) return;
    await _backend.setProfilePhoto(photo);
    state = AuthState(AuthStatus.authenticated, _backend.currentUser);
  }

  /// Signs in with an email and password, in the app and in the console
  /// alike. Throws [SignInFailure] with something worth showing when the
  /// credentials don't match.
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final user = await _backend.signInWithPassword(
      email: email,
      password: password,
    );
    state = AuthState(AuthStatus.authenticated, user);
  }

  Future<void> sendPasswordReset(String email) =>
      _backend.sendPasswordReset(email);

  /// True for an account that exists only on this device — made before the
  /// app asked for an email, so there is no way to sign back into it.
  bool get isDeviceOnlyAccount => _backend.isDeviceOnlyAccount;

  /// Gives a device-only account a way back in, keeping everything it has.
  Future<void> addPasswordSignIn({
    required String email,
    required String password,
  }) async {
    final user = await _backend.addPasswordSignIn(
      email: email,
      password: password,
    );
    state = AuthState(state.status, user);
  }

  Future<void> logout() async {
    await _backend.signOut();
    state = const AuthState(AuthStatus.unauthenticated);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

final currentUserProvider = Provider<UserProfile?>(
  (ref) => ref.watch(authControllerProvider).user,
);

// ---------------------------------------------------------------------------
// Theme mode
// ---------------------------------------------------------------------------
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  static const _preferenceKey = 'bloodlink_appearance_theme_mode';

  @override
  ThemeMode build() {
    unawaited(_restore());
    return ThemeMode.system;
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final savedMode = preferences.getString(_preferenceKey);
    final modes = ThemeMode.values.where((mode) => mode.name == savedMode);
    if (modes.isNotEmpty) state = modes.first;
  }

  void set(ThemeMode mode) {
    state = mode;
    unawaited(_persist(mode));
  }

  Future<void> _persist(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, mode.name);
  }

  void toggle() =>
      set(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}

// ---------------------------------------------------------------------------
// Time & Clock
// ---------------------------------------------------------------------------
/// Live clock that emits the current local DateTime every second.
final currentTimeProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
});

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
  return ref
      .watch(donorProfileProvider)
      .maybeWhen(data: (d) => d, orElse: () => backend.donorProfile);
});

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------
final myRequestsProvider = StreamProvider<List<BloodRequest>>((ref) {
  final backend = ref.watch(backendProvider);
  return backend.myRequestsStream;
});

/// The patient's name on a request, which only its requester and accepted
/// donors are allowed to read. Null for anyone else, and for requests made
/// before the name was moved out of the public document.
final patientNameProvider = StreamProvider.family<String?, String>((ref, id) {
  final backend = ref.watch(backendProvider);
  return backend.patientNameStream(id).handleError((_) => null);
});

/// Live stream of a single request (auto-updating tracking screen).
final requestProvider = StreamProvider.family<BloodRequest, String>((ref, id) {
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
  // The backend builds its queries from Donor Mode, the range and position at
  // the moment of subscribing, so resubscribe whenever any of them changes.
  // Without this, switching Donor Mode off kept requests coming until the app
  // restarted, and a new range did nothing until a request next changed.
  ref.watch(
    donorProfileValueProvider.select(
      (d) => (d.availability, d.bloodGroup, d.isInCooldown, d.maxDistanceKm),
    ),
  );
  ref.watch(deviceLocationProvider.select((l) => l.point));
  return backend.invitationsStream;
});

/// Pending invitations only — what a donor is asked to act on now.
final pendingInvitationsProvider = Provider<List<Invitation>>((ref) {
  final all = ref.watch(invitationsProvider).valueOrNull ?? const [];
  return all.where((i) => i.status == InvitationStatus.pending).toList();
});

/// How many requests are still being worked on for this person: the ones they
/// asked for that aren't finished, plus the ones they agreed to give blood for
/// that aren't finished. Shown on the Requests tab so it's visible from
/// anywhere in the app.
final processingCountProvider = Provider<int>((ref) {
  final mine = ref.watch(myRequestsProvider).valueOrNull ?? const [];
  final invites = ref.watch(invitationsProvider).valueOrNull ?? const [];
  final asking = mine.where((r) => r.status.isActive).length;
  final giving = invites
      .where(
        (i) =>
            i.status == InvitationStatus.accepted && i.requestStatus.isActive,
      )
      .length;
  return asking + giving;
});

/// The donation the user is in the middle of, if any — drives the "active
/// donation" card on Home and blocks accepting a second request at once.
/// Accepted requests that have since been fulfilled or cancelled don't count.
final acceptedInvitationProvider = Provider<Invitation?>((ref) {
  final all = ref.watch(invitationsProvider).valueOrNull ?? const [];
  for (final i in all) {
    if (i.status == InvitationStatus.accepted && i.requestStatus.isActive) {
      return i;
    }
  }
  return null;
});

// ---------------------------------------------------------------------------
// Device location (real GPS + permission — not demo data)
// ---------------------------------------------------------------------------
final locationServiceProvider = Provider<LocationService>(
  (ref) => LocationService(),
);

enum DeviceLocationStatus {
  unknown,
  requesting,
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

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

  DeviceLocationState copyWith({
    DeviceLocationStatus? status,
    GeoPoint? point,
    String? label,
  }) => DeviceLocationState(
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
        status: DeviceLocationStatus.granted,
        point: point,
        label: label,
      ),
      LocationDenied() => state.copyWith(status: DeviceLocationStatus.denied),
      LocationDeniedForever() => state.copyWith(
        status: DeviceLocationStatus.deniedForever,
      ),
      LocationServiceDisabled() => state.copyWith(
        status: DeviceLocationStatus.serviceDisabled,
      ),
    };
    // Keep Donor Mode's location flag, and the backend's cached position used
    // to compute invitation distances, in sync with the real permission state.
    final backend = ref.read(backendProvider);
    backend.myLocation = state.point;
    if (backend.currentUser != null) {
      backend.setDonorProfile(
        backend.donorProfile.copyWith(locationGranted: state.isGranted),
      );
    }
  }
}

final deviceLocationProvider =
    NotifierProvider<DeviceLocationController, DeviceLocationState>(
      DeviceLocationController.new,
    );

// ---------------------------------------------------------------------------
// Chat
// ---------------------------------------------------------------------------
final chatProvider = StreamProvider.family<List<ChatMessage>, String>((
  ref,
  requestId,
) {
  final backend = ref.watch(backendProvider);
  return backend.chatStream(requestId);
});

// ---------------------------------------------------------------------------
// Matched & Nearby Donors
// ---------------------------------------------------------------------------
final nearbyDonorsProvider = StreamProvider.family<List<MatchedDonor>, String>((
  ref,
  requestId,
) {
  final backend = ref.watch(backendProvider);
  return backend.nearbyDonorsStream(requestId);
});

/// Whether this account may ask for blood or donate. Live: an operator's
/// approval reaches the open app.
final canActProvider = StreamProvider<bool>((ref) {
  if (ref.watch(currentUserProvider) == null) return const Stream.empty();
  return ref.watch(backendProvider).canActStream;
});

/// [canActProvider] as a plain answer. True until the stream says otherwise:
/// the security rules are the real enforcement, so a slow first read shouldn't
/// flash a warning at someone who is allowed.
final canActValueProvider = Provider<bool>(
  (ref) => ref.watch(canActProvider).valueOrNull ?? true,
);

/// Camera and gallery, behind a provider so tests can hand back a picture
/// without a device.
final photoPickerProvider = Provider<PhotoPicker>((ref) => const PhotoPicker());
