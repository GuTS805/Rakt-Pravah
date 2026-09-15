import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

/// The base surface for grouped content. A hairline border + a whisper of
/// shadow — deliberately restrained, not the over-shadowed "AI card" look.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.accent,
    this.emphasize = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  /// Optional left accent bar (e.g. urgency color) for emphasis.
  final Color? accent;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.cardLg,
        border: Border.all(color: emphasize ? c.borderStrong : c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.18 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );

    final withAccent = accent == null
        ? content
        : ClipRRect(
            borderRadius: AppRadius.cardLg,
            child: Stack(
              children: [
                content,
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 4, color: accent),
                ),
              ],
            ),
          );

    if (onTap == null) return withAccent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardLg,
        child: withAccent,
      ),
    );
  }
}

/// A section header: a mono eyebrow label with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.trailing});

  final String title;
  final Widget? trailing;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: AppTypography.eyebrow(c.textTertiary),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
