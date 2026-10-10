/// The player: libmpv through `media_kit`, rendered as a full Material 3
/// experience on a true-black cinematic stage.
///
/// The v0.2 chrome is rebuilt on the brand M3 scheme (see
/// `design/color_schemes.dart` → `playerColorScheme`): filled tonal play
/// button, themed sliders with a buffered track, M3 sheets and switches.
/// Feature-complete playback: libass subtitle rendering with user-styled
/// fonts/colors/outline/position, external subtitle files, screen fit and
/// zoom, audio/subtitle sync, speed with a free-form slider, sleep timer,
/// hardware decoding — plus touch gestures (volume, brightness, scrub
/// seeking, double-tap jump, hold-to-speed-up), each individually
/// switchable in Settings → Player gestures.

library aftab_player_screen;

import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show DeviceOrientation, SystemChrome, SystemUiMode, rootBundle;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../components/states.dart' show AftabErrorPane;
import '../core/models.dart';
import '../data/app_settings.dart';
import '../data/player_settings.dart';
import '../data/sources.dart';
import '../data/watch_index.dart';
import '../design/color_schemes.dart';
import '../design/tokens.dart';
import '../features/settings/subtitle_appearance_screen.dart';
import '../l10n/app_localizations.dart';
import '../navigation/app_scope.dart';
import '../platform/form_factor.dart';
import '../utils/format.dart';
import 'gestures.dart';
import 'mpv_bridge.dart';
import 'playback_options.dart';
import 'player_menus.dart';
import 'shortcuts.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.title,
    required this.url,
    required this.item,
    required this.currentQuality,
    this.onPickQuality,
    this.isLocal = false,
  });

  /// Plays an already-downloaded file (no network-URL safety check: the
  /// path was created by our own download manager).
  const PlayerScreen.localFile({
    super.key,
    required this.title,
    required String path,
    this.item,
  })  : url = path,
        currentQuality = '',
        onPickQuality = null,
        isLocal = true;

  final String title;
  final String url;
  final CatalogItem? item;
  final String currentQuality;

  /// Opens the quality picker of the calling screen (movies only).
  final Future<void> Function(BuildContext context)? onPickQuality;

  final bool isLocal;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  /// libass renders subtitles into the video texture; the bundled
  /// Vazirmatn is staged into libass's font dir on Android by media_kit.
  late final Player _player = Player(
    configuration: const PlayerConfiguration(
      libass: true,
      libassAndroidFont: 'assets/fonts/Vazirmatn-Regular.ttf',
      libassAndroidFontName: 'Vazirmatn',
    ),
  );
  late final VideoController _controller = VideoController(_player);

  /// Completes once the media is (re)opened — resume waits for it.
  final Completer<void> _opened = Completer<void>();

  bool _controlsVisible = true;
  Timer? _hideTimer;
  Timer? _progressTimer;
  Timer? _overlayTimer;
  Timer? _sleepTicker;
  bool _restored = false;
  bool _watchIndexRecorded = false;
  bool _fullscreen = false;
  double _volumeBeforeMute = 100.0;
  String? _playbackError;

  FormFactor _formFactor = FormFactor.phone;
  Size _surfaceSize = Size.zero;

  // Cached in didChangeDependencies — used in dispose() where inherited
  // lookups are illegal.
  StoreSource? _store;
  WatchIndex? _watchIndex;
  SettingsController? _settings;
  PlayerSettingsController? _playerSettings;

  // ── Gesture feedback state ──────────────────────────────────────────
  PlayerGestureZone _activeZone = PlayerGestureZone.none;
  PlayerGestureZone _overlayZone = PlayerGestureZone.none;
  double _verticalStartY = 0;
  double _volumeBaseline = 100;
  double _brightnessBaseline = 100; // stored as 0..100
  double _activeValue = 100;
  double? _brightness; // 0..1; null = unavailable
  bool _brightnessTouched = false;
  bool _brightnessNoticeShown = false;

  bool _seekScrubbing = false;
  bool _seekOverlayVisible = false;
  double _seekStartDx = 0;
  double _seekStartSeconds = 0;
  double _seekDeltaSeconds = 0;
  Duration _seekTarget = Duration.zero;

  bool _boosting = false;
  double? _rateBeforeBoost;

  // ── Session playback state ──────────────────────────────────────────
  VideoFit _fit = VideoFit.contain;
  double _zoom = 0;
  double _subtitleDelay = 0;
  double _audioDelay = 0;
  int _sleepMinutes = 0;
  DateTime? _sleepDeadline;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
    _scheduleHide();
    _player.stream.completed.listen((completed) {
      if (completed) unawaited(_persistProgress());
    });
    _player.stream.error.listen((message) {
      if (message.isNotEmpty && mounted) {
        setState(() => _playbackError = message);
      }
    });
    _player.stream.playing.listen((playing) {
      if (playing && _playbackError != null && mounted) {
        setState(() => _playbackError = null);
      }
    });
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_persistProgress());
    });
  }

  /// Opens the media only after cosmetic properties are in place, so the
  /// first frame already honors the user's subtitle style and hwdec
  /// preference.
  Future<void> _bootstrap() async {
    await _stageSubtitleFonts();
    final prefs = _playerSettings;
    if (prefs != null) {
      await applySubtitleStyle(_player, prefs.subtitleStyle);
      await applyHwDecoding(_player, prefs.hwDecoding);
    }
    await enableSidecarSubtitleAutoload(_player);
    await _player.open(Media(widget.url));
    if (!_opened.isCompleted) _opened.complete();
    await _initBrightness();
  }

  /// Copies the bundled Vazirmatn weights next to the app data so libass
  /// can resolve them on platforms without a system fontconfig setup.
  /// (Android is handled by media_kit's `libassAndroidFont`.)
  Future<void> _stageSubtitleFonts() async {
    if (Platform.isAndroid) return;
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(p.join(support.path, 'subtitle-fonts'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      for (final asset in const <String>[
        'Vazirmatn-Regular.ttf',
        'Vazirmatn-Bold.ttf',
      ]) {
        final file = File(p.join(dir.path, asset));
        if (!await file.exists()) {
          final data = await rootBundle.load('assets/fonts/$asset');
          await file.writeAsBytes(data.buffer.asUint8List());
        }
      }
      await applySubtitleFontsDir(_player, dir.path);
    } catch (_) {
      // Font staging is cosmetic; system fonts remain usable.
    }
  }

  Future<void> _initBrightness() async {
    try {
      final value = await ScreenBrightness().application;
      _brightness = value.clamp(0.0, 1.0).toDouble();
    } catch (_) {
      _brightness = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    _store ??= scope.store;
    _watchIndex ??= scope.watchIndex;
    _settings ??= scope.settings;
    _playerSettings ??= scope.playerSettings;
    _formFactor = FormFactorResolver.syncGuess(
        MediaQuery.sizeOf(context).shortestSide);
    if (!_restored) {
      _restored = true;
      unawaited(_restoreProgress());
    }
    if (!_watchIndexRecorded && widget.item != null) {
      _watchIndexRecorded = true;
      unawaited(_watchIndex!.record(widget.item!));
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _hideTimer?.cancel();
    _overlayTimer?.cancel();
    _sleepTicker?.cancel();
    unawaited(_persistProgress());
    _player.dispose();
    if (_brightnessTouched) {
      try {
        unawaited(ScreenBrightness().resetApplicationScreenBrightness());
      } catch (_) {
        // Restoring brightness is best-effort.
      }
    }
    if (_fullscreen) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      unawaited(SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]));
    }
    super.dispose();
  }

  // ── Progress persistence ───────────────────────────────────────────────

  Future<void> _restoreProgress() async {
    if (widget.item == null) return;
    if (!(_settings?.autoResume ?? true)) return;
    try {
      await _opened.future;
      final progress = await _store!.progress(widget.item!);
      if (progress == null || !mounted) return;
      if (progress.positionSeconds > 30 && progress.fraction < 0.95) {
        await _player.seek(
            Duration(milliseconds: progress.positionSeconds.round() * 1000));
        if (mounted) {
          final s = S.of(context);
          final isFa = Localizations.localeOf(context).languageCode == 'fa';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(s
                  .resumedFrom(formatSeconds(progress.positionSeconds,
                      persian: isFa))),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (_) {
      // Resume is best-effort.
    }
  }

  Future<void> _persistProgress() async {
    final item = widget.item;
    final store = _store;
    if (item == null || store == null) return;
    try {
      final position = _player.state.position;
      final duration = _player.state.duration;
      if (duration > Duration.zero) {
        await store.setProgress(
          item,
          position.inMilliseconds / 1000.0,
          duration.inMilliseconds / 1000.0,
        );
      }
    } catch (_) {
      // Persistence is best-effort.
    }
  }

  // ── Controls visibility ────────────────────────────────────────────────

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      // On TV, drop focus first so the D-pad never lands on a hidden
      // control.
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  // ── Playback actions ───────────────────────────────────────────────────

  Future<void> _togglePlay() async {
    if (_player.state.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    _showControls();
  }

  Future<void> _seekBy(Duration delta) async {
    await _player.seek(_player.state.position + delta);
    _showControls();
  }

  Future<void> _setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 100.0));
    _showControls();
  }

  Future<void> _toggleMute() async {
    if (_player.state.volume > 0) {
      _volumeBeforeMute = _player.state.volume;
      await _player.setVolume(0.0);
    } else {
      await _player.setVolume(_volumeBeforeMute == 0 ? 100 : _volumeBeforeMute);
    }
    _showControls();
  }

  Future<void> _toggleFullscreen() async {
    if (_fullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      setState(() => _fullscreen = false);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      setState(() => _fullscreen = true);
    }
    _showControls();
  }

  Future<void> _exit() async {
    await _persistProgress();
    if (!mounted) return;
    if (_fullscreen) {
      await _toggleFullscreen();
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _handleAction(PlayerAction action) async {
    switch (action) {
      case PlayerAction.togglePlay:
        await _togglePlay();
      case PlayerAction.seekBack:
        await _seekBy(-bigSeek);
      case PlayerAction.seekForward:
        await _seekBy(bigSeek);
      case PlayerAction.seekBackSmall:
        await _seekBy(-smallSeek);
      case PlayerAction.seekForwardSmall:
        await _seekBy(smallSeek);
      case PlayerAction.volumeUp:
        await _setVolume(_player.state.volume + 10);
      case PlayerAction.volumeDown:
        await _setVolume(_player.state.volume - 10);
      case PlayerAction.toggleMute:
        await _toggleMute();
      case PlayerAction.toggleFullscreen:
        if (_formFactor.isTouch) await _toggleFullscreen();
      case PlayerAction.exit:
        await _exit();
    }
  }

  // ── Touch gestures ──────────────────────────────────────────────────────

  GestureSettings get _gestureConfig =>
      _playerSettings?.gestures ?? const GestureSettings();

  void _onVerticalDragStart(DragStartDetails details, Size size) {
    final zone = gestureZoneFor(
        dx: details.localPosition.dx, width: size.width);
    if (!_gestureConfig.zoneEnabled(zone)) {
      _activeZone = PlayerGestureZone.none;
      return;
    }
    if (zone == PlayerGestureZone.brightness && _brightness == null) {
      _activeZone = PlayerGestureZone.none;
      _notifyBrightnessUnavailable();
      return;
    }
    _activeZone = zone;
    _overlayZone = zone;
    _verticalStartY = details.localPosition.dy;
    _volumeBaseline = _player.state.volume;
    _brightnessBaseline = (_brightness ?? 0.5) * 100;
    _activeValue = zone == PlayerGestureZone.volume
        ? _volumeBaseline
        : _brightnessBaseline;
    _overlayTimer?.cancel();
    if (mounted) setState(() {});
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, Size size) {
    if (_activeZone == PlayerGestureZone.none) return;
    const span = 100.0;
    const dragFactor = 0.75;
    final value = resolveDragValue(
      baseline:
          _activeZone == PlayerGestureZone.volume
              ? _volumeBaseline
              : _brightnessBaseline,
      totalDy: details.localPosition.dy - _verticalStartY,
      dragExtent: size.height * dragFactor,
      span: span,
    );
    setState(() => _activeValue = value);
    if (_activeZone == PlayerGestureZone.volume) {
      unawaited(_player.setVolume(value));
    } else {
      unawaited(_setBrightness(value / 100));
    }
  }

  void _onVerticalDragEnd() {
    if (_activeZone == PlayerGestureZone.none) return;
    _activeZone = PlayerGestureZone.none;
    _scheduleOverlayDismiss(() {
      if (mounted) setState(() => _overlayZone = PlayerGestureZone.none);
    });
  }

  Future<void> _setBrightness(double value01) async {
    try {
      await ScreenBrightness()
          .setApplicationScreenBrightness(value01.clamp(0.0, 1.0));
      _brightness = value01;
      _brightnessTouched = true;
    } catch (_) {
      _brightness = null;
      _notifyBrightnessUnavailable();
    }
  }

  void _notifyBrightnessUnavailable() {
    if (_brightnessNoticeShown || !mounted) return;
    _brightnessNoticeShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).brightnessUnavailable),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!_gestureConfig.seekSwipe) return;
    _seekStartDx = details.localPosition.dx;
    _seekStartSeconds = _player.state.position.inMilliseconds / 1000.0;
    _seekDeltaSeconds = 0;
    _overlayTimer?.cancel();
    setState(() {
      _seekScrubbing = true;
      _seekOverlayVisible = true;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, Size size) {
    if (!_seekScrubbing) return;
    final delta = resolveDragSeek(
      totalDx: details.localPosition.dx - _seekStartDx,
      width: size.width,
      rtl: Directionality.of(context) == TextDirection.rtl,
    );
    final durationSeconds =
        _player.state.duration.inMilliseconds / 1000.0;
    final targetSeconds = durationSeconds > 0
        ? (_seekStartSeconds + delta).clamp(0.0, durationSeconds)
        : (_seekStartSeconds + delta).clamp(0.0, double.infinity);
    setState(() {
      _seekDeltaSeconds = delta;
      _seekTarget = Duration(milliseconds: (targetSeconds * 1000).round());
    });
  }

  void _onHorizontalDragEnd() {
    if (!_seekScrubbing) return;
    final target = _seekStartSeconds + _seekDeltaSeconds;
    _seekScrubbing = false;
    unawaited(
        _player.seek(Duration(milliseconds: (target * 1000).round())));
    _scheduleOverlayDismiss(() {
      if (mounted) setState(() => _seekOverlayVisible = false);
    });
  }

  Future<void> _onLongPressStart(LongPressStartDetails details) async {
    if (!_gestureConfig.longPressSpeedBoost || !_formFactor.isTouch) return;
    _rateBeforeBoost = _player.state.rate;
    await _player.setRate(GestureSettings.speedBoostRate);
    if (mounted) setState(() => _boosting = true);
  }

  Future<void> _onLongPressEnd(LongPressEndDetails details) async {
    final restore = _rateBeforeBoost;
    _rateBeforeBoost = null;
    if (restore != null) {
      await _player.setRate(restore);
    }
    if (mounted) setState(() => _boosting = false);
  }

  void _scheduleOverlayDismiss(VoidCallback hide) {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 600), hide);
  }

  void _doubleTapSeek(TapDownDetails details) {
    if (!_gestureConfig.doubleTapSeek) return;
    final width = _surfaceSize.width;
    if (width <= 0) return;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final physicalX = details.globalPosition.dx;
    // In RTL the "back" zone is on the right in reading order — map to
    // logical thirds so double-tap-back is always under the "start" thumb.
    final logicalX = isRtl ? width - physicalX : physicalX;
    final seconds = _gestureConfig.doubleTapSeekSeconds;
    if (logicalX < width / 3) {
      unawaited(_seekBy(-Duration(seconds: seconds)));
    } else if (logicalX > 2 * width / 3) {
      unawaited(_seekBy(Duration(seconds: seconds)));
    }
  }

  // ── Sleep timer ────────────────────────────────────────────────────────

  void _setSleepTimer(int minutes) {
    _sleepTicker?.cancel();
    _sleepTicker = null;
    setState(() {
      _sleepMinutes = minutes;
      _sleepDeadline = minutes > 0
          ? DateTime.now().add(Duration(minutes: minutes))
          : null;
    });
    if (minutes <= 0) return;
    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final deadline = _sleepDeadline;
      if (deadline == null) return;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        _sleepTicker?.cancel();
        _sleepTicker = null;
        unawaited(_player.pause());
        if (mounted) {
          setState(() {
            _sleepMinutes = 0;
            _sleepDeadline = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context).sleepTimerDone),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  /// Whole minutes left on the sleep timer (for the top-bar chip).
  int get _sleepRemainingMinutes {
    final deadline = _sleepDeadline;
    if (deadline == null) return 0;
    final seconds = deadline.difference(DateTime.now()).inSeconds;
    return seconds <= 0 ? 0 : (seconds / 60).ceil();
  }

  // ── Menus ──────────────────────────────────────────────────────────────

  Future<void> _openSettings() async {
    _hideTimer?.cancel(); // keep controls while a sheet is open
    final s = S.of(context);
    final isFa = Localizations.localeOf(context).languageCode == 'fa';
    final prefs = _playerSettings;
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: AftabSpacing.lg),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AftabSpacing.lg),
              child: Text(s.playerSettings,
                  style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            _sheetHeader(sheetContext, s.settingsPlayback),
            ListTile(
              leading: const Icon(Icons.speed),
              title: Text(s.playbackSpeed),
              trailing: Text(
                  '${formatDouble(_player.state.rate, persian: isFa)}×'),
              onTap: () => Navigator.of(sheetContext).pop('speed'),
            ),
            ListTile(
              leading: const Icon(Icons.aspect_ratio_outlined),
              title: Text(s.videoFit),
              onTap: () => Navigator.of(sheetContext).pop('fit'),
            ),
            ListTile(
              leading: const Icon(Icons.bedtime_outlined),
              title: Text(s.sleepTimer),
              trailing: Text(_sleepMinutes > 0
                  ? '${formatInt(_sleepRemainingMinutes, persian: isFa)} ${s.sleepTimerMinutes}'
                  : s.sleepTimerOff),
              onTap: () => Navigator.of(sheetContext).pop('sleep'),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.memory),
              title: Text(s.hwdecTitle),
              subtitle: Text(s.hwdecHint),
              value: prefs?.hwDecoding ?? true,
              onChanged: (value) {
                unawaited(prefs?.setHwDecoding(value));
                unawaited(applyHwDecoding(_player, value));
              },
            ),
            _sheetHeader(sheetContext, s.sheetSectionAudio),
            ListTile(
              leading: const Icon(Icons.audiotrack_outlined),
              title: Text(s.audioTrack),
              onTap: () => Navigator.of(sheetContext).pop('audio'),
            ),
            ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: Text(s.audioDelay),
              trailing: Text(
                  formatDelayLabel(_audioDelay, persian: isFa)),
              onTap: () => Navigator.of(sheetContext).pop('audio_delay'),
            ),
            _sheetHeader(sheetContext, s.subtitleTrack),
            ListTile(
              leading: const Icon(Icons.subtitles_outlined),
              title: Text(s.subtitleTrack),
              onTap: () => Navigator.of(sheetContext).pop('subtitle'),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(s.subtitleDelay),
              trailing: Text(
                  formatDelayLabel(_subtitleDelay, persian: isFa)),
              onTap: () => Navigator.of(sheetContext).pop('subtitle_delay'),
            ),
            ListTile(
              leading: const Icon(Icons.format_shapes_outlined),
              title: Text(s.subsAppearanceTitle),
              onTap: () => Navigator.of(sheetContext).pop('appearance'),
            ),
            if (widget.onPickQuality != null)
              ListTile(
                leading: const Icon(Icons.high_quality_outlined),
                title: Text(s.qualityLabel),
                subtitle: Text(widget.currentQuality.isEmpty
                    ? s.qualityUnknown
                    : widget.currentQuality),
                onTap: () => Navigator.of(sheetContext).pop('quality'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'speed':
        final speed = await showSpeedSheet(context, _player.state.rate);
        if (speed != null) await _player.setRate(speed);
      case 'fit':
        await showVideoFitSheet(
          context,
          current: _fit,
          zoom: _zoom,
          onFitChanged: _applyFit,
          onZoomChanged: _applyZoom,
        );
      case 'sleep':
        final minutes = await showSleepTimerSheet(context, _sleepMinutes);
        if (minutes != null) _setSleepTimer(minutes);
      case 'audio':
        final track =
            await showAudioSheet(context, _player.state.tracks.audio);
        if (track != null) await _player.setAudioTrack(track);
      case 'audio_delay':
        await showDelaySheet(
          context,
          title: s.audioDelay,
          current: _audioDelay,
          onChanged: (value) {
            setState(() => _audioDelay = value);
            unawaited(setAudioDelay(_player, value));
          },
        );
      case 'subtitle':
        final result =
            await showSubtitleSheet(context, _player.state.tracks.subtitle);
        if (result == null) break;
        if (result.addFile) {
          await _pickSubtitleFile();
        } else if (result.track != null) {
          await _player.setSubtitleTrack(result.track!);
        }
      case 'subtitle_delay':
        await showDelaySheet(
          context,
          title: s.subtitleDelay,
          current: _subtitleDelay,
          onChanged: (value) {
            setState(() => _subtitleDelay = value);
            unawaited(setSubtitleDelay(_player, value));
          },
        );
      case 'appearance':
        _openSubtitleAppearance();
      case 'quality':
        if (widget.onPickQuality != null) {
          await widget.onPickQuality!(context);
        }
    }
    _showControls();
  }

  void _applyFit(VideoFit fit) {
    setState(() => _fit = fit);
    unawaited(applyVideoFit(_player, fit, _surfaceAspect));
  }

  void _applyZoom(double zoom) {
    setState(() => _zoom = zoom);
    unawaited(applyZoom(_player, zoom));
  }

  double get _surfaceAspect {
    final size = _surfaceSize;
    if (size.width <= 0 || size.height <= 0) return 16 / 9;
    return size.width / size.height;
  }

  void _openSubtitleAppearance() {
    final scheme = playerColorScheme(Theme.of(context).colorScheme);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => Theme(
          data: _playerRouteTheme(scheme),
          child: SubtitleAppearanceScreen(
            onApply: (style) => unawaited(applySubtitleStyle(_player, style)),
          ),
        ),
      ),
    );
  }

  Future<void> _pickSubtitleFile() async {
    try {
      final file = await FilePicker.pickFile(
        // Any file: mpv probes the content, so no extension filter is
        // needed (and none survives every platform's picker intact).
        type: FileType.any,
      );
      final path = file?.path;
      if (path == null || !mounted) return;
      final ok = await addExternalSubtitle(_player, path);
      if (!mounted) return;
      final s = S.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? s.subtitleAdded : s.subtitleAddFailed),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      // The picker was cancelled or is unavailable — nothing to do.
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isTv = _formFactor.isTv;
    final scheme = playerColorScheme(Theme.of(context).colorScheme);
    final shortcuts = <ShortcutActivator, Intent>{
      for (final entry
          in (isTv ? tvPlayerShortcuts : desktopPlayerShortcuts).entries)
        SingleActivator(entry.key): _PlayerIntent(entry.value),
      for (final entry in hardwarePlayerShortcuts.entries)
        SingleActivator(entry.key): _PlayerIntent(entry.value),
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          _PlayerIntent: CallbackAction<_PlayerIntent>(
            onInvoke: (intent) {
              unawaited(_handleAction(intent.action));
              return null;
            },
          ),
        },
        child: Scaffold(
          backgroundColor: scheme.surface,
          body: Theme(
            data: Theme.of(context).copyWith(colorScheme: scheme),
            child: MouseRegion(
              onHover: (_) => _showControls(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  _surfaceSize = size;
                  final touch = _formFactor.isTouch;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (_controlsVisible) {
                        setState(() => _controlsVisible = false);
                        _hideTimer?.cancel();
                      } else {
                        _showControls();
                      }
                    },
                    onDoubleTapDown: touch ? _doubleTapSeek : null,
                    onDoubleTap: touch ? () {} : null,
                    onLongPressStart: touch ? _onLongPressStart : null,
                    onLongPressEnd: touch ? _onLongPressEnd : null,
                    onVerticalDragStart:
                        touch ? (d) => _onVerticalDragStart(d, size) : null,
                    onVerticalDragUpdate:
                        touch ? (d) => _onVerticalDragUpdate(d, size) : null,
                    onVerticalDragEnd: touch ? (_) => _onVerticalDragEnd() : null,
                    onVerticalDragCancel:
                        touch ? _onVerticalDragEnd : null,
                    onHorizontalDragStart:
                        touch ? _onHorizontalDragStart : null,
                    onHorizontalDragUpdate:
                        touch ? (d) => _onHorizontalDragUpdate(d, size) : null,
                    onHorizontalDragEnd:
                        touch ? (_) => _onHorizontalDragEnd() : null,
                    onHorizontalDragCancel:
                        touch ? _onHorizontalDragEnd : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        Positioned.fill(
                          child: Video(
                            controller: _controller,
                            controls: NoVideoControls,
                          ),
                        ),
                        const _BottomScrim(),
                        if (_controlsVisible) ...<Widget>[
                          PositionedDirectional(
                            top: 0,
                            start: 0,
                            end: 0,
                            child: _topBar(context, scheme),
                          ),
                          PositionedDirectional(
                            bottom: 0,
                            start: 0,
                            end: 0,
                            child: _bottomControls(context),
                          ),
                        ],
                        _gestureFeedback(context, scheme),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: StreamBuilder<bool>(
                              stream: _player.stream.buffering,
                              initialData: _player.state.buffering,
                              builder: (context, snap) {
                                if (snap.data != true) {
                                  return const SizedBox.shrink();
                                }
                                return Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      CircularProgressIndicator(
                                        color: scheme.primary,
                                      ),
                                      const SizedBox(height: AftabSpacing.md),
                                      Text(
                                        S.of(context).playerBuffering,
                                        style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        if (_playbackError != null &&
                            !_player.state.playing)
                          Positioned.fill(
                            child: AftabErrorPane(
                              title: S.of(context).playbackFailed,
                              message: _playbackError!,
                              icon: Icons.play_circle_outline,
                              onRetry: () {
                                setState(() => _playbackError = null);
                                unawaited(_player.open(Media(widget.url)));
                              },
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _gestureFeedback(BuildContext context, ColorScheme scheme) {
    final s = S.of(context);
    final isFa = Localizations.localeOf(context).languageCode == 'fa';
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Vertical value capsules — on the physical side of the finger.
          if (_overlayZone == PlayerGestureZone.brightness)
            Positioned(
              left: 28,
              top: 0,
              bottom: 0,
              child: _ValueCapsule(
                icon: _brightnessIcon(_activeValue),
                label: s.brightnessLabel,
                value01: _activeValue / 100,
                isFa: isFa,
                scheme: scheme,
              ),
            ),
          if (_overlayZone == PlayerGestureZone.volume)
            Positioned(
              right: 28,
              top: 0,
              bottom: 0,
              child: _ValueCapsule(
                icon: _volumeIcon(_activeValue),
                label: s.playerVolume,
                value01: _activeValue / 100,
                isFa: isFa,
                scheme: scheme,
              ),
            ),
          // Seek scrub feedback above the control area.
          if (_seekOverlayVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 120,
              child: Center(
                child: _SeekScrubOverlay(
                  deltaSeconds: _seekDeltaSeconds,
                  target: _seekTarget,
                  isFa: isFa,
                  scheme: scheme,
                ),
              ),
            ),
          // Hold-to-speed-up chip.
          if (_boosting)
            Positioned(
              top: 96,
              left: 0,
              right: 0,
              child: Center(
                child: _BoostChip(scheme: scheme, isFa: isFa),
              ),
            ),
        ],
      ),
    );
  }

  IconData _brightnessIcon(double value) {
    if (value <= 1) return Icons.brightness_low;
    if (value < 60) return Icons.brightness_medium;
    return Icons.brightness_high;
  }

  IconData _volumeIcon(double value) {
    if (value <= 1) return Icons.volume_off;
    if (value < 50) return Icons.volume_down;
    return Icons.volume_up;
  }

  Widget _sheetHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AftabSpacing.xl,
        top: AftabSpacing.md,
        bottom: AftabSpacing.xs,
      ),
      child: Text(
        title,
        style: theme.textTheme.labelLarge
            ?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }

  Widget _topBar(BuildContext context, ColorScheme scheme) {
    final s = S.of(context);
    final isFa = Localizations.localeOf(context).languageCode == 'fa';
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AftabSpacing.md,
          vertical: AftabSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip:
                  MaterialLocalizations.of(context).backButtonTooltip,
              icon: const Icon(Icons.arrow_back),
              color: scheme.onSurface,
              onPressed: () => unawaited(_exit()),
            ),
            const SizedBox(width: AftabSpacing.sm),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            if (_sleepMinutes > 0)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                    end: AftabSpacing.sm),
                child: _TopChip(
                  icon: Icons.bedtime_outlined,
                  label: formatInt(_sleepRemainingMinutes, persian: isFa),
                  tooltip: s.sleepTimer,
                  scheme: scheme,
                  onTap: () async {
                    final minutes =
                        await showSleepTimerSheet(context, _sleepMinutes);
                    if (minutes != null) _setSleepTimer(minutes);
                  },
                ),
              ),
            if (widget.currentQuality.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsetsDirectional.only(end: AftabSpacing.sm),
                child: _TopChip(
                  icon: Icons.high_quality_outlined,
                  label: widget.currentQuality,
                  tooltip: s.qualityLabel,
                  scheme: scheme,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomControls(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isFa = Localizations.localeOf(context).languageCode == 'fa';
    final wide = MediaQuery.sizeOf(context).width >= 640;

    final seekRow = StreamBuilder<Duration>(
      stream: _player.stream.position,
      builder: (context, positionSnap) {
        final position = positionSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: _player.stream.duration,
          builder: (context, durationSnap) {
            final duration = durationSnap.data ?? Duration.zero;
            return StreamBuilder<Duration>(
              stream: _player.stream.buffer,
              builder: (context, bufferSnap) {
                final buffer = bufferSnap.data ?? Duration.zero;
                final posMs = position.inMilliseconds
                    .clamp(0, duration.inMilliseconds > 0
                        ? duration.inMilliseconds
                        : 0)
                    .toDouble();
                final durMs =
                    duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
                final bufMs = buffer.inMilliseconds
                    .clamp(0, duration.inMilliseconds > 0
                        ? duration.inMilliseconds
                        : 0)
                    .toDouble();
                return Row(
                  children: <Widget>[
                    SizedBox(
                      width: 56,
                      child: Text(
                        formatDuration(position, persian: isFa),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: posMs.clamp(0.0, durMs),
                        max: durMs,
                        secondaryTrackValue:
                            bufMs >= posMs ? bufMs.clamp(0.0, durMs) : null,
                        onChanged: duration > Duration.zero
                            ? (v) => unawaited(_player
                                .seek(Duration(milliseconds: v.round())))
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        formatDuration(duration, persian: isFa),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );

    final playRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          tooltip: s.playerSeekBack,
          icon: const Icon(Icons.replay_10),
          color: scheme.onSurface,
          iconSize: 28,
          onPressed: () => unawaited(_seekBy(-bigSeek)),
        ),
        const SizedBox(width: AftabSpacing.md),
        StreamBuilder<bool>(
          stream: _player.stream.playing,
          initialData: _player.state.playing,
          builder: (context, playingSnap) {
            final playing = playingSnap.data ?? false;
            return IconButton.filled(
              tooltip: playing ? s.playerPause : s.playerPlay,
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              color: scheme.primary,
              style: ButtonStyle(
                backgroundColor:
                    WidgetStatePropertyAll<Color>(scheme.primary),
                foregroundColor:
                    WidgetStatePropertyAll<Color>(scheme.onPrimary),
              ),
              iconSize: 34,
              onPressed: () => unawaited(_togglePlay()),
            );
          },
        ),
        const SizedBox(width: AftabSpacing.md),
        IconButton(
          tooltip: s.playerSeekForward,
          icon: const Icon(Icons.forward_10),
          color: scheme.onSurface,
          iconSize: 28,
          onPressed: () => unawaited(_seekBy(bigSeek)),
        ),
      ],
    );

    final sideButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_formFactor.hasPointer) ...<Widget>[
          StreamBuilder<double>(
            stream: _player.stream.volume,
            initialData: _player.state.volume,
            builder: (context, volumeSnap) {
              final volume = volumeSnap.data ?? 100.0;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 120,
                    child: Slider(
                      value: volume.clamp(0.0, 100.0),
                      max: 100,
                      onChanged: (v) => unawaited(_setVolume(v)),
                    ),
                  ),
                  IconButton(
                    tooltip: s.playerMute,
                    icon: Icon(volume <= 0
                        ? Icons.volume_off
                        : Icons.volume_up),
                    color: scheme.onSurface,
                    onPressed: () => unawaited(_toggleMute()),
                  ),
                ],
              );
            },
          ),
        ],
        IconButton(
          tooltip: s.playerSettings,
          icon: const Icon(Icons.settings_outlined),
          color: scheme.onSurface,
          onPressed: () => unawaited(_openSettings()),
        ),
        if (_formFactor.isTouch)
          IconButton(
            tooltip:
                _fullscreen ? s.playerExitFullscreen : s.playerFullscreen,
            icon: Icon(_fullscreen
                ? Icons.fullscreen_exit
                : Icons.fullscreen),
            color: scheme.onSurface,
            onPressed: () => unawaited(_toggleFullscreen()),
          ),
      ],
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AftabSpacing.lg,
          vertical: AftabSpacing.md,
        ),
        child: wide
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(child: seekRow),
                      const SizedBox(width: AftabSpacing.lg),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      Expanded(child: playRow),
                      sideButtons,
                    ],
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  seekRow,
                  playRow,
                  sideButtons,
                ],
              ),
      ),
    );
  }
}

