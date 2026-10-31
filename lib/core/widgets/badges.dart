import 'package:flutter/material.dart';

import '../../data/models/enums.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../theme/semantics.dart';

/// The signature identity mark: a blood group set in monospace, like a value on
/// an instrument panel. Two sizes cover cards (small) and headers (large).
class BloodGroupBadge extends StatelessWidget {
  const BloodGroupBadge(this.group, {super.key, this.large = false});

  final BloodGroup group;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? AppSpacing.md : AppSpacing.sm,
        vertical: large ? AppSpacing.sm : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: c.brandSubtle,
        borderRadius: BorderRadius.circular(
          large ? AppRadius.md : AppRadius.sm,
        ),
        border: Border.all(color: c.brand.withValues(alpha: 0.22)),
      ),
      child: Text(
        group.label,
        style: AppTypography.mono(
          size: large ? 20 : 14,
          weight: FontWeight.w700,
          color: c.brand,
          spacing: 0.5,
        ),
      ),
    );
  }
}

/// A request can be open to more than one compatible blood group, so this
/// renders the full set. In space-constrained contexts (list cards) it shows
/// the first couple and folds the rest into a "+N" chip rather than wrapping
/// to a second line and breaking the card's rhythm.
class BloodGroupBadges extends StatelessWidget {
  const BloodGroupBadges(
    this.groups, {
    super.key,
    this.large = false,
    this.maxVisible,
  });

  final List<BloodGroup> groups;
  final bool large;

  /// Cap how many badges render before folding the rest into "+N". Null
  /// shows every group (used in review/detail screens with room to spare).
  final int? maxVisible;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cap = maxVisible ?? groups.length;
    final visible = groups.take(cap).toList();
    final overflow = groups.length - visible.length;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final g in visible) BloodGroupBadge(g, large: large),
        if (overflow > 0)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: large ? AppSpacing.md : AppSpacing.sm,
              vertical: large ? AppSpacing.sm : AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: BorderRadius.circular(
                large ? AppRadius.md : AppRadius.sm,
              ),
              border: Border.all(color: c.border),
            ),
            child: Text(
              '+$overflow',
              style: AppTypography.mono(
                size: large ? 20 : 14,
                weight: FontWeight.w700,
                color: c.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

/// A small pill conveying status via color, an icon, and a label — never color
/// alone (accessibility).
class _SemanticPill extends StatelessWidget {
  const _SemanticPill({
    required this.style,
    required this.label,
    this.dense = false,
  });

  final SemanticStyle style;
  final String label;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.sm : AppSpacing.md,
        vertical: dense ? 3 : AppSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: style.subtle,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: dense ? 12 : 14, color: style.color),
          const SizedBox(width: AppSpacing.xs + 1),
          Text(
            label,
            style: AppTypography.eyebrow(style.color)
                .copyWith(fontSize: dense ? 10 : 11, letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }
}

class UrgencyBadge extends StatelessWidget {
  const UrgencyBadge(this.urgency, {super.key, this.dense = false});
  final Urgency urgency;
  final bool dense;

  @override
  Widget build(BuildContext context) => _SemanticPill(
    style: urgencyStyle(context, urgency),
    label: urgency.label,
    dense: dense,
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.dense = false});
  final RequestStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) => _SemanticPill(
    style: statusStyle(context, status),
    label: status.label,
    dense: dense,
  );
}

class AvailabilityBadge extends StatelessWidget {
  const AvailabilityBadge(this.availability, {super.key, this.dense = false});
  final DonorAvailability availability;
  final bool dense;

  @override
  Widget build(BuildContext context) => _SemanticPill(
    style: availabilityStyle(context, availability),
    label: availability.label,
    dense: dense,
  );
}

class VerificationBadge extends StatelessWidget {
  const VerificationBadge({
    super.key,
    required this.verified,
    this.dense = false,
  });
  final bool verified;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.sm : AppSpacing.md,
        vertical: dense ? 3 : AppSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: verified ? c.successSubtle : c.warningSubtle,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: (verified ? c.success : c.warning).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified ? Icons.verified_rounded : Icons.pending_outlined,
            size: dense ? 12 : 14,
            color: verified ? c.success : c.warning,
          ),
          const SizedBox(width: AppSpacing.xs + 1),
          Text(
            verified ? 'Verified Donor' : 'Pending Verification',
            style: TextStyle(
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w600,
              color: verified ? c.success : c.warning,
            ),
          ),
        ],
      ),
    );
  }
}

class CustomStatusBadge extends StatelessWidget {
  const CustomStatusBadge({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.backgroundColor,
    this.dense = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.sm : AppSpacing.md,
        vertical: dense ? 3 : AppSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: dense ? 12 : 14, color: color),
          const SizedBox(width: AppSpacing.xs + 1),
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Distance readout in mono ("3.2 km"), used on invitation/opportunity cards.
class DistanceIndicator extends StatelessWidget {
  const DistanceIndicator(this.km, {super.key});

  /// Null when a position is missing. Said plainly instead of showing 0 km.
  final double? km;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.near_me_rounded, size: 13, color: c.textTertiary),
        const SizedBox(width: AppSpacing.xs),
        Text(
          km == null ? 'Distance unknown' : '${km!.toStringAsFixed(1)} km',
          style: AppTypography.mono(size: 12.5, color: c.textSecondary),
        ),
      ],
    );
  }
}

/// A labelled data cell for review/detail grids — mono value under a small
/// uppercase label.
class DataField extends StatelessWidget {
  const DataField({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppTypography.eyebrow(c.textTertiary)),
        const SizedBox(height: AppSpacing.xs + 1),
        Text(
          value,
          style: AppTypography.mono(
            size: 15,
            weight: FontWeight.w600,
            color: valueColor ?? c.textPrimary,
          ),
        ),
      ],
    );
  }
}
