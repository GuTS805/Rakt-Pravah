import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../router/app_router.dart';
import '../utils/formatters.dart';
import '../router/routes.dart';
import 'notification_service.dart';

/// Watches the same live streams the UI does and fires a local notification
/// the moment something new shows up — a compatible request appearing for a
/// donor, or a donor accepting the user's own request. Kept alive for the
/// app's lifetime by being watched once from [BloodLinkApp], so it keeps
/// working even while the user is looking at an unrelated tab.
final notificationWatcherProvider = Provider<void>((ref) {
  // The underlying Firestore streams require a signed-in uid; bail out
  // (and re-run once signed in, since watching currentUserProvider makes
  // this whole provider rebuild on auth changes) rather than crash pre-login.
  final user = ref.watch(currentUserProvider);
  if (user == null) return;

  final service = NotificationService.instance;
  service.onTap = (payload) {
    final router = ref.read(routerProvider);
    final id = payload.substring(payload.indexOf(':') + 1);
    if (payload.startsWith('invitation:')) {
      router.push(Routes.invitationDetail(id));
    } else if (payload.startsWith('request:')) {
      router.push(Routes.requestDetail(id));
    }
  };

  final seenInvitationIds = <String>{};
  // Requests this donor accepted, and whether each was still active last time.
  final acceptedActive = <String, bool>{};
  var isFirstInvitationEmission = true;

  ref.listen<AsyncValue<List<Invitation>>>(invitationsProvider, (_, next) {
    final list = next.valueOrNull;
    if (list == null) return;

    if (isFirstInvitationEmission) {
      isFirstInvitationEmission = false;
      seenInvitationIds.addAll(list.map((i) => i.id));
      for (final inv in list) {
        if (inv.status == InvitationStatus.accepted) {
          acceptedActive[inv.id] = inv.requestStatus.isActive;
        }
      }
      return;
    }

    for (final inv in list) {
      if (inv.status != InvitationStatus.accepted) continue;
      final wasActive = acceptedActive[inv.id];
      acceptedActive[inv.id] = inv.requestStatus.isActive;
      if (wasActive == true && inv.requestStatus == RequestStatus.cancelled) {
        service.show(
          id: inv.id.hashCode,
          title: 'Request cancelled',
          body:
              'The request at ${inv.destinationName} was cancelled. No need '
              'to go.',
          payload: 'request:${inv.id}',
        );
      }
    }

    final donor = ref.read(donorProfileValueProvider);
    for (final inv in list) {
      final isNew = seenInvitationIds.add(inv.id);
      if (isNew && inv.status == InvitationStatus.pending) {
        if (!_shouldNotify(donor, inv)) continue;
        final needs =
            inv.patientBloodGroup?.label ??
            inv.bloodGroups.map((g) => g.label).join('/');
        final distance = inv.distanceKm == null
            ? ''
            : ' · ${inv.distanceKm!.toStringAsFixed(1)} km away';
        service.show(
          id: inv.id.hashCode,
          title: '${inv.urgency.label} request: patient needs $needs',
          body:
              '${inv.units} unit${inv.units == 1 ? '' : 's'} at ${inv.destinationName}, ${inv.destinationArea}$distance',
          payload: 'invitation:${inv.id}',
        );
      }
    }
  });

  // Tracks how many donors have committed rather than the status: a request
  // for several units stays in `searching` while donors are joining, so
  // waiting for a status change never fired.
  final lastKnownDonorCount = <String, int>{};
  var isFirstRequestEmission = true;

  ref.listen<AsyncValue<List<BloodRequest>>>(myRequestsProvider, (_, next) {
    final list = next.valueOrNull;
    if (list == null) return;

    if (isFirstRequestEmission) {
      isFirstRequestEmission = false;
      for (final r in list) {
        lastKnownDonorCount[r.id] = r.unitsPledged;
      }
      return;
    }

    for (final r in list) {
      final previous = lastKnownDonorCount[r.id];
      lastKnownDonorCount[r.id] = r.unitsPledged;
      if (previous == null) continue;

      if (r.unitsPledged > previous) {
        final newest = r.acceptedDonors.last.name;
        service.show(
          id: r.id.hashCode,
          title: r.isFullyMatched
              ? 'Every unit has a donor'
              : 'A donor accepted your request',
          body: r.isFullyMatched
              ? '$newest completes the ${Fmt.units(r.units)} you asked for '
                    'at ${r.destination.name}.'
              : '$newest is coming to ${r.destination.name}. '
                    '${r.unitsRemaining} still needed.',
          payload: 'request:${r.id}',
        );
      } else if (r.unitsPledged < previous && r.status.isActive) {
        service.show(
          id: r.id.hashCode,
          title: 'A donor can\'t make it',
          body: 'We\'re looking for another donor for ${r.destination.name}.',
          payload: 'request:${r.id}',
        );
      }
    }
  });
});

/// Whether a newly seen request should buzz the donor's phone, following
/// their own Donor settings. It still shows in the Donate tab either way.
bool _shouldNotify(DonorProfile donor, Invitation inv) {
  if (donor.availability != DonorAvailability.available) return false;
  if (!donor.notifyPush) return false;
  if (donor.notifyCritical && inv.urgency != Urgency.critical) return false;
  final km = inv.distanceKm;
  if (km != null && km > donor.maxDistanceKm) return false;
  // Switching Donor Mode on reloads every open request at once; only the
  // recent ones are worth an alert.
  final age = DateTime.now().difference(inv.createdAt);
  return age < const Duration(minutes: 30);
}