/// A dark M3 theme for routes pushed on top of the player.
ThemeData _playerRouteTheme(ColorScheme scheme) {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surfaceContainerLowest,
  );
}

// ── Gesture feedback widgets ─────────────────────────────────────────────

/// Vertical capsule showing a live 0..1 value while dragging.
class _ValueCapsule extends StatelessWidget {
  const _ValueCapsule({
    required this.icon,
    required this.label,
    required this.value01,
    required this.isFa,
    required this.scheme,
  });

  final IconData icon;
  final String label;
  final double value01;
  final bool isFa;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final value = value01.clamp(0.0, 1.0).toDouble();
    return Semantics(
      label: label,
      value: '${formatDouble(value * 100, persian: isFa)}%',
      child: Container(
        width: 52,
        height: 220,
        decoration: BoxDecoration(
          color: const Color(0x89000000),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: scheme.onSurface, size: 22),
            const SizedBox(height: AftabSpacing.md),
            SizedBox(
              width: 4,
              height: 108,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: <Widget>[
                  Container(
                    width: 4,
                    height: 108,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                  ),
                  SizedBox(
                    width: 4,
                    height: 108 * value,
                    child: ColoredBox(color: scheme.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AftabSpacing.md),
            Text(
              formatInt((value * 100).round(), persian: isFa),
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered scrub feedback: jump offset + the target timestamp.
class _SeekScrubOverlay extends StatelessWidget {
  const _SeekScrubOverlay({
    required this.deltaSeconds,
    required this.target,
    required this.isFa,
    required this.scheme,
  });

  final double deltaSeconds;
  final Duration target;
  final bool isFa;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final forward = deltaSeconds >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AftabSpacing.lg, vertical: AftabSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(AftabRadius.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(forward ? Icons.fast_forward : Icons.fast_rewind,
              color: scheme.primary),
          const SizedBox(width: AftabSpacing.sm),
          Text(
            '${forward ? '+' : '−'}${formatDouble(deltaSeconds.abs(), persian: isFa)}s',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: AftabSpacing.md),
          Text(
            formatDuration(target, persian: isFa),
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// The "2×" chip shown while the hold-to-speed-up gesture is active.
class _BoostChip extends StatelessWidget {
  const _BoostChip({required this.scheme, required this.isFa});

  final ColorScheme scheme;
  final bool isFa;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AftabSpacing.lg, vertical: AftabSpacing.sm),
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(AftabRadius.lg),
        border: Border.all(color: scheme.primary),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.fast_forward, color: scheme.primary, size: 18),
          const SizedBox(width: AftabSpacing.sm),
          Text(
            '${formatDouble(GestureSettings.speedBoostRate, persian: isFa)}×',
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small tonal chip in the top bar (sleep countdown, quality).
class _TopChip extends StatelessWidget {
  const _TopChip({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.scheme,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final ColorScheme scheme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AftabSpacing.sm,
        vertical: AftabSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: const Color(0x61000000),
        borderRadius: BorderRadius.circular(AftabRadius.sm),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: scheme.onSurfaceVariant, size: 14),
          const SizedBox(width: AftabSpacing.xs),
          Text(
            label,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return Tooltip(message: tooltip, child: chip);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AftabRadius.sm)),
        child: chip,
      ),
    );
  }
}

class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.bottomCenter,
            end: AlignmentDirectional.topCenter,
            stops: <double>[0, 0.4],
            colors: <Color>[Colors.black54, Colors.transparent],
          ),
        ),
      ),
    );
  }
}

class _PlayerIntent extends Intent {
  const _PlayerIntent(this.action);

  final PlayerAction action;
}
