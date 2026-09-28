import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/formatters.dart';
import '../data/models/models.dart';
import 'admin_backend.dart';
import 'admin_providers.dart';
import 'admin_shell.dart';
import 'admin_widgets.dart';

// ---------------------------------------------------------------------------
// Enhanced Dashboard
// ---------------------------------------------------------------------------

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final stats = ref.watch(adminStatsProvider);
    final queue = ref.watch(adminAttentionQueueProvider);
    final async = ref.watch(adminRequestsProvider);
    final users = ref.watch(adminUsersProvider).valueOrNull ?? const [];
    final audit = ref.watch(adminAuditProvider).valueOrNull ?? const [];

    final availableDonors = users.where((u) => u.isDonorOn).length;
    final pendingVerification =
        users.where((u) => u.email == null && !u.isAdmin).length;
    final emergencyCount = (async.valueOrNull ?? const [])
        .where(
          (r) =>
              r.isOpen &&
              (r.urgency == Urgency.critical || r.urgency == Urgency.urgent),
        )
        .length;

    return AdminPage(
      title: 'Dashboard',
      subtitle: 'Real-time overview of the blood donation network.',
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmpty(
          icon: Icons.error_outline_rounded,
          message: 'Could not read data: $e',
        ),
        data: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Summary cards ---
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                AdminStatCard(
                  icon: Icons.people_alt_rounded,
                  value: '${users.length}',
                  label: 'Total Users',
                  description: 'Registered accounts',
                  color: c.info,
                  onTap: () => context.go('/users'),
                ),
                AdminStatCard(
                  icon: Icons.volunteer_activism_rounded,
                  value: '$availableDonors',
                  label: 'Available Donors',
                  description: 'Donor mode enabled',
                  color: c.success,
                  onTap: () => context.go('/donors'),
                ),
                AdminStatCard(
                  icon: Icons.verified_user_rounded,
                  value: '$pendingVerification',
                  label: 'Pending Verification',
                  description: 'Need email verification',
                  color: c.warning,
                  onTap: () => context.go('/verification'),
                ),
                AdminStatCard(
                  icon: Icons.receipt_long_rounded,
                  value: '${stats.open}',
                  label: 'Active Requests',
                  description: 'Currently open',
                  color: c.info,
                  onTap: () => context.go('/requests'),
                ),
                AdminStatCard(
                  icon: Icons.emergency_rounded,
                  value: '$emergencyCount',
                  label: 'Emergency Requests',
                  description: 'Urgent / critical',
                  color: c.danger,
                  onTap: () => context.go('/emergency'),
                ),
                AdminStatCard(
                  icon: Icons.check_circle_rounded,
                  value: '${stats.fulfilled}',
                  label: 'Completed',
                  description: 'Donations fulfilled',
                  color: c.success,
                  onTap: () => context.go('/donations'),
                ),
                AdminStatCard(
                  icon: Icons.warning_rounded,
                  value: '${stats.stale}',
                  label: 'Past Expiry',
                  description: 'Open but overdue',
                  color: c.danger,
                ),
                AdminStatCard(
                  icon: Icons.handshake_rounded,
                  value: '${stats.coordinating}',
                  label: 'Coordinating',
                  description: 'Donor on the way',
                  color: c.info,
                  onTap: () => context.go('/connections'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),

            // --- Blood Group Availability ---
            AdminPanel(
              title: 'Blood Group Availability',
              trailing: Text(
                '${users.length} users',
                style: AppTypography.mono(size: 12, color: c.textTertiary),
              ),
              child: _BloodGroupTable(
                users: users,
                requests: async.valueOrNull ?? const [],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // --- Quick Actions ---
            Text('Quick Actions', style: context.text.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AdminQuickAction(
                  icon: Icons.verified_user_rounded,
                  label: 'Review Pending Donors',
                  onTap: () => context.go('/verification'),
                  color: c.warning,
                ),
                AdminQuickAction(
                  icon: Icons.emergency_rounded,
                  label: 'View Emergency Requests',
                  onTap: () => context.go('/emergency'),
                  color: c.danger,
                ),
                AdminQuickAction(
                  icon: Icons.receipt_long_rounded,
                  label: 'View Active Requests',
                  onTap: () => context.go('/requests'),
                  color: c.info,
                ),
                AdminQuickAction(
                  icon: Icons.people_alt_rounded,
                  label: 'Manage Users',
                  onTap: () => context.go('/users'),
                ),
                AdminQuickAction(
                  icon: Icons.local_hospital_rounded,
                  label: 'Verify Hospitals',
                  onTap: () => context.go('/hospitals'),
                  color: c.success,
                ),
                AdminQuickAction(
                  icon: Icons.flag_rounded,
                  label: 'Review Reports',
                  onTap: () => context.go('/reports'),
                  color: c.warning,
                ),
                AdminQuickAction(
                  icon: Icons.analytics_rounded,
                  label: 'View Analytics',
                  onTap: () => context.go('/analytics'),
                  color: c.info,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),

            Builder(
              builder: (context) {
                final isMobile = MediaQuery.sizeOf(context).width < 900;
                final needsAttention = AdminPanel(
                  title: 'Needs Attention',
                  trailing: Text(
                    '${queue.length} of ${stats.total}',
                    style: AppTypography.mono(size: 12, color: c.textTertiary),
                  ),
                  child: AdminRequestTable(
                    requests: queue.take(10).toList(),
                    emptyMessage:
                        'Nothing is stuck. Every open request either has '
                        'a donor or is still inside its window.',
                  ),
                );

                final recentActivity = AdminPanel(
                  title: 'Recent Activity',
                  trailing: TextButton(
                    onPressed: () => context.go('/audit'),
                    child: Text(
                      'View all',
                      style: context.text.labelSmall?.copyWith(color: c.brand),
                    ),
                  ),
                  child: audit.isEmpty
                      ? const AdminEmpty(
                          message: 'No activity yet.',
                          icon: Icons.history_rounded,
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < audit.length && i < 8; i++)
                              AdminActivityItem(
                                icon: _auditIcon(audit[i].action),
                                action: _auditLabel(audit[i].action),
                                detail:
                                    audit[i].detail ?? audit[i].targetId,
                                time: Fmt.relative(audit[i].at),
                                color: _auditColor(c, audit[i].action),
                                isLast:
                                    i == 7 || i == audit.length - 1,
                              ),
                          ],
                        ),
                );

                if (isMobile) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      needsAttention,
                      const SizedBox(height: AppSpacing.lg),
                      recentActivity,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: needsAttention),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(flex: 2, child: recentActivity),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _auditIcon(String action) => switch (action) {
        'request.remove' => Icons.delete_rounded,
        'user.grantAdmin' => Icons.admin_panel_settings_rounded,
        'user.revokeAdmin' => Icons.person_off_rounded,
        'report.resolve' => Icons.flag_rounded,
        'user.verify' => Icons.verified_rounded,
        'user.suspend' => Icons.block_rounded,
        'hospital.verify' => Icons.local_hospital_rounded,
        _ => Icons.history_rounded,
      };

  String _auditLabel(String action) => switch (action) {
        'request.remove' => 'Request removed',
        'user.grantAdmin' => 'Admin granted',
        'user.revokeAdmin' => 'Admin revoked',
        'report.resolve' => 'Report resolved',
        'user.verify' => 'User verified',
        'user.suspend' => 'User suspended',
        'hospital.verify' => 'Hospital verified',
        _ => action,
      };

  Color _auditColor(AppColors c, String action) => switch (action) {
        'request.remove' => c.danger,
        'user.grantAdmin' => c.success,
        'user.revokeAdmin' => c.warning,
        'report.resolve' => c.info,
        _ => c.info,
      };
}

// ---------------------------------------------------------------------------
// Blood Group Availability Table
// ---------------------------------------------------------------------------

class _BloodGroupTable extends StatelessWidget {
  const _BloodGroupTable({required this.users, required this.requests});
  final List<AdminUser> users;
  final List<AdminRequest> requests;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AdminTableScroll(
      minWidth: 480,
      child: Column(
        children: [
          adminHeaderRow(context, [
            ('Blood Group', 2),
            ('Available Donors', 2),
            ('Active Requests', 2),
            ('Emergency', 2),
          ]),
          for (final group in BloodGroup.values)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.border)),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        BloodGroupBadge(group),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${users.where((u) => u.bloodGroup == group && u.isDonorOn).length}',
                      style: AppTypography.mono(
                        size: 13,
                        color: c.success,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${requests.where((r) => r.isOpen && r.bloodGroups.contains(group)).length}',
                      style: AppTypography.mono(
                        size: 13,
                        color: c.info,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${requests.where((r) => r.isOpen && r.urgency == Urgency.critical && r.bloodGroups.contains(group)).length}',
                      style: AppTypography.mono(
                        size: 13,
                        color: c.danger,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Requests Screen (with status filters)
// ---------------------------------------------------------------------------

class AdminRequestsScreen extends ConsumerStatefulWidget {
  const AdminRequestsScreen({super.key});

  @override
  ConsumerState<AdminRequestsScreen> createState() =>
      _AdminRequestsScreenState();
}

class _AdminRequestsScreenState extends ConsumerState<AdminRequestsScreen> {
  RequestStatus? _filter;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(adminRequestsProvider);

    return AdminPage(
      title: 'Blood Requests',
      subtitle: 'Every request in the system, newest first.',
      actions: [
        AdminSearchBar(
          hint: 'Search requests...',
          onChanged: (v) => setState(() => _search = v.toLowerCase()),
        ),
      ],
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmpty(
          icon: Icons.error_outline_rounded,
          message: 'Could not read: $e',
        ),
        data: (all) {
          var shown = _filter == null
              ? all
              : all.where((r) => r.status == _filter).toList();
          if (_search.isNotEmpty) {
            shown = shown
                .where(
                  (r) =>
                      r.requesterName.toLowerCase().contains(_search) ||
                      r.destinationName.toLowerCase().contains(_search) ||
                      r.locationLabel.toLowerCase().contains(_search) ||
                      r.bloodGroups.any(
                        (g) => g.label.toLowerCase().contains(_search),
                      ),
                )
                .toList();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  AdminFilterChip(
                    label: 'All',
                    count: all.length,
                    selected: _filter == null,
                    onTap: () => setState(() => _filter = null),
                  ),
                  for (final s in RequestStatus.values)
                    if (all.any((r) => r.status == s))
                      AdminFilterChip(
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
                trailing: Text(
                  '${shown.length}',
                  style: AppTypography.mono(size: 12, color: c.textTertiary),
                ),
                child: AdminRequestTable(requests: shown),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Emergency Requests Screen
// ---------------------------------------------------------------------------

class AdminEmergencyScreen extends ConsumerWidget {
  const AdminEmergencyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final async = ref.watch(adminRequestsProvider);

    return AdminPage(
      title: 'Emergency Requests',
      subtitle: 'Critical and urgent blood requests requiring immediate attention.',
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmpty(
          icon: Icons.error_outline_rounded,
          message: 'Could not read: $e',
        ),
        data: (all) {
          final emergency = all
              .where(
                (r) =>
                    r.urgency == Urgency.critical ||
                    r.urgency == Urgency.urgent,
              )
              .toList();
          final active = emergency.where((r) => r.isOpen).toList();
          final resolved =
              emergency.where((r) => !r.isOpen).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Emergency stats
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  AdminMetric(
                    value: active.length,
                    label: 'Active emergencies',
                    hint: 'Need immediate action',
                    tone: c.danger,
                  ),
                  AdminMetric(
                    value: active
                        .where((r) => r.urgency == Urgency.critical)
                        .length,
                    label: 'Critical',
                    hint: 'Highest urgency',
                    tone: c.danger,
                  ),
                  AdminMetric(
                    value: active.where((r) => r.isUnmatched).length,
                    label: 'Unmatched',
                    hint: 'No donor accepted',
                    tone: c.warning,
                  ),
                  AdminMetric(
                    value: resolved.length,
                    label: 'Resolved',
                    hint: 'Completed or closed',
                    tone: c.success,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Active emergency table
              AdminPanel(
                title: 'Active Emergency Requests',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.emergency_rounded, size: 14, color: c.danger),
                    const SizedBox(width: 4),
                    Text(
                      '${active.length}',
                      style: AppTypography.mono(size: 12, color: c.danger),
                    ),
                  ],
                ),
                child: AdminRequestTable(
                  requests: active,
                  emptyMessage: 'No active emergency requests.',
                ),
              ),
              if (resolved.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxl),
                AdminPanel(
                  title: 'Resolved Emergency Requests',
                  trailing: Text(
                    '${resolved.length}',
                    style: AppTypography.mono(size: 12, color: c.textTertiary),
                  ),
                  child: AdminRequestTable(requests: resolved.take(20).toList()),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Users Screen (enhanced with search and sub‑filters)
// ---------------------------------------------------------------------------

enum _UserFilter { all, donors, seekers, blocked }

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  _UserFilter _filter = _UserFilter.all;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(adminUsersProvider);

    return AdminPage(
      title: 'Users',
      subtitle: 'Registered people, their donor state, and admin access.',
      actions: [
        AdminSearchBar(
          hint: 'Search users...',
          onChanged: (v) => setState(() => _search = v.toLowerCase()),
        ),
      ],
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmpty(
          icon: Icons.error_outline_rounded,
          message: 'Could not read: $e',
        ),
        data: (users) {
          var shown = switch (_filter) {
            _UserFilter.all => users,
            _UserFilter.donors =>
              users.where((u) => u.donorAvailability != null).toList(),
            _UserFilter.seekers =>
              users.where((u) => u.donorAvailability == null).toList(),
            _UserFilter.blocked => <AdminUser>[],
          };
          if (_search.isNotEmpty) {
            shown = shown
                .where(
                  (u) =>
                      u.name.toLowerCase().contains(_search) ||
                      (u.email?.toLowerCase().contains(_search) ?? false) ||
                      u.phone.contains(_search) ||
                      u.bloodGroup.label.toLowerCase().contains(_search),
                )
                .toList();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  AdminFilterChip(
                    label: 'All',
                    count: users.length,
                    selected: _filter == _UserFilter.all,
                    onTap: () =>
                        setState(() => _filter = _UserFilter.all),
                  ),
                  AdminFilterChip(
                    label: 'Donors',
                    count: users
                        .where((u) => u.donorAvailability != null)
                        .length,
                    selected: _filter == _UserFilter.donors,
                    onTap: () =>
                        setState(() => _filter = _UserFilter.donors),
                  ),
                  AdminFilterChip(
                    label: 'Blood Seekers',
                    count: users
                        .where((u) => u.donorAvailability == null)
                        .length,
                    selected: _filter == _UserFilter.seekers,
                    onTap: () =>
                        setState(() => _filter = _UserFilter.seekers),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AdminPanel(
                title: switch (_filter) {
                  _UserFilter.all => 'All users',
                  _UserFilter.donors => 'Donors',
                  _UserFilter.seekers => 'Blood seekers',
                  _UserFilter.blocked => 'Blocked users',
                },
                trailing: Text(
                  '${shown.length}',
                  style: AppTypography.mono(size: 12, color: c.textTertiary),
                ),
                child: shown.isEmpty
                    ? const AdminEmpty(message: 'No users match this filter.')
                    : AdminTableScroll(
                        minWidth: 720,
                        child: Column(
                          children: [
                            adminHeaderRow(context, [
                              ('Name', 3),
                              ('Group', 1),
                              ('Phone', 2),
                              ('Email', 3),
                              ('Donor', 2),
                              ('Donations', 1),
                              ('Admin', 2),
                            ]),
                            for (final u in shown)
                              _UserRow(user: u),
                          ],
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _UserRow extends ConsumerWidget {
  const _UserRow({required this.user});
  final AdminUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          AdminCell(
            flex: 3,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
                if (user.city != null)
                  Text(
                    user.city!,
                    style: context.text.bodySmall?.copyWith(
                      color: c.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          AdminCell(
            BloodGroupBadge(user.bloodGroup),
          ),
          AdminCell(
            flex: 2,
            Text(
              user.phone,
              style: AppTypography.mono(size: 12, color: c.textSecondary),
            ),
          ),
          AdminCell(
            flex: 3,
            Text(
              user.email ?? 'Not verified',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: user.email == null ? c.textTertiary : c.textPrimary,
              ),
            ),
          ),
          AdminCell(
            flex: 2,
            Text(
              user.isInCooldown
                  ? 'Cooldown'
                  : user.isDonorOn
                      ? 'Available'
                      : 'Off',
              style: context.text.bodySmall?.copyWith(
                color: user.isInCooldown
                    ? c.warning
                    : user.isDonorOn
                        ? c.success
                        : c.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          AdminCell(
            Text(
              '${user.totalDonations}',
              style: AppTypography.mono(size: 12.5, color: c.textPrimary),
            ),
          ),
          AdminCell(
            flex: 2,
            Align(
              alignment: Alignment.centerLeft,
              child: _AdminToggle(user: user),
            ),
          ),
        ],
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
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Switch(value: widget.user.isAdmin, onChanged: _toggle);
  }
}

// ---------------------------------------------------------------------------
// Donors Screen
// ---------------------------------------------------------------------------

class AdminDonorsScreen extends ConsumerStatefulWidget {
  const AdminDonorsScreen({super.key});

  @override
  ConsumerState<AdminDonorsScreen> createState() => _AdminDonorsScreenState();
}

class _AdminDonorsScreenState extends ConsumerState<AdminDonorsScreen> {
  String _search = '';
  BloodGroup? _groupFilter;
  String _availFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(adminUsersProvider);

    return AdminPage(
      title: 'Donors',
      subtitle: 'All users with donor mode configured.',
      actions: [
        AdminSearchBar(
          hint: 'Search donors...',
          onChanged: (v) => setState(() => _search = v.toLowerCase()),
        ),
      ],
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmpty(
          icon: Icons.error_outline_rounded,
          message: 'Could not read: $e',
        ),
        data: (users) {
          var donors =
              users.where((u) => u.donorAvailability != null).toList();

          // Apply filters
          if (_groupFilter != null) {
            donors = donors
                .where((d) => d.bloodGroup == _groupFilter)
                .toList();
          }
          if (_availFilter == 'available') {
            donors = donors.where((d) => d.isDonorOn).toList();
          } else if (_availFilter == 'cooldown') {
            donors = donors.where((d) => d.isInCooldown).toList();
          } else if (_availFilter == 'off') {
            donors = donors.where((d) => !d.isDonorOn).toList();
          }
          if (_search.isNotEmpty) {
            donors = donors
                .where(
                  (d) =>
                      d.name.toLowerCase().contains(_search) ||
                      d.bloodGroup.label.toLowerCase().contains(_search) ||
                      (d.city?.toLowerCase().contains(_search) ?? false),
                )
                .toList();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stats row
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  AdminMetric(
                    value: users
                        .where((u) => u.donorAvailability != null)
                        .length,
                    label: 'Total donors',
                  ),
                  AdminMetric(
                    value: users.where((u) => u.isDonorOn).length,
                    label: 'Available',
                    tone: c.success,
                  ),
                  AdminMetric(
                    value: users.where((u) => u.isInCooldown).length,
                    label: 'In cooldown',
                    tone: c.warning,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Filters
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  // Blood group filter
                  ...BloodGroup.values.map(
                    (g) => AdminFilterChip(
                      label: g.label,
                      count: users
                          .where(
                            (u) =>
                                u.donorAvailability != null &&
                                u.bloodGroup == g,
                          )
                          .length,
                      selected: _groupFilter == g,
                      onTap: () => setState(
                        () => _groupFilter == g
                            ? _groupFilter = null
                            : _groupFilter = g,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  AdminFilterChip(
                    label: 'All',
                    count: users
                        .where((u) => u.donorAvailability != null)
                        .length,
                    selected: _availFilter == 'all',
                    onTap: () => setState(() => _availFilter = 'all'),
                  ),
                  AdminFilterChip(
                    label: 'Available',
                    count: users.where((u) => u.isDonorOn).length,
                    selected: _availFilter == 'available',
                    onTap: () =>
                        setState(() => _availFilter = 'available'),
                  ),
                  AdminFilterChip(
                    label: 'Cooldown',
                    count: users.where((u) => u.isInCooldown).length,
                    selected: _availFilter == 'cooldown',
                    onTap: () =>
                        setState(() => _availFilter = 'cooldown'),
                  ),
                  AdminFilterChip(
                    label: 'Off',
                    count: users
                        .where(
                          (u) =>
                              u.donorAvailability != null && !u.isDonorOn,
                        )
                        .length,
                    selected: _availFilter == 'off',
                    onTap: () => setState(() => _availFilter = 'off'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Table
              AdminPanel(
                title: 'Donors',
                trailing: Text(
                  '${donors.length}',
                  style: AppTypography.mono(size: 12, color: c.textTertiary),
                ),
                child: donors.isEmpty
                    ? const AdminEmpty(
                        message: 'No donors match this filter.',
                      )
                    : AdminTableScroll(
                        minWidth: 700,
                        child: Column(
                          children: [
                            adminHeaderRow(context, [
                              ('Name', 3),
                              ('Blood Group', 2),
                              ('Location', 2),
                              ('Availability', 2),
                              ('Last Donation', 2),
                              ('Total', 1),
                              ('Verified', 2),
                            ]),
                            for (final d in donors)
                              Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: c.border),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.lg,
                                  vertical: AppSpacing.md,
                                ),
                                child: Row(
                                  children: [
                                    AdminCell(
                                      flex: 3,
                                      Text(
                                        d.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.text.titleSmall,
                                      ),
                                    ),
                                    AdminCell(
                                      BloodGroupBadge(d.bloodGroup),
                                      flex: 2,
                                    ),
                                    AdminCell(
                                      flex: 2,
                                      Text(
                                        d.city ?? '—',
                                        style: context.text.bodySmall
                                            ?.copyWith(
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ),
                                    AdminCell(
                                      flex: 2,
                                      StatusPill(
                                        d.isInCooldown
                                            ? 'Cooldown'
                                            : d.isDonorOn
                                                ? 'Available'
                                                : 'Off',
                                        fg: d.isInCooldown
                                            ? c.warning
                                            : d.isDonorOn
                                                ? c.success
                                                : c.textTertiary,
                                        bg: d.isInCooldown
                                            ? c.warningSubtle
                                            : d.isDonorOn
                                                ? c.successSubtle
                                                : c.surfaceMuted,
                                      ),
                                    ),
                                    AdminCell(
                                      flex: 2,
                                      Text(
                                        d.lastDonation != null
                                            ? Fmt.date(d.lastDonation!)
                                            : 'Never',
                                        style: AppTypography.mono(
                                          size: 12,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ),
                                    AdminCell(
                                      Text(
                                        '${d.totalDonations}',
                                        style: AppTypography.mono(
                                          size: 12.5,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                    ),
                                    AdminCell(
                                      flex: 2,
                                      StatusPill(
                                        d.emailVerified
                                            ? 'Verified'
                                            : 'Pending',
                                        fg: d.emailVerified
                                            ? c.success
                                            : c.warning,
                                        bg: d.emailVerified
                                            ? c.successSubtle
                                            : c.warningSubtle,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reports Screen (enhanced)
// ---------------------------------------------------------------------------

class AdminReportsScreen extends ConsumerWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final async = ref.watch(adminReportsProvider);

    return AdminPage(
      title: 'Reports & Abuse',
      subtitle: 'Abuse and problem reports filed by users.',
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmpty(
          icon: Icons.error_outline_rounded,
          message: 'Could not read: $e',
        ),
        data: (reports) {
          final open = reports.where((r) => r.isOpen).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  AdminMetric(value: reports.length, label: 'Total reports'),
                  AdminMetric(
                    value: open,
                    label: 'Open',
                    tone: c.warning,
                  ),
                  AdminMetric(
                    value: reports.length - open,
                    label: 'Resolved',
                    tone: c.success,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              AdminPanel(
                title: 'Filed reports',
                trailing: Text(
                  '$open open',
                  style: AppTypography.mono(size: 12, color: c.textTertiary),
                ),
                child: reports.isEmpty
                    ? const AdminEmpty(
                        icon: Icons.flag_outlined,
                        message:
                            'No reports have been filed. The mobile app has '
                            'no Report screen yet, so nothing can reach this '
                            'queue until that is built.',
                      )
                    : AdminTableScroll(
                        minWidth: 680,
                        child: Column(
                        children: [
                          adminHeaderRow(context, [
                            ('Reason', 3),
                            ('Target', 3),
                            ('Filed', 2),
                            ('Status', 2),
                            ('', 2),
                          ]),
                          for (final r in reports)
                            Container(
                              decoration: BoxDecoration(
                                border:
                                    Border(top: BorderSide(color: c.border)),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                                vertical: AppSpacing.md,
                              ),
                              child: Row(
                                children: [
                                  AdminCell(
                                    flex: 3,
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r.reason,
                                          style: context.text.titleSmall,
                                        ),
                                        if (r.detail != null)
                                          Text(
                                            r.detail!,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: context.text.bodySmall,
                                          ),
                                      ],
                                    ),
                                  ),
                                  AdminCell(
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
                                        size: 11.5,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  ),
                                  AdminCell(
                                    flex: 2,
                                    Text(
                                      Fmt.relative(r.createdAt),
                                      style: AppTypography.mono(
                                        size: 12,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  ),
                                  AdminCell(
                                    flex: 2,
                                    StatusPill(
                                      r.isOpen ? 'Open' : 'Resolved',
                                      fg: r.isOpen ? c.warning : c.success,
                                      bg: r.isOpen
                                          ? c.warningSubtle
                                          : c.successSubtle,
                                    ),
                                  ),
                                  AdminCell(
                                    flex: 2,
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: r.isOpen
                                          ? TextButton(
                                              onPressed: () => ref
                                                  .read(adminBackendProvider)
                                                  ?.resolveReport(
                                                    r.id,
                                                    'Reviewed',
                                                  ),
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
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Moderation Screen
// ---------------------------------------------------------------------------

class AdminModerationScreen extends ConsumerWidget {
  const AdminModerationScreen({super.key});

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    AdminRequest request,
  ) async {
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
              '${request.requesterName} · '
              '${request.bloodGroups.map((g) => g.label).join(", ")} · '
              '${Fmt.units(request.units)}\n\n'
              'This ends the request for everyone: no further matching, '
              'no new coordination. The reason is recorded in the audit log.',
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
            child: const Text('Cancel'),
          ),
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
            trailing: Text(
              '${queue.length}',
              style: AppTypography.mono(size: 12, color: c.textTertiary),
            ),
            child: AdminRequestTable(
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
            trailing: Text(
              '${open.length}',
              style: AppTypography.mono(size: 12, color: c.textTertiary),
            ),
            child: AdminRequestTable(
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
          icon: Icons.error_outline_rounded,
          message: 'Could not read: $e',
        ),
        data: (entries) => AdminPanel(
          title: 'Recent actions',
          trailing: Text(
            '${entries.length}',
            style: AppTypography.mono(size: 12, color: c.textTertiary),
          ),
          child: entries.isEmpty
              ? const AdminEmpty(
                  icon: Icons.fact_check_outlined,
                  message:
                      'No administrative actions have been taken yet. '
                      'Removing a request or changing admin access will be '
                      'recorded here.',
                )
              : AdminTableScroll(
                  minWidth: 720,
                  child: Column(
                    children: [
                      adminHeaderRow(context, [
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
                            vertical: AppSpacing.md,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AdminCell(
                                flex: 2,
                                Text(
                                  '${Fmt.shortDate(e.at)} ${Fmt.clock(e.at)}',
                                  style: AppTypography.mono(
                                    size: 12,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ),
                              AdminCell(
                                flex: 2,
                                Text(
                                  e.actorName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.bodySmall,
                                ),
                              ),
                              AdminCell(
                                flex: 2,
                                Text(
                                  e.action,
                                  style: AppTypography.mono(
                                    size: 12,
                                    color: c.brand,
                                  ),
                                ),
                              ),
                              AdminCell(
                                flex: 3,
                                Text(
                                  e.targetId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.mono(
                                    size: 11.5,
                                    color: c.textTertiary,
                                  ),
                                ),
                              ),
                              AdminCell(
                                flex: 4,
                                Text(
                                  e.detail ?? '—',
                                  style: context.text.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// System Health
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
        .where(
          (r) => r.isUnmatched && r.age > const Duration(minutes: 30),
        )
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
                _HealthCheck(
                  label: 'Database connection',
                  ok: !async.hasError,
                  detail: async.hasError
                      ? 'Firestore read failed: ${async.error}'
                      : 'Reading live request data.',
                ),
                _HealthCheck(
                  label: 'Requests past expiry',
                  ok: stats.stale == 0,
                  detail: stats.stale == 0
                      ? 'Every open request is inside its window.'
                      : '${stats.stale} open request(s) are past their '
                            'expiry and still not closed.',
                ),
                _HealthCheck(
                  label: 'Long-unmatched requests',
                  ok: longUnmatched == 0,
                  detail: longUnmatched == 0
                      ? 'No request has waited over 30 minutes for a donor.'
                      : '$longUnmatched request(s) have waited over 30 '
                            'minutes with nobody accepting.',
                ),
                _HealthCheck(
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
              AdminMetric(value: availableDonors, label: 'Donors available'),
              AdminMetric(value: inCooldown, label: 'Donors in cooldown'),
              AdminMetric(value: verified, label: 'Email on file'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthCheck extends StatelessWidget {
  const _HealthCheck({
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
          Icon(
            ok ? Icons.check_circle_rounded : Icons.warning_rounded,
            size: 18,
            color: ok ? c.success : c.warning,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: context.text.bodySmall?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
