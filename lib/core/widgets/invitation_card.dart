import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/semantics.dart';
import '../utils/formatters.dart';
import 'badges.dart';
import 'buttons.dart';
import 'profile_card.dart';

/// A request somebody else made that you could help with. Same frame as the
/// request cards: the left 30% is the person asking, the right 70% is the
/// patient and the details.
///
/// The patient's name is held back until the donor accepts. Everyone can see
/// a request, because that is how donors find one, but the name is only for
/// the requester and the donors who said yes, and the card follows that rather
/// than showing more than the donor is allowed to read.
class InvitationCard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final inv = invitation;
    final expired = inv.isExpired;
    final accepted = inv.status == InvitationStatus.accepted;
    final actionable = inv.status == InvitationStatus.pending && !expired;

    // Only ask for the name when the donor is allowed to read it; asking
    // earlier would just be a permission error.
    final patientName = accepted
        ? ref.watch(patientNameProvider(inv.requestId)).valueOrNull
        : null;

    final showActions = actionable && (onAccept != null || onDecline != null);

    return ProfileCard(
      requesterName: inv.requesterName,
      requesterPhoto: inv.requesterPhoto,
      accent: urgencyStyle(context, inv.urgency).color,
      onTap: onTap,
      footer: showActions
          ? Row(
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
            )
          : null,
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeadline(
            title: patientName ?? 'Patient',
            userId: Fmt.userId(inv.requesterId),
            aside: Fmt.relative(inv.createdAt),
            caption: patientName == null && !accepted
                ? 'Name shown after you accept'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              BloodGroupBadges(inv.bloodGroups, maxVisible: 2),
              Text(Fmt.units(inv.units), style: context.text.titleSmall),
            ],
          ),
          if (inv.patientBloodGroup != null || _partlyCovered(inv)) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              [
                if (inv.patientBloodGroup != null)
                  'Patient is ${inv.patientBloodGroup!.label}',
                if (_partlyCovered(inv))
                  '${inv.unitsRemaining} of ${inv.units} still need a donor',
              ].join('. '),
              style: context.text.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.local_hospital_outlined,
                  size: 15,
                  color: c.textTertiary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inv.destinationName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                    if (inv.destinationArea.isNotEmpty)
                      Text(
                        inv.destinationArea,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (expired)
            Text(
              'No longer available',
              style: context.text.bodySmall?.copyWith(color: c.textTertiary),
            )
          else
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                UrgencyBadge(inv.urgency, dense: true),
                DistanceIndicator(inv.distanceKm),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined, size: 13, color: c.textTertiary),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      Fmt.remaining(inv.expiresAt),
                      style: context.text.bodySmall?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          if (accepted) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, size: 15, color: c.success),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'You accepted this request',
                  style: context.text.bodySmall?.copyWith(color: c.success),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// A multi-unit request that some donors have already taken a unit of.
  static bool _partlyCovered(Invitation inv) =>
      (inv.unitsRemaining ?? 0) > 0 && inv.units > 1;
}
