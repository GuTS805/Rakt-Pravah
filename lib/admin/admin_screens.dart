import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/router/routes.dart';
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
// Enhanced Operations Dashboard (Section 9 Architecture)
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
      actions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.successSubtle,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: c.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: c.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'SYSTEM ONLINE',
                    style: context.text.labelSmall?.copyWith(
                      color: c.success,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmpty(
          icon: Icons.error_outline_rounded,
          message: 'Could not read data: $e',
        ),
        data: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===============================================================
            // 1. EMERGENCY ALERT BANNER (Top Visibility)
            // ===============================================================
            if (emergencyCount > 0)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.xl),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: c.brandSubtle,
                  borderRadius: AppRadius.cardMd,
                  border: Border.all(
                    color: c.brand.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 600;
                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                decoration: BoxDecoration(
                                  color: c.brand,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.emergency_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  '$emergencyCount Active Emergency Request(s)',
                                  style: context.text.titleSmall?.copyWith(
                                    color: c.brand,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Critical patient requirements are active. Immediate coordination recommended.',
                            style: context.text.bodySmall?.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: c.brand,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(40),
                            ),
                            onPressed: () => context.go(Routes.adminEmergency),
                            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                            label: const Text('View Emergencies'),
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: c.brand,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.emergency_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$emergencyCount Active Emergency Request(s) Require Attention',
                                style: context.text.titleSmall?.copyWith(
                                  color: c.brand,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Critical patient requirements are active. Immediate coordination recommended.',
                                style: context.text.bodySmall?.copyWith(
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: c.brand,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            minimumSize: const Size(44, 40),
                          ),
                          onPressed: () => context.go(Routes.adminEmergency),
                          icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                          label: const Text('View Emergencies'),
                        ),
                      ],
                    );
                  },
                ),
              )
            else
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.xl),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: c.successSubtle,
                  borderRadius: AppRadius.cardMd,
                  border: Border.all(color: c.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 18, color: c.success),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'All emergency requests resolved. No critical alerts active.',
                        style: context.text.bodySmall?.copyWith(
                          color: c.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ===============================================================
            // 2. KEY STATISTICS
            // ===============================================================
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
                  onTap: () => context.go(Routes.adminUsers),
                ),
                AdminStatCard(
                  icon: Icons.volunteer_activism_rounded,
                  value: '$availableDonors',
                  label: 'Available Donors',
                  description: 'Donor mode enabled',
                  color: c.success,
                  onTap: () => context.go(Routes.adminDonors),
                ),
                AdminStatCard(
                  icon: Icons.verified_user_rounded,
                  value: '$pendingVerification',
                  label: 'Pending Verification',
                  description: 'Need email verification',
                  color: c.warning,
                  onTap: () => context.go(Routes.adminVerification),
                ),
                AdminStatCard(
                  icon: Icons.receipt_long_rounded,
                  value: '${stats.open}',
                  label: 'Active Requests',
                  description: 'Currently open',
                  color: c.info,
                  onTap: () => context.go(Routes.adminRequests),
                ),
                AdminStatCard(
                  icon: Icons.emergency_rounded,
                  value: '$emergencyCount',
                  label: 'Emergency Requests',
                  description: 'Urgent / critical',
                  color: c.danger,
                  onTap: () => context.go(Routes.adminEmergency),
                ),
                AdminStatCard(
                  icon: Icons.check_circle_rounded,
                  value: '${stats.fulfilled}',
                  label: 'Completed',
                  description: 'Donations fulfilled',
                  color: c.success,
                  onTap: () => context.go(Routes.adminDonations),
                ),
                AdminStatCard(
                  icon: Icons.warning_rounded,
                  value: '${stats.stale}',
                  label: 'Past Expiry',
                  description: 'Open but overdue',
                  color: c.danger,
                  onTap: () => context.go(Routes.adminRequests),
                ),
                AdminStatCard(
                  icon: Icons.handshake_rounded,
                  value: '${stats.coordinating}',
                  label: 'Coordinating',
                  description: 'Donor on the way',
                  color: c.info,
                  onTap: () => context.go(Routes.adminConnections),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),

            // ===============================================================
            // 3. QUICK ACTIONS (Operational & System Focused)
            // ===============================================================
            Text('Quick Actions', style: context.text.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AdminQuickAction(
                  icon: Icons.people_alt_rounded,
                  label: 'Manage Users',
                  onTap: () => context.go(Routes.adminUsers),
                  color: c.info,
                ),
                AdminQuickAction(
                  icon: Icons.emergency_rounded,
                  label: 'Emergency Monitoring',
                  onTap: () => context.go(Routes.adminEmergency),
                  color: c.danger,
                ),
                AdminQuickAction(
                  icon: Icons.volunteer_activism_rounded,
                  label: 'Donor Network',
                  onTap: () => context.go(Routes.adminDonors),
                  color: c.success,
                ),
                AdminQuickAction(
                  icon: Icons.water_drop_rounded,
                  label: 'Blood Availability',
                  onTap: () => context.go(Routes.adminAvailability),
                  color: c.brand,
                ),
                AdminQuickAction(
                  icon: Icons.analytics_rounded,
                  label: 'View Analytics',
                  onTap: () => context.go(Routes.adminAnalytics),
                  color: c.info,
                ),
                AdminQuickAction(
                  icon: Icons.fact_check_rounded,
                  label: 'Activity Logs',
                  onTap: () => context.go(Routes.adminAudit),
                  color: c.warning,
                ),
                AdminQuickAction(
                  icon: Icons.summarize_rounded,
                  label: 'Reports',
                  onTap: () => context.go(Routes.adminReports),
                  color: c.info,
                ),
                AdminQuickAction(
                  icon: Icons.notifications_rounded,
                  label: 'Notifications',
                  onTap: () => context.go(Routes.adminNotifications),
                  color: c.warning,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),

            // ===============================================================
            // 4. NEEDS ATTENTION & 5. RECENT ACTIVITY
            // ===============================================================
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
                    onPressed: () => context.go(Routes.adminAudit),
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
            const SizedBox(height: AppSpacing.xxl),

            // ===============================================================
            // 6. BLOOD GROUP AVAILABILITY (System-Wide)
            // ===============================================================
            AdminPanel(
              title: 'Blood Group Availability',
              trailing: TextButton.icon(
                onPressed: () => context.go(Routes.adminAvailability),
                icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                label: const Text('Detailed Inventory'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BloodGroupTable(
                    users: users,
                    requests: async.valueOrNull ?? const [],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 14, color: c.textTertiary),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            'Availability states calculated from registered active donors; '
                            'lab-verified shelf inventory requires hospital integration.',
                            style: context.text.bodySmall?.copyWith(
                              color: c.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // ===============================================================
            // 7. ANALYTICS PREVIEW
            // ===============================================================
            AdminPanel(
              title: 'Analytics & System Trends',
              trailing: TextButton.icon(
                onPressed: () => context.go(Routes.adminAnalytics),
                icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                label: const Text('Full Analytics'),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 600;
                    return Wrap(
                      spacing: AppSpacing.lg,
                      runSpacing: AppSpacing.md,
                      children: [
                        _DashboardMetricPill(
                          title: 'Resolution Rate',
                          value: stats.total > 0
                              ? '${((stats.fulfilled / stats.total) * 100).toStringAsFixed(1)}%'
                              : '—',
                          subtitle: '${stats.fulfilled} of ${stats.total} resolved',
                          tone: c.success,
                          width: isCompact ? double.infinity : 200,
                        ),
                        _DashboardMetricPill(
                          title: 'Donor Readiness',
                          value: users.isNotEmpty
                              ? '${((availableDonors / users.length) * 100).toStringAsFixed(0)}%'
                              : '0%',
                          subtitle: '$availableDonors ready donors',
                          tone: c.info,
                          width: isCompact ? double.infinity : 200,
                        ),
                        _DashboardMetricPill(
                          title: 'Emergency Share',
                          value: stats.open > 0
                              ? '${((emergencyCount / stats.open) * 100).toStringAsFixed(0)}%'
                              : '0%',
                          subtitle: '$emergencyCount urgent cases',
                          tone: emergencyCount > 0 ? c.danger : c.success,
                          width: isCompact ? double.infinity : 200,
                        ),
                      ],
                    );
                  },
                ),
              ),
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
        'user.activate' => Icons.check_circle_outline_rounded,
        'user.deactivate' => Icons.block_rounded,
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
        'user.activate' => 'Account activated',
        'user.deactivate' => 'Account deactivated',
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
        'user.activate' => c.success,
        'user.deactivate' => c.danger,
        'report.resolve' => c.info,
        _ => c.info,
      };
}

class _DashboardMetricPill extends StatelessWidget {
  const _DashboardMetricPill({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.tone,
    required this.width,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color tone;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: width,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: AppRadius.cardMd,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.labelSmall?.copyWith(color: c.textSecondary)),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.mono(
              size: 24,
              weight: FontWeight.w700,
              color: tone,
            ),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: context.text.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Blood Group Availability Table (with Clear AVAILABLE / LOW / CRITICAL States)
// ---------------------------------------------------------------------------

class _BloodGroupTable extends StatelessWidget {
  const _BloodGroupTable({required this.users, required this.requests});
  final List<AdminUser> users;
  final List<AdminRequest> requests;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AdminTableScroll(
      minWidth: 540,
      child: Column(
        children: [
          adminHeaderRow(context, [
            ('Blood Group', 2),
            ('Availability State', 2),
            ('Ready Donors', 2),
            ('Active Demands', 2),
            ('Emergency Need', 2),
          ]),
          for (final group in BloodGroup.values)
            _buildRow(context, group, c),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, BloodGroup group, AppColors c) {
    final availableDonors = users
        .where((u) => u.bloodGroup == group && u.isDonorOn && !u.isInCooldown)
        .length;
    final activeDemands = requests
        .where((r) => r.isOpen && r.bloodGroups.contains(group))
        .length;
    final criticalNeed = requests
        .where((r) =>
            r.isOpen &&
            r.urgency == Urgency.critical &&
            r.bloodGroups.contains(group))
        .length;

    final String stateLabel;
    final Color stateFg;
    final Color stateBg;

    if (criticalNeed > 0 || (availableDonors == 0 && activeDemands > 0) || availableDonors < 2) {
      stateLabel = 'CRITICAL';
      stateFg = c.danger;
      stateBg = c.dangerSubtle;
    } else if (availableDonors <= 3 || availableDonors <= activeDemands) {
      stateLabel = 'LOW';
      stateFg = c.warning;
      stateBg = c.warningSubtle;
    } else {
      stateLabel = 'AVAILABLE';
      stateFg = c.success;
      stateBg = c.successSubtle;
    }

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
            child: StatusPill(
              stateLabel,
              fg: stateFg,
              bg: stateBg,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '$availableDonors',
              style: AppTypography.mono(
                size: 13,
                color: availableDonors > 0 ? c.success : c.danger,
                weight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '$activeDemands',
              style: AppTypography.mono(
                size: 13,
                color: c.info,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '$criticalNeed',
              style: AppTypography.mono(
                size: 13,
                color: criticalNeed > 0 ? c.danger : c.textSecondary,
                weight: criticalNeed > 0 ? FontWeight.w700 : FontWeight.w500,
              ),
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
// Operational Emergency Monitoring Screen (Section 8 Architecture)
// ---------------------------------------------------------------------------

class AdminEmergencyScreen extends ConsumerStatefulWidget {
  const AdminEmergencyScreen({super.key});

  @override
  ConsumerState<AdminEmergencyScreen> createState() =>
      _AdminEmergencyScreenState();
}

class _AdminEmergencyScreenState extends ConsumerState<AdminEmergencyScreen> {
  String _search = '';
  Urgency? _urgencyFilter;
  String _statusFilter = 'active'; // 'active', 'resolved', 'all'

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(adminRequestsProvider);

    return AdminPage(
      title: 'Emergency Monitoring',
      subtitle:
          'Real-time operational monitoring of critical blood requests and hospital response.',
      actions: [
        AdminSearchBar(
          hint: 'Search emergency cases...',
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
          final emergencies = all
              .where(
                (r) =>
                    r.urgency == Urgency.critical ||
                    r.urgency == Urgency.urgent,
              )
              .toList();

          final activeList = emergencies.where((r) => r.isOpen).toList();
          final criticalCount =
              activeList.where((r) => r.urgency == Urgency.critical).length;
          final highCount =
              activeList.where((r) => r.urgency == Urgency.urgent).length;
          final unmatchedCount =
              activeList.where((r) => r.isUnmatched).length;
          final resolvedList =
              emergencies.where((r) => !r.isOpen).toList();

          var shown = switch (_statusFilter) {
            'active' => activeList,
            'resolved' => resolvedList,
            _ => emergencies,
          };

          if (_urgencyFilter != null) {
            shown = shown.where((r) => r.urgency == _urgencyFilter).toList();
          }

          if (_search.isNotEmpty) {
            shown = shown.where((r) {
              return r.destinationName.toLowerCase().contains(_search) ||
                  r.requesterName.toLowerCase().contains(_search) ||
                  r.locationLabel.toLowerCase().contains(_search) ||
                  r.bloodGroups.any(
                    (g) => g.label.toLowerCase().contains(_search),
                  );
            }).toList();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Operational Metrics
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  AdminMetric(
                    value: activeList.length,
                    label: 'Active Emergencies',
                    hint: 'Awaiting completion',
                    tone: c.danger,
                  ),
                  AdminMetric(
                    value: criticalCount,
                    label: 'Critical Priority',
                    hint: 'Immediate threat',
                    tone: c.danger,
                  ),
                  AdminMetric(
                    value: highCount,
                    label: 'High Priority',
                    hint: 'Urgent turnaround',
                    tone: c.warning,
                  ),
                  AdminMetric(
                    value: unmatchedCount,
                    label: 'Unmatched',
                    hint: 'Awaiting first donor',
                    tone: c.warning,
                  ),
                  AdminMetric(
                    value: resolvedList.length,
                    label: 'Resolved',
                    hint: 'Fulfilled or closed',
                    tone: c.success,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Filter Controls
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AdminFilterChip(
                    label: 'Active Cases',
                    count: activeList.length,
                    selected: _statusFilter == 'active',
                    onTap: () => setState(() => _statusFilter = 'active'),
                  ),
                  AdminFilterChip(
                    label: 'Resolved Cases',
                    count: resolvedList.length,
                    selected: _statusFilter == 'resolved',
                    onTap: () => setState(() => _statusFilter = 'resolved'),
                  ),
                  AdminFilterChip(
                    label: 'All Cases',
                    count: emergencies.length,
                    selected: _statusFilter == 'all',
                    onTap: () => setState(() => _statusFilter = 'all'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Priority:',
                    style: context.text.labelSmall
                        ?.copyWith(color: c.textSecondary),
                  ),
                  AdminFilterChip(
                    label: 'All Priorities',
                    count: emergencies.length,
                    selected: _urgencyFilter == null,
                    onTap: () => setState(() => _urgencyFilter = null),
                  ),
                  AdminFilterChip(
                    label: 'CRITICAL',
                    count: emergencies
                        .where((r) => r.urgency == Urgency.critical)
                        .length,
                    selected: _urgencyFilter == Urgency.critical,
                    onTap: () => setState(
                      () => _urgencyFilter =
                          _urgencyFilter == Urgency.critical
                              ? null
                              : Urgency.critical,
                    ),
                  ),
                  AdminFilterChip(
                    label: 'HIGH',
                    count: emergencies
                        .where((r) => r.urgency == Urgency.urgent)
                        .length,
                    selected: _urgencyFilter == Urgency.urgent,
                    onTap: () => setState(
                      () => _urgencyFilter =
                          _urgencyFilter == Urgency.urgent
                              ? null
                              : Urgency.urgent,
                    ),
                  ),
                  AdminFilterChip(
                    label: 'NORMAL',
                    count: emergencies
                        .where((r) => r.urgency == Urgency.routine)
                        .length,
                    selected: _urgencyFilter == Urgency.routine,
                    onTap: () => setState(
                      () => _urgencyFilter =
                          _urgencyFilter == Urgency.routine
                              ? null
                              : Urgency.routine,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Operational Table / Cards
              AdminPanel(
                title: switch (_statusFilter) {
                  'active' => 'Active Emergency Monitoring',
                  'resolved' => 'Resolved Emergency Cases',
                  _ => 'All Emergency Cases',
                },
                trailing: Text(
                  '${shown.length} shown',
                  style: AppTypography.mono(size: 12, color: c.textTertiary),
                ),
                child: shown.isEmpty
                    ? const AdminEmpty(
                        message: 'No emergency cases match the current filter.',
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final isMobile = constraints.maxWidth < 800;
                          if (isMobile) {
                            return Column(
                              children: [
                                for (final req in shown)
                                  _EmergencyMobileCard(
                                    request: req,
                                    onViewDetails: () =>
                                        _showCaseDetails(context, ref, req),
                                    onResolve: () =>
                                        _resolveCase(context, ref, req),
                                  ),
                              ],
                            );
                          }

                          return AdminTableScroll(
                            minWidth: 850,
                            child: Column(
                              children: [
                                adminHeaderRow(context, [
                                  ('Priority', 2),
                                  ('Requirement', 2),
                                  ('Hospital / Location', 3),
                                  ('Status', 2),
                                  ('Contacted', 1),
                                  ('Response', 2),
                                  ('Elapsed', 2),
                                  ('Actions', 2),
                                ]),
                                for (final req in shown)
                                  _EmergencyTableRow(
                                    request: req,
                                    onViewDetails: () =>
                                        _showCaseDetails(context, ref, req),
                                    onResolve: () =>
                                        _resolveCase(context, ref, req),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCaseDetails(
    BuildContext context,
    WidgetRef ref,
    AdminRequest request,
  ) {
    final c = context.colors;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            _emergencyPriorityBadge(c, request.urgency),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Case: ${request.destinationName}',
                style: context.text.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow('Case ID', request.id),
                _detailRow('Requester', request.requesterName),
                _detailRow(
                  'Blood Required',
                  '${request.bloodGroups.map((g) => g.label).join(", ")} (${request.units} units)',
                ),
                _detailRow('Hospital / Destination', request.destinationName),
                _detailRow(
                  'Location',
                  request.locationLabel.isEmpty
                      ? 'Not specified'
                      : request.locationLabel,
                ),
                _detailRow('Case Status', request.status.label),
                _detailRow(
                  'Contacted Donors',
                  '${request.declinedCount + request.acceptedDonorIds.length} donors contacted',
                ),
                _detailRow(
                  'Accepted Response',
                  request.acceptedDonorName ?? 'Awaiting accepted response',
                ),
                _detailRow(
                  'Created At',
                  '${Fmt.date(request.createdAt)} (${Fmt.relative(request.createdAt)})',
                ),
                if (request.expiresAt != null)
                  _detailRow(
                    'Expiry Window',
                    '${Fmt.date(request.expiresAt!)} (${Fmt.relative(request.expiresAt!)})',
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          if (request.isOpen)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: c.brand),
              onPressed: () {
                Navigator.of(ctx).pop();
                _resolveCase(context, ref, request);
              },
              icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
              label: const Text('Resolve Case'),
            ),
        ],
      ),
    );
  }

  Future<void> _resolveCase(
    BuildContext context,
    WidgetRef ref,
    AdminRequest request,
  ) async {
    final c = context.colors;
    final controller = TextEditingController(
      text: 'Case resolved by Operations Admin.',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolve Emergency Case'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mark emergency case at ${request.destinationName} as resolved?',
              style: ctx.text.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Resolution note / outcome',
                hintText: 'Enter outcome or closure reason...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.brand),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Resolve Case'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final admin = ref.read(adminBackendProvider);
      if (admin != null) {
        await admin.removeRequest(request.id, controller.text.trim());
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Emergency case marked as resolved.')),
          );
        }
      }
    }
  }

  static Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _emergencyPriorityBadge(AppColors c, Urgency urgency) {
  final (label, bg, fg, icon) = switch (urgency) {
    Urgency.critical => (
        'CRITICAL',
        c.dangerSubtle,
        c.danger,
        Icons.warning_amber_rounded
      ),
    Urgency.urgent => (
        'HIGH',
        c.warningSubtle,
        c.warning,
        Icons.priority_high_rounded
      ),
    Urgency.routine => (
        'NORMAL',
        c.infoSubtle,
        c.info,
        Icons.info_outline_rounded
      ),
  };

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: AppRadius.control,
      border: Border.all(color: fg.withValues(alpha: 0.3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: fg),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTypography.mono(
            size: 11,
            color: fg,
            weight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _EmergencyTableRow extends StatelessWidget {
  const _EmergencyTableRow({
    required this.request,
    required this.onViewDetails,
    required this.onResolve,
  });

  final AdminRequest request;
  final VoidCallback onViewDetails;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
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
            flex: 2,
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: _emergencyPriorityBadge(c, request.urgency),
            ),
          ),
          AdminCell(
            flex: 2,
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: c.brandSubtle,
                    borderRadius: AppRadius.control,
                  ),
                  child: Text(
                    request.bloodGroups.map((g) => g.label).join(' '),
                    style: AppTypography.mono(
                      size: 12,
                      color: c.brand,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${request.units}u',
                  style: AppTypography.mono(size: 12, color: c.textSecondary),
                ),
              ],
            ),
          ),
          AdminCell(
            flex: 3,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.destinationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
                Text(
                  request.locationLabel.isEmpty
                      ? request.requesterName
                      : request.locationLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(
                    color: c.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          AdminCell(
            flex: 2,
            RequestStatusPill(request.status),
          ),
          AdminCell(
            flex: 1,
            Text(
              '${request.declinedCount + request.acceptedDonorIds.length}',
              style: AppTypography.mono(size: 12, color: c.textPrimary),
            ),
          ),
          AdminCell(
            flex: 2,
            Text(
              request.acceptedDonorName ?? 'Awaiting',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: request.acceptedDonorName != null
                    ? c.success
                    : c.textTertiary,
                fontWeight: request.acceptedDonorName != null
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ),
          AdminCell(
            flex: 2,
            Text(
              Fmt.relative(request.createdAt),
              style: AppTypography.mono(size: 12, color: c.textSecondary),
            ),
          ),
          AdminCell(
            flex: 2,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'View Details',
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  onPressed: onViewDetails,
                ),
                if (request.isOpen)
                  IconButton(
                    tooltip: 'Resolve Case',
                    icon: Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: c.brand,
                    ),
                    onPressed: onResolve,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyMobileCard extends StatelessWidget {
  const _EmergencyMobileCard({
    required this.request,
    required this.onViewDetails,
    required this.onResolve,
  });

  final AdminRequest request;
  final VoidCallback onViewDetails;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.cardMd,
        border: Border.all(
          color: request.urgency == Urgency.critical
              ? c.danger.withValues(alpha: 0.3)
              : c.border,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _emergencyPriorityBadge(c, request.urgency),
              RequestStatusPill(request.status),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: c.brandSubtle,
                      borderRadius: AppRadius.control,
                    ),
                    child: Text(
                      request.bloodGroups.map((g) => g.label).join(' '),
                      style: AppTypography.mono(
                        size: 13,
                        color: c.brand,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${request.units} ${request.units == 1 ? "unit" : "units"} needed',
                    style: AppTypography.mono(size: 12, color: c.textSecondary),
                  ),
                ],
              ),
              Text(
                Fmt.relative(request.createdAt),
                style: AppTypography.mono(size: 11, color: c.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            request.destinationName,
            style: context.text.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (request.locationLabel.isNotEmpty)
            Text(
              request.locationLabel,
              style: context.text.bodySmall?.copyWith(color: c.textTertiary),
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                'Contacted: ${request.declinedCount + request.acceptedDonorIds.length}',
                style: AppTypography.mono(size: 11, color: c.textSecondary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Response: ${request.acceptedDonorName ?? "Awaiting"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(
                    color: request.acceptedDonorName != null
                        ? c.success
                        : c.textTertiary,
                    fontWeight: request.acceptedDonorName != null
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: onViewDetails,
                  child: const Text('View Details'),
                ),
              ),
              if (request.isOpen) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.brand,
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: onResolve,
                    child: const Text('Resolve'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Users Screen (Section 8 User Management)
// ---------------------------------------------------------------------------

enum _UserFilter { all, donors, seekers, admins, inactive }

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
      subtitle:
          'Registered users, donor profiles, verification status, and administrative access.',
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
            _UserFilter.admins => users.where((u) => u.isAdmin).toList(),
            _UserFilter.inactive => users.where((u) => !u.isActive).toList(),
          };

          if (_search.isNotEmpty) {
            shown = shown
                .where(
                  (u) =>
                      u.name.toLowerCase().contains(_search) ||
                      (u.email?.toLowerCase().contains(_search) ?? false) ||
                      u.phone.contains(_search) ||
                      (u.city?.toLowerCase().contains(_search) ?? false) ||
                      u.bloodGroup.label.toLowerCase().contains(_search),
                )
                .toList();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AdminFilterChip(
                    label: 'All',
                    count: users.length,
                    selected: _filter == _UserFilter.all,
                    onTap: () => setState(() => _filter = _UserFilter.all),
                  ),
                  AdminFilterChip(
                    label: 'Donors',
                    count: users
                        .where((u) => u.donorAvailability != null)
                        .length,
                    selected: _filter == _UserFilter.donors,
                    onTap: () => setState(() => _filter = _UserFilter.donors),
                  ),
                  AdminFilterChip(
                    label: 'Blood Seekers',
                    count: users
                        .where((u) => u.donorAvailability == null)
                        .length,
                    selected: _filter == _UserFilter.seekers,
                    onTap: () => setState(() => _filter = _UserFilter.seekers),
                  ),
                  AdminFilterChip(
                    label: 'Admins',
                    count: users.where((u) => u.isAdmin).length,
                    selected: _filter == _UserFilter.admins,
                    onTap: () => setState(() => _filter = _UserFilter.admins),
                  ),
                  AdminFilterChip(
                    label: 'Inactive',
                    count: users.where((u) => !u.isActive).length,
                    selected: _filter == _UserFilter.inactive,
                    onTap: () => setState(() => _filter = _UserFilter.inactive),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AdminPanel(
                title: switch (_filter) {
                  _UserFilter.all => 'All users',
                  _UserFilter.donors => 'Donors',
                  _UserFilter.seekers => 'Blood seekers',
                  _UserFilter.admins => 'System Administrators',
                  _UserFilter.inactive => 'Inactive Accounts',
                },
                trailing: Text(
                  '${shown.length}',
                  style: AppTypography.mono(size: 12, color: c.textTertiary),
                ),
                child: shown.isEmpty
                    ? const AdminEmpty(message: 'No users match this filter.')
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final isMobile = constraints.maxWidth < 800;
                          if (isMobile) {
                            return Column(
                              children: [
                                for (final u in shown)
                                  _UserMobileCard(
                                    user: u,
                                    onViewProfile: () =>
                                        _showUserProfile(context, ref, u),
                                  ),
                              ],
                            );
                          }

                          return AdminTableScroll(
                            minWidth: 800,
                            child: Column(
                              children: [
                                adminHeaderRow(context, [
                                  ('Name', 3),
                                  ('Group', 1),
                                  ('Phone', 2),
                                  ('Email', 3),
                                  ('Donor', 2),
                                  ('Donations', 1),
                                  ('Status', 2),
                                  ('Admin', 1),
                                  ('Actions', 2),
                                ]),
                                for (final u in shown)
                                  _UserRow(
                                    user: u,
                                    onViewProfile: () =>
                                        _showUserProfile(context, ref, u),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showUserProfile(BuildContext context, WidgetRef ref, AdminUser user) {
    final c = context.colors;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                BloodGroupBadge(user.bloodGroup),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: context.text.titleMedium),
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
                if (user.isAdmin)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: c.brandSubtle,
                      borderRadius: AppRadius.control,
                    ),
                    child: Text(
                      'ADMIN',
                      style: AppTypography.mono(
                        size: 11,
                        color: c.brand,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _userField('User ID', user.id),
                    _userField('Phone', user.phone),
                    _userField('Email', user.email ?? 'Not provided'),
                    _userField(
                      'Email Verification',
                      user.emailVerified ? 'Verified' : 'Pending Verification',
                    ),
                    _userField(
                      'Account State',
                      user.isActive ? 'Active' : 'Deactivated',
                    ),
                    _userField(
                      'Donor Status',
                      user.isInCooldown
                          ? 'In Cooldown'
                          : user.isDonorOn
                              ? 'Available (Mode ON)'
                              : 'Off / Seek Only',
                    ),
                    if (user.lastDonation != null)
                      _userField(
                        'Last Donation',
                        '${Fmt.date(user.lastDonation!)} (${Fmt.relative(user.lastDonation!)})',
                      ),
                    _userField('Total Donations', '${user.totalDonations}'),
                    const Divider(height: AppSpacing.xl),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Administrator Access',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        _AdminToggle(user: user),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          user.isActive
                              ? 'Account Status (Active)'
                              : 'Account Status (Deactivated)',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: user.isActive ? c.textPrimary : c.danger,
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final admin = ref.read(adminBackendProvider);
                            if (admin != null) {
                              await admin.setUserActive(
                                user.id,
                                !user.isActive,
                              );
                              if (ctx.mounted) {
                                Navigator.of(ctx).pop();
                              }
                            }
                          },
                          child: Text(
                            user.isActive ? 'Deactivate' : 'Activate',
                            style: TextStyle(
                              color: user.isActive ? c.danger : c.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  static Widget _userField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserRow extends ConsumerWidget {
  const _UserRow({required this.user, required this.onViewProfile});

  final AdminUser user;
  final VoidCallback onViewProfile;

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
            flex: 1,
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
            flex: 1,
            Text(
              '${user.totalDonations}',
              style: AppTypography.mono(size: 12.5, color: c.textPrimary),
            ),
          ),
          AdminCell(
            flex: 2,
            StatusPill(
              user.isActive ? 'Active' : 'Inactive',
              fg: user.isActive ? c.success : c.danger,
              bg: user.isActive ? c.successSubtle : c.dangerSubtle,
            ),
          ),
          AdminCell(
            flex: 1,
            Align(
              alignment: Alignment.centerLeft,
              child: _AdminToggle(user: user),
            ),
          ),
          AdminCell(
            flex: 2,
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onViewProfile,
                child: const Text('Profile'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserMobileCard extends StatelessWidget {
  const _UserMobileCard({
    required this.user,
    required this.onViewProfile,
  });

  final AdminUser user;
  final VoidCallback onViewProfile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.cardMd,
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    BloodGroupBadge(user.bloodGroup),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusPill(
                user.isActive ? 'Active' : 'Inactive',
                fg: user.isActive ? c.success : c.danger,
                bg: user.isActive ? c.successSubtle : c.dangerSubtle,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                user.phone,
                style: AppTypography.mono(size: 12, color: c.textSecondary),
              ),
              if (user.city != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '• ${user.city!}',
                    style: context.text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          if (user.email != null)
            Text(
              user.email!,
              style: context.text.bodySmall?.copyWith(color: c.textTertiary),
            ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Donor Mode: ', style: TextStyle(fontSize: 12)),
                  Text(
                    user.isInCooldown
                        ? 'Cooldown'
                        : user.isDonorOn
                            ? 'Available'
                            : 'Off',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: user.isInCooldown
                          ? c.warning
                          : user.isDonorOn
                              ? c.success
                              : c.textTertiary,
                    ),
                  ),
                ],
              ),
              Text(
                'Donations: ${user.totalDonations}',
                style: AppTypography.mono(size: 12, color: c.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: onViewProfile,
                  child: const Text('View Profile'),
                ),
              ),
            ],
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
// Donors Screen (Section 8 Donor Network)
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
  String _sortBy = 'name'; // 'name', 'donations', 'recent'

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(adminUsersProvider);

    return AdminPage(
      title: 'Donor Network',
      subtitle:
          'Admin-level donor management, availability status, and distribution.',
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

          // Apply group filter
          if (_groupFilter != null) {
            donors = donors
                .where((d) => d.bloodGroup == _groupFilter)
                .toList();
          }

          // Apply availability filter
          if (_availFilter == 'available') {
            donors = donors.where((d) => d.isDonorOn).toList();
          } else if (_availFilter == 'cooldown') {
            donors = donors.where((d) => d.isInCooldown).toList();
          } else if (_availFilter == 'off') {
            donors = donors.where((d) => !d.isDonorOn).toList();
          }

          // Apply search
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

          // Apply sorting
          if (_sortBy == 'donations') {
            donors.sort((a, b) => b.totalDonations.compareTo(a.totalDonations));
          } else if (_sortBy == 'recent') {
            donors.sort((a, b) {
              final aDate = a.lastDonation ?? DateTime(1970);
              final bDate = b.lastDonation ?? DateTime(1970);
              return bDate.compareTo(aDate);
            });
          } else {
            donors.sort((a, b) => a.name.compareTo(b.name));
          }

          final totalDonors =
              users.where((u) => u.donorAvailability != null).length;
          final availableCount = users.where((u) => u.isDonorOn).length;
          final cooldownCount = users.where((u) => u.isInCooldown).length;
          final offCount =
              users.where((u) => u.donorAvailability != null && !u.isDonorOn).length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stats
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  AdminMetric(
                    value: totalDonors,
                    label: 'Total Registered Donors',
                    hint: 'Donor Mode configured',
                  ),
                  AdminMetric(
                    value: availableCount,
                    label: 'Available (Mode ON)',
                    hint: 'Ready for emergency alert',
                    tone: c.success,
                  ),
                  AdminMetric(
                    value: cooldownCount,
                    label: 'In Cooldown',
                    hint: 'Recent donation recovery',
                    tone: c.warning,
                  ),
                  AdminMetric(
                    value: offCount,
                    label: 'Donor Mode OFF',
                    hint: 'Standby / Paused',
                    tone: c.textTertiary,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Blood group filter chips
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
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

              // Availability filter chips
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AdminFilterChip(
                    label: 'All',
                    count: totalDonors,
                    selected: _availFilter == 'all',
                    onTap: () => setState(() => _availFilter = 'all'),
                  ),
                  AdminFilterChip(
                    label: 'Available',
                    count: availableCount,
                    selected: _availFilter == 'available',
                    onTap: () => setState(() => _availFilter = 'available'),
                  ),
                  AdminFilterChip(
                    label: 'Cooldown',
                    count: cooldownCount,
                    selected: _availFilter == 'cooldown',
                    onTap: () => setState(() => _availFilter = 'cooldown'),
                  ),
                  AdminFilterChip(
                    label: 'Off',
                    count: offCount,
                    selected: _availFilter == 'off',
                    onTap: () => setState(() => _availFilter = 'off'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Donors Table / Cards
              AdminPanel(
                title: 'Donors',
                trailing: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    Text(
                      'Sort: ',
                      style: context.text.labelSmall
                          ?.copyWith(color: c.textTertiary),
                    ),
                    DropdownButton<String>(
                      value: _sortBy,
                      underline: const SizedBox.shrink(),
                      style: context.text.bodySmall?.copyWith(color: c.brand),
                      items: const [
                        DropdownMenuItem(
                          value: 'name',
                          child: Text('Name (A-Z)'),
                        ),
                        DropdownMenuItem(
                          value: 'donations',
                          child: Text('Total Donations'),
                        ),
                        DropdownMenuItem(
                          value: 'recent',
                          child: Text('Recent Donation'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _sortBy = v);
                      },
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${donors.length}',
                      style: AppTypography.mono(
                        size: 12,
                        color: c.textTertiary,
                      ),
                    ),
                  ],
                ),
                child: donors.isEmpty
                    ? const AdminEmpty(message: 'No donors match this filter.')
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final isMobile = constraints.maxWidth < 800;
                          if (isMobile) {
                            return Column(
                              children: [
                                for (final d in donors)
                                  _DonorMobileCard(
                                    donor: d,
                                    onViewProfile: () =>
                                        _showDonorProfile(context, d),
                                  ),
                              ],
                            );
                          }

                          return AdminTableScroll(
                            minWidth: 800,
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
                                  ('Actions', 2),
                                ]),
                                for (final d in donors)
                                  _DonorRow(
                                    donor: d,
                                    onViewProfile: () =>
                                        _showDonorProfile(context, d),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDonorProfile(BuildContext context, AdminUser donor) {
    final c = context.colors;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            BloodGroupBadge(donor.bloodGroup),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(donor.name, style: context.text.titleMedium),
                  if (donor.city != null)
                    Text(
                      donor.city!,
                      style: context.text.bodySmall?.copyWith(
                        color: c.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _donorField('Donor ID', donor.id),
                _donorField('Contact Phone', donor.phone),
                _donorField('Email', donor.email ?? 'Not provided'),
                _donorField(
                  'Email Verification',
                  donor.emailVerified ? 'Verified' : 'Pending',
                ),
                _donorField(
                  'Donor Availability',
                  donor.isInCooldown
                      ? 'In Cooldown (Eligible soon)'
                      : donor.isDonorOn
                          ? 'Available for dispatch'
                          : 'Donor Mode Paused / Off',
                ),
                _donorField(
                  'Last Donation Date',
                  donor.lastDonation != null
                      ? '${Fmt.date(donor.lastDonation!)} (${Fmt.relative(donor.lastDonation!)})'
                      : 'Never donated yet',
                ),
                _donorField('Total Donations Recorded', '${donor.totalDonations}'),
                _donorField(
                  'Account Status',
                  donor.isActive ? 'Active' : 'Deactivated',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static Widget _donorField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonorRow extends StatelessWidget {
  const _DonorRow({required this.donor, required this.onViewProfile});

  final AdminUser donor;
  final VoidCallback onViewProfile;

  @override
  Widget build(BuildContext context) {
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
            Text(
              donor.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleSmall,
            ),
          ),
          AdminCell(
            BloodGroupBadge(donor.bloodGroup),
            flex: 2,
          ),
          AdminCell(
            flex: 2,
            Text(
              donor.city ?? '—',
              style: context.text.bodySmall?.copyWith(color: c.textSecondary),
            ),
          ),
          AdminCell(
            flex: 2,
            StatusPill(
              donor.isInCooldown
                  ? 'Cooldown'
                  : donor.isDonorOn
                      ? 'Available'
                      : 'Off',
              fg: donor.isInCooldown
                  ? c.warning
                  : donor.isDonorOn
                      ? c.success
                      : c.textTertiary,
              bg: donor.isInCooldown
                  ? c.warningSubtle
                  : donor.isDonorOn
                      ? c.successSubtle
                      : c.surfaceMuted,
            ),
          ),
          AdminCell(
            flex: 2,
            Text(
              donor.lastDonation != null
                  ? Fmt.date(donor.lastDonation!)
                  : 'Never',
              style: AppTypography.mono(size: 12, color: c.textSecondary),
            ),
          ),
          AdminCell(
            flex: 1,
            Text(
              '${donor.totalDonations}',
              style: AppTypography.mono(size: 12.5, color: c.textPrimary),
            ),
          ),
          AdminCell(
            flex: 2,
            StatusPill(
              donor.emailVerified ? 'Verified' : 'Pending',
              fg: donor.emailVerified ? c.success : c.warning,
              bg: donor.emailVerified ? c.successSubtle : c.warningSubtle,
            ),
          ),
          AdminCell(
            flex: 2,
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onViewProfile,
                child: const Text('Profile'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonorMobileCard extends StatelessWidget {
  const _DonorMobileCard({required this.donor, required this.onViewProfile});

  final AdminUser donor;
  final VoidCallback onViewProfile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.cardMd,
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    BloodGroupBadge(donor.bloodGroup),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        donor.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusPill(
                donor.isInCooldown
                    ? 'Cooldown'
                    : donor.isDonorOn
                        ? 'Available'
                        : 'Off',
                fg: donor.isInCooldown
                    ? c.warning
                    : donor.isDonorOn
                        ? c.success
                        : c.textTertiary,
                bg: donor.isInCooldown
                    ? c.warningSubtle
                    : donor.isDonorOn
                        ? c.successSubtle
                        : c.surfaceMuted,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                'Total Donations: ${donor.totalDonations}',
                style: AppTypography.mono(size: 12, color: c.textPrimary),
              ),
              if (donor.city != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '• ${donor.city!}',
                    style: context.text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Last: ${donor.lastDonation != null ? Fmt.date(donor.lastDonation!) : "Never"}',
            style: AppTypography.mono(size: 11, color: c.textTertiary),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            onPressed: onViewProfile,
            child: const Text('View Donor Profile'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reports Screen (Section 8 Administrative Reports & Abuse)
// ---------------------------------------------------------------------------

class AdminReportsScreen extends ConsumerWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final reportsAsync = ref.watch(adminReportsProvider);
    final usersAsync = ref.watch(adminUsersProvider);
    final requestsAsync = ref.watch(adminRequestsProvider);

    return AdminPage(
      title: 'Administrative Reports',
      subtitle:
          'Download operational CSV reports and monitor user abuse and problem reports.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section 1: Administrative Reports (Section 8)
          AdminPanel(
            title: 'System Operational Reports',
            trailing: Text(
              '6 Standard Reports',
              style: AppTypography.mono(size: 12, color: c.textTertiary),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 750;
                final users = usersAsync.valueOrNull ?? const [];
                final requests = requestsAsync.valueOrNull ?? const [];

                final reports = [
                  _ReportDefinition(
                    title: 'User Registry Report',
                    description:
                        'Complete user list with contact, role, and verification data.',
                    icon: Icons.people_outline_rounded,
                    onExport: () => _exportUsersCsv(context, users),
                  ),
                  _ReportDefinition(
                    title: 'Donor Network Report',
                    description:
                        'Registered donors, availability state, and donation counts.',
                    icon: Icons.volunteer_activism_outlined,
                    onExport: () => _exportDonorsCsv(context, users),
                  ),
                  _ReportDefinition(
                    title: 'Emergency Request Report',
                    description:
                        'All urgent & critical emergency cases, destination, and status.',
                    icon: Icons.emergency_outlined,
                    onExport: () => _exportEmergencyCsv(context, requests),
                  ),
                  _ReportDefinition(
                    title: 'Blood Group Distribution Report',
                    description:
                        'System-wide supply & demand breakdown per blood group.',
                    icon: Icons.water_drop_outlined,
                    onExport: () =>
                        _exportBloodGroupCsv(context, users, requests),
                  ),
                  _ReportDefinition(
                    title: 'Donation Activity Report',
                    description:
                        'Historical donation activity and fulfillment metrics.',
                    icon: Icons.fact_check_outlined,
                    onExport: () =>
                        _exportDonationActivityCsv(context, users, requests),
                  ),
                  _ReportDefinition(
                    title: 'Monthly System Report',
                    description:
                        'High-level monthly operational and throughput summary.',
                    icon: Icons.summarize_outlined,
                    onExport: () =>
                        _exportMonthlyReportCsv(context, users, requests),
                  ),
                ];

                if (isMobile) {
                  return Column(
                    children: [
                      for (final r in reports)
                        _ReportCard(definition: r, isMobile: true),
                    ],
                  );
                }

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    mainAxisExtent: 175,
                  ),
                  itemCount: reports.length,
                  itemBuilder: (context, index) =>
                      _ReportCard(definition: reports[index], isMobile: false),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Section 2: Filed Reports & Abuse (Maintained with exact empty state)
          reportsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => AdminEmpty(
              icon: Icons.error_outline_rounded,
              message: 'Could not read reports: $e',
            ),
            data: (reports) {
              final open = reports.where((r) => r.isOpen).length;
              return AdminPanel(
                title: 'User Filed Reports & Abuse',
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
              );
            },
          ),
        ],
      ),
    );
  }

  static void _showCsvDialog(
    BuildContext context,
    String title,
    List<List<String>> rows,
  ) {
    final csvString = rows
        .map((r) => r.map((cell) => '"${cell.replaceAll('"', '""')}"').join(','))
        .join('\n');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Export $title (CSV)'),
        content: SizedBox(
          width: 550,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Generated ${rows.length - 1} records ready for administrative download.',
                style: ctx.text.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                height: 180,
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: ctx.colors.surfaceMuted,
                  borderRadius: AppRadius.control,
                ),
                child: SingleChildScrollView(
                  child: Text(
                    csvString,
                    style: AppTypography.mono(size: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: ctx.colors.brand,
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: csvString));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$title copied to clipboard in CSV format.'),
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy CSV'),
          ),
        ],
      ),
    );
  }

  static void _exportUsersCsv(BuildContext context, List<AdminUser> users) {
    final rows = <List<String>>[
      [
        'User ID',
        'Name',
        'Blood Group',
        'Phone',
        'Email',
        'Email Verified',
        'Is Admin',
        'Donor Mode',
        'Total Donations',
        'City',
      ],
      for (final u in users)
        [
          u.id,
          u.name,
          u.bloodGroup.label,
          u.phone,
          u.email ?? '',
          u.emailVerified ? 'YES' : 'NO',
          u.isAdmin ? 'YES' : 'NO',
          u.isDonorOn ? 'ON' : 'OFF',
          '${u.totalDonations}',
          u.city ?? '',
        ],
    ];
    _showCsvDialog(context, 'User Registry Report', rows);
  }

  static void _exportDonorsCsv(BuildContext context, List<AdminUser> users) {
    final donors = users.where((u) => u.donorAvailability != null).toList();
    final rows = <List<String>>[
      [
        'Donor ID',
        'Name',
        'Blood Group',
        'Phone',
        'Email',
        'Availability',
        'In Cooldown',
        'Last Donation',
        'Total Donations',
        'City',
      ],
      for (final d in donors)
        [
          d.id,
          d.name,
          d.bloodGroup.label,
          d.phone,
          d.email ?? '',
          d.isDonorOn ? 'Available' : 'Off',
          d.isInCooldown ? 'YES' : 'NO',
          d.lastDonation != null ? Fmt.date(d.lastDonation!) : '',
          '${d.totalDonations}',
          d.city ?? '',
        ],
    ];
    _showCsvDialog(context, 'Donor Network Report', rows);
  }

  static void _exportEmergencyCsv(
    BuildContext context,
    List<AdminRequest> requests,
  ) {
    final emergency = requests
        .where(
          (r) =>
              r.urgency == Urgency.critical || r.urgency == Urgency.urgent,
        )
        .toList();
    final rows = <List<String>>[
      [
        'Case ID',
        'Requester',
        'Blood Group',
        'Units',
        'Urgency',
        'Hospital',
        'Location',
        'Status',
        'Created At',
        'Accepted Donor',
      ],
      for (final r in emergency)
        [
          r.id,
          r.requesterName,
          r.bloodGroups.map((g) => g.label).join(';'),
          '${r.units}',
          r.urgency.label,
          r.destinationName,
          r.locationLabel,
          r.status.label,
          Fmt.date(r.createdAt),
          r.acceptedDonorName ?? '',
        ],
    ];
    _showCsvDialog(context, 'Emergency Request Report', rows);
  }

  static void _exportBloodGroupCsv(
    BuildContext context,
    List<AdminUser> users,
    List<AdminRequest> requests,
  ) {
    final rows = <List<String>>[
      [
        'Blood Group',
        'Total Registered Donors',
        'Available Donors (Mode ON)',
        'Open Requests',
        'Total Requested Units',
      ],
      for (final g in BloodGroup.values)
        [
          g.label,
          '${users.where((u) => u.donorAvailability != null && u.bloodGroup == g).length}',
          '${users.where((u) => u.isDonorOn && u.bloodGroup == g).length}',
          '${requests.where((r) => r.isOpen && r.bloodGroups.contains(g)).length}',
          '${requests.where((r) => r.isOpen && r.bloodGroups.contains(g)).fold<int>(0, (sum, r) => sum + r.units)}',
        ],
    ];
    _showCsvDialog(context, 'Blood Group Distribution Report', rows);
  }

  static void _exportDonationActivityCsv(
    BuildContext context,
    List<AdminUser> users,
    List<AdminRequest> requests,
  ) {
    final completed =
        requests.where((r) => r.status == RequestStatus.fulfilled).toList();
    final rows = <List<String>>[
      [
        'Request ID',
        'Recipient Hospital',
        'Blood Group',
        'Units Fulfilled',
        'Date Fulfilled',
        'Accepted Donor',
      ],
      for (final r in completed)
        [
          r.id,
          r.destinationName,
          r.bloodGroups.map((g) => g.label).join(';'),
          '${r.units}',
          Fmt.date(r.createdAt),
          r.acceptedDonorName ?? 'Donor',
        ],
    ];
    _showCsvDialog(context, 'Donation Activity Report', rows);
  }

  static void _exportMonthlyReportCsv(
    BuildContext context,
    List<AdminUser> users,
    List<AdminRequest> requests,
  ) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final thisMonthRequests =
        requests.where((r) => r.createdAt.isAfter(monthStart)).toList();

    final rows = <List<String>>[
      ['Metric', 'Value'],
      ['Report Period', '${now.month}/${now.year}'],
      ['Total Registered Users', '${users.length}'],
      [
        'Total Donors Configured',
        '${users.where((u) => u.donorAvailability != null).length}',
      ],
      ['Total Active Donors (Now)', '${users.where((u) => u.isDonorOn).length}'],
      ['New Requests (This Month)', '${thisMonthRequests.length}'],
      [
        'Fulfilled Requests (This Month)',
        '${thisMonthRequests.where((r) => r.status == RequestStatus.fulfilled).length}',
      ],
      [
        'Critical Emergencies (This Month)',
        '${thisMonthRequests.where((r) => r.urgency == Urgency.critical).length}',
      ],
    ];
    _showCsvDialog(context, 'Monthly System Report', rows);
  }
}

class _ReportDefinition {
  const _ReportDefinition({
    required this.title,
    required this.description,
    required this.icon,
    required this.onExport,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onExport;
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.definition,
    required this.isMobile,
  });

  final _ReportDefinition definition;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: isMobile ? const EdgeInsets.only(bottom: AppSpacing.sm) : null,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.cardMd,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.brandSubtle,
                  borderRadius: AppRadius.control,
                ),
                child: Icon(definition.icon, size: 18, color: c.brand),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  definition.title,
                  style: context.text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            definition.description,
            style: context.text.bodySmall?.copyWith(
              color: c.textSecondary,
              fontSize: 12,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(120, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: definition.onExport,
              icon: const Icon(Icons.file_download_outlined, size: 16),
              label: const Text('Export CSV'),
            ),
          ),
        ],
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
