import 'package:flutter/material.dart';

/// Centralized semantic color tokens for Rakt Pravah.
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
    background: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF1F5F9),
    border: Color(0xFFE2E8F0),
    borderStrong: Color(0xFFCBD5E1),
    textPrimary: Color(0xFF172033),
    textSecondary: Color(0xFF64748B),
    textTertiary: Color(0xFF94A3B8),
    brand: Color(0xFFC62828),
    brandPressed: Color(0xFFA61B1B),
    brandSubtle: Color(0xFFFDECEC),
    onBrand: Color(0xFFFFFFFF),
    success: Color(0xFF2E7D32),
    successSubtle: Color(0xFFE8F5E9),
    warning: Color(0xFFED8B00),
    warningSubtle: Color(0xFFFFF3E0),
    danger: Color(0xFFD32F2F),
    dangerSubtle: Color(0xFFFFEBEE),
    info: Color(0xFF1976D2),
    infoSubtle: Color(0xFFE3F2FD),
    overlay: Color(0x99000000),
  );

  static const dark = AppColors(
    background: Color(0xFF0B0F17),
    surface: Color(0xFF131B26),
    surfaceMuted: Color(0xFF1E293B),
    border: Color(0xFF334155),
    borderStrong: Color(0xFF475569),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF94A3B8),
    textTertiary: Color(0xFF64748B),
    brand: Color(0xFFEF5350),
    brandPressed: Color(0xFFE53935),
    brandSubtle: Color(0xFF361418),
    onBrand: Color(0xFFFFFFFF),
    success: Color(0xFF4CAF50),
    successSubtle: Color(0xFF16331C),
    warning: Color(0xFFFFA726),
    warningSubtle: Color(0xFF3D2A12),
    danger: Color(0xFFEF5350),
    dangerSubtle: Color(0xFF361418),
    info: Color(0xFF42A5F5),
    infoSubtle: Color(0xFF122842),
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
