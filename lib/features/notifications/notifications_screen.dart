import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/states.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';

String _groupsLabel(List<BloodGroup> groups) =>
    groups.map((g) => g.label).join('/');

class _Notif {
  const _Notif(
    this.icon,
    this.color,
    this.title,
    this.body,
    this.time,
    this.route,
  );
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final DateTime time;
  final String route;
}

/// Notifications deep-link into the relevant screen — never just Home (spec
/// §21). Items are derived from live state so taps always land somewhere real.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final requests = ref.watch(myRequestsProvider).valueOrNull ?? const [];
    final pending = ref.watch(pendingInvitationsProvider);
    final now = DateTime.now();

    final items = <_Notif>[];

    for (final r in requests.where((r) => r.status.isActive)) {
      if (r.status == RequestStatus.donorAccepted ||
          r.status == RequestStatus.coordinating) {
        items.add(
          _Notif(
            Icons.how_to_reg_rounded,
            c.success,
            'Your blood request has been accepted by a donor',
            '${r.acceptedDonorName ?? "A donor"} has accepted your ${_groupsLabel(r.bloodGroups)} request.',
            now.subtract(const Duration(minutes: 1)),
            Routes.requestDetail(r.id),
          ),
        );
      } else if (r.status == RequestStatus.searching) {
        items.add(
          _Notif(
            Icons.radar_rounded,
            c.info,
            'Searching for donors',
            '${r.donorsContacted} donors contacted for your ${_groupsLabel(r.bloodGroups)} request.',
            now.subtract(const Duration(minutes: 2)),
            Routes.requestDetail(r.id),
          ),
        );
      }
    }

    for (final inv in pending) {
      items.add(
        _Notif(
          Icons.favorite_rounded,
          c.brand,
          'New donor invitation',
          inv.distanceKm == null
              ? '${_groupsLabel(inv.bloodGroups)} · ${Fmt.units(inv.units)} · '
                    '${inv.destinationName}.'
              : '${_groupsLabel(inv.bloodGroups)} · ${Fmt.units(inv.units)} · '
                    '${inv.distanceKm!.toStringAsFixed(1)} km away.',
          inv.createdAt,
          Routes.invitationDetail(inv.id),
        ),
      );
    }

    items.sort((a, b) => b.time.compareTo(a.time));

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: items.isEmpty
          ? const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'You\'re all caught up',
              message:
                  'Updates about your requests and donations will appear '
                  'here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) => _Row(item: items[i]),
            ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item});
  final _Notif item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: () => context.push(item.route),
      borderRadius: AppRadius.cardLg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AppRadius.cardLg,
          border: Border.all(color: c.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(item.icon, size: 19, color: item.color),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(item.title, style: context.text.titleSmall),
                      ),
                      Text(
                        Fmt.relative(item.time),
                        style: context.text.bodySmall?.copyWith(
                          color: c.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(item.body, style: context.text.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
