import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/semantics.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/status_timeline.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';

/// Live request tracking. Auto-updates as the backend advances the state
/// machine: created -> searching -> donor accepted -> coordinating -> fulfilled
/// (spec §12). Terminal states show the appropriate final UI.
class RequestDetailScreen extends ConsumerWidget {
  const RequestDetailScreen({super.key, required this.requestId});
  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(requestProvider(requestId));

    return Scaffold(
      appBar: AppBar(title: const Text('Request')),
      body: async.when(
        loading: () => const _LoadingBody(),
        error: (e, _) => ErrorStateView(
          message: 'We couldn\'t load this request.',
          onRetry: () => ref.invalidate(requestProvider(requestId)),
        ),
        data: (req) => _Body(request: req),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            CardSkeleton(),
            SizedBox(height: AppSpacing.lg),
            CardSkeleton(),
          ],
        ),
      );
}

class _Body extends ConsumerWidget {
  const _Body({required this.request});
  final BloodRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _SummaryCard(request: request),
              const SizedBox(height: AppSpacing.lg),
              if (request.status == RequestStatus.searching)
                _SearchingCard(request: request),
              if (request.status == RequestStatus.searching)
                const SizedBox(height: AppSpacing.lg),
              const SectionHeader('Progress'),
              AppCard(child: StatusTimeline(request: request)),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader('Destination'),
              _DestinationCard(request: request),
              if (request.status.isTerminal) ...[
                const SizedBox(height: AppSpacing.lg),
                _TerminalNote(status: request.status),
              ],
            ],
          ),
        ),
        _ActionBar(request: request),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.request});
  final BloodRequest request;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accent: request.status.isActive
          ? urgencyStyle(context, request.urgency).color
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BloodGroupBadges(request.bloodGroups, large: true, maxVisible: 3),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Fmt.units(request.units),
                        style: context.text.titleLarge),
                    const SizedBox(height: 2),
                    Text('Created ${Fmt.relative(request.createdAt)}',
                        style: context.text.bodySmall),
                  ],
                ),
              ),
              StatusBadge(request.status),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                  child: DataField(
                      label: 'Urgency', value: request.urgency.label)),
              Expanded(
                  child: DataField(
                      label: 'Location',
                      value: request.requestLocationLabel.split('·').first.trim())),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchingCard extends StatelessWidget {
  const _SearchingCard({required this.request});
  final BloodRequest request;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation(c.info)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text('Searching for nearby donors…',
                    style: context.text.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: DataField(
                  label: 'Donors contacted',
                  value: '${request.donorsContacted}',
                ),
              ),
              Expanded(
                child: DataField(
                  label: 'Search radius',
                  value: '${request.searchRadiusKm.toStringAsFixed(0)} km',
                ),
              ),
            ],
          ),
          if (request.currentWave > 1) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Expanding search area to reach more donors…',
                style: context.text.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.request});
  final BloodRequest request;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = request.destination;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.local_hospital_rounded,
                color: c.textSecondary, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text(d.address, style: context.text.bodyMedium),
                if (d.wardOrContact != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(d.wardOrContact!,
                      style: context.text.bodySmall
                          ?.copyWith(color: c.textTertiary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalNote extends StatelessWidget {
  const _TerminalNote({required this.status});
  final RequestStatus status;

  @override
  Widget build(BuildContext context) {
    final style = statusStyle(context, status);
    final (title, body) = switch (status) {
      RequestStatus.fulfilled => (
          'Request fulfilled',
          'Thank you. This request is complete — no further donors will be contacted.'
        ),
      RequestStatus.cancelled => (
          'Request cancelled',
          'This request was cancelled. Donors are no longer being contacted.'
        ),
      RequestStatus.expired => (
          'Request expired',
          'This request is no longer active. Create a new one if you still need help.'
        ),
      RequestStatus.removedByAdmin => (
          'Removed by an administrator',
          'This request was removed. Contact support if you believe this is a mistake.'
        ),
      _ => ('', ''),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: style.subtle,
        borderRadius: AppRadius.cardLg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(style.icon, color: style.color, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text(body, style: context.text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.request});
  final BloodRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final status = request.status;

    Widget? primary;
    Widget? secondary;

    if (status == RequestStatus.coordinating ||
        status == RequestStatus.donorAccepted) {
      primary = PrimaryButton(
        label: 'Open coordination',
        icon: Icons.forum_rounded,
        onPressed: () => context.push(Routes.coordination(request.id)),
      );
      secondary = SecondaryButton(
        label: 'Mark fulfilled',
        icon: Icons.check_rounded,
        onPressed: () => _confirmFulfill(context, ref),
      );
    } else if (status == RequestStatus.searching ||
        status == RequestStatus.created) {
      primary = SecondaryButton(
        label: 'Cancel request',
        icon: Icons.close_rounded,
        destructive: true,
        onPressed: () => _confirmCancel(context, ref),
      );
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              primary,
              if (secondary != null) ...[
                const SizedBox(height: AppSpacing.sm),
                secondary,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(
      context,
      title: 'Cancel this request?',
      body: 'Donors will stop being contacted. You can create a new request '
          'anytime.',
      confirmLabel: 'Cancel request',
      destructive: true,
    );
    if (ok == true) {
      await ref.read(backendProvider).cancelRequest(request.id);
    }
  }

  Future<void> _confirmFulfill(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(
      context,
      title: 'Mark as fulfilled?',
      body: 'This closes the request and thanks your donor.',
      confirmLabel: 'Mark fulfilled',
      destructive: false,
    );
    if (ok == true) {
      await ref.read(backendProvider).markFulfilled(request.id);
    }
  }
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required bool destructive,
}) {
  final c = context.colors;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: context.text.titleLarge),
      content: Text(body, style: context.text.bodyMedium),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Keep',
              style: context.text.labelLarge
                  ?.copyWith(color: c.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel,
              style: context.text.labelLarge
                  ?.copyWith(color: destructive ? c.danger : c.brand)),
        ),
      ],
    ),
  );
}
