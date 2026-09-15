import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/request_card.dart';
import '../../core/widgets/states.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';

/// Request or donation history. One screen, two modes, so the pattern stays
/// consistent.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key, required this.donations});
  final bool donations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(donations ? 'Donation history' : 'Request history'),
      ),
      body: donations ? _Donations() : _Requests(),
    );
  }
}

class _Requests extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myRequestsProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: CardSkeleton(),
      ),
      error: (e, _) => ErrorStateView(
        message: 'Couldn\'t load history.',
        onRetry: () => ref.invalidate(myRequestsProvider),
      ),
      data: (requests) {
        if (requests.isEmpty) {
          return const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No requests yet',
            message: 'Your past blood requests will appear here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: requests.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, i) => RequestCard(
            request: requests[i],
            onTap: () => context.push(Routes.requestDetail(requests[i].id)),
          ),
        );
      },
    );
  }
}

class _Donations extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final accepted = (ref.watch(invitationsProvider).valueOrNull ?? const [])
        .where((i) => i.status == InvitationStatus.accepted)
        .toList();

    if (accepted.isEmpty) {
      return const EmptyState(
        icon: Icons.volunteer_activism_outlined,
        title: 'No donations yet',
        message:
            'When you accept a request and complete a donation, it\'ll show '
            'here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: accepted.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        final inv = accepted[i];
        return Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: AppRadius.cardLg,
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              BloodGroupBadges(inv.bloodGroups, maxVisible: 2),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(inv.destinationName, style: context.text.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      '${Fmt.units(inv.units)} · ${Fmt.relative(inv.createdAt)}',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.check_circle_rounded, color: c.success, size: 20),
            ],
          ),
        );
      },
    );
  }
}
