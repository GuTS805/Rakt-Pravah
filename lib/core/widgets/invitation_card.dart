import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/semantics.dart';
import '../utils/formatters.dart';
import 'app_card.dart';
import 'badges.dart';
import 'buttons.dart';

/// A donor opportunity. Before acceptance it shows only what a donor needs to
/// decide — blood group, units, urgency, distance, destination area — and no
/// private requester data (spec §16, §26).
class InvitationCard extends StatelessWidget {
  const InvitationCard({
    super.key,
    required this.invitation,
    this.onTap,
    this.onAccept,
    this.onDecline,
    this.busy = false,
  });

  final Invitation invitation;
  final VoidCallback? onTap;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inv = invitation;
    final expired =
        inv.status == InvitationStatus.expired ||
        (inv.expiresAt != null && inv.expiresAt!.isBefore(DateTime.now()));
    final actionable = inv.status == InvitationStatus.pending && !expired;

    return AppCard(
      onTap: onTap,
      accent: urgencyStyle(context, inv.urgency).color,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg + 4,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BloodGroupBadges(inv.bloodGroups, large: true, maxVisible: 2),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          Fmt.units(inv.units),
                          style: context.text.titleMedium,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        DistanceIndicator(inv.distanceKm),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${inv.destinationName} · ${inv.destinationArea}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium,
                    ),
                  ],
                ),
              ),
              UrgencyBadge(inv.urgency, dense: true),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (expired)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                'This opportunity is no longer available.',
                style: context.text.bodySmall?.copyWith(color: c.textTertiary),
              ),
            )
          else ...[
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 14, color: c.textTertiary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  Fmt.remaining(inv.expiresAt),
                  style: context.text.bodySmall?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
            if (actionable && (onAccept != null || onDecline != null)) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Decline',
                      onPressed: busy ? null : onDecline,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: PrimaryButton(
                      label: 'Accept',
                      busy: busy,
                      onPressed: onAccept,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
