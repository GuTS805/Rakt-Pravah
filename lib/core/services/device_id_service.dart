import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// Provides a stable, persistent device ID unique to this physical installation.
class DeviceIdService {
  DeviceIdService._();
  static final instance = DeviceIdService._();

  static const _prefKey = 'rakt_pravah_device_id';
  String? _cachedId;

  /// Returns the persistent unique device ID, generating one if not yet present.
  Future<String> getDeviceId() async {
    if (_cachedId != null) return _cachedId!;
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_prefKey);
      if (id == null || id.isEmpty) {
        id = _generateUniqueId();
        await prefs.setString(_prefKey, id);
      }
      _cachedId = id;
      return id;
    } catch (_) {
      // Fallback if shared_preferences fails
      _cachedId ??= _generateUniqueId();
      return _cachedId!;
    }
  }

  String _generateUniqueId() {
    final rand = Random.secure();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final randomHex = List.generate(
      16,
      (_) => rand.nextInt(16).toRadixString(16),
    ).join();
    return 'dev_${timestamp}_$randomHex';
  }
}
