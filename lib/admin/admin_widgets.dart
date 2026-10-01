import 'package:flutter/material.dart';

import '../core/theme/app_spacing.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/formatters.dart';
import '../data/models/models.dart';
import 'admin_backend.dart';
import 'admin_shell.dart';

// ---------------------------------------------------------------------------
// Shared table components
// ---------------------------------------------------------------------------

/// A container that makes tables horizontally scrollable on narrow viewports
/// without ever allowing page-level horizontal overflow or column squishing.
class AdminTableScroll extends StatelessWidget {
  const AdminTableScroll({super.key, required this.child, this.minWidth = 680});

  final Widget child;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= minWidth) {
          return child;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth, maxWidth: minWidth),
            child: child,
          ),
        );
      },
    );
  }
}

/// A flex‑proportional cell inside a table row.
class AdminCell extends StatelessWidget {
  const AdminCell(this.child, {super.key, this.flex = 1});
  final Widget child;
  final int flex;

  @override
  Widget build(BuildContext context) => Expanded(flex: flex, child: child);
}

/// Column header row for admin tables.
Widget adminHeaderRow(BuildContext context, List<(String, int)> columns) {
  final c = context.colors;
  return Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.sm,
    ),
    color: c.surfaceMuted,
    child: Row(
      children: [
        for (final (label, flex) in columns)
          Expanded(
            flex: flex,
            child: Text(
              label,
              style: context.text.labelSmall?.copyWith(color: c.textSecondary),
            ),
          ),
      ],
    ),
  );
}

/// Status as a coloured pill.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.icon, this.fg, this.bg});
  final String label;
  final IconData? icon;
  final Color? fg;
  final Color? bg;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = fg ?? c.textTertiary;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: bg ?? c.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Request status pill with semantic colours and icons.
class RequestStatusPill extends StatelessWidget {
  const RequestStatusPill(this.status, {super.key});
  final RequestStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (fg, bg, icon) = switch (status) {
      RequestStatus.fulfilled => (
        c.success,
        c.successSubtle,
        Icons.check_circle_rounded,
      ),
      RequestStatus.coordinating => (c.info, c.infoSubtle, Icons.forum_rounded),
      RequestStatus.donorAccepted => (
        c.success,
        c.successSubtle,
        Icons.how_to_reg_rounded,
      ),
      RequestStatus.searching => (
        c.warning,
        c.warningSubtle,
        Icons.radar_rounded,
      ),
      RequestStatus.created => (
        c.textSecondary,
        c.surfaceMuted,
        Icons.add_circle_outline_rounded,
      ),
      RequestStatus.removedByAdmin => (
        c.danger,
        c.dangerSubtle,
        Icons.gavel_rounded,
      ),
      RequestStatus.expired => (
        c.textTertiary,
        c.surfaceMuted,
        Icons.hourglass_disabled_rounded,
      ),
      RequestStatus.cancelled => (
        c.textTertiary,
        c.surfaceMuted,
        Icons.cancel_rounded,
      ),
    };
    return StatusPill(status.label, icon: icon, fg: fg, bg: bg);
  }
}

