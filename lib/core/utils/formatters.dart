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

  /// A short, readable id for an account, e.g. "RP-RDTENC". The real id is a
  /// 28-character Firebase uid nobody can read out over the phone; this is
  /// its first six characters, enough to tell two people apart on a card.
  static String userId(String uid) {
    final head = uid.length < 6 ? uid : uid.substring(0, 6);
    return 'RP-${head.toUpperCase()}';
  }

  /// One or two letters standing in for a person's photo.
  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
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

  static const _fullMonths = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// Short date, e.g. "12 Aug".
  static String shortDate(DateTime t) => '${t.day} ${_months[t.month - 1]}';

  static String date(DateTime t) =>
      '${t.day} ${_months[t.month - 1]} ${t.year}';

  /// Full date, e.g. "22 September 2026".
  static String fullDate(DateTime t) =>
      '${t.day} ${_fullMonths[t.month - 1]} ${t.year}';

  /// Formats user's local date and time:
  /// e.g. "Tuesday, 22 Sep 2026 • 07:35:10 PM"
  static String localDateTime(DateTime t) {
    final weekday = _weekdays[t.weekday - 1];
    final month = _months[t.month - 1];
    final hour12 = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final minute = t.minute.toString().padLeft(2, '0');
    final second = t.second.toString().padLeft(2, '0');
    return '$weekday, ${t.day} $month ${t.year} • ${hour12.toString().padLeft(2, '0')}:$minute:$second $period';
  }

  /// Live countdown formatted as "89d 23h 59m 45s", or "00h 00m 00s"
  static String countdown(Duration d) {
    if (d.isNegative || d == Duration.zero) return '00d 00h 00m 00s';
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    final hStr = hours.toString().padLeft(2, '0');
    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');
    if (days > 0) {
      return '${days}d ${hStr}h ${mStr}m ${sStr}s';
    }
    return '${hStr}h ${mStr}m ${sStr}s';
  }

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
