import 'package:animations/animations.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';
import '../design/typography.dart';

/// Legacy names for the design tokens (lib/design). New code should use
/// LenzoColors / LenzoSpacing / LenzoRadius / LenzoType / LenzoMotion.
abstract final class Lenzo {
  /// App font, bundled (assets/fonts). Set explicitly on text painted on a
  /// canvas, which doesn't inherit the theme.
  static const font = 'Manrope';

  /// App background, nearly black forest green.
  static const background = LenzoColors.background;

  /// Cards, panels and pills (use with some transparency over the camera).
  static const surface = LenzoColors.surface;

  /// Raised controls such as the camera bar; depth comes from these steps
  /// in tone rather than from bright borders.
  static const elevated = LenzoColors.surfaceSecondary;

  /// Quiet sage accent for icons and secondary emphasis.
  static const accentMuted = LenzoColors.textSecondary;

  /// Bright mint: only for actions, verification and active states.
  static const accent = LenzoColors.accent;

  /// Barely visible edge for cards and the camera (1 px).
  static const hairline = LenzoColors.border;

  /// Softer accent for lines and inactive steps.
  static const accentDim = Color(0xFF2F8A5C);

  /// Vibrant green for the one highlight card per screen (with dark text).
  static const highlight = LenzoColors.accent;

  /// Text and icons on [highlight].
  static const onHighlight = LenzoColors.onAccent;

  /// Flat card fill and its hairline border.
  static const card = surface;
  static const cardBorder = LenzoColors.border;

  /// Large, light figures for important amounts, with even-width digits so
  /// they don't jitter while counting.
  static TextStyle figure(double size, {Color color = textPrimary}) =>
      LenzoType.amount(size, color: color);

  /// Small caption above a figure or a section.
  static const caption = LenzoType.secondary;

  /// Warm off-white and muted sage.
  static const textPrimary = LenzoColors.textPrimary;
  static const textSecondary = LenzoColors.textSecondary;

  // Status colors.
  static const danger = LenzoColors.danger;

  /// Muted coral for destructive actions (not alarm-bright), and the dark
  /// text used on it.
  static const dangerMuted = LenzoColors.danger;
  static const onDanger = LenzoColors.onDanger;
  static const warning = LenzoColors.warning;
  static const caution = LenzoColors.payable;

  /// Tinted near-black for scrims and shadows (never pure black).
  static const ink = LenzoColors.ink;

  // Spacing scale (4-pt) and corner radii, so gaps and corners stay
  // consistent across screens.
  static const s4 = LenzoSpacing.x1, s8 = LenzoSpacing.x2;
  static const s12 = LenzoSpacing.x3, s16 = LenzoSpacing.x4;
  static const s20 = LenzoSpacing.x5;
  static const s24 = LenzoSpacing.x6, s32 = LenzoSpacing.x8;
  static const rControl = LenzoRadius.field;
  static const rCard = LenzoRadius.cardSmall, rSheet = LenzoRadius.card;

  /// Minimum touch target.
  static const tap = LenzoSpacing.tap;

  // Motion: refined deceleration, no bounce. Exits run ~75% of entrances.
  static const ease = Curves.easeOutQuart;
  static const easeIn = Curves.easeInCubic;
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 380);

  /// [d], or zero when the phone's "Remove animations" setting is on.
  static Duration motion(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : d;

  static ThemeData theme() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: LenzoColors.accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: LenzoColors.accent,
          onPrimary: LenzoColors.onAccent,
          surface: LenzoColors.surface,
          onSurface: LenzoColors.textPrimary,
          surfaceContainerHighest: LenzoColors.surfaceSecondary,
          outline: LenzoColors.border,
          outlineVariant: LenzoColors.border,
          error: LenzoColors.danger,
        );
    const text = TextTheme(
      headlineSmall: LenzoType.pageHeading,
      titleLarge: LenzoType.sectionHeading,
      titleMedium: LenzoType.cardHeading,
      titleSmall: LenzoType.label,
      bodyLarge: LenzoType.input,
      bodyMedium: LenzoType.body,
      bodySmall: LenzoType.secondary,
      labelLarge: LenzoType.button,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: LenzoRadius.buttonAll,
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: LenzoType.family,
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: LenzoColors.background,
      canvasColor: LenzoColors.background,
      splashFactory: InkSparkle.splashFactory,
      // Every page opens with a short horizontal shared-axis slide and fade
      // (the `animations` package), filled with the background colour.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SharedAxisPageTransitionsBuilder(
            transitionType: SharedAxisTransitionType.horizontal,
            fillColor: LenzoColors.background,
          ),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: LenzoColors.background,
        foregroundColor: LenzoColors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      iconTheme: const IconThemeData(color: LenzoColors.textPrimary, size: 22),
      dividerTheme: const DividerThemeData(
        color: LenzoColors.border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LenzoColors.surface,
        isDense: true,
        hintStyle: LenzoType.input.copyWith(color: LenzoColors.textTertiary),
        border: OutlineInputBorder(
          borderRadius: LenzoRadius.inputAll,
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: LenzoColors.accent,
          foregroundColor: LenzoColors.onAccent,
          minimumSize: const Size(64, 48),
          shape: buttonShape,
          textStyle: LenzoType.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: LenzoColors.textPrimary,
          side: const BorderSide(color: LenzoColors.border),
          minimumSize: const Size(64, 48),
          shape: buttonShape,
          textStyle: LenzoType.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: LenzoColors.accent,
          minimumSize: const Size(48, LenzoSpacing.tap),
          shape: buttonShape,
          textStyle: LenzoType.button,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: LenzoColors.accent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: LenzoColors.surfaceSecondary,
          borderRadius: LenzoRadius.fieldAll,
        ),
        textStyle: LenzoType.secondary.copyWith(color: LenzoColors.textPrimary),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: LenzoColors.surface,
        shape: RoundedRectangleBorder(borderRadius: LenzoRadius.cardAll),
        titleTextStyle: LenzoType.sectionHeading,
        contentTextStyle: LenzoType.body.copyWith(
          color: LenzoColors.textSecondary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: LenzoColors.surfaceSecondary,
        contentTextStyle: LenzoType.body,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: LenzoRadius.fieldAll),
        insetPadding: const EdgeInsets.fromLTRB(
          LenzoSpacing.screen,
          0,
          LenzoSpacing.screen,
          LenzoSpacing.x4,
        ),
      ),
    );
  }
}

/// Status and navigation bars on every screen: transparent status bar, and
/// a navigation bar in the page background colour, light icons.
const lenzoSystemUi = SystemUiOverlayStyle(
  statusBarColor: Color(0x00000000),
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: LenzoColors.background,
  systemNavigationBarDividerColor: LenzoColors.background,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
);
