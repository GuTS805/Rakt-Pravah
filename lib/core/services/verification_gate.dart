import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../router/routes.dart';

/// Spec: only a verified user may request or donate. Call this at the point
/// of action — Create Request, Accept, turning Donor Mode on — rather than
/// hiding the buttons, since verification is a one-time step most people
/// only ever see once. Returns true (and does nothing) once already
/// verified; otherwise routes to the Verify Email screen and returns false
/// so the caller can skip the action. Real enforcement lives in Firestore
/// rules — this is only about a clear message instead of a silent failure.
bool requireVerifiedEmail(BuildContext context, WidgetRef ref) {
  final verified = ref.read(currentUserProvider)?.emailVerified ?? false;
  if (!verified) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Verify your email first — it only takes a minute.'),
      ),
    );
    context.push(Routes.verifyEmail);
  }
  return verified;
}
