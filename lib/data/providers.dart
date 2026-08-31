import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
// Chat
// ---------------------------------------------------------------------------
final chatProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, requestId) {
  final backend = ref.watch(backendProvider);
  return backend.chatStream(requestId);
});
