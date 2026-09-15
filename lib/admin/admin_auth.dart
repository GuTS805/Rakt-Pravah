import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/email_link_store.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/buttons.dart';
import '../data/providers.dart';
import '../shared/brand_mark.dart';

/// Completes an emailed sign-in link when the console is opened with one.
/// The mobile app has its own watcher wired to its router; the console needs
/// the same behaviour without dragging the mobile routes in.
final adminEmailLinkWatcherProvider = Provider<void>((ref) {
  final appLinks = AppLinks();
  final store = EmailLinkStore();

  Future<void> handle(Uri uri) async {
    final link = uri.toString();
    final auth = ref.read(authControllerProvider.notifier);
    if (!auth.isEmailVerificationLink(link)) return;
    final email = await store.read();
    if (email == null) return;
    try {
      await auth.completeEmailVerification(email: email, link: link);
      await store.clear();
    } catch (_) {
      // Surfaced by the sign-in screen, which stays put on failure.
    }
  }

  final sub = appLinks.uriLinkStream.listen(handle);
  ref.onDispose(sub.cancel);
  appLinks.getInitialLink().then((uri) {
    if (uri != null) handle(uri);
  });
});

/// Sends an admin a sign-in link. Deliberately the same passwordless flow the
/// mobile app uses — one identity system, and no separate admin password to
/// leak.
class AdminSignInScreen extends ConsumerStatefulWidget {
  const AdminSignInScreen({super.key});

  @override
  ConsumerState<AdminSignInScreen> createState() => _AdminSignInScreenState();
}

class _AdminSignInScreenState extends ConsumerState<AdminSignInScreen> {
  final _email = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _store = EmailLinkStore();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      await ref
          .read(authControllerProvider.notifier)
          .sendEmailVerification(email);
      await _store.save(email);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not send the link. $e');
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
                        'BloodLink Operations',
                        style: context.text.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (_sent) ...[
                    Text('Check your inbox', style: context.text.headlineSmall),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'A sign-in link is on its way to ${_email.text.trim()}. '
                      'Open it in this browser to finish signing in.',
                      style: context.text.bodyMedium?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextButton(
                      onPressed: _busy ? null : _send,
                      child: const Text('Send again'),
                    ),
                  ] else ...[
                    Text('Sign in', style: context.text.headlineSmall),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Operator access only. You\'ll get a one-time sign-in '
                      'link by email.',
                      style: context.text.bodyMedium?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TextFormField(
                      controller: _email,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
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
                      onFieldSubmitted: (_) => _send(),
                    ),
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
                      label: 'Send sign-in link',
                      busy: _busy,
                      onPressed: _send,
                    ),
                  ],
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
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 34, color: c.textTertiary),
              const SizedBox(height: AppSpacing.lg),
              Text('No operator access', style: context.text.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${user?.name ?? 'This account'} is signed in, but does not '
                'have admin access. Someone with access has to grant it from '
                'the Users page.',
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SecondaryButton(
                label: 'Sign out',
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).logout(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
