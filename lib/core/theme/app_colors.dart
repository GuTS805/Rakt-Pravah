import 'package:flutter/material.dart';

/// Centralized semantic color tokens for BloodLink.
///
/// Colors are never hardcoded in screens. Widgets read tokens from
/// `Theme.of(context).extension<AppColors>()!` (or the `context.colors`
/// helper) so light/dark stay consistent and the palette lives in one place.
///
/// Design intent: calm, neutral chrome so that red *means something*. Red is
/// reserved for brand identity and critical urgency — never used as wallpaper.
/// The urgency ladder doubles as the semantic ladder:
///   routine  -> info (slate blue)
///   urgent   -> warning (amber)
///   critical -> danger (red / brand)
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.brand,
    required this.brandPressed,
    required this.brandSubtle,
    required this.onBrand,
    required this.success,
    required this.successSubtle,
    required this.warning,
    required this.warningSubtle,
    required this.danger,
    required this.dangerSubtle,
    required this.info,
    required this.infoSubtle,
    required this.overlay,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color borderStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  final Color brand;
  final Color brandPressed;
  final Color brandSubtle;
  final Color onBrand;

  final Color success;
  final Color successSubtle;
  final Color warning;
  final Color warningSubtle;
  final Color danger;
  final Color dangerSubtle;
  final Color info;
  final Color infoSubtle;

  final Color overlay;

  static const light = AppColors(
    background: Color(0xFFF7F8FA),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF0F2F5),
    border: Color(0xFFE3E7EC),
    borderStrong: Color(0xFFCFD6DE),
    textPrimary: Color(0xFF141A1F),
    textSecondary: Color(0xFF5B6672),
    textTertiary: Color(0xFF8A94A0),
    brand: Color(0xFFD62839),
    brandPressed: Color(0xFFB21E2F),
    brandSubtle: Color(0xFFFCE8EA),
    onBrand: Color(0xFFFFFFFF),
    success: Color(0xFF128A5E),
    successSubtle: Color(0xFFE2F3EC),
    warning: Color(0xFFB56A00),
    warningSubtle: Color(0xFFFBEFD6),
    danger: Color(0xFFD62839),
    dangerSubtle: Color(0xFFFCE8EA),
    info: Color(0xFF2D6BE0),
    infoSubtle: Color(0xFFE7EEFC),
    overlay: Color(0x99000000),
  );

  static const dark = AppColors(
    background: Color(0xFF0E1216),
    surface: Color(0xFF161B21),
    surfaceMuted: Color(0xFF1E242B),
    border: Color(0xFF2A3138),
    borderStrong: Color(0xFF3A424B),
    textPrimary: Color(0xFFF2F5F8),
    textSecondary: Color(0xFFA3ADB8),
    textTertiary: Color(0xFF6F7A85),
    brand: Color(0xFFEF4457),
    brandPressed: Color(0xFFF06576),
    brandSubtle: Color(0xFF2A1519),
    onBrand: Color(0xFFFFFFFF),
    success: Color(0xFF33B889),
    successSubtle: Color(0xFF11271F),
    warning: Color(0xFFE8A317),
    warningSubtle: Color(0xFF2A2110),
    danger: Color(0xFFEF4457),
    dangerSubtle: Color(0xFF2A1519),
    info: Color(0xFF5B8DEF),
    infoSubtle: Color(0xFF13203A),
    overlay: Color(0xB3000000),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? brand,
    Color? brandPressed,
    Color? brandSubtle,
    Color? onBrand,
    Color? success,
    Color? successSubtle,
    Color? warning,
    Color? warningSubtle,
    Color? danger,
    Color? dangerSubtle,
    Color? info,
    Color? infoSubtle,
    Color? overlay,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      brand: brand ?? this.brand,
      brandPressed: brandPressed ?? this.brandPressed,
      brandSubtle: brandSubtle ?? this.brandSubtle,
      onBrand: onBrand ?? this.onBrand,
      success: success ?? this.success,
      successSubtle: successSubtle ?? this.successSubtle,
      warning: warning ?? this.warning,
      warningSubtle: warningSubtle ?? this.warningSubtle,
      danger: danger ?? this.danger,
      dangerSubtle: dangerSubtle ?? this.dangerSubtle,
      info: info ?? this.info,
      infoSubtle: infoSubtle ?? this.infoSubtle,
      overlay: overlay ?? this.overlay,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandPressed: Color.lerp(brandPressed, other.brandPressed, t)!,
      brandSubtle: Color.lerp(brandSubtle, other.brandSubtle, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSubtle: Color.lerp(successSubtle, other.successSubtle, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSubtle: Color.lerp(warningSubtle, other.warningSubtle, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSubtle: Color.lerp(dangerSubtle, other.dangerSubtle, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSubtle: Color.lerp(infoSubtle, other.infoSubtle, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
    );
  }
}
