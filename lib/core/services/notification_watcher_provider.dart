import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../router/app_router.dart';
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
  var isFirstInvitationEmission = true;

  ref.listen<AsyncValue<List<Invitation>>>(invitationsProvider, (_, next) {
    final list = next.valueOrNull;
    if (list == null) return;

    if (isFirstInvitationEmission) {
      isFirstInvitationEmission = false;
      seenInvitationIds.addAll(list.map((i) => i.id));
      return;
    }

    for (final inv in list) {
      final isNew = seenInvitationIds.add(inv.id);
      if (isNew && inv.status == InvitationStatus.pending) {
        final groups = inv.bloodGroups.map((g) => g.label).join('/');
        service.show(
          id: inv.id.hashCode,
          title: 'Nearby request needs $groups',
          body:
              '${inv.units} unit${inv.units == 1 ? '' : 's'} at ${inv.destinationName}, ${inv.destinationArea} · ${inv.distanceKm.toStringAsFixed(1)} km away',
          payload: 'invitation:${inv.id}',
        );
      }
    }
  });

  final lastKnownStatus = <String, RequestStatus>{};
  var isFirstRequestEmission = true;

  ref.listen<AsyncValue<List<BloodRequest>>>(myRequestsProvider, (_, next) {
    final list = next.valueOrNull;
    if (list == null) return;

    if (isFirstRequestEmission) {
      isFirstRequestEmission = false;
      for (final r in list) {
        lastKnownStatus[r.id] = r.status;
      }
      return;
    }

    for (final r in list) {
      final previous = lastKnownStatus[r.id];
      lastKnownStatus[r.id] = r.status;
      final justAccepted = previous != null &&
          previous != r.status &&
          r.status == RequestStatus.donorAccepted;
      if (justAccepted) {
        service.show(
          id: r.id.hashCode,
          title: 'A donor accepted your request',
          body: '${r.acceptedDonorName ?? 'A donor'} is coordinating with '
              'you now for ${r.destination.name}.',
          payload: 'request:${r.id}',
        );
      }
    }
  });
});
