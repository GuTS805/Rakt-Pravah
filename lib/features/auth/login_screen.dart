import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/buttons.dart';
import '../../data/backend.dart';
import '../../data/providers.dart';
import '../../shared/brand_mark.dart';

/// Sign-in with an email and a password. This used to accept a phone number
/// alone, which meant anyone who knew someone's number could walk into their
/// account.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signInWithPassword(
            email: _email.text.trim(),
            password: _password.text,
          );
    } on SignInFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Couldn\'t sign in. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sends a reset link without saying whether that address has an account —
  /// the same message either way, so this can't be used to find out who is
  /// registered.
  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!_looksLikeEmail(email)) {
      setState(() => _error = 'Enter your email address first.');
      return;
    }
    await ref.read(authControllerProvider.notifier).sendPasswordReset(email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'If $email has an account, a reset link is on its way to it.',
        ),
      ),
    );
  }

  static bool _looksLikeEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandMark(size: 48),
                    const SizedBox(height: AppSpacing.xl),
                    Text('Welcome back', style: context.text.headlineMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Sign in to your account',
                      style: context.text.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.xxxl),
                    Text('Email', style: context.text.titleSmall),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        hintText: 'you@example.com',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) => _looksLikeEmail((v ?? '').trim())
                          ? null
                          : 'Enter a valid email address',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Password', style: context.text.titleSmall),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _password,
                      obscureText: !_showPassword,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        hintText: 'Your password',
                        prefixIcon: const Icon(Icons.lock_outline),
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
                      validator: (v) =>
                          (v ?? '').isEmpty ? 'Enter your password' : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _resetPassword,
                        child: Text(
                          'Forgot password?',
                          style: context.text.labelLarge?.copyWith(
                            color: c.brand,
                          ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _error!,
                        style: context.text.bodySmall?.copyWith(
                          color: c.danger,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      label: 'Sign in',
                      busy: _busy,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Center(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('New here? ', style: context.text.bodyMedium),
                          GestureDetector(
                            onTap: () => context.push(Routes.register),
                            child: Text(
                              'Create an account',
                              style: context.text.labelLarge?.copyWith(
                                color: c.brand,
                              ),
                            ),
                          ),
                        ],
                      ),
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
