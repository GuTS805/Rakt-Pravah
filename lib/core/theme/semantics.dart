import 'package:flutter/material.dart';

import '../../data/models/enums.dart';
import 'app_colors.dart';

/// Maps domain enums to their semantic color pair (foreground + subtle
/// background). Centralized so urgency/status colors are identical everywhere
/// and never guessed per-screen. Status is *also* conveyed by label + icon, so
/// meaning never depends on color alone (accessibility, spec §32).

class SemanticStyle {
  const SemanticStyle(this.color, this.subtle, this.icon);
  final Color color;
  final Color subtle;
  final IconData icon;
}

SemanticStyle urgencyStyle(BuildContext context, Urgency u) {
  final c = Theme.of(context).extension<AppColors>()!;
  switch (u) {
    case Urgency.routine:
      return SemanticStyle(c.info, c.infoSubtle, Icons.schedule_rounded);
    case Urgency.urgent:
      return SemanticStyle(
          c.warning, c.warningSubtle, Icons.priority_high_rounded);
    case Urgency.critical:
      return SemanticStyle(c.danger, c.dangerSubtle, Icons.warning_rounded);
  }
}

SemanticStyle statusStyle(BuildContext context, RequestStatus s) {
  final c = Theme.of(context).extension<AppColors>()!;
  switch (s) {
    case RequestStatus.created:
      return SemanticStyle(
          c.textSecondary, c.surfaceMuted, Icons.add_circle_outline_rounded);
    case RequestStatus.searching:
      return SemanticStyle(c.info, c.infoSubtle, Icons.radar_rounded);
    case RequestStatus.donorAccepted:
      return SemanticStyle(
          c.success, c.successSubtle, Icons.how_to_reg_rounded);
    case RequestStatus.coordinating:
      return SemanticStyle(c.info, c.infoSubtle, Icons.forum_rounded);
    case RequestStatus.fulfilled:
      return SemanticStyle(
          c.success, c.successSubtle, Icons.check_circle_rounded);
    case RequestStatus.cancelled:
      return SemanticStyle(
          c.textTertiary, c.surfaceMuted, Icons.cancel_rounded);
    case RequestStatus.expired:
      return SemanticStyle(
          c.textTertiary, c.surfaceMuted, Icons.hourglass_disabled_rounded);
    case RequestStatus.removedByAdmin:
      return SemanticStyle(c.danger, c.dangerSubtle, Icons.gavel_rounded);
  }
}

SemanticStyle availabilityStyle(BuildContext context, DonorAvailability a) {
  final c = Theme.of(context).extension<AppColors>()!;
  switch (a) {
    case DonorAvailability.available:
      return SemanticStyle(
          c.success, c.successSubtle, Icons.check_circle_rounded);
    case DonorAvailability.paused:
      return SemanticStyle(
          c.warning, c.warningSubtle, Icons.pause_circle_rounded);
    case DonorAvailability.off:
      return SemanticStyle(
          c.textTertiary, c.surfaceMuted, Icons.do_not_disturb_on_rounded);
  }
}
