import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/models.dart';
import '../admin_backend.dart';
import '../admin_providers.dart';
import '../admin_shell.dart';
import '../admin_widgets.dart';

// ---------------------------------------------------------------------------
// Analytics Dashboard
// ---------------------------------------------------------------------------

class AdminAnalyticsScreen extends ConsumerWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final requestsAsync = ref.watch(adminRequestsProvider);
    final usersAsync = ref.watch(adminUsersProvider);
    final requests = requestsAsync.valueOrNull ?? const [];
    final users = usersAsync.valueOrNull ?? const [];

    return AdminPage(
      title: 'Analytics',
      subtitle: 'Data-driven insights about the blood donation network.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Overview Stats ---
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              AdminStatCard(
                icon: Icons.people_alt_rounded,
                value: '${users.length}',
                label: 'Total Users',
                color: c.info,
              ),
              AdminStatCard(
                icon: Icons.volunteer_activism_rounded,
                value:
                    '${users.where((u) => u.donorAvailability != null).length}',
                label: 'Registered Donors',
                color: c.success,
              ),
              AdminStatCard(
                icon: Icons.receipt_long_rounded,
                value: '${requests.length}',
                label: 'Total Requests',
                color: c.info,
              ),
              AdminStatCard(
                icon: Icons.check_circle_rounded,
                value:
                    '${requests.where((r) => r.status == RequestStatus.fulfilled).length}',
                label: 'Fulfilled',
                color: c.success,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),

          // --- Blood Group Distribution ---
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AdminPanel(
                  title: 'Donor Distribution by Blood Group',
                  child: Column(
                    children: [
                      for (final group in BloodGroup.values)
                        _BarRow(
                          label: group.label,
                          value: users
                              .where(
                                (u) =>
                                    u.bloodGroup == group &&
                                    u.donorAvailability != null,
                              )
                              .length,
                          total: users
                              .where((u) => u.donorAvailability != null)
                              .length,
                          color: c.brand,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: AdminPanel(
                  title: 'Requests by Blood Group',
                  child: Column(
                    children: [
                      for (final group in BloodGroup.values)
                        _BarRow(
                          label: group.label,
                          value: requests
                              .where((r) => r.bloodGroups.contains(group))
                              .length,
                          total: requests.length,
                          color: c.info,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),

          // --- Request Status Breakdown ---
          AdminPanel(
            title: 'Request Status Breakdown',
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Wrap(
                spacing: AppSpacing.xxl,
                runSpacing: AppSpacing.lg,
                children: [
                  for (final status in RequestStatus.values)
                    _StatusStat(
                      status: status.label,
                      count: requests.where((r) => r.status == status).length,
                      total: requests.length,
                      color: switch (status) {
                        RequestStatus.fulfilled => c.success,
                        RequestStatus.coordinating ||
                        RequestStatus.donorAccepted => c.info,
                        RequestStatus.searching ||
                        RequestStatus.created => c.warning,
                        RequestStatus.removedByAdmin => c.danger,
                        _ => c.textTertiary,
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          // --- User Analytics ---
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AdminPanel(
                  title: 'Donor Availability',
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      children: [
                        _AnalyticRow(
                          label: 'Available',
                          value: users.where((u) => u.isDonorOn).length,
                          color: c.success,
                        ),
                        _AnalyticRow(
                          label: 'In Cooldown',
                          value: users.where((u) => u.isInCooldown).length,
                          color: c.warning,
                        ),
                        _AnalyticRow(
                          label: 'Donor Off',
                          value: users
                              .where(
                                (u) =>
                                    u.donorAvailability != null &&
                                    !u.isDonorOn &&
                                    !u.isInCooldown,
                              )
                              .length,
                          color: c.textTertiary,
                        ),
                        _AnalyticRow(
                          label: 'No Donor Profile',
                          value: users
                              .where((u) => u.donorAvailability == null)
                              .length,
                          color: c.textTertiary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: AdminPanel(
                  title: 'Request Urgency Distribution',
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      children: [
                        for (final urgency in Urgency.values)
                          _AnalyticRow(
                            label: urgency.label,
                            value: requests
                                .where((r) => r.urgency == urgency)
                                .length,
                            color: switch (urgency) {
                              Urgency.critical => c.danger,
                              Urgency.urgent => c.warning,
                              _ => c.info,
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),

          // --- Geographic Distribution ---
          AdminPanel(
            title: 'Users by City',
            child: AdminTableScroll(
              minWidth: 500,
              child: Column(
                children: [
                  adminHeaderRow(context, [
                    ('City', 3),
                    ('Total Users', 2),
                    ('Available Donors', 2),
                    ('Active Requests', 2),
                  ]),
                  ..._buildCityRows(context, users, requests),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCityRows(
    BuildContext context,
    List<AdminUser> users,
    List<AdminRequest> requests,
  ) {
    final c = context.colors;
    final cityMap = <String, int>{};
    for (final u in users) {
      final city = u.city ?? 'Unknown';
      cityMap[city] = (cityMap[city] ?? 0) + 1;
    }

    final sorted = cityMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return [
      for (final entry in sorted.take(15))
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
                flex: 3,
                child: Text(entry.key, style: context.text.titleSmall),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '${entry.value}',
                  style: AppTypography.mono(size: 13, color: c.textPrimary),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '${users.where((u) => u.city == entry.key && u.isDonorOn).length}',
                  style: AppTypography.mono(size: 13, color: c.success),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '${requests.where((r) => r.isOpen && r.locationLabel.contains(entry.key)).length}',
                  style: AppTypography.mono(size: 13, color: c.info),
                ),
              ),
            ],
          ),
        ),
    ];
  }
}

// --- Shared chart widgets ---

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });
  final String label;
  final int value;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pct = total == 0 ? 0.0 : value / total;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              label,
              style: AppTypography.mono(
                size: 12,
                weight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: c.surfaceMuted,
                color: color.withValues(alpha: 0.7),
                minHeight: 12,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 50,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: AppTypography.mono(
                size: 12,
                weight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusStat extends StatelessWidget {
  const _StatusStat({
    required this.status,
    required this.count,
    required this.total,
    required this.color,
  });
  final String status;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : (count / total * 100);
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: AppTypography.mono(
              size: 24,
              weight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(status, style: context.text.titleSmall),
          Text(
            '${pct.toStringAsFixed(1)}%',
            style: context.text.bodySmall?.copyWith(
              color: context.colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticRow extends StatelessWidget {
  const _AnalyticRow({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: context.text.bodySmall)),
          Text(
            '$value',
            style: AppTypography.mono(
              size: 14,
              weight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
