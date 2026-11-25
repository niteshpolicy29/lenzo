import 'package:material_ui/material_ui.dart';

/// Lenzo design tokens. Every screen and component takes its colours,
/// spacing, corner radii, shadows and motion from here — nothing is styled
/// with one-off values.
///
/// Direction: near-black green surfaces that separate by tone, not by
/// borders; one mint accent kept for amounts, active states and the primary
/// action.
abstract final class LenzoColors {
  /// Screen background.
  static const background = Color(0xFF080D0B);

  /// Headers, bars and the camera surround: one step up from [background].
  static const backgroundElevated = Color(0xFF101815);

  /// Cards and inputs.
  static const surface = Color(0xFF171F1B);

  /// Controls on a card (segmented track, icon buttons, chips).
  static const surfaceSecondary = Color(0xFF202A25);

  /// The one accent: important amounts, active state, primary action.
  static const accent = Color(0xFF69EBA5);

  /// Text and icons on [accent].
  static const onAccent = Color(0xFF06150E);

  /// Money owed by the owner (To Pay). Warm, quieter than [warning].
  static const payable = Color(0xFFF0C46E);

  static const textPrimary = Color(0xFFF5F7F5);
  static const textSecondary = Color(0xFFA0AAA4);

  /// Hints and disabled text.
  static const textTertiary = Color(0xFF6D7872);

  /// Text inputs and the search bar: filled, never outlined. On the page
  /// they use [surface] (the summary-card colour) and lighten a step while
  /// focused; inside a card or panel (already [surface]) they use the
  /// raised pair so they still stand apart.
  static const field = surface;
  static const fieldFocused = Color(0xFF1E2823);
  static const fieldRaised = surfaceSecondary;
  static const fieldRaisedFocused = Color(0xFF29342E);

  /// Hairline borders, only where surfaces need a separation.
  static const border = Color(0xFF29352F);

  static const danger = Color(0xFFFF747A);
  static const onDanger = Color(0xFF2A0B0D);
  static const warning = Color(0xFFFFB547);

  /// Scrims and shadows: a tinted near-black, never pure black.
  static const ink = Color(0xFF020504);
}

/// 4-point spacing scale.
abstract final class LenzoSpacing {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x7 = 28.0;
  static const x8 = 32.0;

  /// Left/right margin of every screen.
  static const screen = x5;

  /// Inside cards.
  static const card = x4;

  /// Between cards in a list or grid.
  static const cardGap = x3;

  /// Between related elements (label → field, icon → text).
  static const related = x2;

  /// Between sections of a screen.
  static const section = x6;

  /// Between major blocks (header → content).
  static const major = x8;

  /// Minimum touch target.
  static const tap = 44.0;

  /// Screen padding as insets.
  static const screenInsets = EdgeInsets.symmetric(horizontal: screen);
}

abstract final class LenzoRadius {
  static const card = 18.0;
  static const cardSmall = 16.0;
  static const field = 14.0;
  static const button = 14.0;

  /// Text inputs and the search bar: the same corners as the cards.
  static const input = card;
  static const pill = 999.0;

  static final cardAll = BorderRadius.circular(card);
  static final cardSmallAll = BorderRadius.circular(cardSmall);
  static final fieldAll = BorderRadius.circular(field);
  static final buttonAll = BorderRadius.circular(button);
  static final inputAll = BorderRadius.circular(input);
  static final pillAll = BorderRadius.circular(pill);
}

/// Soft, tinted shadows. Used for raised surfaces only, never on everything.
abstract final class LenzoShadows {
  /// Cards that sit on the background.
  static const card = [
    BoxShadow(
      color: Color(0x52020504),
      blurRadius: 24,
      spreadRadius: -10,
      offset: Offset(0, 10),
    ),
  ];

  /// Floating controls and dialogs.
  static const raised = [
    BoxShadow(
      color: Color(0x73020504),
      blurRadius: 32,
      spreadRadius: -8,
      offset: Offset(0, 14),
    ),
  ];
}

/// Motion: short, decelerating, no bounce. Exits are quicker than entries.
abstract final class LenzoMotion {
  static const press = Duration(milliseconds: 120);
  static const tab = Duration(milliseconds: 220);
  static const expand = Duration(milliseconds: 250);
  static const page = Duration(milliseconds: 260);
  static const count = Duration(milliseconds: 600);

  static const ease = Curves.easeOutCubic;
  static const easeInOut = Curves.easeInOutCubic;
  static const exit = Curves.easeInCubic;

  /// [d], or zero when Android's "Remove animations" is on.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : d;
}
