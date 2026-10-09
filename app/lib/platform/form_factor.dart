/// Form factor resolution: phone / tablet / desktop / TV.
///
/// TV detection is a layer cake:
///
/// 1. The user's explicit override (Settings → TV interface) wins.
/// 2. On Android, a tiny method channel asks the platform whether the
///    device advertises the leanback feature (real Android TV).
/// 3. Otherwise a conservative size heuristic: very large display on
///    Android behaves TV-ish.
/// 4. Desktop OSes are always desktop; width then picks rail vs. sidebar.
///
/// The channel answer is cached for the process lifetime — it cannot
/// change without a reboot.

library aftab_form_factor;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';

enum FormFactor { phone, tablet, desktop, tv }

/// Resolves once per process (plus the user override, checked live).
class FormFactorResolver {
  FormFactorResolver({bool tvOverride = false})
      : _tvOverride = tvOverride,
        _channelAnswer = _probeTv();

  final bool _tvOverride;
  final Future<bool?> _channelAnswer;

  static const MethodChannel _channel = MethodChannel('aftab/device');

  /// Ask Android whether the leanback feature exists. Non-Android and
  /// missing-handler cases answer null (unknown).
  static Future<bool?> _probeTv() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return _channel
          .invokeMethod<bool>('isTv')
          .catchError((Object _) => null as bool?);
    }
    return Future<bool?>.value(null);
  }

  /// Synchronous size-class resolution (no TV knowledge).
  static FormFactor bySize(double width, {bool desktopOs = false}) {
    if (desktopOs) return FormFactor.desktop;
    if (width >= AftabBreakpoints.expanded) return FormFactor.tablet;
    if (width >= AftabBreakpoints.medium) return FormFactor.tablet;
    return FormFactor.phone;
  }

  /// Whether the current OS is a desktop environment.
  static bool get desktopOs =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Full resolution: override → channel → heuristic.
  Future<FormFactor> resolve(double shortestSide) async {
    if (_tvOverride) return FormFactor.tv;
    if (desktopOs) return FormFactor.desktop;
    final tv = await _channelAnswer;
    if (tv == true) return FormFactor.tv;
    // Fallback heuristic when the channel is unavailable: Android TV
    // panels report 960dp+ shortest side; large tablets stop well below.
    if (defaultTargetPlatform == TargetPlatform.android &&
        shortestSide >= 900) {
      return FormFactor.tv;
    }
    return bySize(shortestSide);
  }

  /// Synchronous best-effort guess (no channel round-trip): used where
  /// only layout decisions depend on the form factor (e.g. the player).
  static FormFactor syncGuess(double shortestSide) {
    if (desktopOs) return FormFactor.desktop;
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        shortestSide >= 900) {
      return FormFactor.tv;
    }
    if (shortestSide >= AftabBreakpoints.medium) return FormFactor.tablet;
    return FormFactor.phone;
  }
}

/// Convenience accessors on a resolved [FormFactor].
extension FormFactorX on FormFactor {
  bool get isTv => this == FormFactor.tv;

  /// Touch-first (phone/tablet) interaction patterns apply.
  bool get isTouch => this == FormFactor.phone || this == FormFactor.tablet;

  /// Mouse + keyboard patterns apply.
  bool get hasPointer => this == FormFactor.desktop;

  /// D-pad/keyboard focus needs to be unmistakable.
  bool get needsTvFocus => this == FormFactor.tv;

  /// Global text bump for the 10-foot UI.
  double get textScaleFactor => this == FormFactor.tv ? 1.12 : 1.0;
}
