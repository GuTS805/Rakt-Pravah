import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/donor_gate.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/semantics.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/settings_widgets.dart';

/// Fine-grained Donor Mode controls (spec §15). Each change is written to the
/// backend; the UI reflects the persisted value.
class DonorSettingsScreen extends ConsumerWidget {
  const DonorSettingsScreen({super.key});

  Future<void> _update(WidgetRef ref, DonorProfile next) =>
      ref.read(backendProvider).setDonorProfile(next);

  /// Turning this on triggers the real OS location permission dialog — not a
  /// fake flag. Turning it off only stops Rakt Pravah from using location for
  /// matching; it can't revoke an already-granted OS permission from inside
  /// the app, so we're upfront about that rather than pretending otherwise.
  Future<void> _toggleLocation(
    BuildContext context,
    WidgetRef ref,
    DonorProfile donor,
    bool on,
  ) async {
    if (!on) {
      await _update(ref, donor.copyWith(locationGranted: false));
      return;
    }
    final result = await ref.read(deviceLocationProvider.notifier).request();
    if (!result.isGranted && context.mounted) {
      final deniedForever = result.status == DeviceLocationStatus.deniedForever;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deniedForever
                ? 'Location is blocked for Rakt Pravah. Enable it in system settings.'
                : 'Location access is needed to match you by distance.',
          ),
          action: deniedForever
              ? SnackBarAction(
                  label: 'Open settings',
                  onPressed: () =>
                      ref.read(locationServiceProvider).openAppSettings(),
                )
              : null,
        ),
      );
    }
    // On success, DeviceLocationController already syncs donor.locationGranted.
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final donor = ref.watch(donorProfileValueProvider);
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Donor settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          SettingsSection(
            title: 'Availability',
            children: [
              for (final a in DonorAvailability.values)
                _AvailabilityRow(
                  availability: a,
                  selected: donor.availability == a,
                  // During the waiting period the app keeps Donor Mode off,
                  // so Paused would be switched straight back too.
                  locked: donor.isInCooldown && a != DonorAvailability.off,
                  onLockedTap: () {
                    final next = donor.nextEligibleDonationDate;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            next == null
                                ? 'Donor Mode stays off during your waiting period.'
                                : 'Donor Mode stays off until '
                                      '${Fmt.fullDate(next)}, when your waiting period ends.',
                          ),
                        ),
                      );
                  },
                  onTap: () {
                    if (a != DonorAvailability.off &&
                        !requireDonorProfile(context, ref)) {
                      return;
                    }
                    _update(ref, donor.copyWith(availability: a));
                  },
                ),
            ],
          ),
          if (donor.isInCooldown) ...[
            const SizedBox(height: AppSpacing.sm),
            _CooldownNotice(
              remaining: donor.cooldownRemaining,
              nextEligibleDate: donor.nextEligibleDonationDate,
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          SettingsSection(
            title: 'Notifications',
            children: [
              SettingsSwitchTile(
                icon: Icons.notifications_active_outlined,
                title: 'Push notifications',
                subtitle: 'Get notified about matching requests',
                value: donor.notifyPush,
                onChanged: (v) => _update(ref, donor.copyWith(notifyPush: v)),
              ),
              SettingsSwitchTile(
                icon: Icons.priority_high_rounded,
                title: 'Critical requests only',
                subtitle: 'Only notify me for critical urgency',
                value: donor.notifyCritical,
                onChanged: (v) =>
                    _update(ref, donor.copyWith(notifyCritical: v)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: Text(
              'MATCH RADIUS',
              style: AppTypography.eyebrow(c.textTertiary),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: AppRadius.cardLg,
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Notify me within', style: context.text.bodyLarge),
                    const Spacer(),
                    Text(
                      '${donor.maxDistanceKm.toStringAsFixed(0)} km',
                      style: AppTypography.mono(
                        size: 15,
                        weight: FontWeight.w600,
                        color: c.brand,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: donor.maxDistanceKm,
                  min: 2,
                  max: 40,
                  divisions: 19,
                  activeColor: c.brand,
                  label: '${donor.maxDistanceKm.toStringAsFixed(0)} km',
                  onChanged: (v) =>
                      _update(ref, donor.copyWith(maxDistanceKm: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SettingsSection(
            title: 'Location',
            children: [
              SettingsSwitchTile(
                icon: Icons.location_on_outlined,
                title: 'Location access',
                subtitle: donor.locationGranted
                    ? 'Granted — matched by distance'
                    : 'Needed to match you by distance',
                value: donor.locationGranted,
                onChanged: (v) => _toggleLocation(context, ref, donor, v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvailabilityRow extends StatelessWidget {
  const _AvailabilityRow({
    required this.availability,
    required this.selected,
    required this.onTap,
    this.locked = false,
    this.onLockedTap,
  });
  final DonorAvailability availability;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;
  final VoidCallback? onLockedTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = availabilityStyle(context, availability);
    return InkWell(
      onTap: locked ? onLockedTap : onTap,
      child: Opacity(
        opacity: locked ? 0.45 : 1,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(
                locked ? Icons.bedtime_rounded : style.icon,
                size: 20,
                color: style.color,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  availability.label,
                  style: context.text.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (locked)
                Icon(
                  Icons.lock_outline_rounded,
                  color: c.textTertiary,
                  size: 18,
                )
              else if (selected)
                Icon(Icons.check_circle_rounded, color: c.brand, size: 20)
              else
                Icon(Icons.circle_outlined, color: c.border, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _CooldownNotice extends StatelessWidget {
  const _CooldownNotice({required this.remaining, this.nextEligibleDate});
  final Duration remaining;
  final DateTime? nextEligibleDate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.warningSubtle,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.bedtime_rounded, size: 18, color: c.warning),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Thanks for donating! Donor Mode is automatically OFF during your 3-month waiting period.',
                  style: context.text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (nextEligibleDate != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Next eligible donation date: ${Fmt.fullDate(nextEligibleDate!)}',
              style: context.text.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Time remaining: ${Fmt.countdown(remaining)}',
              style: AppTypography.mono(
                size: 12,
                weight: FontWeight.w600,
                color: c.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
