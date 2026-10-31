import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/providers.dart';
import '../../shared/brand_mark.dart';

/// Minimal branded splash. Initializes the app and resolves the first route.
/// The redirect in the router moves the user on once auth state settles.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Restore session / load config, then let the router redirect decide.
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) ref.read(authControllerProvider.notifier).finishStartup();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 56),
            const SizedBox(height: AppSpacing.lg),
            Text('Rakt Pravah', style: context.text.headlineMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'An initiative of Vidya Bharati Purv Chatra Parishad',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xxxl),
            SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation(c.brand),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
