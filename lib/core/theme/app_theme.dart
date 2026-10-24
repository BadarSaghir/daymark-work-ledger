import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final c = brightness == Brightness.light ? AppColors.light : AppColors.dark;
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: c.primary,
          brightness: brightness,
        ).copyWith(
          primary: c.primary,
          onPrimary: c.onPrimary,
          primaryContainer: c.primarySoft,
          onPrimaryContainer: c.ink,
          secondary: c.accent,
          onSecondary: isDark ? const Color(0xFF2A140B) : Colors.white,
          secondaryContainer: c.accentSoft,
          onSecondaryContainer: c.ink,
          surface: c.surface,
          onSurface: c.ink,
          surfaceContainerHighest: c.surfaceSunken,
          outline: c.line,
          outlineVariant: c.line,
          error: c.rose,
          onError: Colors.white,
          shadow: c.shadow,
        );

    final textTheme = TextTheme(
      displayLarge: AppText.displayXl.copyWith(color: c.ink),
      displayMedium: AppText.displayL.copyWith(color: c.ink),
      displaySmall: AppText.displayM.copyWith(color: c.ink),
      headlineLarge: AppText.displayL.copyWith(color: c.ink),
      headlineMedium: AppText.displayM.copyWith(color: c.ink),
      headlineSmall: AppText.displayS.copyWith(color: c.ink),
      titleLarge: AppText.titleL.copyWith(color: c.ink),
      titleMedium: AppText.titleM.copyWith(color: c.ink),
      titleSmall: AppText.bodyMedium.copyWith(color: c.ink),
      bodyLarge: AppText.body.copyWith(color: c.ink),
      bodyMedium: AppText.body.copyWith(color: c.ink),
      bodySmall: AppText.bodySmall.copyWith(color: c.inkMuted),
      labelLarge: AppText.bodyMedium.copyWith(color: c.ink),
      labelMedium: AppText.bodySmall.copyWith(color: c.inkMuted),
      labelSmall: AppText.label.copyWith(color: c.inkMuted),
    );

    const inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.input)),
      borderSide: BorderSide.none,
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: AppFonts.sans,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.canvas,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[c],
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.md,
        ),
        hintStyle: AppText.body.copyWith(color: c.inkFaint),
        labelStyle: AppText.bodySmall.copyWith(color: c.inkMuted),
        prefixIconColor: c.inkMuted,
        suffixIconColor: c.inkMuted,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: c.primary, width: 1.4),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: c.rose, width: 1.2),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: c.rose, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: AppSpace.lg,
              vertical: AppSpace.md,
            ),
          ),
          shape: WidgetStatePropertyAll(buttonShape),
          textStyle: WidgetStatePropertyAll(
            AppText.bodyMedium.copyWith(fontWeight: FontWeight.w700),
          ),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: AppSpace.lg,
              vertical: AppSpace.md,
            ),
          ),
          shape: WidgetStatePropertyAll(buttonShape),
          side: WidgetStatePropertyAll(BorderSide(color: c.lineStrong)),
          foregroundColor: WidgetStatePropertyAll(c.ink),
          textStyle: WidgetStatePropertyAll(
            AppText.bodyMedium.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 40)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.sm,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.badge),
            ),
          ),
          foregroundColor: WidgetStatePropertyAll(c.primary),
          textStyle: WidgetStatePropertyAll(
            AppText.bodySmall.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.badge),
            ),
          ),
          foregroundColor: WidgetStatePropertyAll(c.inkMuted),
          overlayColor: WidgetStatePropertyAll(c.ink.withValues(alpha: 0.06)),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceRaised,
        elevation: 8,
        shadowColor: c.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          side: BorderSide(color: c.line),
        ),
        textStyle: AppText.body.copyWith(color: c.ink, fontSize: 13.5),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.ink,
        contentTextStyle: AppText.bodySmall.copyWith(color: c.canvas),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        insetPadding: const EdgeInsets.all(AppSpace.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.ink,
          borderRadius: BorderRadius.circular(AppRadius.badge),
        ),
        textStyle: AppText.bodySmall.copyWith(color: c.canvas),
        waitDuration: const Duration(milliseconds: 500),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.primary,
        selectionColor: c.primary.withValues(alpha: 0.18),
        selectionHandleColor: c.primary,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(7),
        radius: const Radius.circular(8),
        thumbColor: WidgetStatePropertyAll(c.inkFaint.withValues(alpha: 0.4)),
        trackColor: WidgetStatePropertyAll(c.line.withValues(alpha: 0.35)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.surfaceSunken,
        circularTrackColor: c.surfaceSunken,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: c.lineStrong, width: 1.4),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(c.onPrimary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surface,
        modalBarrierColor: Colors.black.withValues(alpha: 0.35),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),
    );
    return base;
  }
}
