import 'package:flutter/material.dart';

/// Design tokens. Widgets never hard-code hex values; they read these through
/// `context.colors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.line,
    required this.lineStrong,
    required this.primary,
    required this.onPrimary,
    required this.primarySoft,
    required this.accent,
    required this.accentSoft,
    required this.gold,
    required this.blue,
    required this.rose,
    required this.green,
    required this.shadow,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color line;
  final Color lineStrong;
  final Color primary;
  final Color onPrimary;
  final Color primarySoft;
  final Color accent;
  final Color accentSoft;
  final Color gold;
  final Color blue;
  final Color rose;
  final Color green;
  final Color shadow;

  static const light = AppColors(
    canvas: Color(0xFFF4F0E8),
    surface: Color(0xFFFFFCF6),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEDE7DB),
    ink: Color(0xFF171712),
    inkMuted: Color(0xFF6F6A5F),
    inkFaint: Color(0xFF928B7C),
    line: Color(0xFFE5DCCB),
    lineStrong: Color(0xFFD3C7B2),
    primary: Color(0xFF1D5B4F),
    onPrimary: Color(0xFFFFFCF6),
    primarySoft: Color(0xFFDCEBE4),
    accent: Color(0xFFE2673C),
    accentSoft: Color(0xFFFBE4DA),
    gold: Color(0xFFC98A2E),
    blue: Color(0xFF3C6E91),
    rose: Color(0xFFB4556C),
    green: Color(0xFF2F7D5B),
    shadow: Color(0x24171712),
  );

  static const dark = AppColors(
    canvas: Color(0xFF121310),
    surface: Color(0xFF1A1B17),
    surfaceRaised: Color(0xFF20211C),
    surfaceSunken: Color(0xFF0D0E0C),
    ink: Color(0xFFF2EDE3),
    inkMuted: Color(0xFFA6A093),
    inkFaint: Color(0xFF7C776B),
    line: Color(0xFF2D2F28),
    lineStrong: Color(0xFF3B3E34),
    primary: Color(0xFF8FD0BC),
    onPrimary: Color(0xFF10241E),
    primarySoft: Color(0xFF1F3A32),
    accent: Color(0xFFFF986F),
    accentSoft: Color(0xFF3A241C),
    gold: Color(0xFFE6B35E),
    blue: Color(0xFF8CB6D2),
    rose: Color(0xFFE19AAE),
    green: Color(0xFF7FCBAA),
    shadow: Color(0x99000000),
  );

  static const categoryPalette = <Color>[
    Color(0xFF1D5B4F),
    Color(0xFF3C6E91),
    Color(0xFF7A5CA8),
    Color(0xFFB4556C),
    Color(0xFFC26A32),
    Color(0xFF8A7A2E),
    Color(0xFF2F7D5B),
    Color(0xFF8E5A3A),
    Color(0xFF4F6B78),
    Color(0xFF9A4F8C),
    Color(0xFF5E6B3A),
    Color(0xFF6B5E52),
  ];

  @override
  AppColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? ink,
    Color? inkMuted,
    Color? inkFaint,
    Color? line,
    Color? lineStrong,
    Color? primary,
    Color? onPrimary,
    Color? primarySoft,
    Color? accent,
    Color? accentSoft,
    Color? gold,
    Color? blue,
    Color? rose,
    Color? green,
    Color? shadow,
  }) {
    return AppColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      inkFaint: inkFaint ?? this.inkFaint,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primarySoft: primarySoft ?? this.primarySoft,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      gold: gold ?? this.gold,
      blue: blue ?? this.blue,
      rose: rose ?? this.rose,
      green: green ?? this.green,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      rose: Color.lerp(rose, other.rose, t)!,
      green: Color.lerp(green, other.green, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// Spacing scale (4-based).
class AppSpace {
  AppSpace._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double x3 = 32;
  static const double x4 = 40;
  static const double x5 = 48;
  static const double x6 = 64;
}

class AppRadius {
  AppRadius._();
  static const double badge = 8;
  static const double input = 12;
  static const double button = 14;
  static const double card = 20;
  static const double sheet = 28;
  static const double pill = 999;
}

class AppDurations {
  AppDurations._();
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);
}

class AppBreakpoints {
  AppBreakpoints._();
  static const double compact = 720;
  static const double expanded = 1080;
  static const double maxContent = 1280;
  static const double prose = 720;
}
