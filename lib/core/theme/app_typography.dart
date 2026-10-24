import 'package:flutter/material.dart';

class AppFonts {
  AppFonts._();
  static const sans = 'Manrope';
  static const display = 'Newsreader';
  static const mono = 'JetBrainsMono';
}

/// Typographic styles. Colours are intentionally inherited unless a style is
/// being used on a coloured surface.
class AppText {
  AppText._();

  static const displayXl = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 44,
    height: 1.06,
    letterSpacing: -1.4,
    fontWeight: FontWeight.w400,
  );

  static const displayL = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 34,
    height: 1.12,
    letterSpacing: -0.8,
    fontWeight: FontWeight.w400,
  );

  static const displayM = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 26,
    height: 1.18,
    letterSpacing: -0.4,
    fontWeight: FontWeight.w500,
  );

  static const displayS = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 21,
    height: 1.25,
    letterSpacing: -0.2,
    fontWeight: FontWeight.w500,
  );

  static const titleL = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 20,
    height: 1.3,
    letterSpacing: -0.3,
    fontWeight: FontWeight.w700,
  );

  static const titleM = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 16.5,
    height: 1.35,
    letterSpacing: -0.15,
    fontWeight: FontWeight.w700,
  );

  static const body = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 14.5,
    height: 1.55,
    fontWeight: FontWeight.w400,
  );

  static const bodyMedium = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w600,
  );

  static const bodySmall = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 12.8,
    height: 1.45,
    fontWeight: FontWeight.w500,
  );

  static const label = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 10.5,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.1,
  );

  static const eyebrow = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 10.5,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.4,
  );

  static const monoData = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const monoLarge = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 34,
    height: 1.05,
    fontWeight: FontWeight.w500,
    letterSpacing: -1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const monoHuge = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 56,
    height: 1,
    fontWeight: FontWeight.w400,
    letterSpacing: -2.5,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
