/// Playback option models + their libmpv property mappings.
///
/// Pure Dart — unit-testable without a player. The thin glue that pushes
/// these onto `NativePlayer` lives in `mpv_bridge.dart`.

library aftab_playback_options;

/// How the video fills the player surface.
enum VideoFit {
  /// Letterboxed to the video's own aspect (mpv default).
  contain,

  /// Stretched to the surface aspect, ignoring the video's own.
  stretch,

  /// Uniformly scaled to cover the surface, cropping the overflow.
  cropFill,

  /// Forced 16:9.
  ratio169,

  /// Forced 4:3.
  ratio43,

  /// Forced 2.35:1 (cinemascope).
  ratio235,
}

/// The mpv properties implementing [fit], given the current surface aspect
/// (width / height of the visible video area).
Map<String, String> videoFitProperties(VideoFit fit, double surfaceAspect) {
  final aspect = switch (fit) {
    // 'no' → trust the container's own aspect.
    VideoFit.contain || VideoFit.cropFill => 'no',
    // The surface's live aspect, e.g. 1.7778 for a 16:9 window.
    VideoFit.stretch => _ratio(surfaceAspect),
    VideoFit.ratio169 => '16:9',
    VideoFit.ratio43 => '4:3',
    VideoFit.ratio235 => '2.35:1',
  };
  return <String, String>{
    'video-aspect-override': aspect,
    // panscan crops uniformly (0 = off, 1 = full cover) while keeping the
    // video's own aspect — that is the "crop to fill" mode.
    'panscan': fit == VideoFit.cropFill ? '1' : '0',
  };
}

String _ratio(double aspect) {
  if (!aspect.isFinite || aspect <= 0) return 'no';
  return aspect.toStringAsFixed(4);
}

/// Zoom is log2: `+1` doubles the size, `-1` halves it (mpv `video-zoom`).
const double kZoomStep = 0.25;
const double kMaxZoom = 2.0;
const double kMinZoom = -1.0;

/// Sleep-timer presets, in minutes; 0 disables the timer.
const List<int> kSleepTimerChoices = <int>[0, 15, 30, 45, 60];

/// Audio/subtitle sync adjustments, in seconds.
const List<double> kDelaySteps = <double>[-0.5, -0.1, 0.1, 0.5];

/// Clamps an accumulated delay to a sane sync range.
double clampDelay(double seconds) =>
    seconds.clamp(-30.0, 30.0).toDouble();

/// `+0.5s` / `−0.2s` / `0.0s` labels with locale-aware digits and sign.
String formatDelayLabel(double seconds, {required bool persian}) {
  final sign = seconds > 0 ? '+' : (seconds < 0 ? '−' : '');
  final abs = seconds == 0 ? '0.0' : seconds.abs().toStringAsFixed(1);
  final digits = persian ? _toPersian(abs) : abs;
  return '$sign${digits}s';
}

/// mpv property payload for a delay (applies to `sub-delay`/`audio-delay`).
String delayPropertyValue(double seconds) => seconds.toStringAsFixed(2);

/// Speed presets shown in the speed sheet; the slider covers the rest.
const List<double> kSpeedChoices = <double>[
  0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0,
];

/// Clamp for the free-form speed slider.
double clampSpeed(double rate) => rate.clamp(0.25, 4.0).toDouble();

const String _latin = '0123456789.';
const String _persianDigits = '۰۱۲۳۴۵۶۷۸۹٫';

String _toPersian(String input) {
  final out = StringBuffer();
  for (final ch in input.runes) {
    final i = _latin.indexOf(String.fromCharCode(ch));
    out.write(i >= 0 ? _persianDigits[i] : String.fromCharCode(ch));
  }
  return out.toString();
}
