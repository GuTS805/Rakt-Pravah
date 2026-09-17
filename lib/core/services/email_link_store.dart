import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the email address the admin console sent a sign-in link to, so
/// sign-in can complete when the link is opened later, even after a reload.
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
