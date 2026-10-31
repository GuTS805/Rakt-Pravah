import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/buttons.dart';
import '../../data/backend.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/profile_fields.dart';

/// Confirms the account's phone number with a code sent by SMS. Until it is
/// confirmed the account can look around but not request blood or donate.
/// Also changes an already verified number, which takes a new code.
class VerifyPhoneScreen extends ConsumerStatefulWidget {
  const VerifyPhoneScreen({super.key});

  @override
  ConsumerState<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends ConsumerState<VerifyPhoneScreen> {
  static const _resendAfter = 30;

  final _numberForm = GlobalKey<FormState>();
  late final TextEditingController _phone;
  final _code = TextEditingController();
  late String _countryCode;

  /// The account already had a verified number when the screen opened.
  late final bool _changing;

  PhoneCodeSent? _sent;
  bool _busy = false;
  String? _error;
  int _resendIn = 0;
  Timer? _ticker;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _changing = user?.phoneVerified ?? false;
    _countryCode = user?.countryCode ?? '+91';
    _phone = TextEditingController(text: _changing ? '' : user?.phone ?? '');
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _number =>
      PhoneUtils.toInternational(_phone.text, countryCode: _countryCode);

  Future<void> _send({bool again = false}) async {
    if (!again && !_numberForm.currentState!.validate()) return;
    final number = again ? _sent!.phoneNumber : _number;
    final current = ref.read(currentUserProvider);
    if (_changing && current != null && number == current.fullPhoneNumber) {
      setState(() => _error = 'That is already your verified number.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sent = await ref
          .read(backendProvider)
          .sendPhoneCode(number, resend: again ? _sent : null);
      if (!mounted) return;
      if (sent == null) {
        // The phone read the SMS itself: nothing left to type.
        _done(ref.read(backendProvider).currentUser);
        return;
      }
      setState(() {
        _sent = sent;
        _code.clear();
      });
      _startResendTimer();
    } on PhoneVerificationFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Couldn\'t send the code. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from the SMS.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(backendProvider)
          .confirmPhoneCode(_sent!, code);
      if (mounted) _done(user);
    } on PhoneVerificationFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Couldn\'t verify the code. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done(UserProfile? user) {
    if (_finished) return;
    _finished = true;
    if (user != null) {
      ref.read(authControllerProvider.notifier).phoneVerified(user);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _changing ? 'Phone number changed.' : 'Phone number verified.',
        ),
      ),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  void _startResendTimer() {
    _ticker?.cancel();
    setState(() => _resendIn = _resendAfter);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _resendIn <= 1) t.cancel();
      if (mounted) setState(() => _resendIn--);
    });
  }

  void _editNumber() {
    _ticker?.cancel();
    setState(() {
      _sent = null;
      _error = null;
      _resendIn = 0;
      _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Android can confirm the number by itself while the code screen is up.
    ref.listen(canActProvider, (previous, next) {
      if (!_changing && next.valueOrNull == true && _sent != null && !_busy) {
        _done(ref.read(backendProvider).currentUser);
      }
    });

    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: Text(_changing ? 'Change phone number' : 'Verify phone number'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sms_outlined, size: 40, color: c.brand),
                  const SizedBox(height: AppSpacing.lg),
                  if (_sent == null) ..._numberStep(context) else ..._codeStep(context),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      _error!,
                      style: context.text.bodySmall?.copyWith(color: c.danger),
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

  List<Widget> _numberStep(BuildContext context) => [
    Text(
      _changing
          ? 'We\'ll text a code to your new number.'
          : 'We\'ll text you a 6-digit code to confirm this number is yours. '
                'Donors and patients rely on it to reach each other.',
      style: context.text.bodyMedium,
    ),
    const SizedBox(height: AppSpacing.xl),
    FieldLabel(_changing ? 'New phone number' : 'Phone number'),
    Form(
      key: _numberForm,
      child: PhoneNumberField(
        phoneController: _phone,
        initialCountryCode: _countryCode,
        textInputAction: TextInputAction.done,
        onCountryChanged: (c) => setState(() => _countryCode = c.dialCode),
      ),
    ),
    const SizedBox(height: AppSpacing.xxl),
    PrimaryButton(label: 'Send code', busy: _busy, onPressed: _send),
    const SizedBox(height: AppSpacing.md),
    Text(
      'Standard SMS rates from your carrier may apply.',
      style: context.text.bodySmall,
    ),
  ];

  List<Widget> _codeStep(BuildContext context) => [
    Text(
      'Enter the 6-digit code sent to '
      '${PhoneUtils.formatDisplay(null, _sent!.phoneNumber)}.',
      style: context.text.bodyMedium,
    ),
    const SizedBox(height: AppSpacing.xl),
    const FieldLabel('Code'),
    TextField(
      controller: _code,
      autofocus: true,
      keyboardType: TextInputType.number,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _busy ? null : _confirm(),
      style: context.text.headlineSmall?.copyWith(letterSpacing: 8),
      decoration: const InputDecoration(hintText: '••••••'),
    ),
    const SizedBox(height: AppSpacing.xxl),
    PrimaryButton(label: 'Verify', busy: _busy, onPressed: _confirm),
    const SizedBox(height: AppSpacing.md),
    // Wraps on narrow phones and with large text instead of overflowing.
    Wrap(
      alignment: WrapAlignment.spaceBetween,
      children: [
        TextButton(
          onPressed: _busy ? null : _editNumber,
          child: const Text('Change number'),
        ),
        TextButton(
          onPressed: _busy || _resendIn > 0 ? null : () => _send(again: true),
          child: Text(
            _resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code',
          ),
        ),
      ],
    ),
  ];
}
