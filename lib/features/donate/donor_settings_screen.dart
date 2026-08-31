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
                  onTap: () => _update(ref, donor.copyWith(availability: a)),
                ),
            ],
          ),
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
                onChanged: (v) =>
                    _update(ref, donor.copyWith(locationGranted: v)),
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
  });
  final DonorAvailability availability;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = availabilityStyle(context, availability);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(style.icon, size: 20, color: style.color),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(availability.label,
                  style: context.text.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w500)),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: c.brand, size: 20)
            else
              Icon(Icons.circle_outlined, color: c.border, size: 20),
          ],
        ),
      ),
    );
  }
}
