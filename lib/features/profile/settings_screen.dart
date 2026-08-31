import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/providers.dart';
import '../../shared/settings_widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          SettingsSection(
            title: 'Appearance',
            children: [
              for (final m in ThemeMode.values)
                InkWell(
                  onTap: () =>
                      ref.read(themeModeProvider.notifier).set(m),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Icon(_icon(m), size: 20, color: c.textSecondary),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(_label(m),
                              style: context.text.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w500)),
                        ),
                        if (mode == m)
                          Icon(Icons.check_circle_rounded,
                              color: c.brand, size: 20)
                        else
                          Icon(Icons.circle_outlined,
                              color: c.border, size: 20),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SettingsSection(
            title: 'About',
            children: [
              SettingsTile(
                icon: Icons.info_outline_rounded,
                title: 'Version',
                trailing: Text('1.0.0', style: context.text.bodyMedium),
              ),
              SettingsTile(
                icon: Icons.description_outlined,
                title: 'Terms & privacy policy',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _icon(ThemeMode m) => switch (m) {
        ThemeMode.system => Icons.brightness_auto_rounded,
        ThemeMode.light => Icons.light_mode_rounded,
        ThemeMode.dark => Icons.dark_mode_rounded,
      };

  String _label(ThemeMode m) => switch (m) {
        ThemeMode.system => 'System default',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };
}
