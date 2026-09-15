import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/services/email_link_store.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/buttons.dart';
import '../../data/providers.dart';

/// Gate screen for spec's "only a verified user may request or donate" rule.
/// Reached whenever Create Request, Accept, or Donor Mode is tapped without
/// a verified email on file. Sending the link and tapping it (from this
/// device) are two separate moments, so this screen just watches the user's
/// live profile and reacts the instant `emailVerified` flips true — no
/// polling, no manual "I clicked it" button needed.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _email = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _store = EmailLinkStore();
  bool _busy = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(currentUserProvider)?.email;
    if (existing != null) _email.text = existing;
    // A retry after a failed verify should arrive pre-filled with whatever
    // address the link was actually requested for.
    _store.read().then((saved) {
      if (mounted && saved != null && _email.text.isEmpty) {
        setState(() => _email.text = saved);
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  /// Completes sign-in for a link that arrived without a stored email, using
  /// the address the user just confirmed.
  Future<void> _confirm(String link) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .completeEmailVerification(email: _email.text.trim(), link: link);
      await _store.clear();
      if (mounted) {
        ref.read(pendingEmailLinkProvider.notifier).state = null;
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Couldn\'t verify with that address. Check it '
              'matches the one you requested, or send a new link.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Abandons a link that can't be completed (expired, or the wrong address)
  /// and returns to the send form — always an escape hatch, never a dead end.
  void _startOver() {
    ref.read(pendingEmailLinkProvider.notifier).state = null;
    setState(() => _sent = false);
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final email = _email.text.trim();
      await ref
          .read(authControllerProvider.notifier)
          .sendEmailVerification(email);
      await _store.save(email);
      if (mounted) setState(() => _sent = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Couldn\'t send the link. Check the address and try again.',
            ),
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
    final verified = ref.watch(currentUserProvider)?.emailVerified ?? false;
    final pendingLink = ref.watch(pendingEmailLinkProvider);

    if (!verified && pendingLink != null) {
      return _confirmView(context, pendingLink);
    }

    if (verified) {
      return Scaffold(
        appBar: AppBar(title: const Text('Verify your email')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded, size: 56, color: c.success),
                const SizedBox(height: AppSpacing.lg),
                Text('Email verified', style: context.text.headlineSmall),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'You can now request blood and turn on Donor Mode.',
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: 'Continue',
                  // go, not pop: this screen is often reached by redirect
                  // (from a link or a blocked action) with nothing beneath
                  // it on the stack to pop back to.
                  onPressed: () => context.go(Routes.home),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.mark_email_unread_outlined,
                    size: 40,
                    color: c.brand,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Only verified people can request or donate blood on '
                    'BloodLink — it keeps the network real.',
                    style: context.text.bodyMedium?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  if (_sent) ...[
                    _SentNotice(email: _email.text.trim()),
                    const SizedBox(height: AppSpacing.lg),
                    TextButton(
                      onPressed: _busy ? null : _send,
                      child: const Text('Resend link'),
                    ),
                  ] else ...[
                    Text('Email address', style: context.text.titleSmall),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
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
                    const SizedBox(height: AppSpacing.xl),
                    PrimaryButton(
                      label: 'Send verification link',
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

  /// Shown when a verification link opened the app but nothing here knows
  /// which address it belongs to. Asking is the only honest recovery — the
  /// link alone doesn't carry a verifiable address.
  Widget _confirmView(BuildContext context, String link) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm your email')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.mark_email_read_outlined,
                    size: 40,
                    color: c.brand,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Type the email address you asked us to verify, so we can '
                    'match it to the link you just opened.',
                    style: context.text.bodyMedium?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Text('Email address', style: context.text.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
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
                    onFieldSubmitted: (_) => _confirm(link),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: 'Verify email',
                    busy: _busy,
                    onPressed: () => _confirm(link),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : _startOver,
                      child: const Text('Send a new link instead'),
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

class _SentNotice extends StatelessWidget {
  const _SentNotice({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.infoSubtle,
        borderRadius: AppRadius.cardLg,
        border: Border.all(color: c.info.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.mark_email_read_outlined, color: c.info, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Link sent to $email. Open it on this phone to finish '
              'verifying — this screen will update on its own.',
              style: context.text.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
