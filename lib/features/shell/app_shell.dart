import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../data/providers.dart';

/// The single unified shell. One account, four flows — never separate donor and
/// requester apps (spec §4). A badge on Donate reflects pending opportunities.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingInvitationsProvider).length;
    final donorOn = ref.watch(donorProfileValueProvider).isOn;

    return Scaffold(
      body: shell,
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: shell.currentIndex,
        donateBadge: donorOn ? pending : 0,
        onTap: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.activeIcon, this.label);
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

const _items = [
  _NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
  _NavItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Requests'),
  _NavItem(Icons.favorite_outline_rounded, Icons.favorite_rounded, 'Donate'),
  _NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'You'),
];

class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.donateBadge = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int donateBadge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (int i = 0; i < _items.length; i++)
                Expanded(
                  child: _NavButton(
                    item: _items[i],
                    selected: i == currentIndex,
                    badge: i == 2 ? donateBadge : 0,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = selected ? c.brand : c.textTertiary;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkResponse(
        onTap: onTap,
        radius: 44,
        highlightColor: c.brand.withValues(alpha: 0.05),
        splashColor: c.brand.withValues(alpha: 0.06),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedScale(
                  scale: selected ? 1.06 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    selected ? item.activeIcon : item.icon,
                    size: 24,
                    color: color,
                  ),
                ),
                if (badge > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(minWidth: 16),
                      decoration: BoxDecoration(
                        color: c.brand,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: c.surface, width: 1.5),
                      ),
                      child: Text(
                        '$badge',
                        textAlign: TextAlign.center,
                        style: AppTypography.mono(
                          size: 9,
                          weight: FontWeight.w700,
                          color: c.onBrand,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              item.label,
              style: context.text.labelSmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
