import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/blood_group_picker.dart';
import '../../core/widgets/buttons.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';
import '../../shared/profile_fields.dart';

/// Registration asks for everything up front: name, phone, blood group, date
/// of birth, gender and home location. Collecting it once here means donating
/// or requesting later never stops to ask for more (spec §8).
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _country = TextEditingController(text: 'India');
  final _state = TextEditingController();
  final _city = TextEditingController();
  BloodGroup? _group;
  DateTime? _dateOfBirth;
  Gender? _gender;
  bool _busy = false;
  bool _groupError = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _country.dispose();
    _state.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final validForm = _formKey.currentState!.validate();
    setState(() => _groupError = _group == null);
    if (!validForm || _group == null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .register(
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            bloodGroup: _group!,
            dateOfBirth: _dateOfBirth!,
            gender: _gender!,
            country: _country.text.trim(),
            state: _state.text.trim(),
            city: _city.text.trim(),
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t create your account. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'A few details so donors near you can help fast.',
                      style: context.text.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    const FieldLabel('Full name'),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: 'Your name'),
                      validator: (v) => (v ?? '').trim().length < 2
                          ? 'Enter your name'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const FieldLabel('Phone number'),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                      ],
                      decoration: const InputDecoration(
                        hintText: '98765 43210',
                      ),
                      validator: (v) {
                        final digits = (v ?? '').replaceAll(
                          RegExp(r'[^0-9]'),
                          '',
                        );
                        return digits.length < 10
                            ? 'Enter a valid phone number'
                            : null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const FieldLabel('Your blood group'),
                    BloodGroupPicker(
                      selected: _group,
                      onChanged: (g) => setState(() {
                        _group = g;
                        _groupError = false;
                      }),
                    ),
                    if (_groupError) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Select your blood group',
                        style: context.text.bodySmall?.copyWith(
                          color: c.danger,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    const FieldLabel('Date of birth'),
                    DateOfBirthField(onChanged: (d) => _dateOfBirth = d),
                    const SizedBox(height: AppSpacing.lg),
                    const FieldLabel('Gender'),
                    GenderField(onChanged: (g) => _gender = g),
                    const SizedBox(height: AppSpacing.lg),
                    HomeLocationFields(
                      country: _country,
                      state: _state,
                      city: _city,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    PrimaryButton(
                      label: 'Create account',
                      busy: _busy,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Your date of birth and gender are only used to check '
                      'donor eligibility. You control when you\'re available '
                      'as a donor.',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
