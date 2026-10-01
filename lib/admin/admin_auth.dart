import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/router/routes.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/buttons.dart';
import '../data/providers.dart';
import '../features/auth/login_screen.dart';

/// Legacy alias / redirect: the operations console and standard user app
/// now share a single unified sign-in screen ([LoginScreen]).
class AdminSignInScreen extends StatelessWidget {
  const AdminSignInScreen({super.key});

  @override
  Widget build(BuildContext context) => const LoginScreen();
}

/// Signed in, but not an operator. Says so plainly instead of showing an
/// empty console that looks broken.
class AdminNoAccessScreen extends ConsumerWidget {
  const AdminNoAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: AppRadius.cardLg,
                border: Border.all(color: c.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: c.dangerSubtle,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_person_rounded,
                      size: 36,
                      color: c.danger,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Access Restricted', style: context.text.headlineSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${user?.name ?? 'This account'} is signed in as a standard user. '
                    'Administrator privileges are required to view the Operations Console.',
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: 'Go to User Dashboard',
                    onPressed: () => context.go(Routes.home),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SecondaryButton(
                    label: 'Sign out',
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).logout(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
