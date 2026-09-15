import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/semantics.dart';
import '../utils/formatters.dart';
import 'app_card.dart';
import 'badges.dart';

/// A requester-facing summary of one blood request. Used in My Requests and
/// history. Urgency is echoed as a left accent bar for at-a-glance triage.
class RequestCard extends StatelessWidget {
  const RequestCard({super.key, required this.request, this.onTap});

  final BloodRequest request;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = request.status.isActive
        ? urgencyStyle(context, request.urgency).color
        : null;

    return AppCard(
      onTap: onTap,
      accent: accent,
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
            children: [
              BloodGroupBadges(request.bloodGroups, maxVisible: 2),
              const SizedBox(width: AppSpacing.sm),
              Text(Fmt.units(request.units), style: context.text.titleSmall),
              const Spacer(),
              StatusBadge(request.status, dense: true),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 15, color: c.textTertiary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  request.destination.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    color: c.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              UrgencyBadge(request.urgency, dense: true),
              const Spacer(),
              Text(
                Fmt.relative(request.createdAt),
                style: context.text.bodySmall?.copyWith(color: c.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
