/// Player menus: speed, audio/subtitle tracks (+ external subtitle files),
/// screen fit & zoom, sync delays, sleep timer — Material 3 bottom sheets
/// that stay readable in both themes and both text directions.

library aftab_player_menus;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../core/models.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../player/playback_options.dart';
import '../utils/format.dart';

const List<double> kSpeedSteps = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// What the subtitle sheet decided: pick a track, turn them off, or load
/// an external file.
class SubtitleSheetResult {
  const SubtitleSheetResult.pick(this.track) : addFile = false;
  const SubtitleSheetResult.addFile()
      : track = null,
        addFile = true;

  /// The chosen track (`null` only when [addFile]).
  final SubtitleTrack? track;

  /// The user asked for the "load a subtitle file…" flow.
  final bool addFile;
}

Future<double?> showSpeedSheet(BuildContext context, double current) {
  final s = S.of(context);
  final isFa = Localizations.localeOf(context).languageCode == 'fa';
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      var rate = current;
      return SafeArea(
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: AftabSpacing.lg),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(AftabSpacing.lg),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(s.playbackSpeed,
                          style:
                              Theme.of(sheetContext).textTheme.titleMedium),
                    ),
                    Text(
                      '${formatDouble(rate, persian: isFa)}×',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                              color: Theme.of(sheetContext)
                                  .colorScheme
                                  .primary),
                    ),
                  ],
                ),
              ),
              for (final speed in kSpeedChoices)
                ListTile(
                  dense: true,
                  title: Text('${formatDouble(speed, persian: isFa)}×'),
                  trailing: (speed - rate).abs() < 0.01
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    setSheetState(() => rate = speed);
                    Navigator.of(sheetContext).pop(speed);
                  },
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AftabSpacing.xl, vertical: AftabSpacing.md),
                child: Text(s.speedCustomHint,
                    style: Theme.of(sheetContext).textTheme.bodySmall),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AftabSpacing.xl),
                child: Slider(
                  value: rate.clamp(0.25, 4.0).toDouble(),
                  min: 0.25,
                  max: 4.0,
                  divisions: 15,
                  label: '${formatDouble(rate, persian: isFa)}×',
                  onChanged: (v) => setSheetState(() => rate = v),
                  onChangeEnd: (v) => Navigator.of(sheetContext).pop(v),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<AudioTrack?> showAudioSheet(
    BuildContext context, List<AudioTrack> tracks) {
  final s = S.of(context);
  final isFa = Localizations.localeOf(context).languageCode == 'fa';
  return _showSheet<AudioTrack>(
    context,
    title: s.audioTrack,
    current: null,
    values: tracks,
    labelOf: (t) => t.title ??
        t.language ??
        '#${formatInt(int.tryParse(t.id) ?? 0, persian: isFa)}',
  );
}

Future<SubtitleSheetResult?> showSubtitleSheet(
    BuildContext context, List<SubtitleTrack> tracks) {
  final s = S.of(context);
  return showModalBottomSheet<SubtitleSheetResult>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: AftabSpacing.lg),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AftabSpacing.lg),
            child: Text(s.subtitleTrack,
                style: Theme.of(sheetContext).textTheme.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.note_add_outlined),
            title: Text(s.subtitleAddFile),
            subtitle: Text(s.subtitleAddFileHint),
            onTap: () => Navigator.of(sheetContext)
                .pop(const SubtitleSheetResult.addFile()),
          ),
          const Divider(indent: AftabSpacing.lg, endIndent: AftabSpacing.lg),
          for (final track in <SubtitleTrack>[
            SubtitleTrack.no(),
            ...tracks,
          ])
            ListTile(
              leading: track.id == 'no'
                  ? const Icon(Icons.subtitles_off_outlined)
                  : (track.title != null && track.title!.isNotEmpty
                      ? const Icon(Icons.description_outlined)
                      : const Icon(Icons.subtitles_outlined)),
              title: Text(track.id == 'no'
                  ? s.subtitleOff
                  : track.title ?? track.language ?? track.id),
              onTap: () => Navigator.of(sheetContext)
                  .pop(SubtitleSheetResult.pick(track)),
            ),
        ],
      ),
    ),
  );
}

Future<Source?> showQualitySheet(BuildContext context, List<Source> sources) {
  final s = S.of(context);
  return _showSheet<Source>(
    context,
    title: s.selectQuality,
    current: null,
    values: sources,
    labelOf: (source) =>
        source.quality.isEmpty ? s.qualityUnknown : source.quality,
    subtitleOf: (source) => source.type,
  );
}

