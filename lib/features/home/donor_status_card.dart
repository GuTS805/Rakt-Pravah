import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/donor_gate.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';

/// Donor Mode status with an inline toggle. The backend is the source of truth:
/// the switch shows a busy state while the change is in flight and reverts with
/// a message if it fails (spec §15) — a local toggle never lies about server
/// state.
///
/// While a donor is within the 90-day cooldown after their last donation,
/// the switch is frozen — this isn't optional, it's the same real constraint
/// the backend's matching query enforces, just made visible here.
class DonorStatusCard extends ConsumerStatefulWidget {
  const DonorStatusCard({super.key});

  @override
  ConsumerState<DonorStatusCard> createState() => _DonorStatusCardState();
}

class _DonorStatusCardState extends ConsumerState<DonorStatusCard> {
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    if (on && !requireDonorProfile(context, ref)) return;
    final backend = ref.read(backendProvider);
    final current = ref.read(donorProfileValueProvider);
    setState(() => _busy = true);
    try {
      await backend.setDonorProfile(
        current.copyWith(
          availability: on
              ? DonorAvailability.available
              : DonorAvailability.off,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t update Donor Mode. Try again.'),
          ),
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
    final cooldown = donor.isInCooldown;
    // The heart stays warm whether or not Donor Mode is on — it's an
    // invitation, and the switch beside it already says what the state is.
    // Greying it out only when the cooldown locks the control keeps "off"
    // looking switchable instead of looking broken.
    final (tint, tintSubtle) = cooldown
        ? (c.textTertiary, c.surfaceMuted)
        : donor.availability == DonorAvailability.paused
        ? (c.warning, c.warningSubtle)
        : (c.brand, c.brandSubtle);

    return AppCard(
      child: Row(
        children: [
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              color: tintSubtle,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              cooldown ? Icons.bedtime_rounded : Icons.favorite_rounded,
              color: tint,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Donor Mode',
                        style: context.text.titleMedium,
                      ),
                    ),
                    // Only the cooldown badge survives: it carries a number
                    // the subtitle doesn't. An availability chip would just
                    // repeat the line underneath it.
                    if (cooldown) ...[
                      const SizedBox(width: AppSpacing.sm),
                      _CooldownBadge(remaining: donor.cooldownRemaining),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  cooldown
                      ? 'Resting after your last donation — thank you.'
                      : _subtitle(donor.availability),
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
                valueColor: AlwaysStoppedAnimation(c.brand),
              ),
            )
          else
            Switch(
              value: donor.isOn && !cooldown,
              activeThumbColor: c.brand,
              onChanged: cooldown ? null : (v) => _toggle(v),
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

class _CooldownBadge extends StatelessWidget {
  const _CooldownBadge({required this.remaining});
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final days = remaining.inHours < 24 ? 1 : (remaining.inHours / 24).ceil();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: c.warningSubtle,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bedtime_rounded, size: 12, color: c.warning),
          const SizedBox(width: 4),
          Text(
            days == 1 ? 'Eligible tomorrow' : 'Eligible in $days days',
            style: context.text.labelSmall?.copyWith(
              color: c.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
