import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Primary call-to-action. One per screen region — the obvious next action.
/// Handles its own busy state so callers can't double-submit (spec §11).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = danger ? c.danger : c.brand;
    final enabled = onPressed != null && !busy;

    final child = busy
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation(c.onBrand),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 19, color: c.onBrand),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelLarge?.copyWith(
                    color: c.onBrand,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          );

    final button = Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: enabled ? bg : bg.withValues(alpha: 0.5),
        borderRadius: AppRadius.control,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: AppRadius.control,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: child,
          ),
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Secondary / outline action.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = true,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = destructive ? c.danger : c.textPrimary;
    final enabled = onPressed != null;

    final button = Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: c.surface,
        borderRadius: AppRadius.control,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadius.control,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: AppRadius.control,
              border: Border.all(
                color: destructive ? c.danger.withValues(alpha: 0.4) : c.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: fg),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelLarge?.copyWith(color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