/// Screen fit + zoom, applied live through the callbacks.
Future<void> showVideoFitSheet(
  BuildContext context, {
  required VideoFit current,
  required double zoom,
  required ValueChanged<VideoFit> onFitChanged,
  required ValueChanged<double> onZoomChanged,
}) {
  final s = S.of(context);
  final isFa = Localizations.localeOf(context).languageCode == 'fa';
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      var fit = current;
      var zoomValue = zoom;
      return SafeArea(
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: AftabSpacing.lg),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(AftabSpacing.lg),
                child: Text(s.videoFit,
                    style: Theme.of(sheetContext).textTheme.titleMedium),
              ),
              for (final choice in VideoFit.values)
                ListTile(
                  dense: true,
                  title: Text(_fitLabel(s, choice)),
                  trailing: choice == fit ? const Icon(Icons.check) : null,
                  onTap: () {
                    setSheetState(() => fit = choice);
                    onFitChanged(choice);
                  },
                ),
              const Divider(indent: AftabSpacing.lg, endIndent: AftabSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AftabSpacing.xl, vertical: AftabSpacing.sm),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text(s.videoZoom)),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.remove),
                      onPressed: () {
                        final next =
                            (zoomValue - kZoomStep).clamp(kMinZoom, kMaxZoom);
                        setSheetState(() => zoomValue = next);
                        onZoomChanged(next);
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AftabSpacing.md),
                      child: Text(
                        formatDouble(
                            zoomValue == 0 ? 1 : _zoomFactor(zoomValue),
                            persian: isFa),
                      ),
                    ),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final next =
                            (zoomValue + kZoomStep).clamp(kMinZoom, kMaxZoom);
                        setSheetState(() => zoomValue = next);
                        onZoomChanged(next);
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AftabSpacing.xl, vertical: AftabSpacing.sm),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text(s.videoZoomReset)),
                    TextButton(
                      onPressed: () {
                        setSheetState(() => zoomValue = 0);
                        onZoomChanged(0);
                      },
                      child: Text(s.resetDefaults),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Sync adjustment for audio or subtitles, applied live through
/// [onChanged] (mpv re-syncs instantly — instant feedback is the point).
Future<void> showDelaySheet(
  BuildContext context, {
  required String title,
  required double current,
  required ValueChanged<double> onChanged,
}) {
  final s = S.of(context);
  final isFa = Localizations.localeOf(context).languageCode == 'fa';
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      var delay = current;
      return SafeArea(
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(AftabSpacing.lg),
                child: Text(title,
                    style: Theme.of(sheetContext).textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: AftabSpacing.md),
                child: Text(
                  formatDelayLabel(delay, persian: isFa),
                  style: Theme.of(sheetContext)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(
                          color: Theme.of(sheetContext).colorScheme.primary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AftabSpacing.xl),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    for (final step in kDelaySteps)
                      IconButton.filledTonal(
                        tooltip:
                            '${step > 0 ? '+' : step < 0 ? '−' : ''}${step.abs().toStringAsFixed(1)}s',
                        icon: Icon(step > 0
                            ? Icons.add
                            : Icons.remove),
                        onPressed: () {
                          final next = clampDelay(delay + step);
                          setSheetState(() => delay = next);
                          onChanged(next);
                        },
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AftabSpacing.md),
                child: Text(
                  s.delayHint,
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: AftabSpacing.lg),
                child: TextButton(
                  onPressed: () {
                    setSheetState(() => delay = 0);
                    onChanged(0);
                  },
                  child: Text(s.delayReset),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Sleep-timer presets; returns the chosen minutes (0 = off).
Future<int?> showSleepTimerSheet(BuildContext context, int currentMinutes) {
  final s = S.of(context);
  final isFa = Localizations.localeOf(context).languageCode == 'fa';
  return showModalBottomSheet<int>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: AftabSpacing.lg),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AftabSpacing.lg),
            child: Text(s.sleepTimer,
                style: Theme.of(sheetContext).textTheme.titleMedium),
          ),
          for (final minutes in kSleepTimerChoices)
            ListTile(
              dense: true,
              title: Text(minutes == 0
                  ? s.sleepTimerOff
                  : '${formatInt(minutes, persian: isFa)} ${s.sleepTimerMinutes}'),
              trailing: minutes == currentMinutes
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(minutes),
            ),
        ],
      ),
    ),
  );
}

String _fitLabel(S s, VideoFit fit) {
  return switch (fit) {
    VideoFit.contain => s.fitContain,
    VideoFit.stretch => s.fitStretch,
    VideoFit.cropFill => s.fitCrop,
    VideoFit.ratio169 => s.fit169,
    VideoFit.ratio43 => s.fit43,
    VideoFit.ratio235 => s.fit235,
  };
}

/// Linear magnification factor of a log2 zoom value.
double _zoomFactor(double zoom) {
  final factor = _pow2(zoom);
  return factor < 10 ? factor : factor.roundToDouble();
}

double _pow2(double exponent) {
  // 2^exponent for the small range we allow (−1 .. 2).
  var result = 1.0;
  if (exponent >= 0) {
    for (var i = 0; i < exponent.round(); i++) {
      result *= 2;
    }
    return result;
  }
  for (var i = 0; i < -exponent.round(); i++) {
    result /= 2;
  }
  return result;
}

Future<T?> _showSheet<T>(
  BuildContext context, {
  required String title,
  required T? current,
  required List<T> values,
  required String Function(T) labelOf,
  String Function(T)? subtitleOf,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: AftabSpacing.lg),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AftabSpacing.lg),
            child: Text(title, style: Theme.of(sheetContext).textTheme.titleMedium),
          ),
          for (final value in values)
            ListTile(
              title: Text(labelOf(value)),
              subtitle:
                  subtitleOf != null ? Text(subtitleOf(value)) : null,
              trailing: value == current
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(value),
            ),
        ],
      ),
    ),
  );
}
