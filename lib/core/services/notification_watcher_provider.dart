import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../router/app_router.dart';
import '../router/routes.dart';
import 'notification_service.dart';

/// Keeps this device registered for push notifications while someone is
/// signed in, and opens the right screen when a notification is tapped.
/// Kept alive for the app's lifetime by being watched once from
/// [RaktPravahApp].
///
/// The alerts themselves (a new request, a donor accepting or dropping out, a
/// cancelled request, a chat message) all come from the server, so they also
/// reach a phone whose app is closed. This used to show its own copies while
/// the app was running, which doubled every alert.
final notificationWatcherProvider = Provider<void>((ref) {
  // Only who is signed in matters here. Watching the whole profile rebuilt
  // this on every profile snapshot, and registering the token writes to the
  // profile, so each registration triggered the next one in an endless loop
  // that exhausted the phone's threads and crashed the app.
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return;

  final backend = ref.read(backendProvider);
  final service = NotificationService.instance;

  // Every signed-in device gets a token, Donor Mode or not: a requester needs
  // to hear that a donor accepted or wrote to them. The server only sends new
  // requests to people whose Donor Mode is on.
  service.syncDeviceToken(backend, enabled: true);

  service.onTap = (payload) {
    final router = ref.read(routerProvider);
    final id = payload.substring(payload.indexOf(':') + 1);
    if (payload.startsWith('invitation:')) {
      router.push(Routes.invitationDetail(id));
    } else if (payload.startsWith('request:')) {
      router.push(Routes.requestDetail(id));
    } else if (payload.startsWith('chat:')) {
      router.push(Routes.chat(id));
    }
  };

  ref.onDispose(() {
    service.onTap = null;
  });
});
