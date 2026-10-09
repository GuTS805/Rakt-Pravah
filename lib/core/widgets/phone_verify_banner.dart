import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/routes.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Shown on Home until the account's phone number is verified. It says what is
/// held back and how to fix it, so the blocked buttons don't read as a bug.
class PhoneVerifyBanner extends StatelessWidget {
  const PhoneVerifyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.infoSubtle,
      borderRadius: AppRadius.cardLg,
      child: InkWell(
        borderRadius: AppRadius.cardLg,
        onTap: () => context.push(Routes.verifyPhone),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined, size: 19, color: c.info),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verify your phone number',
                      style: context.text.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'We text you a code once. After that you can request '
                      'blood and donate.',
                      style: context.text.bodySmall?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
