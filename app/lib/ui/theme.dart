/// آفتاب (sun) — a Persian-first dark theme with a warm amber accent.

import 'package:flutter/material.dart';

class AftabTheme {
  AftabTheme._();

  static const Color background = Color(0xFF0E1320);
  static const Color surface = Color(0xFF161D2F);
  static const Color surfaceVariant = Color(0xFF1F2940);
  static const Color accent = Color(0xFFF5A623);
  static const Color accentDark = Color(0xFFB36F00);
  static const Color onBackground = Color(0xFFF2F4F8);
  static const Color onSurface = Color(0xFFF2F4F8);
  static const Color muted = Color(0xFF8D97AD);

  static ThemeData dark() {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        onPrimary: Colors.black,
        secondary: accentDark,
        surface: surface,
        onSurface: onSurface,
        error: Color(0xFFFF5C5C),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: onBackground,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accent,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: muted,
        indicatorColor: accent,
      ),
      dividerTheme: const DividerThemeData(color: surfaceVariant),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceVariant,
        contentTextStyle: TextStyle(color: onSurface),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: onBackground,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: onBackground,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: onBackground,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(color: onSurface),
        bodySmall: TextStyle(color: muted),
      ),
    );
  }
}
