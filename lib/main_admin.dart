import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'admin/admin_auth.dart';
import 'admin/admin_screens.dart';
import 'admin/admin_shell.dart';
import 'admin/screens/admin_analytics_screen.dart';
import 'admin/screens/admin_availability_screen.dart';
import 'admin/screens/admin_connections_screen.dart';
import 'admin/screens/admin_donations_screen.dart';
import 'admin/screens/admin_hospitals_screen.dart';
import 'admin/screens/admin_live_map_screen.dart';
import 'admin/screens/admin_notifications_screen.dart';
import 'admin/screens/admin_settings_screen.dart';
import 'admin/screens/admin_verification_screen.dart';
import 'core/theme/app_theme.dart';
import 'data/providers.dart';
import 'firebase_options.dart';

/// Separate entrypoint for the operations console: a desktop web surface with
/// its own sidebar layout, deliberately not reachable from the mobile app's
/// bottom navigation.
///
/// Build it with:
///   flutter build web -t lib/main_admin.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: AdminApp()));
}

final adminRouterProvider = Provider<GoRouter>((ref) {
  final authListenable = ValueNotifier(ref.read(authControllerProvider));
  ref.onDispose(authListenable.dispose);
  ref.listen(authControllerProvider, (_, next) => authListenable.value = next);

  return GoRouter(
    initialLocation: _booting,
    refreshListenable: authListenable,
    redirect: (context, state) {
      final auth = authListenable.value;
      final loc = state.matchedLocation;
      const gates = {_booting, _signIn, _noAccess};

      switch (auth.status) {
        case AuthStatus.unknown:
          return loc == _booting ? null : _booting;
        case AuthStatus.unauthenticated:
          return loc == _signIn ? null : _signIn;
        case AuthStatus.needsOnboarding:
        case AuthStatus.authenticated:
          if (!(auth.user?.isAdmin ?? false)) {
            return loc == _noAccess ? null : _noAccess;
          }
          return gates.contains(loc) ? '/' : null;
      }
    },
    routes: [
      GoRoute(path: _booting, builder: (_, _) => const _Booting()),
      GoRoute(path: _signIn, builder: (_, _) => const AdminSignInScreen()),
      GoRoute(path: _noAccess, builder: (_, _) => const AdminNoAccessScreen()),
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          // Dashboard
          GoRoute(
            path: '/',
            builder: (_, _) => const AdminDashboardScreen(),
          ),

          // People
          GoRoute(
            path: '/users',
            builder: (_, _) => const AdminUsersScreen(),
          ),
          GoRoute(
            path: '/donors',
            builder: (_, _) => const AdminDonorsScreen(),
          ),
          GoRoute(
            path: '/verification',
            builder: (_, _) => const AdminVerificationScreen(),
          ),

          // Blood Operations
          GoRoute(
            path: '/requests',
            builder: (_, _) => const AdminRequestsScreen(),
          ),
          GoRoute(
            path: '/emergency',
            builder: (_, _) => const AdminEmergencyScreen(),
          ),
          GoRoute(
            path: '/map',
            builder: (_, _) => const AdminLiveMapScreen(),
          ),
          GoRoute(
            path: '/availability',
            builder: (_, _) => const AdminAvailabilityScreen(),
          ),
          GoRoute(
            path: '/donations',
            builder: (_, _) => const AdminDonationsScreen(),
          ),
          GoRoute(
            path: '/connections',
            builder: (_, _) => const AdminConnectionsScreen(),
          ),

          // Management
          GoRoute(
            path: '/hospitals',
            builder: (_, _) => const AdminHospitalsScreen(),
          ),
          GoRoute(
            path: '/analytics',
            builder: (_, _) => const AdminAnalyticsScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (_, _) => const AdminNotificationsScreen(),
          ),

          // Safety
          GoRoute(
            path: '/reports',
            builder: (_, _) => const AdminReportsScreen(),
          ),
          GoRoute(
            path: '/moderation',
            builder: (_, _) => const AdminModerationScreen(),
          ),
          GoRoute(
            path: '/audit',
            builder: (_, _) => const AdminAuditScreen(),
          ),

          // System
          GoRoute(
            path: '/health',
            builder: (_, _) => const AdminHealthScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const AdminSettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

const _booting = '/booting';
const _signIn = '/sign-in';
const _noAccess = '/no-access';

class AdminApp extends ConsumerStatefulWidget {
  const AdminApp({super.key});

  @override
  ConsumerState<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends ConsumerState<AdminApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).finishStartup();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Rakt Pravah Operations',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(adminRouterProvider),
    );
  }
}

class _Booting extends StatelessWidget {
  const _Booting();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
