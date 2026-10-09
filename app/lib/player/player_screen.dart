/// The player: libmpv through `media_kit`, wrapped in a cinematic,
/// distraction-free chrome.
///
/// Playback wiring (open / seek / progress persistence every 5 s /
/// resume) is preserved from the v0.1 implementation; the presentation
/// is rebuilt: auto-hiding gradient controls, seek bar with times,
/// volume, playback speed, audio/subtitle track selection, quality
/// switching, keyboard shortcuts, double-tap seek, TV focus support.

library aftab_player_screen;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/models.dart';
import '../data/app_settings.dart';
import '../data/sources.dart';
import '../data/watch_index.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../navigation/app_scope.dart';
import '../platform/form_factor.dart';
import '../utils/format.dart';
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
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  bool _controlsVisible = true;
  Timer? _hideTimer;
  Timer? _progressTimer;
  bool _restored = false;
  bool _watchIndexRecorded = false;
  bool _fullscreen = false;
  double _volumeBeforeMute = 100.0;

  FormFactor _formFactor = FormFactor.phone;

  // Cached in didChangeDependencies — used in dispose() where inherited
  // lookups are illegal.
  StoreSource? _store;
  WatchIndex? _watchIndex;
  SettingsController? _settings;

  @override
  void initState() {
    super.initState();
    _player.open(Media(widget.url));
    _scheduleHide();
    _player.stream.completed.listen((completed) {
      if (completed) unawaited(_persistProgress());
    });
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_persistProgress());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    _store ??= scope.store;
    _watchIndex ??= scope.watchIndex;
    _settings ??= scope.settings;
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
    unawaited(_persistProgress());
    _player.dispose();
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

  // ── Menus ──────────────────────────────────────────────────────────────

  Future<void> _openSettings() async {
    _hideTimer?.cancel(); // keep controls while a sheet is open
    final s = S.of(context);
    final isFa = Localizations.localeOf(context).languageCode == 'fa';
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AftabSpacing.lg),
              child: Text(s.playerSettings,
                  style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.speed),
              title: Text(s.playbackSpeed),
              trailing: Text(
                '${formatDouble(_player.state.rate, persian: isFa)}×',
              ),
              onTap: () => Navigator.of(sheetContext).pop('speed'),
            ),
            ListTile(
              leading: const Icon(Icons.audiotrack_outlined),
              title: Text(s.audioTrack),
              onTap: () => Navigator.of(sheetContext).pop('audio'),
            ),
            ListTile(
              leading: const Icon(Icons.subtitles_outlined),
              title: Text(s.subtitleTrack),
              onTap: () => Navigator.of(sheetContext).pop('subtitle'),
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
      case 'audio':
        final track =
            await showAudioSheet(context, _player.state.tracks.audio);
        if (track != null) await _player.setAudioTrack(track);
      case 'subtitle':
        final track =
            await showSubtitleSheet(context, _player.state.tracks.subtitle);
        if (track != null) await _player.setSubtitleTrack(track);
      case 'quality':
        if (widget.onPickQuality != null) {
          await widget.onPickQuality!(context);
        }
    }
    _showControls();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isTv = _formFactor.isTv;
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
            backgroundColor: Colors.black,
            body: MouseRegion(
              onHover: (_) => _showControls(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_controlsVisible) {
                    setState(() => _controlsVisible = false);
                    _hideTimer?.cancel();
                  } else {
                    _showControls();
                  }
                },
                onDoubleTapDown: _formFactor.isTouch
                    ? (details) => _doubleTapSeek(details)
                    : null,
                onDoubleTap: _formFactor.isTouch ? () {} : null,
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
                        child: _topBar(context),
                      ),
                      PositionedDirectional(
                        bottom: 0,
                        start: 0,
                        end: 0,
                        child: _bottomControls(context),
                      ),
                    ],
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
                                  const CircularProgressIndicator(
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(height: AftabSpacing.md),
                                  Text(
                                    S.of(context).playerBuffering,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }

  void _doubleTapSeek(TapDownDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final physicalX = details.globalPosition.dx;
    // In RTL the "back" zone is on the right in reading order — map to
    // logical thirds so double-tap-back is always under the "start" thumb.
    final logicalX = isRtl ? width - physicalX : physicalX;
    if (logicalX < width / 3) {
      unawaited(_seekBy(-bigSeek));
    } else if (logicalX > 2 * width / 3) {
      unawaited(_seekBy(bigSeek));
    }
  }

  Widget _topBar(BuildContext context) {
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
              tooltip: MaterialLocalizations.of(context)
                  .backButtonTooltip,
              icon: const Icon(Icons.arrow_back),
              color: Colors.white,
              onPressed: () => unawaited(_exit()),
            ),
            const SizedBox(width: AftabSpacing.sm),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
            if (widget.currentQuality.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                    end: AftabSpacing.sm),
                child: _GlassChip(label: widget.currentQuality),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomControls(BuildContext context) {
    final s = S.of(context);
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
            final posMs = position.inMilliseconds
                .clamp(0, duration.inMilliseconds > 0
                    ? duration.inMilliseconds
                    : 0)
                .toDouble();
            final durMs =
                duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
            return Row(
              children: <Widget>[
                SizedBox(
                  width: 56,
                  child: Text(
                    formatDuration(position, persian: isFa),
                    style: _timeStyle,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: posMs.clamp(0.0, durMs),
                    max: durMs,
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
                    style: _timeStyle,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
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
          color: Colors.white,
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
              color: Colors.white,
              style: const ButtonStyle(
                backgroundColor: WidgetStatePropertyAll<Color>(
                    Colors.white24),
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
          color: Colors.white,
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
                    color: Colors.white,
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
          color: Colors.white,
          onPressed: () => unawaited(_openSettings()),
        ),
        if (_formFactor.isTouch)
          IconButton(
            tooltip:
                _fullscreen ? s.playerExitFullscreen : s.playerFullscreen,
            icon: Icon(_fullscreen
                ? Icons.fullscreen_exit
                : Icons.fullscreen),
            color: Colors.white,
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

  static const TextStyle _timeStyle = TextStyle(
    color: Colors.white70,
    fontSize: 12,
  );
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AftabSpacing.sm,
        vertical: AftabSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(AftabRadius.sm),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
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
