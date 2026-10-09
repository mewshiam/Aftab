/// Design tokens: the single source of truth for spacing, radii, elevation,
/// motion and responsive breakpoints.
///
/// Screens and components consume these constants instead of scattering
/// magic numbers. See `docs/DESIGN-SYSTEM.md` for the full rationale.

library aftab_design_tokens;

import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

/// Spacing scale (4dp base).
abstract final class AftabSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;

  /// Screen-edge padding by window size class.
  static double screenPadding(double width) {
    if (width >= AftabBreakpoints.expanded) return xl;
    if (width >= AftabBreakpoints.medium) return lg;
    return md;
  }

  /// Horizontal padding of horizontal content rails.
  static double railPadding(double width) => screenPadding(width);
}

/// Corner radii. Deliberately restrained — content, not chrome, is the hero.
abstract final class AftabRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;

  static const Radius rSm = Radius.circular(sm);
  static const Radius rMd = Radius.circular(md);
  static const Radius rLg = Radius.circular(lg);
}

/// Elevation levels (M3). Cards stay flat (tonal surfaces, no shadows).
abstract final class AftabElevation {
  static const double level0 = 0;
  static const double level1 = 1;
  static const double level2 = 3;
  static const double level3 = 6;
}

/// Motion durations and curves. Everything is quick and interruptible.
abstract final class AftabMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration emphasized = Duration(milliseconds: 400);

  /// Standard M3 emphasized-ish easing.
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Cubic(0.2, 0, 0, 1);

  /// Whether the user asked the OS to reduce motion.
  static bool reducedMotion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Duration-aware helper: collapses to zero when motion is reduced.
  static Duration maybe(Duration d, BuildContext context) =>
      reducedMotion(context) ? Duration.zero : d;
}

/// M3 window size classes.
abstract final class AftabBreakpoints {
  /// Phones in portrait.
  static const double medium = 600;

  /// Tablets landscape / small desktop windows.
  static const double expanded = 840;
}

/// How many poster cards fit per rail "page" per form factor.
int railCardCount(double width) {
  if (width >= AftabBreakpoints.expanded) return 6;
  if (width >= AftabBreakpoints.medium) return 4;
  return 3;
}

/// Approximate poster card width for a horizontal rail.
double railCardWidth(double width) {
  final usable = width - 2 * AftabSpacing.railPadding(width);
  return (usable - (railCardCount(width) - 1) * AftabSpacing.sm) /
      railCardCount(width);
}

/// Linear interpolation helper for token-driven animations.
double? lerpToken(double a, double b, double t) => lerpDouble(a, b, t);
