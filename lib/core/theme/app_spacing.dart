import 'package:flutter/widgets.dart';

/// 4-based spacing scale. Use these constants instead of literal EdgeInsets
/// values so vertical rhythm stays consistent across every screen.
abstract class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;

  /// Standard horizontal page padding.
  static const EdgeInsets pageH = EdgeInsets.symmetric(horizontal: lg);

  /// Standard page padding (horizontal + comfortable top/bottom).
  static const EdgeInsets page = EdgeInsets.fromLTRB(lg, lg, lg, xxxl);
}

/// Corner radius scale. Cards and controls stay in a restrained range —
/// deliberately not the over-rounded "AI app" look.
abstract class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 14;
  static const double xl = 20;
  static const double pill = 999;

  static const BorderRadius cardMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius cardLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius control = BorderRadius.all(Radius.circular(md));
}
