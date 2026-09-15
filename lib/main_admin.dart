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

final _adminRouter = GoRouter(
  routes: [
    ShellRoute(
      builder: (context, state, child) => AdminShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, _) => const AdminDashboardScreen()),
        GoRoute(
            path: '/requests', builder: (_, _) => const AdminRequestsScreen()),
        GoRoute(path: '/users', builder: (_, _) => const AdminUsersScreen()),
        GoRoute(
            path: '/reports', builder: (_, _) => const AdminReportsScreen()),
        GoRoute(
            path: '/moderation',
            builder: (_, _) => const AdminModerationScreen()),
        GoRoute(path: '/audit', builder: (_, _) => const AdminAuditScreen()),
        GoRoute(path: '/health', builder: (_, _) => const AdminHealthScreen()),
      ],
    ),
  ],
);

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
    final auth = ref.watch(authControllerProvider);
    // Keeps an emailed sign-in link working if the console is opened with one.
    ref.watch(adminEmailLinkWatcherProvider);

    return MaterialApp.router(
      title: 'BloodLink Operations',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: _adminRouter,
      builder: (context, child) {
        return switch (auth.status) {
          AuthStatus.unknown => const _Booting(),
          AuthStatus.unauthenticated => const AdminSignInScreen(),
          _ => (auth.user?.isAdmin ?? false)
              ? (child ?? const SizedBox.shrink())
              : const AdminNoAccessScreen(),
        };
      },
    );
  }
}

class _Booting extends StatelessWidget {
  const _Booting();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
