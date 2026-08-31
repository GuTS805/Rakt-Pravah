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
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  /// Short date, e.g. "12 Aug".
  static String shortDate(DateTime t) => '${t.day} ${_months[t.month - 1]}';

  /// Units label, e.g. "2 units" / "1 unit".
  static String units(int n) => n == 1 ? '1 unit' : '$n units';
}
