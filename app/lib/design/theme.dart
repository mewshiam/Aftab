/// ThemeData assembly: token-backed, M3, light + dark + optional dynamic
/// (Material You) variants.

library aftab_design_theme;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'color_schemes.dart';
import 'tokens.dart';
import 'typography.dart';

/// Whether [scheme] has enough contrast for edge-accent decorations.
///
/// Used to decide when card focus borders should flip to a brighter color.
bool isDarkScheme(ColorScheme scheme) => scheme.brightness == Brightness.dark;

/// The hand-tuned base theme (no dynamic colors).
ThemeData aftabTheme(Brightness brightness) {
  final scheme = brightness == Brightness.dark
      ? aftabColorSchemeDark
      : aftabColorSchemeLight;
  return _fromScheme(scheme);
}

/// Wraps [child] with Material You dynamic color support: on Android 12+
/// the wallpaper palette replaces the brand palette. Falls back to the
/// brand schemes everywhere else (and while the OS has not answered).
Widget withDynamicColor({
  required Widget Function(ColorScheme light, ColorScheme dark) builder,
}) {
  return DynamicColorBuilder(
    builder: (light, dark) =>
        builder(light ?? aftabColorSchemeLight, dark ?? aftabColorSchemeDark),
  );
}

ThemeData _fromScheme(ColorScheme scheme) {
  return ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: aftabFontFamily,
    textTheme: aftabTextTheme(scheme),
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: AftabElevation.level0,
      scrolledUnderElevation: AftabElevation.level2,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontFamily: aftabFontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: AftabElevation.level0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AftabRadius.md)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.primaryContainer,
      surfaceTintColor: scheme.surfaceTint,
      labelTextStyle: const WidgetStatePropertyAll<TextStyle>(
        TextStyle(
          fontFamily: aftabFontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      labelType: NavigationRailLabelType.all,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: scheme.primary,
      dividerColor: scheme.outlineVariant,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AftabRadius.md)),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: scheme.outlineVariant),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AftabRadius.sm))),
      labelStyle: const TextStyle(
          fontFamily: aftabFontFamily, fontWeight: FontWeight.w500),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(
        color: scheme.onInverseSurface,
        fontFamily: aftabFontFamily,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AftabRadius.md)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AftabRadius.lg)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AftabRadius.lg)),
      ),
      showDragHandle: true,
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 4,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AftabRadius.md))),
        textStyle: const TextStyle(
            fontFamily: aftabFontFamily, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(
            horizontal: AftabSpacing.xl, vertical: AftabSpacing.md),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AftabRadius.md)),
        textStyle: const TextStyle(fontFamily: aftabFontFamily, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontFamily: aftabFontFamily, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        highlightColor: scheme.primary.withValues(alpha: 0.12),
      ),
    ),
    // Focus visibility: keyboard/remote focus must always be unmistakable.
    focusColor: scheme.primary.withValues(alpha: 0.18),
  );
}
