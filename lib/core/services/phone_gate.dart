import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../router/routes.dart';

/// True when this account may ask for blood or donate: its phone number is
/// verified and the account is switched on. Otherwise opens the verification
/// screen (or says the account is off) and returns false so the caller skips
/// the action. The security rules refuse the same actions
/// server-side; this is the friendly half.
bool requireVerifiedPhone(BuildContext context, WidgetRef ref) {
  if (ref.read(canActValueProvider)) return true;
  if (ref.read(currentUserProvider)?.phoneVerified ?? false) {
    // Verified, so the console has switched this account off.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This account has been switched off. Contact the Rakt Pravah team.',
        ),
      ),
    );
  } else {
    context.push(Routes.verifyPhone);
  }
  return false;
}
