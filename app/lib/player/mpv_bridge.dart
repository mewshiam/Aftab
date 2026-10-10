/// Thin, fault-tolerant glue between our option models and libmpv.
///
/// Everything here funnels into `NativePlayer.setProperty` / `command`.
/// Each call is best-effort: a property mpv rejects (unsupported on some
/// platform, transient state) is logged-and-skipped so playback never dies
/// because a cosmetic preference could not be applied.
///
/// The property vocabulary and formats are verified against the mpv
/// manual:
///
/// * colors — `#AARRGGBB` (alpha **first**);
/// * `sub-font-size` — scaled pixels at a 720p window height;
/// * `video-aspect-override` — `no`, `W:H`, or a plain float ratio;
/// * `panscan` — 0..1 crop-to-fill while keeping the video's own aspect;
/// * `sub-add <url> [<flags> [<title> [<lang>]]]` — runtime track load.

library aftab_mpv_bridge;

import 'package:media_kit/media_kit.dart';

import '../data/player_settings.dart';
import 'playback_options.dart';
import 'subtitle_style.dart';

/// The native player handle, or `null` (web / not yet initialized).
NativePlayer? nativeOf(Player player) {
  final platform = player.platform;
  return platform is NativePlayer ? platform : null;
}

/// Pushes a complete subtitle appearance onto the running player.
Future<void> applySubtitleStyle(Player player, SubtitleStyle style) async {
  final native = nativeOf(player);
  if (native == null) return;
  for (final entry in style.toMpvProperties().entries) {
    await _setProperty(native, entry.key, entry.value);
  }
}

/// Enables or disables hardware decoding at runtime.
Future<void> applyHwDecoding(Player player, bool enabled) async {
  await _setPlayerProperty(player, 'hwdec',
      enabled ? kHwdecAuto : kHwdecOff);
}

/// Applies a video fit mode; [surfaceAspect] (width / height) is only
/// needed by [VideoFit.stretch].
Future<void> applyVideoFit(
    Player player, VideoFit fit, double surfaceAspect) async {
  final native = nativeOf(player);
  if (native == null) return;
  for (final entry in videoFitProperties(fit, surfaceAspect).entries) {
    await _setProperty(native, entry.key, entry.value);
  }
}

/// Applies a zoom delta (log2 scale; 0 = original size).
Future<void> applyZoom(Player player, double zoom) async {
  await _setPlayerProperty(player, 'video-zoom', zoom.toStringAsFixed(3));
}

/// Adjusts subtitle timing relative to the video (seconds, may be negative).
Future<void> setSubtitleDelay(Player player, double seconds) async {
  await _setPlayerProperty(player, 'sub-delay', delayPropertyValue(seconds));
}

/// Adjusts audio timing relative to the video (seconds, may be negative).
Future<void> setAudioDelay(Player player, double seconds) async {
  await _setPlayerProperty(player, 'audio-delay', delayPropertyValue(seconds));
}

/// Loads an external subtitle file as the selected track.
///
/// Returns `false` if the native player is unavailable or mpv rejected the
/// command; the caller then surfaces a non-fatal message.
Future<bool> addExternalSubtitle(Player player, String path,
    {String? title}) async {
  final native = nativeOf(player);
  if (native == null) return false;
  try {
    final name = title ?? _basename(path);
    // 'select' makes the newly added track current immediately.
    await native.command(<String>['sub-add', path, 'select', name, '']);
    return true;
  } catch (_) {
    return false;
  }
}

/// Auto-loads subtitle files that sit next to the video (same or fuzzy
/// name) — useful for downloaded copies with sidecar `.srt` files.
Future<void> enableSidecarSubtitleAutoload(Player player) async {
  await _setPlayerProperty(player, 'sub-auto', 'fuzzy');
}

/// Points libass at a directory of staged font files, so bundled fonts
/// (Vazirmatn) resolve on platforms where they are not system-installed.
Future<void> applySubtitleFontsDir(Player player, String path) async {
  await _setPlayerProperty(player, 'sub-fonts-dir', path);
}

/// Sets a property through the [Player] (resolves the native handle).
Future<void> _setPlayerProperty(
    Player player, String name, String value) async {
  final native = nativeOf(player);
  if (native == null) return;
  await _setProperty(native, name, value);
}

Future<void> _setProperty(NativePlayer native, String name, String value) async {
  try {
    await native.setProperty(name, value);
  } catch (_) {
    // Cosmetic preferences must never break playback.
  }
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash >= 0 ? normalized.substring(slash + 1) : normalized;
}
