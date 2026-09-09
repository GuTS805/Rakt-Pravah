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
    if (email == null) return;

    try {
      await auth.completeEmailVerification(email: email, link: link);
      await store.clear();
      ref.read(routerProvider).go(Routes.home);
    } catch (_) {
      // Link expired, already used, or the network dropped mid-verify — the
      // Verify Email screen's own "resend" path is the recovery route, so
      // there's nothing more to do here than leave the pending email in
      // place for a retry.
    }
  }

  final sub = appLinks.uriLinkStream.listen(handle);
  ref.onDispose(sub.cancel);

  appLinks.getInitialLink().then((uri) {
    if (uri != null) handle(uri);
  });
});
