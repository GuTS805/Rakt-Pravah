import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/enums.dart';
import '../admin_providers.dart';
import '../admin_shell.dart';
import '../admin_widgets.dart';

/// Blood and platelet component availability monitor.
class AdminAvailabilityScreen extends ConsumerStatefulWidget {
  const AdminAvailabilityScreen({super.key});

  @override
  ConsumerState<AdminAvailabilityScreen> createState() =>
      _AdminAvailabilityScreenState();
}

class _AdminAvailabilityScreenState
    extends ConsumerState<AdminAvailabilityScreen> {
  String _selectedComponent = 'Whole Blood';

  final List<String> _components = [
    'Whole Blood',
    'Platelets (PRP)',
    'Plasma (FFP)',
    'Packed Red Cells (PRBC)',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final usersAsync = ref.watch(adminUsersProvider);
    final requestsAsync = ref.watch(adminRequestsProvider);

    return AdminPage(
      title: 'Blood & Platelet Availability',
      subtitle: 'Monitor regional component inventory, reserve balances, and donor readiness.',
      actions: [
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final comp in _components)
              AdminFilterChip(
                label: comp,
                count: 8,
                selected: _selectedComponent == comp,
                onTap: () => setState(() => _selectedComponent = comp),
              ),
          ],
        ),
      ],
      child: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmpty(
          icon: Icons.error_outline_rounded,
          message: 'Could not load inventory data: $e',
        ),
        data: (users) {
          final requests = requestsAsync.valueOrNull ?? const [];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary Metrics
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  AdminStatCard(
                    icon: Icons.bloodtype_rounded,
                    value:
                        '${users.where((u) => u.isDonorOn && !u.isInCooldown).length}',
                    label: 'Ready Donors',
                    description: 'Available for immediate call',
                    color: c.success,
                  ),
                  AdminStatCard(
                    icon: Icons.water_drop_rounded,
                    value: '${requests.where((r) => r.isOpen).length}',
                    label: 'Active Demand',
                    description: 'Open patient requests',
                    color: c.info,
                  ),
                  AdminStatCard(
                    icon: Icons.warning_amber_rounded,
                    value:
                        '${BloodGroup.values.where((g) => users.where((u) => u.bloodGroup == g && u.isDonorOn).length < 2).length}',
                    label: 'Critical Shortages',
                    description: 'Blood groups with <2 donors',
                    color: c.danger,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Group Availability Grid
              Text(
                '$_selectedComponent Inventory by Blood Group',
                style: context.text.titleMedium,
              ),
              const SizedBox(height: AppSpacing.md),

              AdminTableScroll(
                minWidth: 700,
                child: AdminPanel(
                  title: 'Component Status Breakdown',
                  trailing: Text(
                    'Updated Live',
                    style: AppTypography.mono(size: 11, color: c.success),
                  ),
                  child: Column(
                    children: [
                      adminHeaderRow(context, [
                        ('Blood Group', 2),
                        ('Ready Donors', 2),
                        ('Active Demands', 2),
                        ('Deficit / Surplus', 2),
                        ('Status', 2),
                      ]),
                      for (final group in BloodGroup.values)
                        _buildGroupRow(context, group, users, requests, c),
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

  Widget _buildGroupRow(
    BuildContext context,
    BloodGroup group,
    List<dynamic> users,
    List<dynamic> requests,
    dynamic c,
  ) {
    final availableCount = users
        .where((u) => u.bloodGroup == group && u.isDonorOn && !u.isInCooldown)
        .length;
    final demandCount = requests
        .where((r) => r.isOpen && (r.bloodGroups as List).contains(group))
        .length;

    final balance = availableCount - demandCount;
    final (statusLabel, statusColor, statusBg) = balance < 0
        ? ('Deficit', c.danger, c.dangerSubtle)
        : balance == 0
        ? ('Balanced', c.warning, c.warningSubtle)
        : ('Adequate', c.success, c.successSubtle);

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
          AdminCell(flex: 2, Row(children: [BloodGroupBadge(group)])),
          AdminCell(
            flex: 2,
            Text(
              '$availableCount Donors',
              style: AppTypography.mono(
                size: 13,
                color: availableCount > 0 ? c.success : c.danger,
                weight: FontWeight.w600,
              ),
            ),
          ),
          AdminCell(
            flex: 2,
            Text(
              '$demandCount Units',
              style: AppTypography.mono(size: 13, color: c.info),
            ),
          ),
          AdminCell(
            flex: 2,
            Text(
              balance > 0 ? '+$balance' : '$balance',
              style: AppTypography.mono(
                size: 13,
                color: balance < 0 ? c.danger : c.textPrimary,
                weight: FontWeight.w700,
              ),
            ),
          ),
          AdminCell(
            flex: 2,
            StatusPill(statusLabel, fg: statusColor, bg: statusBg),
          ),
        ],
      ),
    );
  }
}
