import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/profile_photo_sheet.dart';
import '../../data/providers.dart';
import '../../shared/settings_widgets.dart';

/// The "You" tab: identity, donor capability, activity, privacy, and settings —
/// grouped, not overloaded (spec §20).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final donor = ref.watch(donorProfileValueProvider);
    final c = context.colors;

    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          children: [
            Text('You', style: context.text.headlineMedium),
            const SizedBox(height: AppSpacing.lg),

            // Identity header.
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: AppRadius.cardLg,
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Avatar(
                    initials: user.initials,
                    photo: user.photo,
                    size: 64,
                    showCameraBadge: true,
                    onCameraTap: () =>
                        showProfilePhotoOptions(context: context, ref: ref),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: context.text.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Verified means the phone number was confirmed by SMS.
                        if (user.phoneVerified) ...[
                          const SizedBox(height: 4),
                          const VerificationBadge(verified: true, dense: true),
                        ],
                        const SizedBox(height: 4),
                        Text(user.displayPhone, style: context.text.bodyMedium),
                        if (user.placeLabel != null) ...[
                          const SizedBox(height: 2),
                          Text(user.placeLabel!, style: context.text.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  BloodGroupBadge(user.bloodGroup, large: true),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Quick donation metric stats
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: AppRadius.cardMd,
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL DONATIONS',
                          style: AppTypography.eyebrow(c.textTertiary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${donor.totalDonations} completed',
                          style: context.text.titleSmall?.copyWith(
                            color: c.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 32, width: 1, color: c.border),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AVAILABILITY',
                          style: AppTypography.eyebrow(c.textTertiary),
                        ),
                        const SizedBox(height: 4),
                        AvailabilityBadge(donor.availability, dense: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            SettingsSection(
              title: 'Donor',
              children: [
                if (ref
                    .read(authControllerProvider.notifier)
                    .isDeviceOnlyAccount)
                  SettingsTile(
                    icon: Icons.lock_outline_rounded,
                    title: 'Secure your account',
                    subtitle: 'Add an email so you can sign in anywhere',
                    onTap: () => context.push(Routes.secureAccount),
                  ),
                SettingsTile(
                  icon: Icons.favorite_outline_rounded,
                  title: 'Donor Mode',
                  subtitle: donor.availability.label,
                  trailing: AvailabilityBadge(donor.availability, dense: true),
                  onTap: () => context.push(Routes.donorSettings),
                ),
                SettingsTile(
                  icon: Icons.tune_rounded,
                  title: 'Donor settings',
                  onTap: () => context.push(Routes.donorSettings),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            SettingsSection(
              title: 'Activity',
              children: [
                SettingsTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Request history',
                  onTap: () => context.push(Routes.requestHistory),
                ),
                SettingsTile(
                  icon: Icons.volunteer_activism_outlined,
                  title: 'Donation history',
                  subtitle: '${donor.totalDonations} donations',
                  onTap: () => context.push(Routes.donationHistory),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            SettingsSection(
              title: 'Safety & privacy',
              children: [
                SettingsTile(
                  icon: Icons.shield_outlined,
                  title: 'Privacy & location',
                  onTap: () => context.push(Routes.privacy),
                ),
                SettingsTile(
                  icon: Icons.flag_outlined,
                  title: 'Report a problem',
                  onTap: () => _showReport(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            SettingsSection(
              title: 'Account',
              children: [
                SettingsTile(
                  icon: Icons.person_outline_rounded,
                  title: 'Edit profile',
                  onTap: () => context.push(Routes.profileEdit),
                ),
                SettingsTile(
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                  onTap: () => context.push(Routes.settings),
                ),
                SettingsTile(
                  icon: Icons.logout_rounded,
                  title: 'Log out',
                  danger: true,
                  onTap: () => _confirmLogout(context, ref),
                ),
                SettingsTile(
                  icon: Icons.delete_outline_rounded,
                  title: 'Delete account',
                  danger: true,
                  onTap: () => context.push(Routes.deleteAccount),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showReport(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report a problem', style: context.text.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tell us what went wrong — misuse, a safety concern, or a bug. '
              'Our team reviews every report.',
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            const TextField(
              maxLines: 4,
              decoration: InputDecoration(hintText: 'Describe the problem…'),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Report submitted. Thank you.'),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: context.colors.brand,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Submit report'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final c = context.colors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You\'ll need to sign in again to use Rakt Pravah.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Log out', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
    if (ok == true) ref.read(authControllerProvider.notifier).logout();
  }
}
