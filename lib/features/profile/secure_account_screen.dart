import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/buttons.dart';
import '../../data/backend.dart';
import '../../data/providers.dart';
import '../../shared/profile_fields.dart';

/// Gives an account made before the app asked for an email a way back in.
/// Those accounts live only on the device they were created on: clear the
/// app's data and everything they've done is unreachable. Attaching an email
/// and password keeps the same account, with its requests and donations.
class SecureAccountScreen extends ConsumerStatefulWidget {
  const SecureAccountScreen({super.key});

  @override
  ConsumerState<SecureAccountScreen> createState() =>
      _SecureAccountScreenState();
}

class _SecureAccountScreenState extends ConsumerState<SecureAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .addPasswordSignIn(
            email: _email.text.trim(),
            password: _password.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Done. You can sign in with this email anywhere.'),
          ),
        );
        context.pop();
      }
    } on SignInFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Couldn\'t save that. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Secure your account')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              'This account exists only on this phone. Add an email and a '
              'password and it becomes yours to sign into anywhere — with '
              'every request and donation it already has.',
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            const FieldLabel('Email'),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(hintText: 'you@example.com'),
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
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
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
              validator: (v) =>
                  (v ?? '').length < 6 ? 'Use at least 6 characters' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                _error!,
                style: context.text.bodySmall?.copyWith(color: c.danger),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            PrimaryButton(label: 'Save', busy: _busy, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
