import 'package:shared_preferences/shared_preferences.dart';

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
