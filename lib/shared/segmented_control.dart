import 'package:flutter/material.dart';

import '../core/theme/app_spacing.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_typography.dart';

class Segment {
  const Segment(this.label, {this.badge = 0});
  final String label;
  final int badge;
}

/// A pill segmented control with a sliding selection. Used where a screen has
/// two or three peer views (My requests / Invitations, history tabs).
class SegmentedControl extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<Segment> segments;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          for (int i = 0; i < segments.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? c.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    boxShadow: i == selected
                        ? [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: context.isDark ? 0.3 : 0.06),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        segments[i].label,
                        style: context.text.labelMedium?.copyWith(
                          color: i == selected
                              ? c.textPrimary
                              : c.textSecondary,
                        ),
                      ),
                      if (segments[i].badge > 0) ...[
                        const SizedBox(width: AppSpacing.xs + 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: c.brand,
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            '${segments[i].badge}',
                            style: AppTypography.mono(
                                size: 10,
                                weight: FontWeight.w700,
                                color: c.onBrand),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
