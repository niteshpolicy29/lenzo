import 'package:flutter/painting.dart';

import 'tokens.dart';

/// Lenzo type scale (Manrope). Seven roles; screens use these, not sizes.
abstract final class LenzoType {
  static const family = 'Manrope';

  /// The one large headline on the Welcome screen.
  static const display = TextStyle(
    fontFamily: family,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.6,
    color: LenzoColors.textPrimary,
  );

  /// Page title, e.g. "Saved People".
  static const pageHeading = TextStyle(
    fontFamily: family,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.4,
    color: LenzoColors.textPrimary,
  );

  /// Section title inside a page.
  static const sectionHeading = TextStyle(
    fontFamily: family,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.2,
    color: LenzoColors.textPrimary,
  );

  /// Title on a card or row (also a person's name).
  static const cardHeading = TextStyle(
    fontFamily: family,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: LenzoColors.textPrimary,
  );

  static const body = TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: LenzoColors.textPrimary,
  );

  /// Supporting text, captions and labels above values.
  static const secondary = TextStyle(
    fontFamily: family,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.35,
    letterSpacing: 0.1,
    color: LenzoColors.textSecondary,
  );

  /// A person's name at the top of their profile.
  static const profileName = TextStyle(
    fontFamily: family,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.4,
    color: LenzoColors.textPrimary,
  );

  /// Label above a value on a card (e.g. "To Receive").
  static const cardLabel = TextStyle(
    fontFamily: family,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: LenzoColors.textSecondary,
  );

  /// Field labels and small emphasised captions.
  static const label = TextStyle(
    fontFamily: family,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0.1,
    color: LenzoColors.textSecondary,
  );

  static const input = TextStyle(
    fontFamily: family,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: LenzoColors.textPrimary,
  );

  static const button = TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.1,
  );

  /// Financial figures: semibold, even-width digits so counting doesn't
  /// jitter. 28–34 for key amounts; smaller sizes for row amounts.
  static TextStyle amount(
    double size, {
    Color color = LenzoColors.textPrimary,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: FontWeight.w600,
    height: 1.1,
    letterSpacing: -size * 0.02,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
