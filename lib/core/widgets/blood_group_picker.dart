import 'package:flutter/material.dart';

import '../../data/models/enums.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

/// A grid of selectable blood-group chips. Values are set in mono to match the
/// instrument-panel treatment used everywhere blood groups appear.
class BloodGroupPicker extends StatelessWidget {
  const BloodGroupPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final BloodGroup? selected;
  final ValueChanged<BloodGroup> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final g in BloodGroup.values)
          _Chip(
            group: g,
            selected: g == selected,
            onTap: () => onChanged(g),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.group, required this.selected, required this.onTap});

  final BloodGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Blood group ${group.label}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 62,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.brandSubtle : c.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? c.brand : c.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Text(
            group.label,
            style: AppTypography.mono(
              size: 16,
              weight: FontWeight.w700,
              color: selected ? c.brand : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
