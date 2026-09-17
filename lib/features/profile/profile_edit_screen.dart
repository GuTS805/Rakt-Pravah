import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/blood_group_picker.dart';
import '../../core/widgets/buttons.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';
import '../../shared/profile_fields.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _country;
  late final TextEditingController _state;
  late final TextEditingController _city;
  late BloodGroup _group;
  DateTime? _dateOfBirth;
  Gender? _gender;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider)!;
    _name = TextEditingController(text: user.name);
    _country = TextEditingController(text: user.country ?? 'India');
    _state = TextEditingController(text: user.state ?? '');
    _city = TextEditingController(text: user.city ?? '');
    _group = user.bloodGroup;
    _dateOfBirth = user.dateOfBirth;
    _gender = user.gender;
  }

  @override
  void dispose() {
    _name.dispose();
    _country.dispose();
    _state.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .updateProfile(
            name: _name.text.trim(),
            bloodGroup: _group,
            dateOfBirth: _dateOfBirth!,
            gender: _gender!,
            country: _country.text.trim(),
            state: _state.text.trim(),
            city: _city.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile updated.')));
        context.pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t save changes. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const FieldLabel('Full name'),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Your name'),
              validator: (v) =>
                  (v ?? '').trim().length < 2 ? 'Enter your name' : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            const FieldLabel('Blood group'),
            BloodGroupPicker(
              selected: _group,
              onChanged: (g) => setState(() => _group = g),
            ),
            const SizedBox(height: AppSpacing.lg),
            const FieldLabel('Date of birth'),
            DateOfBirthField(
              initialValue: _dateOfBirth,
              onChanged: (d) => _dateOfBirth = d,
            ),
            const SizedBox(height: AppSpacing.lg),
            const FieldLabel('Gender'),
            GenderField(initialValue: _gender, onChanged: (g) => _gender = g),
            const SizedBox(height: AppSpacing.lg),
            HomeLocationFields(country: _country, state: _state, city: _city),
            const SizedBox(height: AppSpacing.xxl),
            PrimaryButton(label: 'Save changes', busy: _busy, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
