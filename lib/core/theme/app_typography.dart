import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Type system for Rakt Pravah.
///
/// Two families, one idea:
///  - IBM Plex Sans  -> all UI text and headings (heavier weights for display).
///  - IBM Plex Mono  -> the "instrument readout" for critical data: blood
///    groups, unit counts, distances, ETAs, countdowns, IDs. Setting data in
///    mono is the signature typographic move — it reads like a calm dispatch
///    console rather than a social feed.
abstract class AppTypography {
  static TextTheme textTheme(Color primary, Color secondary) {
    final sans = GoogleFonts.inter;

    TextStyle s(
      double size,
      FontWeight weight,
      double height, {
      double spacing = 0,
      Color? color,
    }) => sans(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing,
      color: color ?? primary,
    );

    return TextTheme(
      // Page Titles (28–32px)
      displaySmall: s(32, FontWeight.w700, 1.2, spacing: -0.6),
      headlineLarge: s(28, FontWeight.w700, 1.25, spacing: -0.4),
      // Section Titles (20–24px)
      headlineMedium: s(24, FontWeight.w600, 1.3, spacing: -0.3),
      headlineSmall: s(20, FontWeight.w600, 1.3, spacing: -0.2),
      // Card Titles (16–18px)
      titleLarge: s(18, FontWeight.w600, 1.35),
      titleMedium: s(16, FontWeight.w600, 1.35),
      titleSmall: s(15, FontWeight.w600, 1.35),
      // Body (14–16px)
      bodyLarge: s(16, FontWeight.w400, 1.5, color: primary),
      bodyMedium: s(14, FontWeight.w400, 1.5, color: secondary),
      // Secondary (12–14px)
      bodySmall: s(13, FontWeight.w400, 1.45, color: secondary),
      labelLarge: s(15, FontWeight.w600, 1.25),
      labelMedium: s(13, FontWeight.w600, 1.2),
      // Caption (11–12px)
      labelSmall: s(11.5, FontWeight.w500, 1.2, color: secondary),
    );
  }

  /// Monospace style for data readouts.
  static TextStyle mono({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double spacing = 0.2,
    double height = 1.2,
  }) => GoogleFonts.ibmPlexMono(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: spacing,
    height: height,
  );

  /// Uppercase eyebrow/label style used for section headers and badges.
  static TextStyle eyebrow(Color color) => GoogleFonts.ibmPlexMono(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    color: color,
    height: 1.2,
  );
}
