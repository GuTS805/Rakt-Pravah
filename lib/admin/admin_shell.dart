import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_spacing.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_typography.dart';
import '../data/providers.dart';
import '../shared/brand_mark.dart';
import 'admin_providers.dart';

class AdminSection {
  const AdminSection(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

/// Spec §27: Dashboard, Requests, Users, Reports, Moderation, Audit Logs,
/// System Health — in that order, in a desktop sidebar.
const adminSections = [
  AdminSection('/', 'Dashboard', Icons.speed_rounded),
  AdminSection('/requests', 'Requests', Icons.receipt_long_rounded),
  AdminSection('/users', 'Users', Icons.people_alt_rounded),
  AdminSection('/reports', 'Reports', Icons.flag_rounded),
  AdminSection('/moderation', 'Moderation', Icons.gavel_rounded),
  AdminSection('/audit', 'Audit Logs', Icons.fact_check_rounded),
  AdminSection('/health', 'System Health', Icons.monitor_heart_rounded),
];

/// The console frame: a fixed sidebar and a scrolling work area. Nothing here
/// is shared with the mobile app's bottom navigation — admin is a separate
/// surface by design.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final location = GoRouterState.of(context).uri.path;
    final user = ref.watch(currentUserProvider);
    final attention = ref.watch(adminAttentionQueueProvider).length;

    return Scaffold(
      backgroundColor: c.background,
      body: Row(
        children: [
          Container(
            width: 232,
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(right: BorderSide(color: c.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                      AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
                  child: Row(
                    children: [
                      const BrandMark(size: 26),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('BloodLink',
                                style: context.text.titleMedium),
                            Text('Operations',
                                style: context.text.bodySmall
                                    ?.copyWith(color: c.textTertiary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.border),
                const SizedBox(height: AppSpacing.sm),
                for (final section in adminSections)
                  _NavItem(
                    section: section,
                    selected: section.path == '/'
                        ? location == '/'
                        : location.startsWith(section.path),
                    badge: section.path == '/moderation' && attention > 0
                        ? attention
                        : null,
                  ),
                const Spacer(),
                Divider(height: 1, color: c.border),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user?.name ?? 'Signed out',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.titleSmall),
                            Text('Administrator',
                                style: context.text.bodySmall
                                    ?.copyWith(color: c.textTertiary)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Sign out',
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        onPressed: () =>
                            ref.read(authControllerProvider.notifier).logout(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.section, required this.selected, this.badge});
  final AdminSection section;
  final bool selected;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 1),
      child: Material(
        color: selected ? c.brandSubtle : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () => context.go(section.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.md),
            child: Row(
              children: [
                Icon(section.icon,
                    size: 18,
                    color: selected ? c.brand : c.textSecondary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    section.label,
                    style: context.text.titleSmall?.copyWith(
                      color: selected ? c.brand : c.textPrimary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.warning,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text('$badge',
                        style: AppTypography.mono(
                            size: 11,
                            weight: FontWeight.w700,
                            color: Colors.white)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every admin page opens the same way: what this page is, and how much work
/// is on it. No decorative headers.
class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl, AppSpacing.xl, AppSpacing.xxl, AppSpacing.lg),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.headlineSmall),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: context.text.bodyMedium
                            ?.copyWith(color: c.textSecondary)),
                  ],
                ),
              ),
              ...?actions,
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// A count with a label. Reads as an instrument, not a marketing stat: the
/// number carries a semantic colour only when it represents work that is
/// going wrong.
class AdminMetric extends StatelessWidget {
  const AdminMetric({
    super.key,
    required this.value,
    required this.label,
    this.hint,
    this.tone,
  });

  final int value;
  final String label;
  final String? hint;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final colour = value == 0 ? c.textPrimary : (tone ?? c.textPrimary);
    return Container(
      width: 190,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.cardLg,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value',
              style: AppTypography.mono(
                  size: 30, weight: FontWeight.w700, color: colour)),
          const SizedBox(height: AppSpacing.xs),
          Text(label, style: context.text.titleSmall),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!,
                style:
                    context.text.bodySmall?.copyWith(color: c.textTertiary)),
          ],
        ],
      ),
    );
  }
}

/// A bordered surface for a table or list. Tables scroll horizontally inside
/// it rather than forcing the page to.
class AdminPanel extends StatelessWidget {
  const AdminPanel({super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.cardLg,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md,
                AppSpacing.md, AppSpacing.md),
            child: Row(
              children: [
                Expanded(child: Text(title, style: context.text.titleMedium)),
                ?trailing,
              ],
            ),
          ),
          Divider(height: 1, color: c.border),
          child,
        ],
      ),
    );
  }
}

/// Honest empty state: says why there is nothing here, not just that there
/// isn't.
class AdminEmpty extends StatelessWidget {
  const AdminEmpty({super.key, required this.message, this.icon});
  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.huge),
      child: Center(
        child: Column(
          children: [
            Icon(icon ?? Icons.inbox_rounded, size: 28, color: c.textTertiary),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: 420,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style:
                    context.text.bodyMedium?.copyWith(color: c.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
