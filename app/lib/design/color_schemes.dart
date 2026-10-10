/// Aftab Media color system — "گوشهٔ نور" (edge of light): a cinema in the
/// dark with a warm sun accent.
///
/// Roles follow Material 3 semantic naming. Two hand-tuned schemes:
///
/// * Dark  — deep blue-black projector room, amber "آفتاب" (sun) primary.
/// * Light — warm paper, deep amber-brown primary with AA contrast.
///
/// Dynamic color (Material You) variants are derived at runtime from the
/// platform palette with the same tonal mapping (see `theme.dart`).

library aftab_design_colors;

import 'package:flutter/material.dart';

/// Core brand hues, kept as named constants for documentation and tests.
abstract final class AftabColors {
  /// The sun accent.
  static const Color amber = Color(0xFFF6B545);

  /// Deep amber for light-scheme contrast.
  static const Color amberDeep = Color(0xFF8A5400);

  /// Cinema-room blue-black.
  static const Color night = Color(0xFF0B0E16);
}

const ColorScheme aftabColorSchemeDark = ColorScheme.dark(
  brightness: Brightness.dark,
  primary: Color(0xFFF6B545),
  onPrimary: Color(0xFF2A1A00),
  primaryContainer: Color(0xFF5C4200),
  onPrimaryContainer: Color(0xFFFFDF9E),
  secondary: Color(0xFFA6C9BF),
  onSecondary: Color(0xFF0E211C),
  secondaryContainer: Color(0xFF294A43),
  onSecondaryContainer: Color(0xFFC2E5DB),
  tertiary: Color(0xFFE5B8C4),
  onTertiary: Color(0xFF3C2A31),
  tertiaryContainer: Color(0xFF553F47),
  onTertiaryContainer: Color(0xFFFFDAE6),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF540005),
  errorContainer: Color(0xFF71111B),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF10131B),
  onSurface: Color(0xFFE7E9F0),
  onSurfaceVariant: Color(0xFFB9BFCB),
  outline: Color(0xFF8A93A3),
  outlineVariant: Color(0xFF3A404B),
  surfaceContainerLowest: Color(0xFF0B0E16),
  surfaceContainerLow: Color(0xFF181C25),
  surfaceContainer: Color(0xFF1C212B),
  surfaceContainerHigh: Color(0xFF272D37),
  surfaceContainerHighest: Color(0xFF323843),
  inverseSurface: Color(0xFFE7E9F0),
  onInverseSurface: Color(0xFF2B2F38),
  inversePrimary: Color(0xFF7A5900),
  scrim: Color(0xFF000000),
);

const ColorScheme aftabColorSchemeLight = ColorScheme.light(
  brightness: Brightness.light,
  primary: Color(0xFF8A5400),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFFFDF9E),
  onPrimaryContainer: Color(0xFF2A1A00),
  secondary: Color(0xFF4A625B),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFC2E5DB),
  onSecondaryContainer: Color(0xFF0A211C),
  tertiary: Color(0xFF7A564F),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFFFDAD6),
  onTertiaryContainer: Color(0xFF30140F),
  error: Color(0xFF93000A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),
  surface: Color(0xFFFCF8F4),
  onSurface: Color(0xFF1C1B17),
  onSurfaceVariant: Color(0xFF4A473F),
  outline: Color(0xFF7B776C),
  outlineVariant: Color(0xFFCCC7BD),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF7F1EA),
  surfaceContainer: Color(0xFFF1EBE3),
  surfaceContainerHigh: Color(0xFFEBE5DC),
  surfaceContainerHighest: Color(0xFFE5E0D6),
  inverseSurface: Color(0xFF31302B),
  onInverseSurface: Color(0xFFF3F0E7),
  inversePrimary: Color(0xFFF6B545),
  scrim: Color(0xFF000000),
);

/// The player surface scheme: the cinema dark scheme on a true-black stage.
///
/// Players stay cinematic regardless of the app theme — even in light
/// mode, video chrome belongs to the dark "projector room". Dynamic-color
/// palettes (Material You) keep their accent when the app is in dark mode.
ColorScheme playerColorScheme(ColorScheme base) {
  final dark = base.brightness == Brightness.dark ? base : aftabColorSchemeDark;
  return dark.copyWith(
    surface: const Color(0xFF000000),
    surfaceContainerLowest: const Color(0xFF000000),
  );
}
