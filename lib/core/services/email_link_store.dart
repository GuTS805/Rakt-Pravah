import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A verification link that arrived without a matching pending email — the
/// link was opened on a device that never requested it, or after app data was
/// cleared. The app can't know which address Firebase issued it for, so the
/// user has to confirm that themselves before sign-in can complete. Held here
/// (rather than in the watcher) so the Verify Email screen can read it without
/// importing the router and creating a cycle.
final pendingEmailLinkProvider = StateProvider<String?>((ref) => null);

/// Remembers the email address a verification link was sent to, so the app
/// can complete sign-in when the link is opened later — possibly after a
/// cold start, when nothing else in memory still knows what email this was.
class EmailLinkStore {
  static const _key = 'bloodlink_pending_verification_email';

  Future<void> save(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, email);
  }

  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
