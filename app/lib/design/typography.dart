/// Typography: Vazirmatn everywhere, one family for Persian and Latin so
/// mixed-direction titles stay visually consistent.
///
/// Weights are mapped to the four bundled static instances
/// (400 / 500 / 600 / 700). Missing glyphs fall back to the platform font
/// through Flutter's per-glyph fallback.

library aftab_design_typography;

import 'package:flutter/material.dart';

/// The family name declared in `pubspec.yaml`.
const String aftabFontFamily = 'Vazirmatn';

/// Builds the app text theme for a [ColorScheme].
TextTheme aftabTextTheme(ColorScheme scheme) {
  final base = TextTheme(
    displaySmall: TextStyle(
      fontFamily: aftabFontFamily,
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
      height: 1.2,
    ),
    headlineMedium: TextStyle(
      fontFamily: aftabFontFamily,
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
      height: 1.25,
    ),
    headlineSmall: TextStyle(
      fontFamily: aftabFontFamily,
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
      height: 1.3,
    ),
    titleLarge: TextStyle(
      fontFamily: aftabFontFamily,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
      height: 1.35,
    ),
    titleMedium: TextStyle(
      fontFamily: aftabFontFamily,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
      height: 1.4,
    ),
    titleSmall: TextStyle(
      fontFamily: aftabFontFamily,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
      height: 1.4,
    ),
    bodyLarge: TextStyle(
      fontFamily: aftabFontFamily,
      fontWeight: FontWeight.w400,
      color: scheme.onSurface,
      height: 1.5,
    ),
    bodyMedium: TextStyle(
      fontFamily: aftabFontFamily,
      fontWeight: FontWeight.w400,
      color: scheme.onSurface,
      height: 1.5,
    ),
    bodySmall: TextStyle(
      fontFamily: aftabFontFamily,
      fontWeight: FontWeight.w400,
      color: scheme.onSurfaceVariant,
      height: 1.4,
    ),
    labelLarge: TextStyle(
      fontFamily: aftabFontFamily,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
      height: 1.3,
    ),
    labelMedium: TextStyle(
      fontFamily: aftabFontFamily,
      fontWeight: FontWeight.w500,
      color: scheme.onSurfaceVariant,
      height: 1.3,
    ),
    labelSmall: TextStyle(
      fontFamily: aftabFontFamily,
      fontWeight: FontWeight.w500,
      color: scheme.onSurfaceVariant,
      height: 1.3,
    ),
  );
  return base;
}
