/// Player preferences: subtitle appearance defaults, playback defaults and
/// touch-gesture switches — persisted through the core store's settings
/// map, hot-swappable in both Settings and the player itself.

library aftab_player_settings;

import 'package:flutter/foundation.dart';

import '../player/gestures.dart';
import '../player/subtitle_style.dart';
import 'sources.dart';

/// All persisted keys live under `player.*`.
const String _kSubsPrefix = 'player.subs.';
const String _kHwdec = 'player.hwdec';
const String _kGesturesPrefix = 'player.gestures.';

/// Hardware-decoding mode pushed onto mpv. `auto-safe` avoids decoders
/// known to misbehave — a deliberate choice for a consumer app.
const String kHwdecAuto = 'auto-safe';
const String kHwdecOff = 'no';

/// Player-facing preferences, shared by the Settings screens and the
/// player (which applies them live).
class PlayerSettingsController extends ChangeNotifier {
  PlayerSettingsController({required StoreSource store}) : _store = store;

  final StoreSource _store;

  SubtitleStyle _subtitleStyle = const SubtitleStyle();
  bool _hwDecoding = true;
  GestureSettings _gestures = const GestureSettings();
  bool _loaded = false;

  SubtitleStyle get subtitleStyle => _subtitleStyle;
  bool get hwDecoding => _hwDecoding;
  GestureSettings get gestures => _gestures;
  bool get loaded => _loaded;

  /// Reads persisted values; missing/corrupt entries keep the defaults.
  Future<void> load() async {
    try {
      final subs = <String, String?>{
        for (final key in _subsKeys)
          key: await _store.getSetting('$_kSubsPrefix$key'),
      };
      final hwdec = await _store.getSetting(_kHwdec);
      final gestures = <String, String?>{
        for (final key in _gestureKeys)
          key: await _store.getSetting('$_kGesturesPrefix$key'),
      };
      _subtitleStyle = SubtitleStyle.fromPersisted(subs);
      _hwDecoding = hwdec != '0';
      _gestures = GestureSettings.fromPersisted(gestures);
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // Best-effort: defaults are already in place.
      _loaded = true;
    }
  }

  /// Updates (part of) the subtitle style and persists every field —
  /// the flat store makes partial updates cheap and idempotent.
  Future<void> updateSubtitleStyle(SubtitleStyle style) async {
    if (_subtitleStyle == style) return;
    _subtitleStyle = style;
    notifyListeners();
    await _persistAll(_subtitleStyle.toPersisted(), _kSubsPrefix);
  }

  Future<void> setHwDecoding(bool value) async {
    if (_hwDecoding == value) return;
    _hwDecoding = value;
    notifyListeners();
    await _persist(_kHwdec, value ? '1' : '0');
  }

  Future<void> updateGestures(GestureSettings value) async {
    if (_gestures == value) return;
    _gestures = value;
    notifyListeners();
    await _persistAll(_gestures.toPersisted(), _kGesturesPrefix);
  }

  Future<void> resetSubtitleStyle() =>
      updateSubtitleStyle(const SubtitleStyle());

  Future<void> resetGestures() => updateGestures(const GestureSettings());

  Future<void> _persistAll(Map<String, String> flat, String prefix) async {
    for (final entry in flat.entries) {
      await _persist('$prefix${entry.key}', entry.value);
    }
  }

  Future<void> _persist(String key, String value) async {
    try {
      await _store.setSetting(key, value);
    } catch (_) {
      // Settings are best-effort; the in-memory value still applies.
    }
  }
}

const List<String> _subsKeys = <String>[
  'font',
  'size',
  'color',
  'outline_size',
  'outline_color',
  'background',
  'bold',
  'italic',
  'position',
  'override',
];

const List<String> _gestureKeys = <String>[
  'volume_swipe',
  'brightness_swipe',
  'seek_swipe',
  'double_tap_seek',
  'double_tap_seek_seconds',
  'long_press_speed_boost',
];
