import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/router/routes.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_typography.dart';
import '../data/models/models.dart';
import '../data/providers.dart';
import '../shared/brand_mark.dart';
import 'admin_providers.dart';

class AdminSection {
  const AdminSection(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

/// Sidebar sections grouped by category.
const _mainSections = [
  AdminSection(Routes.adminDashboard, 'Dashboard', Icons.dashboard_rounded),
];

const _operationsSections = [
  AdminSection(
    Routes.adminEmergency,
    'Emergency Monitoring',
    Icons.emergency_rounded,
  ),
  AdminSection(
    Routes.adminAvailability,
    'Blood Availability',
    Icons.water_drop_rounded,
  ),
  AdminSection(Routes.adminLiveMap, 'Live Map', Icons.map_rounded),
  AdminSection(
    Routes.adminRequests,
    'Requests Overview',
    Icons.receipt_long_rounded,
  ),
  AdminSection(Routes.adminDonations, 'Donations', Icons.bloodtype_rounded),
  AdminSection(Routes.adminConnections, 'Connections', Icons.handshake_rounded),
];

const _peopleSections = [
  AdminSection(Routes.adminUsers, 'User Management', Icons.people_alt_rounded),
  AdminSection(
    Routes.adminDonors,
    'Donor Network',
    Icons.volunteer_activism_rounded,
  ),
  AdminSection(
    Routes.adminVerification,
    'Donor Verification',
    Icons.verified_user_rounded,
  ),
  AdminSection(
    Routes.adminHospitals,
    'Hospitals',
    Icons.local_hospital_rounded,
  ),
];

const _insightsSections = [
  AdminSection(Routes.adminAnalytics, 'Analytics', Icons.analytics_rounded),
  AdminSection(
    Routes.adminAudit,
    'Activity & Audit Logs',
    Icons.fact_check_rounded,
  ),
  AdminSection(Routes.adminReports, 'Reports', Icons.summarize_rounded),
  AdminSection(
    Routes.adminNotifications,
    'Notifications',
    Icons.notifications_rounded,
  ),
  AdminSection(Routes.adminModeration, 'Moderation', Icons.gavel_rounded),
];

const _systemSections = [
  AdminSection(
    Routes.adminHealth,
    'System Health',
    Icons.monitor_heart_rounded,
  ),
  AdminSection(Routes.adminSettings, 'Settings', Icons.settings_rounded),
];

/// The console frame: responsive with desktop sidebar (>=800px) and
/// mobile header + navigation drawer (<800px).
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 800;
    final location = GoRouterState.of(context).uri.path;
    final user = ref.watch(currentUserProvider);
    final attention = ref.watch(adminAttentionQueueProvider).length;

    Widget navItem(AdminSection section, {int? badge, VoidCallback? onNav}) {
      final selected = section.path == Routes.adminDashboard
          ? (location == '/' || location == Routes.adminDashboard)
          : (location == section.path ||
                location.startsWith('${section.path}/'));
      return _NavItem(
        section: section,
        selected: selected,
        badge: badge,
        onTap: () {
          if (onNav != null) onNav();
          context.go(section.path);
        },
      );
    }

    Widget buildNavList({VoidCallback? onNav}) {
      return SingleChildScrollView(
        padding: const EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in _mainSections) navItem(s, onNav: onNav),
            const AdminSidebarSection('Blood Operations'),
            for (final s in _operationsSections)
              navItem(
                s,
                onNav: onNav,
                badge: s.path == Routes.adminEmergency
                    ? _emergencyCount(ref)
                    : null,
              ),
            const AdminSidebarSection('People & Donors'),
            for (final s in _peopleSections) navItem(s, onNav: onNav),
            const AdminSidebarSection('Insights & Governance'),
            for (final s in _insightsSections)
              navItem(
                s,
                onNav: onNav,
                badge: s.path == Routes.adminModeration && attention > 0
                    ? attention
                    : null,
              ),
            const AdminSidebarSection('System'),
            for (final s in _systemSections) navItem(s, onNav: onNav),
          ],
        ),
      );
    }

    Widget buildFooter() {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: c.brand.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  (user?.name.isNotEmpty == true ? user!.name[0] : '?')
                      .toUpperCase(),
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user?.name ?? 'Signed out',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall,
                  ),
                  Text(
                    'Administrator',
                    style: context.text.bodySmall?.copyWith(
                      color: c.textTertiary,
                    ),
                  ),
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
      );
    }

    if (isMobile) {
      return Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.surface,
          elevation: 0,
          leading: Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu_rounded),
              tooltip: 'Navigation Menu',
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 24),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  'Rakt Pravah Admin',
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: c.border, height: 1),
          ),
          actions: [
            IconButton(
              tooltip: 'Notifications',
              icon: const Icon(Icons.notifications_outlined, size: 22),
              onPressed: () => context.go(Routes.adminNotifications),
            ),
          ],
        ),
        drawer: Drawer(
          backgroundColor: c.surface,
          width: (width * 0.82).clamp(280.0, 340.0),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      const BrandMark(size: 28),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rakt Pravah',
                              style: context.text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Operations Console',
                              style: context.text.bodySmall?.copyWith(
                                color: c.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        tooltip: 'Close Menu',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.border),
                Expanded(
                  child: buildNavList(onNav: () => Navigator.of(context).pop()),
                ),
                Divider(height: 1, color: c.border),
                buildFooter(),
              ],
            ),
          ),
        ),
        body: child,
      );
    }

    // Desktop permanent sidebar
    return Scaffold(
      backgroundColor: c.background,
      body: Row(
        children: [
          Container(
            width: 250,
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(right: BorderSide(color: c.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: Row(
                    children: [
                      const BrandMark(size: 26),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rakt Pravah',
                              style: context.text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Admin Console',
                              style: context.text.bodySmall?.copyWith(
                                color: c.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.border),
                Expanded(child: buildNavList()),
                Divider(height: 1, color: c.border),
                buildFooter(),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  int _emergencyCount(WidgetRef ref) {
    final requests = ref.watch(adminRequestsProvider).valueOrNull ?? const [];
    return requests
        .where(
          (r) =>
              r.isOpen &&
              (r.urgency == Urgency.critical || r.urgency == Urgency.urgent),
        )
        .length;
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.section,
    required this.selected,
    this.badge,
    this.onTap,
  });

  final AdminSection section;
  final bool selected;
  final int? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 1,
      ),
      child: Material(
        color: selected ? c.brandSubtle : Colors.transparent,
        borderRadius: AppRadius.buttonRadius,
        child: InkWell(
          borderRadius: AppRadius.buttonRadius,
          onTap: onTap ?? () => context.go(section.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 10,
            ),
            child: Row(
              children: [
                Icon(
                  section.icon,
                  size: 18,
                  color: selected ? c.brand : c.textSecondary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    section.label,
                    style: context.text.titleSmall?.copyWith(
                      color: selected ? c.brand : c.textPrimary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (badge != null && badge! > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: c.danger,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '$badge',
                      style: AppTypography.mono(
                        size: 11,
                        weight: FontWeight.w700,
                        color: Colors.white,
                      ),
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

/// Category divider in the sidebar.
class AdminSidebarSection extends StatelessWidget {
  const AdminSidebarSection(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.mono(
          size: 10,
          weight: FontWeight.w700,
          color: c.textTertiary,
          spacing: 0.8,
        ),
      ),
    );
  }
}

/// Every admin page opens the same way: what this page is, and how much work
/// is on it. Responsive padding ensures no overflow on narrow mobile screens.
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
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 600;
    final hPad = isMobile ? AppSpacing.md : AppSpacing.xxl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(
            hPad,
            isMobile ? AppSpacing.md : AppSpacing.xl,
            hPad,
            isMobile ? AppSpacing.md : AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.headlineSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: context.text.bodyMedium?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                    if (actions != null && actions!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: actions!,
                      ),
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: context.text.headlineSmall),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: context.text.bodyMedium?.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (actions != null && actions!.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      ...actions!,
                    ],
                  ],
                ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(hPad),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// A count with a label. Reads as an instrument, not a marketing stat.
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
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 220),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.cardMd,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: AppTypography.mono(
              size: 28,
              weight: FontWeight.w700,
              color: colour,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(label, style: context.text.titleSmall),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(
              hint!,
              style: context.text.bodySmall?.copyWith(color: c.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// A bordered surface for a table or list.
class AdminPanel extends StatelessWidget {
  const AdminPanel({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.cardMd,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                Text(title, style: context.text.titleMedium),
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

/// Honest empty state.
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
                style: context.text.bodyMedium?.copyWith(
                  color: c.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
