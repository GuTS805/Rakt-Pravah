import 'package:flutter/material.dart';

import '../../data/models/blood_compatibility.dart';
import '../../data/models/enums.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import 'buttons.dart';

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
          _Chip(group: g, selected: g == selected, onTap: () => onChanged(g)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.group,
    required this.selected,
    required this.onTap,
  });

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

/// Multiple blood groups can genuinely fulfill one request — a patient isn't
/// limited to donors of their exact type, so requests are open to a *set* of
/// compatible groups rather than a single one. This picker lets a requester
/// choose that set directly, with an optional guided helper (below) for
/// anyone who doesn't have ABO/Rh compatibility memorized, which is a
/// reasonable thing not to know in an emergency.
class BloodGroupMultiPicker extends StatelessWidget {
  const BloodGroupMultiPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Set<BloodGroup> selected;
  final ValueChanged<Set<BloodGroup>> onChanged;

  void _toggle(BloodGroup g) {
    final next = Set<BloodGroup>.of(selected);
    next.contains(g) ? next.remove(g) : next.add(g);
    onChanged(next);
  }

  Future<void> _openSuggestSheet(BuildContext context) async {
    final picked = await showModalBottomSheet<BloodGroup>(
      context: context,
      showDragHandle: true,
      builder: (context) => _SuggestSheet(current: selected),
    );
    if (picked != null) {
      onChanged(Set<BloodGroup>.of(donorsCompatibleWith(picked)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final g in BloodGroup.values)
              _MultiChip(
                group: g,
                selected: selected.contains(g),
                onTap: () => _toggle(g),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: Text(
                selected.isEmpty
                    ? 'Choose at least one group.'
                    : selected.length == 1
                    ? 'Donors with this exact type will see it.'
                    : 'Donors with any of these ${selected.length} types will see it.',
                style: context.text.bodySmall,
              ),
            ),
            TextButton.icon(
              onPressed: () => _openSuggestSheet(context),
              icon: Icon(Icons.auto_awesome_rounded, size: 16, color: c.brand),
              label: Text(
                'Suggest for a patient',
                style: context.text.labelMedium?.copyWith(color: c.brand),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MultiChip extends StatefulWidget {
  const _MultiChip({
    required this.group,
    required this.selected,
    required this.onTap,
  });

  final BloodGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_MultiChip> createState() => _MultiChipState();
}

class _MultiChipState extends State<_MultiChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    lowerBound: 0.0,
    upperBound: 1.0,
  );
  late final Animation<double> _scale = Tween(begin: 1.0, end: 0.9).animate(
    CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    ),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selected = widget.selected;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Blood group ${widget.group.label}',
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) => _ctrl.reverse(),
        onTapCancel: () => _ctrl.reverse(),
        onTap: widget.onTap,
        child: ScaleTransition(
          scale: _scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 62,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? c.brand : c.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: selected ? c.brand : c.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Text(
                  widget.group.label,
                  style: AppTypography.mono(
                    size: 16,
                    weight: FontWeight.w700,
                    color: selected ? c.onBrand : c.textSecondary,
                  ),
                ),
                if (selected)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      height: 16,
                      width: 16,
                      decoration: BoxDecoration(
                        color: c.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.surface, width: 1.5),
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 11,
                        color: c.onBrand,
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

/// "What's the patient's blood group?" — a single-select micro-picker that
/// hands back the compatible donor set for that type, so the multi-select
/// above can be filled correctly in one tap instead of requiring the
/// requester to already know ABO/Rh compatibility.
class _SuggestSheet extends StatefulWidget {
  const _SuggestSheet({required this.current});
  final Set<BloodGroup> current;

  @override
  State<_SuggestSheet> createState() => _SuggestSheetState();
}

class _SuggestSheetState extends State<_SuggestSheet> {
  BloodGroup? _patient;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final preview = _patient == null ? null : donorsCompatibleWith(_patient!);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xxl + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What\'s the patient\'s blood group?',
            style: context.text.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'We\'ll select every donor type that can safely give to this '
            'patient — you can still adjust it after.',
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          BloodGroupPicker(
            selected: _patient,
            onChanged: (g) => setState(() => _patient = g),
          ),
          if (preview != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final g in preview)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: c.successSubtle,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      g.label,
                      style: AppTypography.mono(
                        size: 13,
                        weight: FontWeight.w700,
                        color: c.success,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'Use these groups',
            onPressed: _patient == null
                ? null
                : () => Navigator.pop(context, _patient),
          ),
        ],
      ),
    );
  }
}
