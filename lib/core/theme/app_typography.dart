import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Type system for BloodLink.
///
/// Two families, one idea:
///  - IBM Plex Sans  -> all UI text and headings (heavier weights for display).
///  - IBM Plex Mono  -> the "instrument readout" for critical data: blood
///    groups, unit counts, distances, ETAs, countdowns, IDs. Setting data in
///    mono is the signature typographic move — it reads like a calm dispatch
///    console rather than a social feed.
abstract class AppTypography {
  static TextTheme textTheme(Color primary, Color secondary) {
    final sans = GoogleFonts.ibmPlexSans;

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
      // Display / big moments (used sparingly)
      displaySmall: s(30, FontWeight.w700, 1.15, spacing: -0.5),
      headlineLarge: s(26, FontWeight.w700, 1.2, spacing: -0.3),
      headlineMedium: s(22, FontWeight.w700, 1.25, spacing: -0.2),
      headlineSmall: s(19, FontWeight.w600, 1.3, spacing: -0.1),
      titleLarge: s(17, FontWeight.w600, 1.3),
      titleMedium: s(15, FontWeight.w600, 1.35),
      titleSmall: s(13, FontWeight.w600, 1.35),
      bodyLarge: s(16, FontWeight.w400, 1.45, color: primary),
      bodyMedium: s(14, FontWeight.w400, 1.45, color: secondary),
      bodySmall: s(12.5, FontWeight.w400, 1.4, color: secondary),
      labelLarge: s(14, FontWeight.w600, 1.2),
      labelMedium: s(12.5, FontWeight.w600, 1.2),
      labelSmall: s(11, FontWeight.w500, 1.2, color: secondary),
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
