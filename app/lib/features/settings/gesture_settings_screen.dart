/// Settings → Player gestures: every touch gesture can be switched on or
/// off, and the double-tap jump distance is adjustable.

library aftab_gesture_settings_screen;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../data/player_settings.dart';
import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../navigation/app_scope.dart';
import '../../player/gestures.dart';
import '../../utils/format.dart';

class GestureSettingsScreen extends StatefulWidget {
  const GestureSettingsScreen({super.key});

  @override
  State<GestureSettingsScreen> createState() => _GestureSettingsScreenState();
}

class _GestureSettingsScreenState extends State<GestureSettingsScreen> {
  PlayerSettingsController? _settings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settings ??= AppScope.playerSettingsOf(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final settings = _settings ?? AppScope.playerSettingsOf(context);
    final isFa = Localizations.localeOf(context).languageCode == 'fa';

    return Scaffold(
      appBar: AppBar(
        title: Text(s.gestureSettingsTitle),
        actions: <Widget>[
          IconButton(
            tooltip: s.resetDefaults,
            icon: const Icon(Icons.restart_alt),
            onPressed: () =>
                unawaited(settings.resetGestures()),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final gestures = settings.gestures;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: AftabSpacing.sm),
            children: <Widget>[
              _header(context, s.gestureSectionSwipes),
              SwitchListTile(
                secondary: const Icon(Icons.volume_up),
                title: Text(s.gestureVolumeSwipe),
                subtitle: Text(s.gestureVolumeSwipeHint),
                value: gestures.volumeSwipe,
                onChanged: (v) => _update(
                    settings, gestures.copyWith(volumeSwipe: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.brightness_6),
                title: Text(s.gestureBrightnessSwipe),
                subtitle: Text(s.gestureBrightnessSwipeHint),
                value: gestures.brightnessSwipe,
                onChanged: (v) => _update(
                    settings, gestures.copyWith(brightnessSwipe: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.swap_horiz),
                title: Text(s.gestureSeekSwipe),
                subtitle: Text(s.gestureSeekSwipeHint),
                value: gestures.seekSwipe,
                onChanged: (v) =>
                    _update(settings, gestures.copyWith(seekSwipe: v)),
              ),
              _header(context, s.gestureSectionTaps),
              SwitchListTile(
                secondary: const Icon(Icons.touch_app),
                title: Text(s.gestureDoubleTapSeek),
                subtitle: Text(s.gestureDoubleTapSeekHint),
                value: gestures.doubleTapSeek,
                onChanged: (v) => _update(
                    settings, gestures.copyWith(doubleTapSeek: v)),
              ),
              if (gestures.doubleTapSeek)
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text(s.gestureDoubleTapSeconds),
                  subtitle: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: <ButtonSegment<int>>[
                      for (final seconds
                          in GestureSettings.kSeekSecondsChoices)
                        ButtonSegment<int>(
                          value: seconds,
                          label: Text(
                              '${formatInt(seconds, persian: isFa)}s'),
                        ),
                    ],
                    selected: <int>{gestures.doubleTapSeekSeconds},
                    onSelectionChanged: (selection) => _update(
                        settings,
                        gestures.copyWith(
                            doubleTapSeekSeconds: selection.first)),
                  ),
                ),
              SwitchListTile(
                secondary: const Icon(Icons.fast_forward),
                title: Text(s.gestureLongPressBoost),
                subtitle: Text(s.gestureLongPressBoostHint),
                value: gestures.longPressSpeedBoost,
                onChanged: (v) => _update(
                    settings, gestures.copyWith(longPressSpeedBoost: v)),
              ),
              const SizedBox(height: AftabSpacing.lg),
            ],
          );
        },
      ),
    );
  }

  void _update(PlayerSettingsController settings, GestureSettings value) {
    unawaited(settings.updateGestures(value));
  }

  Widget _header(BuildContext context, String title) {
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
}
