/// The player: libmpv via `media_kit`, with Persian controls, a seek bar,
/// quality switching, and watch-progress persistence.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/models.dart';
import '../core/store.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.title,
    required this.url,
    required this.item,
    required this.currentQuality,
    this.onPickQuality,
  });

  final String title;
  final String url;
  final CatalogItem item;
  final String currentQuality;

  /// Opens the quality picker of the calling screen (movies only; series
  /// switch quality by picking another episode).
  final Future<void> Function(BuildContext context)? onPickQuality;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  final _store = AftabStore.instance;
  Timer? _progressTimer;

  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    _player.open(Media(widget.url));
    _scheduleHide();
    _restoreProgress();
    // Watch progress: persist every 5 seconds while playing.
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _persistProgress();
    });
    _player.stream.completed.listen((completed) {
      if (completed) _persistProgress();
    });
  }

  Future<void> _restoreProgress() async {
    if (_restored) return;
    _restored = true;
    try {
      final progress = await _store.progress(widget.item);
      if (progress == null || !mounted) return;
      if (progress.positionSeconds > 30 && progress.fraction < 0.95) {
        await _player.seek(Duration(milliseconds: progress.positionSeconds.round() * 1000));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'از ${_fmt(Duration(milliseconds: progress.positionSeconds.round() * 1000))} ادامه می‌دهیم',
              ),
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
    try {
      final position = _player.state.position;
      final duration = _player.state.duration;
      if (duration > Duration.zero) {
        await _store.setProgress(
          widget.item,
          position.inMilliseconds / 1000.0,
          duration.inMilliseconds / 1000.0,
        );
      }
    } catch (_) {
      // Persistence is best-effort.
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _hideTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: MouseRegion(
        onHover: (_) => _showControls(),
        child: GestureDetector(
          onTap: _showControls,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: <Widget>[
              Positioned.fill(
                child: Video(
                  controller: _controller,
                  controls: NoVideoControls,
                ),
              ),
              AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: _buildControls(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: Colors.black54,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: StreamBuilder<Duration>(
        stream: _player.stream.position,
        builder: (context, positionSnap) {
          final position = positionSnap.data ?? Duration.zero;
          return StreamBuilder<Duration>(
            stream: _player.stream.duration,
            builder: (context, durationSnap) {
              final duration = durationSnap.data ?? Duration.zero;
              return Row(
                children: <Widget>[
                  IconButton(
                    tooltip: '۱۰ ثانیه عقب',
                    icon: const Icon(Icons.replay_10),
                    color: Colors.white,
                    onPressed: () => _player.seek(
                      position - const Duration(seconds: 10),
                    ),
                  ),
                  StreamBuilder<bool>(
                    stream: _player.stream.playing,
                    builder: (context, playingSnap) {
                      final playing = playingSnap.data ?? false;
                      return IconButton(
                        tooltip: playing ? 'توقف' : 'پخش',
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                        color: Colors.white,
                        iconSize: 32,
                        onPressed: () => playing
                            ? _player.pause()
                            : _player.play(),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: '۱۰ ثانیه جلو',
                    icon: const Icon(Icons.forward_10),
                    color: Colors.white,
                    onPressed: () => _player.seek(
                      position + const Duration(seconds: 10),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Slider(
                          value: duration > Duration.zero
                              ? position.inMilliseconds
                                  .clamp(0, duration.inMilliseconds)
                                  .toDouble()
                              : 0,
                          max: duration > Duration.zero
                              ? duration.inMilliseconds.toDouble()
                              : 1,
                          onChanged: duration > Duration.zero
                              ? (v) => _player.seek(
                                    Duration(milliseconds: v.round()),
                                  )
                              : null,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              _fmt(position),
                              style: const TextStyle(color: Colors.white70),
                            ),
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(color: Colors.white),
                                ),
                              ),
                            ),
                            Text(
                              _fmt(duration),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.onPickQuality != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TextButton.icon(
                        onPressed: () => widget.onPickQuality!(context),
                        icon: const Icon(Icons.high_quality_outlined,
                            color: Colors.white),
                        label: Text(
                          widget.currentQuality.isEmpty
                              ? 'کیفیت'
                              : widget.currentQuality,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'خروج',
                    icon: const Icon(Icons.close),
                    color: Colors.white,
                    onPressed: () async {
                      await _persistProgress();
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
