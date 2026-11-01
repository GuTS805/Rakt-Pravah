import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/links.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/providers.dart';
import '../../shared/settings_widgets.dart';

/// What Rakt Pravah is and isn't, for anyone relying on it in an emergency.
const medicalDisclaimer =
    'Rakt Pravah connects people who need blood with volunteer donors. It '
    'is not a medical service and does not give medical advice. Whether '
    'someone can donate, and every transfusion, is decided by the hospital '
    'or blood bank after their own screening and tests. In an emergency, '
    'contact a hospital or call 112.';

/// Opens [url] in the browser. Replaceable in tests, which have no browser.
@visibleForTesting
Future<bool> Function(String url) openLink = (url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

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
                  onTap: () => ref.read(themeModeProvider.notifier).set(m),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Icon(_icon(m), size: 20, color: c.textSecondary),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            _label(m),
                            style: context.text.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (mode == m)
                          Icon(
                            Icons.check_circle_rounded,
                            color: c.brand,
                            size: 20,
                          )
                        else
                          Icon(
                            Icons.circle_outlined,
                            color: c.border,
                            size: 20,
                          ),
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
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy policy',
                onTap: () => _open(context, Links.privacy),
              ),
              SettingsTile(
                icon: Icons.description_outlined,
                title: 'Terms of use',
                onTap: () => _open(context, Links.terms),
              ),
              SettingsTile(
                icon: Icons.health_and_safety_outlined,
                title: 'Medical disclaimer',
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Medical disclaimer'),
                    content: const Text(medicalDisclaimer),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await openLink(url);
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't open the page. It's at $url")),
      );
    }
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
