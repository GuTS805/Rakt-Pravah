import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/buttons.dart';
import '../../data/backend.dart';
import '../../data/providers.dart';
import '../../shared/brand_mark.dart';
import '../../shared/profile_fields.dart';

/// Forgotten password, all inside the app: a 6-digit code goes to the email,
/// and the code and the new password are typed in here. Closes with the
/// email, so the sign-in screen can fill it in.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.email = ''});

  final String email;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;
  bool _codeSent = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  static bool _looksLikeEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

  /// Runs [action] with the buttons held, showing what went wrong. Returns
  /// whether it worked.
  Future<bool> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      return true;
    } on PasswordResetFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              "Couldn't reach the server. Check your connection and try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return false;
  }

  Future<void> _sendCode({bool again = false}) async {
    if (!again) {
      setState(() => _autovalidate = AutovalidateMode.always);
      if (!_formKey.currentState!.validate()) return;
    }
    final email = _email.text.trim();
    final sent = await _run(
      () => ref
          .read(authControllerProvider.notifier)
          .sendPasswordResetCode(email),
    );
    if (!sent || !mounted) return;
    setState(() {
      _codeSent = true;
      _autovalidate = AutovalidateMode.disabled;
    });
    if (again) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code is on its way.')),
      );
    }
  }

  Future<void> _setPassword() async {
    setState(() => _autovalidate = AutovalidateMode.always);
    if (!_formKey.currentState!.validate()) return;
    final email = _email.text.trim();
    final done = await _run(
      () => ref
          .read(authControllerProvider.notifier)
          .resetPasswordWithCode(
            email: email,
            code: _code.text.trim(),
            newPassword: _password.text,
          ),
    );
    if (!done || !mounted) return;
    if (context.canPop()) {
      context.pop(email);
    } else {
      context.go(Routes.login);
    }
  }

  void _changeEmail() => setState(() {
    _codeSent = false;
    _code.clear();
    _password.clear();
    _error = null;
    _autovalidate = AutovalidateMode.disabled;
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                autovalidateMode: _autovalidate,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(child: BrandMark(size: 72)),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      _codeSent
                          ? 'If ${_email.text.trim()} has an account, we have '
                                'emailed it a 6-digit code. It works for 10 '
                                'minutes. Check the spam folder too.'
                          : "Enter your account's email. We'll send a "
                                '6-digit code to it.',
                      style: context.text.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    if (!_codeSent) ...[
                      const FieldLabel('Email'),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          hintText: 'you@example.com',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (v) => _looksLikeEmail((v ?? '').trim())
                            ? null
                            : 'Please enter a valid email address.',
                        onFieldSubmitted: (_) => _busy ? null : _sendCode(),
                      ),
                    ] else ...[
                      const FieldLabel('Code from the email'),
                      TextFormField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: const InputDecoration(
                          hintText: '6-digit code',
                          prefixIcon: Icon(Icons.pin_outlined),
                        ),
                        validator: (v) => (v ?? '').trim().length == 6
                            ? null
                            : 'Enter the 6-digit code from the email.',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const FieldLabel('New password'),
                      TextFormField(
                        controller: _password,
                        obscureText: !_showPassword,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          hintText: 'At least 6 characters',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: ExcludeFocus(
                            child: IconButton(
                              tooltip: _showPassword
                                  ? 'Hide password'
                                  : 'Show password',
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                              ),
                              onPressed: () => setState(
                                () => _showPassword = !_showPassword,
                              ),
                            ),
                          ),
                        ),
                        validator: (v) => (v ?? '').length < 6
                            ? 'Use at least 6 characters'
                            : null,
                        onFieldSubmitted: (_) => _busy ? null : _setPassword(),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _error!,
                        style: context.text.bodySmall?.copyWith(
                          color: c.danger,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    PrimaryButton(
                      label: _codeSent ? 'Set new password' : 'Send code',
                      busy: _busy,
                      onPressed: _codeSent ? _setPassword : _sendCode,
                    ),
                    if (_codeSent) ...[
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.md,
                        children: [
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _sendCode(again: true),
                            child: const Text('Send a new code'),
                          ),
                          TextButton(
                            onPressed: _busy ? null : _changeEmail,
                            child: const Text('Use a different email'),
                          ),
                        ],
                      ),
                    ],
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
