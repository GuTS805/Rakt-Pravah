import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/blood_group_picker.dart';
import '../../core/widgets/buttons.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';

/// Registration collects only what the product needs: name, phone, blood group,
/// and (optional) city. No unnecessary personal data (spec §8).
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  BloodGroup? _group;
  bool _busy = false;
  bool _groupError = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
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
            city: _city.text.trim().isEmpty ? null : _city.text.trim(),
          );
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
                    _Label('Full name'),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: 'Your name'),
                      validator: (v) => (v ?? '').trim().length < 2
                          ? 'Enter your name'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _Label('Phone number'),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                      ],
                      decoration: const InputDecoration(
                        hintText: '+971 50 123 4567',
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
                    _Label('Your blood group'),
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
                    _Label('City (optional)'),
                    TextFormField(
                      controller: _city,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: 'e.g. Dubai'),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    PrimaryButton(
                      label: 'Create account',
                      busy: _busy,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'By continuing you agree to help coordinate responsibly. '
                      'You control when you\'re available as a donor.',
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

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(text, style: context.text.titleSmall),
  );
}
