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
// Notifications Management Screen
// ---------------------------------------------------------------------------

/// Provider for admin notifications from Firestore.
final adminNotificationsProvider =
    StreamProvider.autoDispose<List<AdminNotificationEntry>>((ref) {
      final admin = ref.watch(adminBackendProvider);
      if (admin == null) return Stream.value(const []);
      return admin.adminNotifications;
    });

class AdminNotificationsScreen extends ConsumerStatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  ConsumerState<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState
    extends ConsumerState<AdminNotificationsScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(adminNotificationsProvider);

    return AdminPage(
      title: 'Notifications',
      subtitle: 'Send alerts and announcements to users.',
      actions: [
        FilledButton.icon(
          icon: const Icon(Icons.campaign_rounded, size: 18),
          label: const Text('Send Notification'),
          onPressed: () => _showSendDialog(context),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton.icon(
          icon: const Icon(Icons.emergency_rounded, size: 18),
          label: const Text('Emergency Alert'),
          onPressed: () => _showEmergencyDialog(context),
          style: FilledButton.styleFrom(backgroundColor: c.danger),
        ),
      ],
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmpty(
          icon: Icons.error_outline_rounded,
          message: 'Could not read: $e',
        ),
        data: (notifications) {
          final emergency = notifications
              .where((n) => n.type == 'emergency')
              .length;

          var shown = switch (_filter) {
            'emergency' =>
              notifications.where((n) => n.type == 'emergency').toList(),
            'general' =>
              notifications.where((n) => n.type == 'general').toList(),
            _ => notifications,
          };

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  AdminMetric(
                    value: notifications.length,
                    label: 'Total sent',
                    hint: 'All time',
                  ),
                  AdminMetric(
                    value: emergency,
                    label: 'Emergency alerts',
                    hint: 'Critical notifications',
                    tone: c.danger,
                  ),
                  AdminMetric(
                    value: notifications.length - emergency,
                    label: 'General',
                    hint: 'Announcements & updates',
                    tone: c.info,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  AdminFilterChip(
                    label: 'All',
                    count: notifications.length,
                    selected: _filter == 'all',
                    onTap: () => setState(() => _filter = 'all'),
                  ),
                  AdminFilterChip(
                    label: 'Emergency',
                    count: emergency,
                    selected: _filter == 'emergency',
                    onTap: () => setState(() => _filter = 'emergency'),
                  ),
                  AdminFilterChip(
                    label: 'General',
                    count: notifications.length - emergency,
                    selected: _filter == 'general',
                    onTap: () => setState(() => _filter = 'general'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              AdminPanel(
                title: 'Sent Notifications',
                trailing: Text(
                  '${shown.length}',
                  style: AppTypography.mono(size: 12, color: c.textTertiary),
                ),
                child: shown.isEmpty
                    ? const AdminEmpty(
                        icon: Icons.notifications_none_rounded,
                        message: 'No notifications have been sent yet.',
                      )
                    : AdminTableScroll(
                        minWidth: 680,
                        child: Column(
                          children: [
                            adminHeaderRow(context, [
                              ('Title', 3),
                              ('Type', 2),
                              ('Target', 2),
                              ('Sent By', 2),
                              ('Sent At', 2),
                            ]),
                            for (final n in shown)
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
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            n.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: context.text.titleSmall,
                                          ),
                                          Text(
                                            n.body,
                                            maxLines: 2,
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
                                      flex: 2,
                                      StatusPill(
                                        n.type == 'emergency'
                                            ? 'Emergency'
                                            : 'General',
                                        fg: n.type == 'emergency'
                                            ? c.danger
                                            : c.info,
                                        bg: n.type == 'emergency'
                                            ? c.dangerSubtle
                                            : c.infoSubtle,
                                      ),
                                    ),
                                    AdminCell(
                                      flex: 2,
                                      Text(
                                        n.target,
                                        style: context.text.bodySmall?.copyWith(
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ),
                                    AdminCell(
                                      flex: 2,
                                      Text(
                                        n.sentBy,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.text.bodySmall,
                                      ),
                                    ),
                                    AdminCell(
                                      flex: 2,
                                      Text(
                                        Fmt.relative(n.sentAt),
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

  void _showSendDialog(BuildContext context) {
    final titleC = TextEditingController();
    final bodyC = TextEditingController();
    String target = 'all';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Send Notification'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleC,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: bodyC,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    hintText: 'Enter notification message...',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: target,
                  decoration: const InputDecoration(labelText: 'Target'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Users')),
                    DropdownMenuItem(
                      value: 'donors',
                      child: Text('Donors Only'),
                    ),
                    DropdownMenuItem(
                      value: 'seekers',
                      child: Text('Blood Seekers'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => target = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (titleC.text.trim().isEmpty) return;
                final admin = ref.read(adminBackendProvider);
                await admin?.sendNotification(
                  title: titleC.text.trim(),
                  body: bodyC.text.trim(),
                  type: 'general',
                  target: target,
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  showAdminToast(context, 'Notification sent.');
                }
              },
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEmergencyDialog(BuildContext context) {
    final titleC = TextEditingController(text: 'Urgent Blood Needed');
    final bodyC = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.emergency_rounded,
              color: context.colors.danger,
              size: 22,
            ),
            const SizedBox(width: AppSpacing.sm),
            const Text('Emergency Alert'),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleC,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: bodyC,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Emergency Details',
                  hintText: 'Blood group, hospital, units needed, contact...',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.danger,
            ),
            onPressed: () async {
              if (titleC.text.trim().isEmpty) return;
              final admin = ref.read(adminBackendProvider);
              await admin?.sendNotification(
                title: titleC.text.trim(),
                body: bodyC.text.trim(),
                type: 'emergency',
                target: 'donors',
              );
              if (ctx.mounted) {
                Navigator.pop(ctx);
                showAdminToast(context, 'Emergency alert sent to all donors.');
              }
            },
            child: const Text('Send Emergency Alert'),
          ),
        ],
      ),
    );
  }
}
