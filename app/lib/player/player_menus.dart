/// Player menus: playback speed, audio track, subtitle track and quality
/// sheets — readable in both themes and both text directions.

library aftab_player_menus;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../core/models.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../utils/format.dart';

const List<double> kSpeedSteps = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

Future<double?> showSpeedSheet(BuildContext context, double current) {
  final s = S.of(context);
  final isFa = Localizations.localeOf(context).languageCode == 'fa';
  return _showSheet<double>(
    context,
    title: s.playbackSpeed,
    current: current,
    values: kSpeedSteps,
    labelOf: (v) => '${formatDouble(v, persian: isFa)}×',
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
    labelOf: (t) => t.title ?? t.language ?? '#${formatInt(int.tryParse(t.id) ?? 0, persian: isFa)}',
  );
}

Future<SubtitleTrack?> showSubtitleSheet(
    BuildContext context, List<SubtitleTrack> tracks) {
  final s = S.of(context);
  return _showSheet<SubtitleTrack>(
    context,
    title: s.subtitleTrack,
    current: null,
    values: <SubtitleTrack>[SubtitleTrack.no(), ...tracks],
    labelOf: (t) => t.id == 'no'
        ? s.subtitleOff
        : t.title ?? t.language ?? t.id,
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
