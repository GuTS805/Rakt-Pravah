import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/semantics.dart';
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
  /// fake flag. Turning it off only stops BloodLink from using location for
  /// matching; it can't revoke an already-granted OS permission from inside
  /// the app, so we're upfront about that rather than pretending otherwise.
  Future<void> _toggleLocation(
      BuildContext context, WidgetRef ref, DonorProfile donor, bool on) async {
    if (!on) {
      await _update(ref, donor.copyWith(locationGranted: false));
      return;
    }
    final result = await ref.read(deviceLocationProvider.notifier).request();
    if (!result.isGranted && context.mounted) {
      final deniedForever =
          result.status == DeviceLocationStatus.deniedForever;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(deniedForever
            ? 'Location is blocked for BloodLink. Enable it in system settings.'
            : 'Location access is needed to match you by distance.'),
        action: deniedForever
            ? SnackBarAction(
                label: 'Open settings',
                onPressed: () =>
                    ref.read(locationServiceProvider).openAppSettings(),
              )
            : null,
      ));
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
                  locked: donor.isInCooldown && a == DonorAvailability.available,
                  onTap: () => _update(ref, donor.copyWith(availability: a)),
                ),
            ],
          ),
          if (donor.isInCooldown) ...[
            const SizedBox(height: AppSpacing.sm),
            _CooldownNotice(remaining: donor.cooldownRemaining),
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
                onChanged: (v) =>
                    _update(ref, donor.copyWith(notifyPush: v)),
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
                left: AppSpacing.xs, bottom: AppSpacing.sm),
            child: Text('MATCH RADIUS',
                style: AppTypography.eyebrow(c.textTertiary)),
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
                    Text('${donor.maxDistanceKm.toStringAsFixed(0)} km',
                        style: AppTypography.mono(
                            size: 15,
                            weight: FontWeight.w600,
                            color: c.brand)),
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
  });
  final DonorAvailability availability;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = availabilityStyle(context, availability);
    return InkWell(
      onTap: locked ? null : onTap,
      child: Opacity(
        opacity: locked ? 0.45 : 1,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(locked ? Icons.bedtime_rounded : style.icon,
                  size: 20, color: style.color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(availability.label,
                    style: context.text.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w500)),
              ),
              if (locked)
                Icon(Icons.lock_outline_rounded, color: c.textTertiary, size: 18)
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
  const _CooldownNotice({required this.remaining});
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final days = remaining.inHours < 24 ? 1 : (remaining.inHours / 24).ceil();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.warningSubtle,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.bedtime_rounded, size: 18, color: c.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              days == 1
                  ? 'Thanks for donating. You\'ll be eligible to donate again tomorrow.'
                  : 'Thanks for donating. You\'ll be eligible to donate again in $days days — this keeps donation safe for you.',
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
