import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/semantics.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/badges.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';

/// Donor Mode status with an inline toggle. The backend is the source of truth:
/// the switch shows a busy state while the change is in flight and reverts with
/// a message if it fails (spec §15) — a local toggle never lies about server
/// state.
class DonorStatusCard extends ConsumerStatefulWidget {
  const DonorStatusCard({super.key});

  @override
  ConsumerState<DonorStatusCard> createState() => _DonorStatusCardState();
}

class _DonorStatusCardState extends ConsumerState<DonorStatusCard> {
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    final backend = ref.read(backendProvider);
    final current = ref.read(donorProfileValueProvider);
    setState(() => _busy = true);
    try {
      await backend.setDonorProfile(current.copyWith(
        availability:
            on ? DonorAvailability.available : DonorAvailability.off,
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Couldn\'t update Donor Mode. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final donor = ref.watch(donorProfileValueProvider);
    final style = availabilityStyle(context, donor.availability);

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: style.subtle,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(style.icon, color: style.color, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Donor Mode', style: context.text.titleSmall),
                        const SizedBox(width: AppSpacing.sm),
                        AvailabilityBadge(donor.availability, dense: true),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(donor.availability),
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              if (_busy)
                SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(c.brand)),
                )
              else
                Switch(
                  value: donor.isOn,
                  activeThumbColor: c.brand,
                  onChanged: (v) => _toggle(v),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _subtitle(DonorAvailability a) {
    switch (a) {
      case DonorAvailability.available:
        return 'You can receive matching requests nearby.';
      case DonorAvailability.paused:
        return 'Paused — you won\'t be notified for now.';
      case DonorAvailability.off:
        return 'You\'re not participating as a donor.';
    }
  }
}
