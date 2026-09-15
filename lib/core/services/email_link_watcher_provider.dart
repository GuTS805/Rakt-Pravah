import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../router/app_router.dart';
import '../router/routes.dart';
import 'email_link_store.dart';

/// Catches the email verification link when Android hands it to the app via
/// App Links (see AndroidManifest.xml's second intent-filter and
/// hosting_public/.well-known/assetlinks.json) and completes sign-in with
/// it. Handles both a cold start (app opened by tapping the link) and the
/// app already running in the background.
final emailLinkWatcherProvider = Provider<void>((ref) {
  final appLinks = AppLinks();
  final store = EmailLinkStore();

  Future<void> handle(Uri uri) async {
    final link = uri.toString();
    final auth = ref.read(authControllerProvider.notifier);
    if (!auth.isEmailVerificationLink(link)) return;

    final email = await store.read();

    // Opened on a device that never requested it, or after app data was
    // cleared: hand the link to the Verify Email screen so the user can
    // confirm which address it was sent to. Failing silently here would leave
    // them staring at an unchanged screen with no idea why.
    if (email == null) {
      ref.read(pendingEmailLinkProvider.notifier).state = link;
      ref.read(routerProvider).go(Routes.verifyEmail);
      return;
    }

    try {
      await auth.completeEmailVerification(email: email, link: link);
      await store.clear();
      ref.read(pendingEmailLinkProvider.notifier).state = null;
      ref.read(routerProvider).go(Routes.home);
    } catch (_) {
      // Expired, already used, or the network dropped mid-verify. Send the
      // user somewhere that can explain it and offer a fresh link, rather
      // than swallowing the failure. The stored email is deliberately kept so
      // the retry arrives pre-filled.
      ref.read(pendingEmailLinkProvider.notifier).state = link;
      ref.read(routerProvider).go(Routes.verifyEmail);
    }
  }

  final sub = appLinks.uriLinkStream.listen(handle);
  ref.onDispose(sub.cancel);

  appLinks.getInitialLink().then((uri) {
    if (uri != null) handle(uri);
  });
});
