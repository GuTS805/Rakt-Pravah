import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../admin_backend.dart';
import '../admin_providers.dart';
import '../admin_shell.dart';
import '../admin_widgets.dart';

// ---------------------------------------------------------------------------
// Accepted Connections Screen
// ---------------------------------------------------------------------------

class AdminConnectionsScreen extends ConsumerStatefulWidget {
  const AdminConnectionsScreen({super.key});

  @override
  ConsumerState<AdminConnectionsScreen> createState() =>
      _AdminConnectionsScreenState();
}

class _AdminConnectionsScreenState
    extends ConsumerState<AdminConnectionsScreen> {
  String _tab = 'active';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(adminRequestsProvider);

    return AdminPage(
      title: 'Accepted Connections',
      subtitle: 'Donor-requester pairs after a donor has accepted.',
      actions: [
        AdminSearchBar(
          hint: 'Search connections...',
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
          final connected = all
              .where((r) => r.acceptedDonorIds.isNotEmpty)
              .toList();
          final active = connected.where((r) => r.isOpen).toList();
          final completed = connected
              .where((r) => r.status == RequestStatus.fulfilled)
              .toList();

          var shown = switch (_tab) {
            'active' => active,
            'completed' => completed,
            _ => connected,
          };

          if (_search.isNotEmpty) {
            shown = shown
                .where(
                  (r) =>
                      r.requesterName.toLowerCase().contains(_search) ||
                      (r.acceptedDonorName?.toLowerCase().contains(_search) ??
                          false),
                )
                .toList();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  AdminMetric(
                    value: active.length,
                    label: 'Active connections',
                    hint: 'Donor & requester paired',
                    tone: c.info,
                  ),
                  AdminMetric(
                    value: connected
                        .where((r) => r.status == RequestStatus.coordinating)
                        .length,
                    label: 'Coordinating',
                    hint: 'Contact shared, in progress',
                    tone: c.info,
                  ),
                  AdminMetric(
                    value: completed.length,
                    label: 'Completed',
                    hint: 'Donation successful',
                    tone: c.success,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

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
                    label: 'All',
                    count: connected.length,
                    selected: _tab == 'all',
                    onTap: () => setState(() => _tab = 'all'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              AdminPanel(
                title: 'Connections',
                trailing: Text(
                  '${shown.length}',
                  style: AppTypography.mono(size: 12, color: c.textTertiary),
                ),
                child: shown.isEmpty
                    ? const AdminEmpty(
                        icon: Icons.handshake_rounded,
                        message: 'No connections match this view.',
                      )
                    : AdminTableScroll(
                        minWidth: 720,
                        child: Column(
                          children: [
                            adminHeaderRow(context, [
                              ('Requester', 3),
                              ('Donor', 3),
                              ('Blood Groups', 2),
                              ('Status', 2),
                              ('Donors', 1),
                              ('Location', 2),
                              ('Created', 2),
                            ]),
                            for (final r in shown) _ConnectionRow(request: r),
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

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({required this.request});
  final AdminRequest request;

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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.requesterName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
                Text(
                  request.destinationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(
                    color: c.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          AdminCell(
            flex: 3,
            Row(
              children: [
                Icon(Icons.arrow_forward_rounded, size: 14, color: c.success),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    request.acceptedDonorName ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall?.copyWith(color: c.success),
                  ),
                ),
              ],
            ),
          ),
          AdminCell(
            flex: 2,
            Wrap(
              spacing: 4,
              children: [
                for (final g in request.bloodGroups)
                  BloodGroupBadge(g, size: 11),
              ],
            ),
          ),
          AdminCell(flex: 2, RequestStatusPill(request.status)),
          AdminCell(
            Text(
              '${request.acceptedDonorIds.length}',
              style: AppTypography.mono(size: 12.5, color: c.textPrimary),
            ),
          ),
          AdminCell(
            flex: 2,
            Text(
              request.locationLabel.isNotEmpty ? request.locationLabel : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(color: c.textSecondary),
            ),
          ),
          AdminCell(
            flex: 2,
            Text(
              Fmt.relative(request.createdAt),
              style: AppTypography.mono(size: 12, color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
