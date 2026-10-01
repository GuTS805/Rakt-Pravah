import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
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
  // Simulated settings state — in production these would read/write Firestore.
  bool _maintenanceMode = false;
  bool _allowNewRegistrations = true;
  bool _autoMatchDonors = true;
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  bool _emergencyAlerts = true;
  int _maxRequestsPerUser = 3;
  int _cooldownDays = 90;
  int _requestExpiryHours = 24;
  double _maxSearchRadius = 50.0;

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'Settings',
      subtitle: 'Configure system behavior and platform settings.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- General Settings ---
          _SettingsSection(
            title: 'General',
            icon: Icons.settings_rounded,
            children: [
              _ToggleSetting(
                title: 'Maintenance Mode',
                description:
                    'When enabled, only admins can access the platform.',
                value: _maintenanceMode,
                onChanged: (v) => setState(() => _maintenanceMode = v),
                isDangerous: true,
              ),
              _ToggleSetting(
                title: 'Allow New Registrations',
                description: 'Enable new users to create accounts.',
                value: _allowNewRegistrations,
                onChanged: (v) => setState(() => _allowNewRegistrations = v),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Donor Settings ---
          _SettingsSection(
            title: 'Donor Configuration',
            icon: Icons.volunteer_activism_rounded,
            children: [
              _ToggleSetting(
                title: 'Auto-Match Donors',
                description:
                    'Automatically match donors to requests based on '
                    'blood group and location.',
                value: _autoMatchDonors,
                onChanged: (v) => setState(() => _autoMatchDonors = v),
              ),
              _SliderSetting(
                title: 'Cooldown Period (days)',
                description: 'Minimum days between donations for donor safety.',
                value: _cooldownDays.toDouble(),
                min: 30,
                max: 180,
                divisions: 15,
                label: '$_cooldownDays days',
                onChanged: (v) => setState(() => _cooldownDays = v.round()),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Blood Request Settings ---
          _SettingsSection(
            title: 'Blood Request Configuration',
            icon: Icons.receipt_long_rounded,
            children: [
              _SliderSetting(
                title: 'Max Requests Per User',
                description:
                    'Maximum active blood requests per user at a time.',
                value: _maxRequestsPerUser.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: '$_maxRequestsPerUser',
                onChanged: (v) =>
                    setState(() => _maxRequestsPerUser = v.round()),
              ),
              _SliderSetting(
                title: 'Request Expiry (hours)',
                description:
                    'Hours before an unmatched request is marked expired.',
                value: _requestExpiryHours.toDouble(),
                min: 1,
                max: 72,
                divisions: 71,
                label: '$_requestExpiryHours hours',
                onChanged: (v) =>
                    setState(() => _requestExpiryHours = v.round()),
              ),
              _SliderSetting(
                title: 'Max Search Radius (km)',
                description:
                    'Maximum radius for donor matching around the request '
                    'location.',
                value: _maxSearchRadius,
                min: 5,
                max: 200,
                divisions: 39,
                label: '${_maxSearchRadius.round()} km',
                onChanged: (v) => setState(() => _maxSearchRadius = v),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Notification Settings ---
          _SettingsSection(
            title: 'Notifications',
            icon: Icons.notifications_rounded,
            children: [
              _ToggleSetting(
                title: 'Email Notifications',
                description: 'Send email notifications for critical events.',
                value: _emailNotifications,
                onChanged: (v) => setState(() => _emailNotifications = v),
              ),
              _ToggleSetting(
                title: 'Push Notifications',
                description: 'Send push notifications to mobile devices.',
                value: _pushNotifications,
                onChanged: (v) => setState(() => _pushNotifications = v),
              ),
              _ToggleSetting(
                title: 'Emergency Alerts',
                description:
                    'Allow sending emergency blood need alerts to all '
                    'available donors.',
                value: _emergencyAlerts,
                onChanged: (v) => setState(() => _emergencyAlerts = v),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Security Settings ---
          _SettingsSection(
            title: 'Security',
            icon: Icons.security_rounded,
            children: [
              _ActionSetting(
                title: 'Export Audit Logs',
                description: 'Download all administrative audit logs as CSV.',
                actionLabel: 'Export',
                icon: Icons.download_rounded,
                onTap: () => showAdminToast(
                  context,
                  'Audit log export is not yet implemented.',
                ),
              ),
              _ActionSetting(
                title: 'Clear Session Cache',
                description: 'Clear all cached session data.',
                actionLabel: 'Clear',
                icon: Icons.cleaning_services_rounded,
                isDangerous: true,
                onTap: () => showAdminToast(context, 'Session cache cleared.'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Save button
          Center(
            child: FilledButton.icon(
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save Settings'),
              onPressed: () => showAdminToast(
                context,
                'Settings saved. Note: Settings are currently in-memory '
                'only and will reset on reload. Firestore persistence '
                'requires backend configuration.',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxl,
                  vertical: AppSpacing.md,
                ),
              ),
            ),
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
    this.isDangerous = false,
  });
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDangerous;

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
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: isDangerous ? c.danger : null,
          ),
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
    this.divisions,
    this.label,
  });
  final String title;
  final String description;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
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
                    color: c.brandSubtle,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    label!,
                    style: AppTypography.mono(
                      size: 12,
                      weight: FontWeight.w600,
                      color: c.brand,
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
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ActionSetting extends StatelessWidget {
  const _ActionSetting({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.icon,
    required this.onTap,
    this.isDangerous = false,
  });
  final String title;
  final String description;
  final String actionLabel;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDangerous;

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
          OutlinedButton.icon(
            icon: Icon(icon, size: 16),
            label: Text(actionLabel),
            onPressed: onTap,
            style: isDangerous
                ? OutlinedButton.styleFrom(
                    foregroundColor: c.danger,
                    side: BorderSide(color: c.danger),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
