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
    this.height = 48,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final bool danger;
  final double height;

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
                Icon(icon, size: 18, color: c.onBrand),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelLarge?.copyWith(
                    color: c.onBrand,
                    fontWeight: FontWeight.w600,
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
        color: enabled ? bg : bg.withValues(alpha: 0.45),
        borderRadius: AppRadius.buttonRadius,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: AppRadius.buttonRadius,
          child: Container(
            height: height,
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
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
    this.height = 48,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool destructive;
  final double height;

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
        borderRadius: AppRadius.buttonRadius,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadius.buttonRadius,
          child: Container(
            height: height,
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: AppRadius.buttonRadius,
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
                    style: context.text.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
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

/// Destructive button for dangerous actions (delete, block, reject).
class DestructiveButton extends StatelessWidget {
  const DestructiveButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
    this.outlined = false,
    this.height = 48,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final bool outlined;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null && !busy;

    final child = busy
        ? SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(
                outlined ? c.danger : Colors.white,
              ),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: outlined ? c.danger : Colors.white),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelLarge?.copyWith(
                    color: outlined ? c.danger : Colors.white,
                    fontWeight: FontWeight.w600,
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
        color: outlined
            ? c.surface
            : (enabled ? c.danger : c.danger.withValues(alpha: 0.45)),
        borderRadius: AppRadius.buttonRadius,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: AppRadius.buttonRadius,
          child: Container(
            height: height,
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: outlined
                ? BoxDecoration(
                    borderRadius: AppRadius.buttonRadius,
                    border: Border.all(
                      color: c.danger.withValues(alpha: 0.45),
                    ),
                  )
                : null,
            child: child,
          ),
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Emergency button: exclusively for urgent/critical blood responses.
class EmergencyButton extends StatelessWidget {
  const EmergencyButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon = Icons.emergency_rounded,
    this.busy = false,
    this.expand = true,
    this.height = 50,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool busy;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null && !busy;

    final child = busy
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation(Colors.white),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: Colors.white),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
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
        color: enabled ? c.brand : c.brand.withValues(alpha: 0.5),
        borderRadius: AppRadius.buttonRadius,
        elevation: enabled ? 2 : 0,
        shadowColor: c.brand.withValues(alpha: 0.35),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: AppRadius.buttonRadius,
          child: Container(
            height: height,
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
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

/// Accessible icon button with minimum touch target (44x44px).
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.color,
    this.backgroundColor,
    this.size = 20,
    this.padding = 10,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final Color? backgroundColor;
  final double size;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final iconWidget = Icon(
      icon,
      size: size,
      color: color ?? c.textPrimary,
    );

    final button = Material(
      color: backgroundColor ?? Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: iconWidget,
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
