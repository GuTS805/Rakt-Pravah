import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

/// True when this account may ask for blood or donate. Otherwise explains that
/// it is waiting for an operator and returns false so the caller skips the
/// action. The security rules refuse the same actions server-side; this is
/// the friendly half.
bool requireApproval(BuildContext context, WidgetRef ref) {
  if (ref.read(canActValueProvider)) return true;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Your account is waiting for approval. You can request blood or '
        'donate as soon as it is approved.',
      ),
    ),
  );
  return false;
}
