import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/blood_group_picker.dart';
import '../../core/widgets/buttons.dart';
import '../../data/backend.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';
import '../../shared/brand_mark.dart';
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
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _countryCode = '+91';
  final _country = TextEditingController(text: 'India');
  final _countryIsoCode = TextEditingController(text: 'IN');
  final _state = TextEditingController();
  final _stateCode = TextEditingController();
  final _city = TextEditingController();
  final _latitude = ValueNotifier<double?>(null);
  final _longitude = ValueNotifier<double?>(null);
  BloodGroup? _group;
  DateTime? _dateOfBirth;
  Gender? _gender;
  bool _busy = false;
  bool _showPassword = false;
  bool _groupError = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _phone.dispose();
    _country.dispose();
    _countryIsoCode.dispose();
    _state.dispose();
    _stateCode.dispose();
    _city.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final validForm = _formKey.currentState!.validate();
    setState(() => _groupError = _group == null);
    if (!validForm || _group == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .register(
            email: _email.text.trim(),
            password: _password.text,
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            countryCode: _countryCode,
            countryIsoCode: _countryIsoCode.text.trim().isNotEmpty
                ? _countryIsoCode.text.trim()
                : null,
            bloodGroup: _group!,
            dateOfBirth: _dateOfBirth!,
            gender: _gender!,
            country: _country.text.trim(),
            state: _state.text.trim(),
            stateCode: _stateCode.text.trim().isNotEmpty
                ? _stateCode.text.trim()
                : null,
            city: _city.text.trim(),
            latitude: _latitude.value,
            longitude: _longitude.value,
          );
    } on SignInFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Couldn\'t create your account. Try again.');
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
                    const Center(child: BrandMark(size: 72)),
                    const SizedBox(height: AppSpacing.xl),
                    Center(
                      child: Text(
                        'A few details so donors near you can help fast.',
                        textAlign: TextAlign.center,
                        style: context.text.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    const FieldLabel('Email'),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        hintText: 'you@example.com',
                      ),
                      validator: (v) =>
                          RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch((v ?? '').trim())
                          ? null
                          : 'Enter a valid email address',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const FieldLabel('Password'),
                    TextFormField(
                      controller: _password,
                      obscureText: !_showPassword,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        hintText: 'At least 6 characters',
                        suffixIcon: IconButton(
                          tooltip: _showPassword
                              ? 'Hide password'
                              : 'Show password',
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      validator: (v) => (v ?? '').length < 6
                          ? 'Use at least 6 characters'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
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
                    PhoneNumberField(
                      phoneController: _phone,
                      initialCountryCode: _countryCode,
                      onCountryChanged: (c) =>
                          setState(() => _countryCode = c.dialCode),
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
                      countryCode: _countryIsoCode,
                      state: _state,
                      stateCode: _stateCode,
                      city: _city,
                      latitude: _latitude,
                      longitude: _longitude,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        _error!,
                        style: context.text.bodySmall?.copyWith(
                          color: c.danger,
                        ),
                      ),
                    ],
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
