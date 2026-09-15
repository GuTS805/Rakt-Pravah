import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/settings_widgets.dart';

class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _shareAfterAccept = true;
  bool _hideLastDonation = false;

  /// Real OS permission dialog on enable — turning it off is a local
  /// preference only, since an already-granted OS permission can't be revoked
  /// from inside the app.
  Future<void> _toggleLocation(DonorProfile donor, bool on) async {
    if (!on) {
      await ref
          .read(backendProvider)
          .setDonorProfile(donor.copyWith(locationGranted: false));
      return;
    }
    final result = await ref.read(deviceLocationProvider.notifier).request();
    if (!result.isGranted && mounted) {
      final deniedForever = result.status == DeviceLocationStatus.deniedForever;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deniedForever
                ? 'Location is blocked for BloodLink. Enable it in system settings.'
                : 'Location access is needed to match you with nearby requests.',
          ),
          action: deniedForever
              ? SnackBarAction(
                  label: 'Open settings',
                  onPressed: () =>
                      ref.read(locationServiceProvider).openAppSettings(),
                )
              : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final donor = ref.watch(donorProfileValueProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & location')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: c.infoSubtle,
              borderRadius: AppRadius.cardLg,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, color: c.info, size: 20),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Your phone number and exact location are private by '
                    'default. They\'re shared only when you accept a request or '
                    'choose to share live location.',
                    style: context.text.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SettingsSection(
            title: 'Location',
            children: [
              SettingsSwitchTile(
                icon: Icons.location_on_outlined,
                title: 'Location access',
                subtitle: 'Used to match you with nearby requests',
                value: donor.locationGranted,
                onChanged: (v) => _toggleLocation(donor, v),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SettingsSection(
            title: 'Sharing',
            children: [
              SettingsSwitchTile(
                icon: Icons.contact_phone_outlined,
                title: 'Share contact after accepting',
                subtitle:
                    'Let the other party message you once you\'ve accepted',
                value: _shareAfterAccept,
                onChanged: (v) => setState(() => _shareAfterAccept = v),
              ),
              SettingsSwitchTile(
                icon: Icons.visibility_off_outlined,
                title: 'Hide last donation date',
                subtitle: 'Keep your donation timing private',
                value: _hideLastDonation,
                onChanged: (v) => setState(() => _hideLastDonation = v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
