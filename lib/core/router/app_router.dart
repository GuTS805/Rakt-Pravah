import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/onboarding_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/coordination/chat_screen.dart';
import '../../features/coordination/coordination_screen.dart';
import '../../features/coordination/live_location_screen.dart';
import '../../features/donate/donate_screen.dart';
import '../../features/donate/donor_settings_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/invitations/invitation_detail_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/profile/history_screen.dart';
import '../../features/profile/privacy_screen.dart';
import '../../features/profile/profile_edit_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/settings_screen.dart';
import '../../features/requests/create_request_screen.dart';
import '../../features/requests/request_detail_screen.dart';
import '../../features/requests/requests_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/splash/splash_screen.dart';
import 'routes.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authListenable = ValueNotifier(ref.read(authControllerProvider));
  ref.onDispose(authListenable.dispose);
  ref.listen(authControllerProvider, (_, next) => authListenable.value = next);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.splash,
    refreshListenable: authListenable,
    redirect: (context, state) {
      final auth = authListenable.value;
      final loc = state.matchedLocation;

      const authPages = {Routes.login, Routes.register};

      switch (auth.status) {
        case AuthStatus.unknown:
          return loc == Routes.splash ? null : Routes.splash;
        case AuthStatus.unauthenticated:
          return authPages.contains(loc) ? null : Routes.login;
        case AuthStatus.needsOnboarding:
          return loc == Routes.onboarding ? null : Routes.onboarding;
        case AuthStatus.authenticated:
          if (loc == Routes.splash ||
              authPages.contains(loc) ||
              loc == Routes.onboarding) {
            return Routes.home;
          }
          return null;
      }
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, _) => const OnboardingScreen(),
      ),

      // ---- Main app shell (4-tab bottom navigation) ----
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.requests,
                builder: (_, _) => const RequestsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.donate,
                builder: (_, _) => const DonateScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.you,
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // ---- Contextual full-screen routes (cover the bottom nav) ----
      GoRoute(
        path: Routes.notifications,
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: Routes.createRequest,
        builder: (_, _) => const CreateRequestScreen(),
      ),
      GoRoute(
        path: '/requests/:id',
        builder: (_, s) =>
            RequestDetailScreen(requestId: s.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'coordination',
            builder: (_, s) =>
                CoordinationScreen(requestId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: 'chat',
            builder: (_, s) => ChatScreen(requestId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: 'location',
            builder: (_, s) =>
                LiveLocationScreen(requestId: s.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/invitations/:id',
        builder: (_, s) =>
            InvitationDetailScreen(invitationId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.donorSettings,
        builder: (_, _) => const DonorSettingsScreen(),
      ),
      GoRoute(
        path: Routes.profileEdit,
        builder: (_, _) => const ProfileEditScreen(),
      ),
      GoRoute(
        path: Routes.requestHistory,
        builder: (_, _) => const HistoryScreen(donations: false),
      ),
      GoRoute(
        path: Routes.donationHistory,
        builder: (_, _) => const HistoryScreen(donations: true),
      ),
      GoRoute(path: Routes.privacy, builder: (_, _) => const PrivacyScreen()),
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
    ],
  );
});
