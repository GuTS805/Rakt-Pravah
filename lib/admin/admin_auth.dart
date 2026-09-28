import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/router/routes.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/buttons.dart';
import '../data/backend.dart';
import '../data/providers.dart';
import '../shared/brand_mark.dart';

/// Sign-in for the operations console. Operator accounts are created in the
/// Firebase console and granted access from the Users page — there is no
/// sign-up here, because anyone who could sign themselves up wouldn't be an
/// operator.
class AdminSignInScreen extends ConsumerStatefulWidget {
  const AdminSignInScreen({super.key});

  @override
  ConsumerState<AdminSignInScreen> createState() => _AdminSignInScreenState();
}

class _AdminSignInScreenState extends ConsumerState<AdminSignInScreen> {
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

  Future<void> _signIn() async {
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
      final user = ref.read(currentUserProvider);
      if (user != null && !user.isAdmin) {
        await ref.read(authControllerProvider.notifier).logout();
        if (mounted) {
          setState(() {
            _error = 'Access Denied: This account does not have administrator privileges.';
          });
        }
        return;
      }
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(AppSpacing.xxl),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: AppRadius.cardLg,
              border: Border.all(color: c.border),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const BrandMark(size: 30),
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        'Rakt Pravah Operations',
                        style: context.text.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Sign in', style: context.text.headlineSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Operator access only.',
                    style: context.text.bodyMedium?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  TextFormField(
                    controller: _email,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: 'Work email',
                      hintText: 'you@example.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(value)) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _password,
                    obscureText: !_showPassword,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      // No tooltip here on purpose: this screen is built by
                      // MaterialApp's builder, above the Navigator, so there
                      // is no Overlay for a tooltip to live in and one would
                      // crash the page. The icon carries the label instead.
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          semanticLabel: _showPassword
                              ? 'Hide password'
                              : 'Show password',
                        ),
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                    validator: (v) =>
                        (v ?? '').isEmpty ? 'Enter your password' : null,
                    onFieldSubmitted: (_) => _signIn(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _error!,
                      style: context.text.bodySmall?.copyWith(color: c.danger),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: 'Sign in to Console',
                    busy: _busy,
                    onPressed: _signIn,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.arrow_back_rounded, size: 16),
                      label: const Text('Back to User Login'),
                      onPressed: () => context.go(Routes.login),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Signed in, but not an operator. Says so plainly instead of showing an
/// empty console that looks broken.
class AdminNoAccessScreen extends ConsumerWidget {
  const AdminNoAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: AppRadius.cardLg,
                border: Border.all(color: c.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: c.dangerSubtle,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.lock_person_rounded, size: 36, color: c.danger),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Access Restricted', style: context.text.headlineSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${user?.name ?? 'This account'} is signed in as a standard user. '
                    'Administrator privileges are required to view the Operations Console.',
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: 'Go to User Dashboard',
                    onPressed: () => context.go(Routes.home),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SecondaryButton(
                    label: 'Sign out',
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).logout(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
