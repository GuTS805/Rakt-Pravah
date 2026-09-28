import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'buttons.dart';

/// Empty state — an invitation to act, never just a shrug (spec §30).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 64,
              width: 64,
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Icon(icon, size: 30, color: c.textTertiary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.text.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error state — says what went wrong and how to recover, in the app's voice.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    this.title = 'Something went wrong',
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 64,
              width: 64,
              decoration: BoxDecoration(
                color: c.dangerSubtle,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 30,
                color: c.danger,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: context.text.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              SecondaryButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A shimmering skeleton block for loading states.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.height = 16,
    this.width = double.infinity,
    this.radius = AppRadius.sm,
  });

  final double height;
  final double width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: Color.lerp(c.surfaceMuted, c.border, _ctrl.value),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// A skeleton shaped like a content card, for list loading states.
class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.cardLg,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Skeleton(height: 40, width: 40, radius: AppRadius.sm),
              SizedBox(width: AppSpacing.md),
              Expanded(child: Skeleton(height: 16, width: 120)),
              Skeleton(height: 22, width: 64, radius: AppRadius.pill),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          Skeleton(height: 12, width: double.infinity),
          SizedBox(height: AppSpacing.sm),
          Skeleton(height: 12, width: 180),
        ],
      ),
    );
  }
}

/// A skeleton loader for tabular/grid views.
class TableSkeleton extends StatelessWidget {
  const TableSkeleton({super.key, this.rows = 4});
  final int rows;

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
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            color: c.surfaceMuted,
            child: Row(
              children: const [
                Expanded(flex: 3, child: Skeleton(height: 12, width: 80)),
                SizedBox(width: AppSpacing.md),
                Expanded(flex: 2, child: Skeleton(height: 12, width: 60)),
                SizedBox(width: AppSpacing.md),
                Expanded(flex: 2, child: Skeleton(height: 12, width: 60)),
                SizedBox(width: AppSpacing.md),
                Expanded(flex: 1, child: Skeleton(height: 12, width: 40)),
              ],
            ),
          ),
          for (int i = 0; i < rows; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md + 2,
              ),
              child: Row(
                children: [
                  const Expanded(flex: 3, child: Skeleton(height: 14)),
                  const SizedBox(width: AppSpacing.md),
                  const Expanded(flex: 2, child: Skeleton(height: 14)),
                  const SizedBox(width: AppSpacing.md),
                  const Expanded(flex: 2, child: Skeleton(height: 14)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 1,
                    child: Skeleton(
                      height: 22,
                      width: 48,
                      radius: AppRadius.pill,
                    ),
                  ),
                ],
              ),
            ),
            if (i < rows - 1) Divider(height: 1, color: c.border),
          ],
        ],
      ),
    );
  }
}

/// A skeleton loader for KPI/Stat cards.
class StatCardSkeleton extends StatelessWidget {
  const StatCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 200,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.cardMd,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Skeleton(height: 28, width: 28, radius: AppRadius.sm),
          SizedBox(height: AppSpacing.md),
          Skeleton(height: 24, width: 64),
          SizedBox(height: AppSpacing.xs),
          Skeleton(height: 12, width: 100),
        ],
      ),
    );
  }
}

/// Consistent toast & feedback helper for the entire application.
abstract class AppToast {
  static void showSuccess(BuildContext context, String message) {
    _show(context, message, isError: false, icon: Icons.check_circle_rounded);
  }

  static void showError(BuildContext context, String message) {
    _show(context, message, isError: true, icon: Icons.error_outline_rounded);
  }

  static void showWarning(BuildContext context, String message) {
    final c = context.colors;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.buttonRadius,
          side: BorderSide(color: c.warning.withValues(alpha: 0.4)),
        ),
        content: Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: c.warning),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: context.text.bodyMedium?.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _show(
    BuildContext context,
    String message, {
    required bool isError,
    required IconData icon,
  }) {
    final c = context.colors;
    final color = isError ? c.danger : c.success;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.buttonRadius,
          side: BorderSide(color: color.withValues(alpha: 0.4)),
        ),
        content: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: context.text.bodyMedium?.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
