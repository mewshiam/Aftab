/// Player touch gestures: zones, drag math and per-gesture configuration.
///
/// Pure Dart — the pointer plumbing lives in `player_screen.dart`, this file
/// only decides *what a drag means*, so every rule is unit-testable.
///
/// Layout (physical halves, both text directions):
///
/// ```text
/// ┌──────────────────┬──────────────────┐
/// │                  │                  │
/// │  brightness ↕    │   volume ↕       │
/// │                  │                  │
/// └──────────────────┴──────────────────┘
///        ←  horizontal drag: seek  →
/// ```
///
/// The halves stay physical (left = brightness, right = volume) in RTL and
/// LTR alike — matching the muscle memory of every mainstream player.

library aftab_player_gestures;

import 'package:flutter/foundation.dart';

/// Which vertical-drag zone a touch-down landed in.
enum PlayerGestureZone { none, brightness, volume }

/// Resolves the zone from the touch-down x position.
PlayerGestureZone gestureZoneFor({required double dx, required double width}) {
  if (width <= 0) return PlayerGestureZone.none;
  return dx < width / 2
      ? PlayerGestureZone.brightness
      : PlayerGestureZone.volume;
}

/// Per-gesture configuration, persisted in Settings → Gestures.
@immutable
class GestureSettings {
  const GestureSettings({
    this.volumeSwipe = true,
    this.brightnessSwipe = true,
    this.seekSwipe = true,
    this.doubleTapSeek = true,
    this.doubleTapSeekSeconds = 10,
    this.longPressSpeedBoost = true,
  });

  /// Right-half vertical drag adjusts player volume.
  final bool volumeSwipe;

  /// Left-half vertical drag adjusts screen brightness.
  final bool brightnessSwipe;

  /// Horizontal drag scrubs playback position.
  final bool seekSwipe;

  /// Double-tap on the left/right edge seeks backward/forward.
  final bool doubleTapSeek;

  /// Seconds jumped per double-tap (also used by double-tap zones).
  static const List<int> kSeekSecondsChoices = <int>[5, 10, 15, 30];
  final int doubleTapSeekSeconds;

  /// Press-and-hold temporarily plays at 2× speed.
  final bool longPressSpeedBoost;

  /// The temporary rate while the boost gesture is held.
  static const double speedBoostRate = 2.0;

  GestureSettings copyWith({
    bool? volumeSwipe,
    bool? brightnessSwipe,
    bool? seekSwipe,
    bool? doubleTapSeek,
    int? doubleTapSeekSeconds,
    bool? longPressSpeedBoost,
  }) {
    return GestureSettings(
      volumeSwipe: volumeSwipe ?? this.volumeSwipe,
      brightnessSwipe: brightnessSwipe ?? this.brightnessSwipe,
      seekSwipe: seekSwipe ?? this.seekSwipe,
      doubleTapSeek: doubleTapSeek ?? this.doubleTapSeek,
      doubleTapSeekSeconds:
          doubleTapSeekSeconds ?? this.doubleTapSeekSeconds,
      longPressSpeedBoost: longPressSpeedBoost ?? this.longPressSpeedBoost,
    );
  }

  /// Flat map for the settings store (`gestures.*` namespace).
  Map<String, String> toPersisted() => <String, String>{
        'volume_swipe': volumeSwipe ? '1' : '0',
        'brightness_swipe': brightnessSwipe ? '1' : '0',
        'seek_swipe': seekSwipe ? '1' : '0',
        'double_tap_seek': doubleTapSeek ? '1' : '0',
        'double_tap_seek_seconds': doubleTapSeekSeconds.toString(),
        'long_press_speed_boost': longPressSpeedBoost ? '1' : '0',
      };

  /// Restores from the store's flat map; malformed values fall back.
  static GestureSettings fromPersisted(Map<String, String?> persisted) {
    return GestureSettings(
      volumeSwipe: persisted['volume_swipe'] != '0',
      brightnessSwipe: persisted['brightness_swipe'] != '0',
      seekSwipe: persisted['seek_swipe'] != '0',
      doubleTapSeek: persisted['double_tap_seek'] != '0',
      doubleTapSeekSeconds: _choice(
          persisted['double_tap_seek_seconds'], kSeekSecondsChoices, 10),
      longPressSpeedBoost: persisted['long_press_speed_boost'] != '0',
    );
  }

  /// Whether [zone]'s gesture is currently enabled.
  bool zoneEnabled(PlayerGestureZone zone) {
    switch (zone) {
      case PlayerGestureZone.brightness:
        return brightnessSwipe;
      case PlayerGestureZone.volume:
        return volumeSwipe;
      case PlayerGestureZone.none:
        return false;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GestureSettings &&
          other.volumeSwipe == volumeSwipe &&
          other.brightnessSwipe == brightnessSwipe &&
          other.seekSwipe == seekSwipe &&
          other.doubleTapSeek == doubleTapSeek &&
          other.doubleTapSeekSeconds == doubleTapSeekSeconds &&
          other.longPressSpeedBoost == longPressSpeedBoost;

  @override
  int get hashCode => Object.hash(
        volumeSwipe,
        brightnessSwipe,
        seekSwipe,
        doubleTapSeek,
        doubleTapSeekSeconds,
        longPressSpeedBoost,
      );
}

/// New value after dragging `totalDy` pixels over `dragExtent` pixels.
///
/// Dragging **up** (negative dy) increases the value, like every common
/// player. [span] is the full value range (100 for volume, 1.0 for
/// brightness); the drag maps 1:1 across [dragExtent] so a full-height
/// swipe sweeps the whole range.
double resolveDragValue({
  required double baseline,
  required double totalDy,
  required double dragExtent,
  required double span,
}) {
  if (dragExtent <= 0 || span <= 0) return baseline.clamp(0, span);
  final delta = -totalDy / dragExtent * span;
  return (baseline + delta).clamp(0.0, span).toDouble();
}

/// Seek offset (seconds, may be negative) for a horizontal drag of
/// `totalDx` pixels across [width] pixels. The full width equals
/// [fullWidthSeconds]; RTL mirrors the direction.
double resolveDragSeek({
  required double totalDx,
  required double width,
  required bool rtl,
  double fullWidthSeconds = 180,
}) {
  if (width <= 0) return 0;
  final dx = rtl ? -totalDx : totalDx;
  return dx / width * fullWidthSeconds;
}

int _choice(String? raw, List<int> choices, int fallback) {
  final v = int.tryParse(raw ?? '');
  return (v != null && choices.contains(v)) ? v : fallback;
}
