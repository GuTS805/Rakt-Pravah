import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../router/routes.dart';
import 'approval_gate.dart';

/// Checks the things a donor action needs before it happens: turning Donor
/// Mode on, or accepting a request. Returns true when the user can go ahead;
/// otherwise explains why not and returns false so the caller skips the
/// action.
///
/// Requesting blood never checks age or profile state: anyone may ask for
/// help. Approval, when the operators have switched it on, applies to both.
bool requireDonorProfile(BuildContext context, WidgetRef ref) {
  final user = ref.read(currentUserProvider);
  if (user == null) return false;
  if (!requireApproval(context, ref)) return false;
  final messenger = ScaffoldMessenger.of(context);
  final age = user.ageOn();

  // Accounts created before registration asked for these don't have them.
  if (age == null || user.gender == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Add your date of birth and gender before donating.'),
      ),
    );
    context.push(Routes.profileEdit);
    return false;
  }

  if (!DonorEligibility.ageAllowed(age)) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Blood donors must be ${DonorEligibility.minAge} to '
          '${DonorEligibility.maxAge} years old. You can still request blood.',
        ),
      ),
    );
    return false;
  }
  return true;
}
