import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'admin/admin_auth.dart';
import 'admin/admin_screens.dart';
import 'admin/admin_shell.dart';
import 'core/theme/app_theme.dart';
import 'data/providers.dart';
import 'firebase_options.dart';

/// Separate entrypoint for the operations console (spec §27): a desktop web
/// surface with its own sidebar layout, deliberately not reachable from the
/// mobile app's bottom navigation.
///
/// Build it with:
///   flutter build web -t lib/main_admin.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: AdminApp()));
}

/// Sign-in and the console are routes, not a wrapper around them: a screen
/// built by MaterialApp's builder sits above the Navigator, where there is no
/// Overlay — and a text field without an Overlay crashes the page the moment
/// it takes focus.
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
          // Signed in is not the same as being an operator.
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
          GoRoute(path: '/', builder: (_, _) => const AdminDashboardScreen()),
          GoRoute(
            path: '/requests',
            builder: (_, _) => const AdminRequestsScreen(),
          ),
          GoRoute(path: '/users', builder: (_, _) => const AdminUsersScreen()),
          GoRoute(
            path: '/reports',
            builder: (_, _) => const AdminReportsScreen(),
          ),
          GoRoute(
            path: '/moderation',
            builder: (_, _) => const AdminModerationScreen(),
          ),
          GoRoute(path: '/audit', builder: (_, _) => const AdminAuditScreen()),
          GoRoute(
            path: '/health',
            builder: (_, _) => const AdminHealthScreen(),
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
    // The mobile app does this from its splash screen; the console has no
    // splash, so it restores any existing session on first frame instead.
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
