import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/invitation_card.dart';
import '../../core/widgets/request_card.dart';
import '../../core/widgets/states.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/segmented_control.dart';

/// Two tabs: the user's own requests, and incoming donor invitations. One
/// unified surface — the same person both asks and helps (spec §4, §13).
class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingInvitationsProvider).length;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Text('Requests', style: context.text.headlineMedium),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: SegmentedControl(
                segments: [
                  Segment('My requests'),
                  Segment('Invitations', badge: pending),
                ],
                selected: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: const [_MyRequests(), _Invitations()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyRequests extends ConsumerWidget {
  const _MyRequests();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myRequestsProvider);
    return async.when(
      loading: () => const _ListSkeleton(),
      error: (e, _) => ErrorStateView(
        message: 'We couldn\'t load your requests.',
        onRetry: () => ref.invalidate(myRequestsProvider),
      ),
      data: (requests) {
        if (requests.isEmpty) {
          return EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No requests yet',
            message: 'When you request blood, you\'ll track it here.',
            actionLabel: 'Request blood',
            onAction: () => context.push(Routes.createRequest),
          );
        }
        final active = requests.where((r) => r.status.isActive).toList();
        final past = requests.where((r) => r.status.isTerminal).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          children: [
            if (active.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'Active',
                  style: context.text.labelMedium?.copyWith(
                    color: context.colors.textTertiary,
                  ),
                ),
              ),
              for (final r in active) ...[
                RequestCard(
                  request: r,
                  onTap: () => context.push(Routes.requestDetail(r.id)),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
            if (past.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'Past',
                  style: context.text.labelMedium?.copyWith(
                    color: context.colors.textTertiary,
                  ),
                ),
              ),
              for (final r in past) ...[
                RequestCard(
                  request: r,
                  onTap: () => context.push(Routes.requestDetail(r.id)),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _Invitations extends ConsumerWidget {
  const _Invitations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(invitationsProvider);
    final donorOn = ref.watch(donorProfileValueProvider).isOn;

    return async.when(
      loading: () => const _ListSkeleton(),
      error: (e, _) => ErrorStateView(
        message: 'We couldn\'t load invitations.',
        onRetry: () => ref.invalidate(invitationsProvider),
      ),
      data: (invites) {
        final visible = invites
            .where((i) => i.status != InvitationStatus.declined)
            .toList();
        if (!donorOn) {
          return EmptyState(
            icon: Icons.favorite_outline_rounded,
            title: 'Donor Mode is off',
            message:
                'Turn on Donor Mode to receive requests from people nearby who '
                'share your blood type.',
            actionLabel: 'Go to Donate',
            onAction: () => context.go(Routes.donate),
          );
        }
        if (visible.isEmpty) {
          return const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'No invitations right now',
            message:
                'We\'ll notify you the moment someone nearby needs your '
                'help.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, i) {
            final inv = visible[i];
            return InvitationCard(
              invitation: inv,
              onTap: () => context.push(Routes.invitationDetail(inv.id)),
              onAccept: () => context.push(Routes.invitationDetail(inv.id)),
              onDecline: () => ref
                  .read(backendProvider)
                  .respondToInvitation(inv.id, InvitationStatus.declined),
            );
          },
        );
      },
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      0,
      AppSpacing.lg,
      AppSpacing.xxxl,
    ),
    children: const [
      CardSkeleton(),
      SizedBox(height: AppSpacing.md),
      CardSkeleton(),
    ],
  );
}
