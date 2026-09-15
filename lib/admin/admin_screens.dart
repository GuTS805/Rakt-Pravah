import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_spacing.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/formatters.dart';
import '../data/models/models.dart';
import 'admin_backend.dart';
import 'admin_providers.dart';
import 'admin_shell.dart';

// ---------------------------------------------------------------------------
// Shared table pieces
// ---------------------------------------------------------------------------

class _Cell extends StatelessWidget {
  const _Cell(this.child, {this.flex = 1});
  final Widget child;
  final int flex;

  @override
  Widget build(BuildContext context) => Expanded(flex: flex, child: child);
}

Widget _headerRow(BuildContext context, List<(String, int)> columns) {
  final c = context.colors;
  return Container(
    padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
    color: c.surfaceMuted,
    child: Row(
      children: [
        for (final (label, flex) in columns)
          Expanded(
            flex: flex,
            child: Text(label,
                style: context.text.labelSmall
                    ?.copyWith(color: c.textSecondary)),
          ),
      ],
    ),
  );
}

/// Status as a coloured pill. The colour is the request state machine's own
/// semantics, so scanning a column tells you the queue's health at a glance.
class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);
  final RequestStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (fg, bg) = switch (status) {
      RequestStatus.fulfilled => (c.success, c.successSubtle),
      RequestStatus.coordinating ||
      RequestStatus.donorAccepted =>
        (c.info, c.infoSubtle),
      RequestStatus.searching || RequestStatus.created => (
          c.warning,
          c.warningSubtle
        ),
      RequestStatus.removedByAdmin => (c.danger, c.dangerSubtle),
      _ => (c.textTertiary, c.surfaceMuted),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(status.label,
            style: context.text.labelSmall
                ?.copyWith(color: fg, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// The shared request table. `onRemove` being non-null turns it into the
/// moderation view — the same rows, plus the ability to act on them.
class _RequestTable extends StatelessWidget {
  const _RequestTable({
    required this.requests,
    this.onRemove,
    this.emptyMessage = 'No requests match this view.',
  });

  final List<AdminRequest> requests;
  final void Function(AdminRequest)? onRemove;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (requests.isEmpty) return AdminEmpty(message: emptyMessage);

    return Column(
      children: [
        _headerRow(context, [
          ('Requester', 3),
          ('Groups', 2),
          ('Units', 1),
          ('Urgency', 2),
          ('Status', 2),
          ('Donor', 3),
          ('Age', 2),
          if (onRemove != null) ('', 2),
        ]),
        for (final r in requests)
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.border)),
              color: r.isStale ? c.dangerSubtle.withValues(alpha: 0.35) : null,
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              children: [
                _Cell(
                  flex: 3,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.requesterName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall),
                      Text(r.destinationName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall
                              ?.copyWith(color: c.textTertiary)),
                    ],
                  ),
                ),
                _Cell(
                  flex: 2,
                  Text(r.bloodGroups.map((g) => g.label).join(' '),
                      style: AppTypography.mono(size: 12.5, color: c.brand)),
                ),
                _Cell(
                  Text('${r.units}',
                      style: AppTypography.mono(
                          size: 12.5, color: c.textPrimary)),
                ),
                _Cell(
                  flex: 2,
                  Text(r.urgency.label,
                      style: context.text.bodySmall?.copyWith(
                        color: r.urgency == Urgency.critical
                            ? c.danger
                            : c.textSecondary,
                        fontWeight: r.urgency == Urgency.critical
                            ? FontWeight.w600
                            : FontWeight.w400,
                      )),
                ),
                _Cell(flex: 2, _StatusPill(r.status)),
                _Cell(
                  flex: 3,
                  Text(
                    r.acceptedDonorName ??
                        (r.isUnmatched ? 'Nobody yet' : '—'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                        color: r.acceptedDonorName == null
                            ? c.textTertiary
                            : c.textPrimary),
                  ),
                ),
                _Cell(
                  flex: 2,
                  Text(
                    r.isStale ? 'Expired' : Fmt.relative(r.createdAt),
                    style: AppTypography.mono(
                        size: 12,
                        color: r.isStale ? c.danger : c.textSecondary),
                  ),
                ),
                if (onRemove != null)
                  _Cell(
                    flex: 2,
                    Align(
                      alignment: Alignment.centerRight,
                      child: r.status.isTerminal
                          ? Text('Closed',
                              style: context.text.bodySmall
                                  ?.copyWith(color: c.textTertiary))
                          : TextButton(
                              onPressed: () => onRemove!(r),
                              child: Text('Remove',
                                  style: context.text.labelMedium
                                      ?.copyWith(color: c.danger)),
                            ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final stats = ref.watch(adminStatsProvider);
    final queue = ref.watch(adminAttentionQueueProvider);
    final async = ref.watch(adminRequestsProvider);

    return AdminPage(
      title: 'Dashboard',
      subtitle: 'What the network is doing right now.',
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmpty(
            icon: Icons.error_outline_rounded,
            message: 'Could not read requests: $e'),
        data: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                AdminMetric(
                  value: stats.open,
                  label: 'Open requests',
                  hint: 'Not yet closed',
                ),
                AdminMetric(
                  value: stats.unmatched,
                  label: 'Awaiting a donor',
                  hint: 'Nobody accepted yet',
                  tone: c.warning,
                ),
                AdminMetric(
                  value: stats.stale,
                  label: 'Past expiry',
                  hint: 'Open but overdue',
                  tone: c.danger,
                ),
                AdminMetric(
                  value: stats.critical,
                  label: 'Critical open',
                  hint: 'Highest urgency',
                  tone: c.danger,
                ),
                AdminMetric(
                  value: stats.coordinating,
                  label: 'Coordinating',
                  hint: 'Donor is on the way',
                  tone: c.info,
                ),
                AdminMetric(
                  value: stats.fulfilled,
                  label: 'Fulfilled',
                  hint: 'All time',
                  tone: c.success,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            AdminPanel(
              title: 'Needs attention',
              trailing: Text('${queue.length} of ${stats.total}',
                  style: AppTypography.mono(size: 12, color: c.textTertiary)),
              child: _RequestTable(
                requests: queue.take(15).toList(),
                emptyMessage:
                    'Nothing is stuck. Every open request either has a donor '
                    'or is still inside its window.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------

class AdminRequestsScreen extends ConsumerStatefulWidget {
  const AdminRequestsScreen({super.key});

  @override
  ConsumerState<AdminRequestsScreen> createState() =>
      _AdminRequestsScreenState();
}

class _AdminRequestsScreenState extends ConsumerState<AdminRequestsScreen> {
  RequestStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(adminRequestsProvider);

    return AdminPage(
      title: 'Requests',
      subtitle: 'Every request in the system, newest first.',
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmpty(
            icon: Icons.error_outline_rounded, message: 'Could not read: $e'),
        data: (all) {
          final shown = _filter == null
              ? all
              : all.where((r) => r.status == _filter).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  _FilterChip(
                    label: 'All',
                    count: all.length,
                    selected: _filter == null,
                    onTap: () => setState(() => _filter = null),
                  ),
                  for (final s in RequestStatus.values)
                    if (all.any((r) => r.status == s))
                      _FilterChip(
                        label: s.label,
                        count: all.where((r) => r.status == s).length,
                        selected: _filter == s,
                        onTap: () => setState(() => _filter = s),
                      ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AdminPanel(
                title: _filter?.label ?? 'All requests',
                trailing: Text('${shown.length}',
                    style:
                        AppTypography.mono(size: 12, color: c.textTertiary)),
                child: _RequestTable(requests: shown),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: selected ? c.brand : c.surface,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: selected ? c.brand : c.border),
          ),
          child: Text('$label  $count',
              style: context.text.labelMedium?.copyWith(
                  color: selected ? c.onBrand : c.textSecondary)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------

class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final async = ref.watch(adminUsersProvider);

    return AdminPage(
      title: 'Users',
      subtitle: 'Registered people, their donor state, and admin access.',
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmpty(
            icon: Icons.error_outline_rounded, message: 'Could not read: $e'),
        data: (users) => AdminPanel(
          title: 'All users',
          trailing: Text('${users.length}',
              style: AppTypography.mono(size: 12, color: c.textTertiary)),
          child: users.isEmpty
              ? const AdminEmpty(message: 'Nobody has registered yet.')
              : Column(
                  children: [
                    _headerRow(context, [
                      ('Name', 3),
                      ('Group', 1),
                      ('Phone', 2),
                      ('Email', 3),
                      ('Donor', 2),
                      ('Donations', 2),
                      ('Admin', 2),
                    ]),
                    for (final u in users)
                      Container(
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: c.border)),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.md),
                        child: Row(
                          children: [
                            _Cell(
                              flex: 3,
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(u.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.text.titleSmall),
                                  if (u.city != null)
                                    Text(u.city!,
                                        style: context.text.bodySmall
                                            ?.copyWith(
                                                color: c.textTertiary)),
                                ],
                              ),
                            ),
                            _Cell(
                              Text(u.bloodGroup.label,
                                  style: AppTypography.mono(
                                      size: 12.5, color: c.brand)),
                            ),
                            _Cell(
                              flex: 2,
                              Text(u.phone,
                                  style: AppTypography.mono(
                                      size: 12, color: c.textSecondary)),
                            ),
                            _Cell(
                              flex: 3,
                              Text(u.email ?? 'Not verified',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.bodySmall?.copyWith(
                                      color: u.email == null
                                          ? c.textTertiary
                                          : c.textPrimary)),
                            ),
                            _Cell(
                              flex: 2,
                              Text(
                                u.isInCooldown
                                    ? 'Cooldown'
                                    : u.isDonorOn
                                        ? 'On'
                                        : 'Off',
                                style: context.text.bodySmall?.copyWith(
                                  color: u.isInCooldown
                                      ? c.warning
                                      : u.isDonorOn
                                          ? c.success
                                          : c.textTertiary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            _Cell(
                              flex: 2,
                              Text('${u.totalDonations}',
                                  style: AppTypography.mono(
                                      size: 12.5, color: c.textPrimary)),
                            ),
                            _Cell(
                              flex: 2,
                              Align(
                                alignment: Alignment.centerLeft,
                                child: _AdminToggle(user: u),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _AdminToggle extends ConsumerStatefulWidget {
  const _AdminToggle({required this.user});
  final AdminUser user;

  @override
  ConsumerState<_AdminToggle> createState() => _AdminToggleState();
}

class _AdminToggleState extends ConsumerState<_AdminToggle> {
  bool _busy = false;

  Future<void> _toggle(bool next) async {
    final admin = ref.read(adminBackendProvider);
    if (admin == null) return;
    setState(() => _busy = true);
    try {
      await admin.setAdmin(widget.user.id, next);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Switch(
      value: widget.user.isAdmin,
      onChanged: _toggle,
    );
  }
}

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------

class AdminReportsScreen extends ConsumerWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final async = ref.watch(adminReportsProvider);

    return AdminPage(
      title: 'Reports',
      subtitle: 'Abuse and problem reports filed by users.',
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmpty(
            icon: Icons.error_outline_rounded, message: 'Could not read: $e'),
        data: (reports) => AdminPanel(
          title: 'Filed reports',
          trailing: Text('${reports.where((r) => r.isOpen).length} open',
              style: AppTypography.mono(size: 12, color: c.textTertiary)),
          child: reports.isEmpty
              ? const AdminEmpty(
                  icon: Icons.flag_outlined,
                  message:
                      'No reports have been filed. The mobile app has no '
                      'Report screen yet, so nothing can reach this queue '
                      'until that is built — this is empty by design, not '
                      'because reports are being dropped.',
                )
              : Column(
                  children: [
                    _headerRow(context, [
                      ('Reason', 3),
                      ('Target', 3),
                      ('Filed', 2),
                      ('Status', 2),
                      ('', 2),
                    ]),
                    for (final r in reports)
                      Container(
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: c.border)),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.md),
                        child: Row(
                          children: [
                            _Cell(
                              flex: 3,
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.reason,
                                      style: context.text.titleSmall),
                                  if (r.detail != null)
                                    Text(r.detail!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.text.bodySmall),
                                ],
                              ),
                            ),
                            _Cell(
                              flex: 3,
                              Text(
                                r.targetRequestId != null
                                    ? 'Request ${r.targetRequestId}'
                                    : r.targetUserId != null
                                        ? 'User ${r.targetUserId}'
                                        : '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.mono(
                                    size: 11.5, color: c.textSecondary),
                              ),
                            ),
                            _Cell(
                              flex: 2,
                              Text(Fmt.relative(r.createdAt),
                                  style: AppTypography.mono(
                                      size: 12, color: c.textSecondary)),
                            ),
                            _Cell(
                              flex: 2,
                              Text(r.isOpen ? 'Open' : 'Resolved',
                                  style: context.text.bodySmall?.copyWith(
                                      color: r.isOpen
                                          ? c.warning
                                          : c.success,
                                      fontWeight: FontWeight.w600)),
                            ),
                            _Cell(
                              flex: 2,
                              Align(
                                alignment: Alignment.centerRight,
                                child: r.isOpen
                                    ? TextButton(
                                        onPressed: () => ref
                                            .read(adminBackendProvider)
                                            ?.resolveReport(
                                                r.id, 'Reviewed'),
                                        child: const Text('Resolve'),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Moderation
// ---------------------------------------------------------------------------

class AdminModerationScreen extends ConsumerWidget {
  const AdminModerationScreen({super.key});

  Future<void> _remove(
      BuildContext context, WidgetRef ref, AdminRequest request) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this request?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${request.requesterName} · ${request.bloodGroups.map((g) => g.label).join(", ")} · '
              '${Fmt.units(request.units)}\n\n'
              'This ends the request for everyone: no further matching, no new '
              'coordination. The reason is recorded in the audit log.',
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'e.g. Duplicate request, or reported as fake',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Remove request'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    await ref.read(adminBackendProvider)?.removeRequest(request.id, reason);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final queue = ref.watch(adminAttentionQueueProvider);
    final all = ref.watch(adminRequestsProvider).valueOrNull ?? const [];
    final open = all.where((r) => r.isOpen).toList();

    return AdminPage(
      title: 'Moderation',
      subtitle: 'Act on requests that are stuck, duplicated, or abusive.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminPanel(
            title: 'Needs attention',
            trailing: Text('${queue.length}',
                style: AppTypography.mono(size: 12, color: c.textTertiary)),
            child: _RequestTable(
              requests: queue,
              onRemove: (r) => _remove(context, ref, r),
              emptyMessage:
                  'Nothing is stuck right now. Stale and unmatched requests '
                  'surface here automatically.',
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          AdminPanel(
            title: 'All open requests',
            trailing: Text('${open.length}',
                style: AppTypography.mono(size: 12, color: c.textTertiary)),
            child: _RequestTable(
              requests: open,
              onRemove: (r) => _remove(context, ref, r),
              emptyMessage: 'No open requests.',
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Audit log
// ---------------------------------------------------------------------------

class AdminAuditScreen extends ConsumerWidget {
  const AdminAuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final async = ref.watch(adminAuditProvider);

    return AdminPage(
      title: 'Audit Logs',
      subtitle: 'Every administrative action, and who took it.',
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmpty(
            icon: Icons.error_outline_rounded, message: 'Could not read: $e'),
        data: (entries) => AdminPanel(
          title: 'Recent actions',
          trailing: Text('${entries.length}',
              style: AppTypography.mono(size: 12, color: c.textTertiary)),
          child: entries.isEmpty
              ? const AdminEmpty(
                  icon: Icons.fact_check_outlined,
                  message:
                      'No administrative actions have been taken yet. '
                      'Removing a request or changing admin access will be '
                      'recorded here.',
                )
              : Column(
                  children: [
                    _headerRow(context, [
                      ('When', 2),
                      ('Actor', 2),
                      ('Action', 2),
                      ('Target', 3),
                      ('Detail', 4),
                    ]),
                    for (final e in entries)
                      Container(
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: c.border)),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.md),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Cell(
                              flex: 2,
                              Text(
                                '${Fmt.shortDate(e.at)} ${Fmt.clock(e.at)}',
                                style: AppTypography.mono(
                                    size: 12, color: c.textSecondary),
                              ),
                            ),
                            _Cell(
                                flex: 2,
                                Text(e.actorName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.text.bodySmall)),
                            _Cell(
                              flex: 2,
                              Text(e.action,
                                  style: AppTypography.mono(
                                      size: 12, color: c.brand)),
                            ),
                            _Cell(
                              flex: 3,
                              Text(e.targetId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.mono(
                                      size: 11.5, color: c.textTertiary)),
                            ),
                            _Cell(
                                flex: 4,
                                Text(e.detail ?? '—',
                                    style: context.text.bodySmall)),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// System health
// ---------------------------------------------------------------------------

class AdminHealthScreen extends ConsumerWidget {
  const AdminHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminRequestsProvider);
    final users = ref.watch(adminUsersProvider).valueOrNull ?? const [];
    final stats = ref.watch(adminStatsProvider);
    final requests = async.valueOrNull ?? const [];

    final availableDonors = users.where((u) => u.isDonorOn).length;
    final inCooldown = users.where((u) => u.isInCooldown).length;
    final verified = users.where((u) => u.email != null).length;
    final longUnmatched = requests
        .where((r) =>
            r.isUnmatched && r.age > const Duration(minutes: 30))
        .length;

    return AdminPage(
      title: 'System Health',
      subtitle: 'Live operational signals, read straight from the database.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminPanel(
            title: 'Checks',
            child: Column(
              children: [
                _Check(
                  label: 'Database connection',
                  ok: !async.hasError,
                  detail: async.hasError
                      ? 'Firestore read failed: ${async.error}'
                      : 'Reading live request data.',
                ),
                _Check(
                  label: 'Requests past expiry',
                  ok: stats.stale == 0,
                  detail: stats.stale == 0
                      ? 'Every open request is inside its window.'
                      : '${stats.stale} open request(s) are past their expiry '
                          'and still not closed.',
                ),
                _Check(
                  label: 'Long-unmatched requests',
                  ok: longUnmatched == 0,
                  detail: longUnmatched == 0
                      ? 'No request has waited over 30 minutes for a donor.'
                      : '$longUnmatched request(s) have waited over 30 '
                          'minutes with nobody accepting.',
                ),
                _Check(
                  label: 'Donor pool',
                  ok: availableDonors > 0,
                  detail: availableDonors > 0
                      ? '$availableDonors donor(s) currently available.'
                      : 'No donors have Donor Mode on — nothing can be '
                          'matched right now.',
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              AdminMetric(value: users.length, label: 'Registered users'),
              AdminMetric(
                  value: availableDonors, label: 'Donors available'),
              AdminMetric(value: inCooldown, label: 'Donors in cooldown'),
              AdminMetric(value: verified, label: 'Email on file'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({
    required this.label,
    required this.ok,
    required this.detail,
    this.last = false,
  });

  final String label;
  final bool ok;
  final String detail;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.warning_rounded,
              size: 18, color: ok ? c.success : c.warning),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text(detail,
                    style: context.text.bodySmall
                        ?.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
