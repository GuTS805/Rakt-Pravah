import 'package:flutter/material.dart';

import '../../data/backend_error.dart';

/// Tells the person that an action on a request didn't go through, with the
/// backend's own reason when it has one (no connection, quota used up,
/// refused) and [fallback] otherwise.
void showActionError(BuildContext context, Object error, String fallback) {
  if (!context.mounted) return;
  final message = error is BackendUnavailable ? error.message : fallback;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
}