/// Selectable filter chip.
class AdminFilterChip extends StatelessWidget {
  const AdminFilterChip({
    super.key,
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
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: selected ? c.brand : c.border),
          ),
          child: Text(
            '$label  $count',
            style: context.text.labelMedium?.copyWith(
              color: selected ? c.onBrand : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Request table shared by multiple screens.
class AdminRequestTable extends StatelessWidget {
  const AdminRequestTable({
    super.key,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 650) {
          return Column(
            children: [
              for (final r in requests)
                Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.border)),
                    color: r.isStale
                        ? c.dangerSubtle.withValues(alpha: 0.35)
                        : null,
                  ),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          RequestStatusPill(r.status),
                          Text(
                            r.isStale ? 'Expired' : Fmt.relative(r.createdAt),
                            style: AppTypography.mono(
                              size: 11,
                              color: r.isStale ? c.danger : c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        r.requesterName,
                        style: context.text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        r.destinationName,
                        style: context.text.bodySmall?.copyWith(
                          color: c.textTertiary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
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
                              r.bloodGroups.map((g) => g.label).join(' '),
                              style: AppTypography.mono(
                                size: 12,
                                color: c.brand,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            '${r.units} ${r.units == 1 ? "unit" : "units"}',
                            style: AppTypography.mono(
                              size: 12,
                              color: c.textSecondary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            r.urgency.label,
                            style: context.text.labelSmall?.copyWith(
                              color: r.urgency == Urgency.critical
                                  ? c.danger
                                  : c.textSecondary,
                              fontWeight: r.urgency == Urgency.critical
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Donor: ${r.acceptedDonorName ?? (r.isUnmatched ? 'Nobody yet' : '—')}',
                              style: context.text.bodySmall?.copyWith(
                                color: r.acceptedDonorName == null
                                    ? c.textTertiary
                                    : c.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (onRemove != null && !r.status.isTerminal)
                            TextButton(
                              onPressed: () => onRemove!(r),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                minimumSize: const Size(44, 32),
                              ),
                              child: Text(
                                'Remove',
                                style: context.text.labelSmall?.copyWith(
                                  color: c.danger,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          );
        }

        return AdminTableScroll(
          minWidth: 720,
          child: Column(
            children: [
              adminHeaderRow(context, [
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
                    color: r.isStale
                        ? c.dangerSubtle.withValues(alpha: 0.35)
                        : null,
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
                              r.requesterName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.titleSmall,
                            ),
                            Text(
                              r.destinationName,
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
                        Text(
                          r.bloodGroups.map((g) => g.label).join(' '),
                          style: AppTypography.mono(size: 12.5, color: c.brand),
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
                        Text(
                          r.urgency.label,
                          style: context.text.bodySmall?.copyWith(
                            color: r.urgency == Urgency.critical
                                ? c.danger
                                : c.textSecondary,
                            fontWeight: r.urgency == Urgency.critical
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      AdminCell(flex: 2, RequestStatusPill(r.status)),
                      AdminCell(
                        flex: 3,
                        Text(
                          r.acceptedDonorName ??
                              (r.isUnmatched ? 'Nobody yet' : '—'),
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
                        Text(
                          r.isStale ? 'Expired' : Fmt.relative(r.createdAt),
                          style: AppTypography.mono(
                            size: 12,
                            color: r.isStale ? c.danger : c.textSecondary,
                          ),
                        ),
                      ),
                      if (onRemove != null)
                        AdminCell(
                          flex: 2,
                          Align(
                            alignment: Alignment.centerRight,
                            child: r.status.isTerminal
                                ? Text(
                                    'Closed',
                                    style: context.text.bodySmall?.copyWith(
                                      color: c.textTertiary,
                                    ),
                                  )
                                : TextButton(
                                    onPressed: () => onRemove!(r),
                                    child: Text(
                                      'Remove',
                                      style: context.text.labelMedium?.copyWith(
                                        color: c.danger,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Search bar
// ---------------------------------------------------------------------------

class AdminSearchBar extends StatelessWidget {
  const AdminSearchBar({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 320,
      height: 40,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: context.text.bodySmall,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 18,
            color: c.textTertiary,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          filled: true,
          fillColor: c.surface,
          border: OutlineInputBorder(
            borderRadius: AppRadius.control,
            borderSide: BorderSide(color: c.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.control,
            borderSide: BorderSide(color: c.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.control,
            borderSide: BorderSide(color: c.brand, width: 1.6),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stat card (clickable metric card with icon)
// ---------------------------------------------------------------------------

class AdminStatCard extends StatelessWidget {
  const AdminStatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.description,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final String? description;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 520;
    final accent = color ?? c.brand;
    return Material(
      color: c.surface,
      borderRadius: AppRadius.cardLg,
      child: InkWell(
        borderRadius: AppRadius.cardLg,
        onTap: onTap,
        child: Container(
          width: isCompact ? double.infinity : 210,
          constraints: const BoxConstraints(minWidth: 150),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: AppRadius.cardLg,
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(icon, size: 18, color: accent),
                  ),
                  const Spacer(),
                  if (onTap != null)
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: c.textTertiary,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                value,
                style: AppTypography.mono(
                  size: 28,
                  weight: FontWeight.w700,
                  color: accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(label, style: context.text.titleSmall),
              if (description != null) ...[
                const SizedBox(height: 2),
                Text(
                  description!,
                  style: context.text.bodySmall?.copyWith(
                    color: c.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick action button
// ---------------------------------------------------------------------------

class AdminQuickAction extends StatelessWidget {
  const AdminQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = color ?? c.brand;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelMedium?.copyWith(color: accent),
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
// Blood group badge
// ---------------------------------------------------------------------------

class BloodGroupBadge extends StatelessWidget {
  const BloodGroupBadge(this.group, {super.key, this.size = 12.5});
  final BloodGroup group;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.brandSubtle,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        group.label,
        style: AppTypography.mono(
          size: size,
          weight: FontWeight.w600,
          color: c.brand,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Confirmation dialog
// ---------------------------------------------------------------------------

Future<bool> showAdminConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool isDangerous = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final c = context.colors;
      return AlertDialog(
        title: Text(title),
        content: Text(message, style: context.text.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: isDangerous
                ? FilledButton.styleFrom(backgroundColor: c.danger)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

// ---------------------------------------------------------------------------
// Toast / Snackbar helper
// ---------------------------------------------------------------------------

void showAdminToast(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final c = context.colors;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? c.danger : null,
      behavior: SnackBarBehavior.floating,
      width: 400,
    ),
  );
}

// ---------------------------------------------------------------------------
// Activity item
// ---------------------------------------------------------------------------

class AdminActivityItem extends StatelessWidget {
  const AdminActivityItem({
    super.key,
    required this.icon,
    required this.action,
    required this.detail,
    required this.time,
    this.color,
    this.isLast = false,
  });

  final IconData icon;
  final String action;
  final String detail;
  final String time;
  final Color? color;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: (color ?? c.info).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: color ?? c.info),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action, style: context.text.titleSmall),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: AppTypography.mono(size: 11, color: c.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section divider for sidebar
// ---------------------------------------------------------------------------

class AdminSidebarSection extends StatelessWidget {
  const AdminSidebarSection(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        style: context.text.labelSmall?.copyWith(
          color: c.textTertiary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          fontSize: 10,
        ),
      ),
    );
  }
}
