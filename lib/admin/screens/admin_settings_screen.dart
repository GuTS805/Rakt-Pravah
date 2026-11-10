import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../admin_providers.dart';
import '../admin_shell.dart';
import '../admin_widgets.dart';

// ---------------------------------------------------------------------------
// Settings Screen
// ---------------------------------------------------------------------------

class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  ConsumerState<AdminSettingsScreen> createState() =>
      _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  // Only settings the app actually reads are offered here. Switches that
  // saved nothing (maintenance mode, registrations, notifications...) were
  // taken out: an operator would believe they had changed something.
  int? _cooldownDays;
  bool? _cooldownEnabled;

  Future<void> _applyCooldownConfig(CooldownConfig config) async {
    // 1. Immediately update backend if it's FakeBackend/test backend
    final backend = ref.read(backendProvider);
    try {
      (backend as dynamic).emitCooldownConfig(config);
    } catch (_) {}

    // 2. Persist to local storage immediately so page refresh never resets state
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('rakt_cooldown_enabled', config.enabled);
      await prefs.setInt('rakt_cooldown_days', config.durationDays);
    } catch (_) {}

    // 3. Persist to remote Firestore via AdminBackend
    final admin = ref.read(adminBackendProvider);
    if (admin != null) {
      try {
        await admin.setCooldownConfig(config);
      } catch (e) {
        if (mounted) {
          showAdminToast(
            context,
            'Setting saved locally. (Firestore sync notice: $e)',
          );
        }
        return;
      }
    }

    if (mounted) {
      showAdminToast(
        context,
        config.enabled
            ? 'Cooldown period enabled (${config.durationDays} days).'
            : 'Cooldown period disabled.',
      );
    }
  }

  Future<void> _onToggleCooldown(bool nextVal, CooldownConfig current) async {
    final confirmed = await showAdminConfirmDialog(
      context,
      title: nextVal ? 'Enable Cooldown Period?' : 'Disable Cooldown Period?',
      message: nextVal
          ? 'Enabling the cooldown period will enforce a minimum waiting duration between blood donations. Donors who recently donated will have Donor Mode disabled until their cooldown expires.'
          : 'Disabling the cooldown period will remove donation cooldown restrictions. Donors will remain eligible according to other rules, and previous donations will not automatically disable Donor Mode.',
      confirmLabel: nextVal ? 'Enable' : 'Disable',
      isDangerous: !nextVal,
    );
    if (!confirmed || !mounted) return;

    final updated = current.copyWith(enabled: nextVal);
    setState(() {
      _cooldownEnabled = nextVal;
    });
    await _applyCooldownConfig(updated);
  }

  Future<void> _onDurationChangeEnd(int newDays, CooldownConfig current) async {
    if (newDays == current.durationDays) return;
    final confirmed = await showAdminConfirmDialog(
      context,
      title: 'Update Cooldown Duration?',
      message:
          'Set donation cooldown to $newDays days? This will immediately affect donor eligibility calculations across the application.',
      confirmLabel: 'Update Duration',
    );
    if (!confirmed || !mounted) {
      setState(() {
        _cooldownDays = current.durationDays;
      });
      return;
    }

    final updated = current.copyWith(durationDays: newDays);
    setState(() {
      _cooldownDays = newDays;
    });
    await _applyCooldownConfig(updated);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<CooldownConfig>>(adminCooldownConfigProvider, (prev, next) {
      final config = next.valueOrNull;
      if (config != null && mounted) {
        setState(() {
          _cooldownEnabled = config.enabled;
          _cooldownDays = config.durationDays;
        });
      }
    });

    final cooldownAsync = ref.watch(adminCooldownConfigProvider);
    final serverCooldown = cooldownAsync.valueOrNull ?? const CooldownConfig();
    final cooldownEnabled = _cooldownEnabled ?? serverCooldown.enabled;
    final cooldownDays = _cooldownDays ?? serverCooldown.durationDays;
    final currentCooldownConfig = CooldownConfig(
      enabled: cooldownEnabled,
      durationDays: cooldownDays,
    );

    return AdminPage(
      title: 'Settings',
      subtitle: 'Settings that apply across the app.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Donor Settings ---
          _SettingsSection(
            title: 'Donor Configuration',
            icon: Icons.volunteer_activism_rounded,
            children: [
              _ToggleSetting(
                title: 'Cooldown Period',
                description: 'Minimum days between donations for donor safety.',
                value: cooldownEnabled,
                statusBadge: cooldownEnabled ? 'ON' : 'OFF',
                onChanged: (v) => _onToggleCooldown(v, currentCooldownConfig),
              ),
              _SliderSetting(
                title: 'Cooldown Duration: [ $cooldownDays days ]',
                description: cooldownEnabled
                    ? 'Minimum days between donations for donor safety.'
                    : 'Cooldown restriction is disabled. Donors are not placed in cooldown.',
                value: cooldownDays.toDouble().clamp(15, 180),
                min: 15,
                max: 180,
                divisions: 33,
                label: '$cooldownDays days',
                enabled: cooldownEnabled,
                onChanged: cooldownEnabled
                    ? (v) => setState(() => _cooldownDays = v.round())
                    : null,
                onChangeEnd: cooldownEnabled
                    ? (v) => _onDurationChangeEnd(
                        v.round(),
                        currentCooldownConfig,
                      )
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Settings widgets ---

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: c.brand),
                const SizedBox(width: AppSpacing.sm),
                Text(title, style: context.text.titleMedium),
              ],
            ),
          ),
          Divider(height: 1, color: c.border),
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(height: 1, indent: AppSpacing.lg, color: c.border),
          ],
        ],
      ),
    );
  }
}

class _ToggleSetting extends StatelessWidget {
  const _ToggleSetting({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.statusBadge,
  });
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? statusBadge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: context.text.bodySmall?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (statusBadge != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 2,
              ),
              margin: const EdgeInsets.only(right: AppSpacing.sm),
              decoration: BoxDecoration(
                color: value ? c.brandSubtle : c.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: value ? c.brand.withValues(alpha: 0.3) : c.border,
                ),
              ),
              child: Text(
                statusBadge!,
                style: AppTypography.mono(
                  size: 11,
                  weight: FontWeight.w700,
                  color: value ? c.brand : c.textSecondary,
                ),
              ),
            ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.divisions,
    this.label,
    this.enabled = true,
  });
  final String title;
  final String description;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final bool enabled;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final effectiveColor = enabled ? c.brand : c.textSecondary;
    return Opacity(
      opacity: enabled ? 1.0 : 0.6,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: context.text.bodySmall?.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (label != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: enabled ? c.brandSubtle : c.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      label!,
                      style: AppTypography.mono(
                        size: 12,
                        weight: FontWeight.w600,
                        color: effectiveColor,
                      ),
                    ),
                  ),
              ],
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: enabled ? onChanged : null,
              onChangeEnd: enabled ? onChangeEnd : null,
            ),
          ],
        ),
      ),
    );
  }
}
