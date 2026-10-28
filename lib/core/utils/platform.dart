import 'package:flutter/foundation.dart';

/// Platform capability helpers.
///
/// Daymark runs on phones, tablets, and desktop. The UI should never offer a
/// desktop affordance (keyboard shortcuts, hover copy, precise drag hints) on a
/// touch-first device, and should never hide a useful touch affordance on a
/// desktop just because the window happens to be narrow.
class AppPlatform {
  AppPlatform._();

  static bool get isWeb => kIsWeb;

  static bool get isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  /// Physical keyboard shortcuts only make sense where one is likely to exist.
  static bool get showsKeyboardHints => !isMobile;

  /// Copy that references a mouse or keyboard should adapt on touch devices.
  static String get primaryActionVerb => isMobile ? 'Tap' : 'Click';
}
