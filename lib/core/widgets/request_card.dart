import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/semantics.dart';
import '../utils/formatters.dart';
import 'badges.dart';
import 'profile_card.dart';

/// One blood request you asked for. Used in My Requests and history. The left
/// 30% is you as the requester, the right 70% is the patient and the details;
/// urgency is echoed as a bar down the left edge for at-a-glance triage.
class RequestCard extends ConsumerWidget {
  const RequestCard({super.key, required this.request, this.onTap});

  final BloodRequest request;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final accent = request.status.isActive
        ? urgencyStyle(context, request.urgency).color
        : null;
    // Read from the request's private subcollection, which the requester can
    // open. Requests made before the name moved there still carry it inline.
    final patientName =
        ref.watch(patientNameProvider(request.id)).valueOrNull ??
        request.patientName;
    final patientGroup = request.patientBloodGroup;

    return ProfileCard(
      requesterName: request.requesterName,
      requesterPhoto: request.requesterPhoto,
      accent: accent,
      onTap: onTap,
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeadline(
            title: patientName ?? 'Patient',
            userId: Fmt.userId(request.requesterId),
            aside: Fmt.relative(request.createdAt),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              BloodGroupBadges(request.bloodGroups, maxVisible: 2),
              Text(Fmt.units(request.units), style: context.text.titleSmall),
            ],
          ),
          if (patientGroup != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Patient is ${patientGroup.label}',
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
                      request.destination.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                    if (request.destination.address.isNotEmpty)
                      Text(
                        request.destination.address,
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
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              UrgencyBadge(request.urgency, dense: true),
              StatusBadge(request.status, dense: true),
            ],
          ),
        ],
      ),
    );
  }
}
