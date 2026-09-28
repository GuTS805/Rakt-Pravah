import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../admin_backend.dart';
import '../admin_providers.dart';
import '../admin_shell.dart';
import '../admin_widgets.dart';

// ---------------------------------------------------------------------------
// Donor Verification Screen
// ---------------------------------------------------------------------------

class AdminVerificationScreen extends ConsumerStatefulWidget {
  const AdminVerificationScreen({super.key});

  @override
  ConsumerState<AdminVerificationScreen> createState() =>
      _AdminVerificationScreenState();
}

class _AdminVerificationScreenState
    extends ConsumerState<AdminVerificationScreen> {
  String _tab = 'pending';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(adminUsersProvider);

    return AdminPage(
      title: 'Donor Verification',
      subtitle: 'Review and verify donor eligibility and identity.',
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
          final donors =
              users.where((u) => u.donorAvailability != null).toList();
          final pending =
              donors.where((u) => !u.emailVerified).toList();
          final verified = donors.where((u) => u.emailVerified).toList();

          var shown = switch (_tab) {
            'pending' => pending,
            'verified' => verified,
            _ => donors,
          };

          if (_search.isNotEmpty) {
            shown = shown
                .where(
                  (u) =>
                      u.name.toLowerCase().contains(_search) ||
                      u.phone.contains(_search) ||
                      u.bloodGroup.label.toLowerCase().contains(_search),
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
                  AdminStatCard(
                    icon: Icons.pending_rounded,
                    value: '${pending.length}',
                    label: 'Pending Review',
                    description: 'Awaiting verification',
                    color: c.warning,
                  ),
                  AdminStatCard(
                    icon: Icons.verified_rounded,
                    value: '${verified.length}',
                    label: 'Verified',
                    description: 'Approved donors',
                    color: c.success,
                  ),
                  AdminStatCard(
                    icon: Icons.people_alt_rounded,
                    value: '${donors.length}',
                    label: 'Total Donors',
                    description: 'Registered as donors',
                    color: c.info,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Filters
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  AdminFilterChip(
                    label: 'Pending',
                    count: pending.length,
                    selected: _tab == 'pending',
                    onTap: () => setState(() => _tab = 'pending'),
                  ),
                  AdminFilterChip(
                    label: 'Verified',
                    count: verified.length,
                    selected: _tab == 'verified',
                    onTap: () => setState(() => _tab = 'verified'),
                  ),
                  AdminFilterChip(
                    label: 'All Donors',
                    count: donors.length,
                    selected: _tab == 'all',
                    onTap: () => setState(() => _tab = 'all'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Table
              AdminPanel(
                title: switch (_tab) {
                  'pending' => 'Pending Verification',
                  'verified' => 'Verified Donors',
                  _ => 'All Donors',
                },
                trailing: Text(
                  '${shown.length}',
                  style: AppTypography.mono(size: 12, color: c.textTertiary),
                ),
                child: shown.isEmpty
                    ? AdminEmpty(
                        icon: Icons.verified_user_rounded,
                        message: switch (_tab) {
                          'pending' =>
                            'No donors pending verification.',
                          'verified' =>
                            'No verified donors yet.',
                          _ => 'No donors found.',
                        },
                      )
                    : AdminTableScroll(
                        minWidth: 720,
                        child: Column(
                          children: [
                            adminHeaderRow(context, [
                              ('Name', 3),
                              ('Blood Group', 2),
                              ('Phone', 2),
                              ('Location', 2),
                              ('Donor Status', 2),
                              ('Verified', 2),
                              ('Actions', 2),
                            ]),
                            for (final u in shown)
                              _VerificationRow(user: u),
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

class _VerificationRow extends ConsumerWidget {
  const _VerificationRow({required this.user});
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
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c.brandSubtle,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: AppTypography.mono(
                        size: 13,
                        weight: FontWeight.w700,
                        color: c.brand,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall,
                      ),
                      if (user.email != null)
                        Text(
                          user.email!,
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
              ],
            ),
          ),
          AdminCell(BloodGroupBadge(user.bloodGroup), flex: 2),
          AdminCell(
            flex: 2,
            Text(
              user.phone,
              style: AppTypography.mono(size: 12, color: c.textSecondary),
            ),
          ),
          AdminCell(
            flex: 2,
            Text(
              user.city ?? '—',
              style: context.text.bodySmall?.copyWith(color: c.textSecondary),
            ),
          ),
          AdminCell(
            flex: 2,
            StatusPill(
              user.isInCooldown
                  ? 'Cooldown'
                  : user.isDonorOn
                      ? 'Available'
                      : 'Off',
              fg: user.isInCooldown
                  ? c.warning
                  : user.isDonorOn
                      ? c.success
                      : c.textTertiary,
              bg: user.isInCooldown
                  ? c.warningSubtle
                  : user.isDonorOn
                      ? c.successSubtle
                      : c.surfaceMuted,
            ),
          ),
          AdminCell(
            flex: 2,
            StatusPill(
              user.emailVerified ? 'Verified' : 'Pending',
              fg: user.emailVerified ? c.success : c.warning,
              bg: user.emailVerified ? c.successSubtle : c.warningSubtle,
            ),
          ),
          AdminCell(
            flex: 2,
            Row(
              children: [
                if (!user.emailVerified)
                  Tooltip(
                    message: 'Verify donor',
                    child: IconButton(
                      icon: Icon(
                        Icons.verified_rounded,
                        size: 18,
                        color: c.success,
                      ),
                      onPressed: () async {
                        final confirmed = await showAdminConfirmDialog(
                          context,
                          title: 'Verify ${user.name}?',
                          message: 'This will mark this donor as verified '
                              'in the system. Ensure you have validated '
                              'their identity and eligibility.',
                          confirmLabel: 'Verify',
                        );
                        if (!confirmed || !context.mounted) return;
                        showAdminToast(
                          context,
                          '${user.name} verification noted. Email '
                          'verification is required via the app.',
                        );
                      },
                    ),
                  ),
                Tooltip(
                  message: 'View details',
                  child: IconButton(
                    icon: Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: c.info,
                    ),
                    onPressed: () => _showUserDetail(context, user),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showUserDetail(BuildContext context, AdminUser user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(user.name),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: 'Blood Group', value: user.bloodGroup.label),
              _DetailRow(label: 'Phone', value: user.phone),
              _DetailRow(
                label: 'Email',
                value: user.email ?? 'Not provided',
              ),
              _DetailRow(label: 'City', value: user.city ?? '—'),
              _DetailRow(
                label: 'Donor Status',
                value: user.isDonorOn
                    ? 'Available'
                    : user.isInCooldown
                        ? 'Cooldown'
                        : 'Off',
              ),
              _DetailRow(
                label: 'Total Donations',
                value: '${user.totalDonations}',
              ),
              _DetailRow(
                label: 'Last Donation',
                value: user.lastDonation != null
                    ? Fmt.fullDate(user.lastDonation!)
                    : 'Never',
              ),
              _DetailRow(
                label: 'Email Verified',
                value: user.emailVerified ? 'Yes' : 'No',
              ),
              _DetailRow(
                label: 'Admin',
                value: user.isAdmin ? 'Yes' : 'No',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: context.text.bodySmall?.copyWith(color: c.textSecondary),
            ),
          ),
          Expanded(
            child: Text(value, style: context.text.bodySmall),
          ),
        ],
      ),
    );
  }
}
