import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/buttons.dart';
import '../../data/backend.dart';
import '../../data/providers.dart';
import '../../shared/profile_fields.dart';

/// Deletes the account for good, from inside the app, as Google Play and the
/// App Store require. Says plainly what goes and what stays before asking
/// for the password.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete({required bool needsPassword}) async {
    if (needsPassword && _password.text.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    final c = context.colors;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text('This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .deleteAccount(password: needsPassword ? _password.text : null);
      // Signed out now, so the router has already left this screen.
      messenger.showSnackBar(
        const SnackBar(content: Text('Your account has been deleted.')),
      );
    } on AccountDeletionFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Couldn\'t delete your account. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final needsPassword = !ref
        .read(authControllerProvider.notifier)
        .isDeviceOnlyAccount;

    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            'Deleting your account is permanent.',
            style: context.text.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          const _Point(
            'Your profile, phone number and donation history are deleted.',
          ),
          const _Point(
            'Your open blood requests are cancelled, and your name, photo '
            'and number are removed from all your requests.',
          ),
          const _Point(
            'Requests you accepted as a donor and haven\'t finished go back '
            'to searching for another donor.',
          ),
          const _Point(
            'Chat messages you sent stay with the person you sent them to, '
            'and donors who already donated to your requests keep that record.',
          ),
          const _Point(
            'You can make a new account later with the same email or number.',
          ),
          const SizedBox(height: AppSpacing.xl),
          if (needsPassword) ...[
            const FieldLabel('Password'),
            TextField(
              controller: _password,
              obscureText: !_showPassword,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                hintText: 'Your current password',
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
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              _error!,
              style: context.text.bodySmall?.copyWith(color: c.danger),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
          PrimaryButton(
            label: 'Delete my account',
            danger: true,
            busy: _busy,
            onPressed: () => _delete(needsPassword: needsPassword),
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: AppSpacing.sm),
            child: Icon(
              Icons.circle,
              size: 6,
              color: context.colors.textSecondary,
            ),
          ),
          Expanded(child: Text(text, style: context.text.bodyMedium)),
        ],
      ),
    );
  }
}
