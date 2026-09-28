import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../admin_providers.dart';
import '../admin_shell.dart';
import '../admin_widgets.dart';

// ---------------------------------------------------------------------------
// Donations Screen — Active, Completed, and History views
// ---------------------------------------------------------------------------

class AdminDonationsScreen extends ConsumerStatefulWidget {
  const AdminDonationsScreen({super.key});

  @override
  ConsumerState<AdminDonationsScreen> createState() =>
      _AdminDonationsScreenState();
}

class _AdminDonationsScreenState extends ConsumerState<AdminDonationsScreen> {
  String _tab = 'active';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(adminRequestsProvider);

    return AdminPage(
      title: 'Donations',
      subtitle: 'Track donation lifecycle from match to completion.',
      actions: [
        AdminSearchBar(
          hint: 'Search donations...',
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
          final active = all
              .where(
                (r) =>
                    r.status == RequestStatus.donorAccepted ||
                    r.status == RequestStatus.coordinating,
              )
              .toList();
          final completed = all
              .where((r) => r.status == RequestStatus.fulfilled)
              .toList();

          var shown = switch (_tab) {
            'active' => active,
            'completed' => completed,
            _ => all.where((r) => r.acceptedDonorIds.isNotEmpty).toList(),
          };

          if (_search.isNotEmpty) {
            shown = shown
                .where(
                  (r) =>
                      r.requesterName.toLowerCase().contains(_search) ||
                      (r.acceptedDonorName
                              ?.toLowerCase()
                              .contains(_search) ??
                          false),
                )
                .toList();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stats
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  AdminMetric(
                    value: active.length,
                    label: 'Active donations',
                    hint: 'In progress',
                    tone: c.info,
                  ),
                  AdminMetric(
                    value: completed.length,
                    label: 'Completed',
                    hint: 'All time',
                    tone: c.success,
                  ),
                  AdminMetric(
                    value: all
                        .where((r) => r.acceptedDonorIds.isNotEmpty)
                        .length,
                    label: 'Total matched',
                    hint: 'Donor accepted',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Tab filters
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  AdminFilterChip(
                    label: 'Active',
                    count: active.length,
                    selected: _tab == 'active',
                    onTap: () => setState(() => _tab = 'active'),
                  ),
                  AdminFilterChip(
                    label: 'Completed',
                    count: completed.length,
                    selected: _tab == 'completed',
                    onTap: () => setState(() => _tab = 'completed'),
                  ),
                  AdminFilterChip(
                    label: 'All History',
                    count: all
                        .where((r) => r.acceptedDonorIds.isNotEmpty)
                        .length,
                    selected: _tab == 'history',
                    onTap: () => setState(() => _tab = 'history'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Donation lifecycle
              AdminPanel(
                title: 'Donation Lifecycle',
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      _LifecycleStep(
                        label: 'Request',
                        icon: Icons.receipt_long_rounded,
                        count: all.length,
                        color: c.textSecondary,
                      ),
                      _LifecycleArrow(c: c),
                      _LifecycleStep(
                        label: 'Match',
                        icon: Icons.search_rounded,
                        count: all
                            .where(
                              (r) =>
                                  r.status == RequestStatus.searching ||
                                  r.status == RequestStatus.created,
                            )
                            .length,
                        color: c.warning,
                      ),
                      _LifecycleArrow(c: c),
                      _LifecycleStep(
                        label: 'Accept',
                        icon: Icons.check_rounded,
                        count: all
                            .where(
                              (r) =>
                                  r.status == RequestStatus.donorAccepted,
                            )
                            .length,
                        color: c.info,
                      ),
                      _LifecycleArrow(c: c),
                      _LifecycleStep(
                        label: 'Coordinate',
                        icon: Icons.handshake_rounded,
                        count: all
                            .where(
                              (r) =>
                                  r.status == RequestStatus.coordinating,
                            )
                            .length,
                        color: c.info,
                      ),
                      _LifecycleArrow(c: c),
                      _LifecycleStep(
                        label: 'Complete',
                        icon: Icons.check_circle_rounded,
                        count: completed.length,
                        color: c.success,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Table
              AdminPanel(
                title: switch (_tab) {
                  'active' => 'Active Donations',
                  'completed' => 'Completed Donations',
                  _ => 'All Donation History',
                },
                trailing: Text(
                  '${shown.length}',
                  style: AppTypography.mono(size: 12, color: c.textTertiary),
                ),
                child: shown.isEmpty
                    ? AdminEmpty(
                        icon: Icons.bloodtype_rounded,
                        message: switch (_tab) {
                          'active' =>
                            'No active donations right now.',
                          'completed' =>
                            'No completed donations yet.',
                          _ => 'No donation history.',
                        },
                      )
                    : AdminTableScroll(
                        minWidth: 700,
                        child: Column(
                          children: [
                            adminHeaderRow(context, [
                              ('Requester', 3),
                              ('Donor', 3),
                              ('Blood Groups', 2),
                              ('Units', 1),
                              ('Status', 2),
                              ('Created', 2),
                            ]),
                          for (final r in shown)
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
                                          r.requesterName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: context.text.titleSmall,
                                        ),
                                        Text(
                                          r.destinationName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: context.text.bodySmall
                                              ?.copyWith(
                                            color: c.textTertiary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  AdminCell(
                                    flex: 3,
                                    Text(
                                      r.acceptedDonorName ?? '—',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.text.bodySmall?.copyWith(
                                        color: r.acceptedDonorName == null
                                            ? c.textTertiary
                                            : c.textPrimary,
                                      ),
                                    ),
                                  ),
                                  AdminCell(
                                    flex: 2,
                                    Wrap(
                                      spacing: 4,
                                      children: [
                                        for (final g in r.bloodGroups)
                                          BloodGroupBadge(g, size: 11),
                                      ],
                                    ),
                                  ),
                                  AdminCell(
                                    Text(
                                      '${r.units}',
                                      style: AppTypography.mono(
                                        size: 12.5,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                  ),
                                  AdminCell(
                                    flex: 2,
                                    RequestStatusPill(r.status),
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

class _LifecycleStep extends StatelessWidget {
  const _LifecycleStep({
    required this.label,
    required this.icon,
    required this.count,
    required this.color,
  });
  final String label;
  final IconData icon;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$count',
            style: AppTypography.mono(
              size: 18,
              weight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LifecycleArrow extends StatelessWidget {
  const _LifecycleArrow({required this.c});
  final AppColors c;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Icon(
        Icons.arrow_forward_rounded,
        size: 16,
        color: c.textTertiary,
      ),
    );
  }
}
