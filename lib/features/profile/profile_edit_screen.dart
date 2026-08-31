import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/blood_group_picker.dart';
import '../../core/widgets/buttons.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _city;
  late BloodGroup _group;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider)!;
    _name = TextEditingController(text: user.name);
    _city = TextEditingController(text: user.city ?? '');
    _group = user.bloodGroup;
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) return;
    setState(() => _busy = true);
    await ref.read(authControllerProvider.notifier).updateProfile(
          name: _name.text.trim(),
          bloodGroup: _group,
          city: _city.text.trim().isEmpty ? null : _city.text.trim(),
        );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile updated.')));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text('Full name', style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Your name'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Blood group', style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.md),
          BloodGroupPicker(
              selected: _group, onChanged: (g) => setState(() => _group = g)),
          const SizedBox(height: AppSpacing.lg),
          Text('City', style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _city,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'e.g. Bengaluru'),
          ),
          const SizedBox(height: AppSpacing.xxl),
          PrimaryButton(label: 'Save changes', busy: _busy, onPressed: _save),
        ],
      ),
    );
  }
}
