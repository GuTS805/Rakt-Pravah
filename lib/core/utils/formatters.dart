/// Small formatting helpers shared across screens.
abstract class Fmt {
  /// Compact relative time, e.g. "just now", "6 min ago", "3 h ago", "2 d ago".
  static String relative(DateTime time) {
    final d = DateTime.now().difference(time);
    if (d.inSeconds < 45) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays < 7) return '${d.inDays} d ago';
    final weeks = (d.inDays / 7).floor();
    if (weeks < 5) return '${weeks}w ago';
    final months = (d.inDays / 30).floor();
    return '${months}mo ago';
  }

  /// Time remaining until [time], e.g. "24 min left", or "Expired".
  static String remaining(DateTime? time) {
    if (time == null) return '';
    final d = time.difference(DateTime.now());
    if (d.isNegative) return 'Expired';
    if (d.inMinutes < 60) return '${d.inMinutes} min left';
    if (d.inHours < 24) return '${d.inHours} h left';
    return '${d.inDays} d left';
  }

  /// Clock time, e.g. "14:32".
  static String clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Short date, e.g. "12 Aug".
  static String shortDate(DateTime t) => '${t.day} ${_months[t.month - 1]}';

  /// Units label, e.g. "2 units" / "1 unit".
  static String units(int n) => n == 1 ? '1 unit' : '$n units';

  static final _coords = RegExp(r'^-?\d+(\.\d+)?,\s*-?\d+(\.\d+)?$');

  /// Picks a human place name to show the user, given a best-effort
  /// reverse-geocoded label and the city on their profile.
  ///
  /// Reverse geocoding falls back to raw coordinates when it's unavailable
  /// (Flutter Web, some emulators), and "12.9716, 77.5946" is not a place
  /// name — so a coordinate pair is rejected in favour of the profile city.
  /// Returns null when neither yields something real, so the caller can omit
  /// the label entirely rather than showing someone their own coordinates.
  /// Only the first segment of a label like "Dubai Marina, Dubai,
  /// United Arab Emirates" is kept, since the chip has room for a neighbourhood, not an
  /// address.
  static String? placeName(String? geocodedLabel, String? city) {
    final label = geocodedLabel?.trim();
    final usable =
        label != null && label.isNotEmpty && !_coords.hasMatch(label);
    final resolved = usable ? label.split(',').first.trim() : city?.trim();
    return (resolved == null || resolved.isEmpty) ? null : resolved;
  }
}
