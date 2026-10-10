/// Player feature tests: subtitle styling model → mpv property mapping,
/// playback options, touch gestures, persisted player preferences, and
/// the new Settings → Player screens.

library aftab_player_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aftab_media/data/player_settings.dart';
import 'package:aftab_media/features/settings/gesture_settings_screen.dart';
import 'package:aftab_media/features/settings/settings_screen.dart';
import 'package:aftab_media/features/settings/subtitle_appearance_screen.dart';
import 'package:aftab_media/player/gestures.dart';
import 'package:aftab_media/player/playback_options.dart';
import 'package:aftab_media/player/subtitle_style.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mpv color strings', () {
    test('alpha comes first: #AARRGGBB', () {
      expect(toMpvColorString(const Color(0xFFFF8040)), '#FFFF8040');
      expect(toMpvColorString(const Color(0x80FF00FF)), '#80FF00FF');
      expect(toMpvColorString(const Color(0x00000000)), '#00000000');
    });

    test('parsing round-trips 8-digit strings', () {
      expect(parseMpvColorString('#80FF00FF'), const Color(0x80FF00FF));
      expect(parseMpvColorString('#FFFF8040'), const Color(0xFFFF8040));
    });

    test('6-digit strings parse opaque', () {
      expect(parseMpvColorString('#FF8040'), const Color(0xFFFF8040));
    });

    test('invalid input is rejected, not crashed', () {
      expect(parseMpvColorString(null), isNull);
      expect(parseMpvColorString(''), isNull);
      expect(parseMpvColorString('#12345'), isNull);
      expect(parseMpvColorString('blue'), isNull);
    });
  });

  group('SubtitleStyle mpv mapping', () {
    test('defaults map onto documented mpv values', () {
      final props = const SubtitleStyle().toMpvProperties();
      expect(props, containsPair('sub-font', 'Vazirmatn'));
      expect(props, containsPair('sub-font-size', '38'));
      expect(props, containsPair('sub-color', '#FFFFFFFF'));
      expect(props, containsPair('sub-outline-size', '3'));
      expect(props, containsPair('sub-outline-color', '#FF000000'));
      expect(props, containsPair('sub-back-color', '#00000000'));
      expect(props, containsPair('sub-bold', 'no'));
      expect(props, containsPair('sub-italic', 'no'));
      expect(props, containsPair('sub-pos', '100'));
      expect(props, containsPair('sub-ass-override', 'no'));
    });

    test('a fully customized style maps onto yes/force and colors', () {
      const style = SubtitleStyle(
        fontFamily: 'serif',
        fontSize: 72,
        color: Color(0xFFFFFF00),
        outlineSize: 8,
        outlineColor: Color(0xFF0000FF),
        background: Color(0x80000000),
        bold: true,
        italic: true,
        position: 120,
        overrideEmbedded: true,
      );
      final props = style.toMpvProperties();
      expect(props, containsPair('sub-font', 'serif'));
      expect(props, containsPair('sub-font-size', '72'));
      expect(props, containsPair('sub-color', '#FFFFFF00'));
      expect(props, containsPair('sub-outline-size', '8'));
      expect(props, containsPair('sub-outline-color', '#FF0000FF'));
      expect(props, containsPair('sub-back-color', '#80000000'));
      expect(props, containsPair('sub-bold', 'yes'));
      expect(props, containsPair('sub-italic', 'yes'));
      expect(props, containsPair('sub-pos', '120'));
      expect(props, containsPair('sub-ass-override', 'force'));
    });

    test('persistence round-trips exactly', () {
      const style = SubtitleStyle(
        fontFamily: 'monospace',
        fontSize: 55,
        color: Color(0xFF00E5FF),
        outlineSize: 0,
        outlineColor: Color(0xFF112233),
        background: Color(0x40FFFFFF),
        bold: true,
        italic: true,
        position: 90,
        overrideEmbedded: true,
      );
      expect(SubtitleStyle.fromPersisted(style.toPersisted()), style);
    });

    test('corrupt persisted values fall back field by field', () {
      final restored = SubtitleStyle.fromPersisted(const <String, String?>{
        'font': '',
        'size': 'not-a-number',
        'color': '#zzzzzzzz',
        'outline_size': '999',
        'position': '-5',
        'bold': '1',
      });
      expect(restored.fontFamily, SubtitleStyle.defaultFontFamily);
      expect(restored.fontSize, SubtitleStyle.defaultFontSize);
      expect(restored.color, SubtitleStyle.defaultColor);
      expect(restored.outlineSize, SubtitleStyle.maxOutlineSize);
      expect(restored.position, SubtitleStyle.minPosition);
      expect(restored.bold, isTrue);
    });

    test('custom font family validation', () {
      expect(isValidCustomFontFamily('Roboto'), isTrue);
      expect(isValidCustomFontFamily('My Font 2'), isTrue);
      expect(isValidCustomFontFamily(''), isFalse);
      expect(isValidCustomFontFamily('Vazirmatn'), isFalse); // preset
      expect(isValidCustomFontFamily('a' * 49), isFalse);
    });
  });

  group('VideoFit mpv mapping', () {
    test('contain keeps the container aspect and no crop', () {
      expect(videoFitProperties(VideoFit.contain, 16 / 9),
          containsPair('video-aspect-override', 'no'));
      expect(videoFitProperties(VideoFit.contain, 16 / 9),
          containsPair('panscan', '0'));
    });

    test('crop-to-fill crops while keeping the video aspect', () {
      final props = videoFitProperties(VideoFit.cropFill, 4 / 3);
      expect(props, containsPair('video-aspect-override', 'no'));
      expect(props, containsPair('panscan', '1'));
    });

    test('stretch uses the live surface aspect', () {
      expect(videoFitProperties(VideoFit.stretch, 16 / 9),
          containsPair('video-aspect-override', '1.7778'));
      expect(videoFitProperties(VideoFit.stretch, 16 / 9),
          containsPair('panscan', '0'));
    });

    test('forced ratios map onto W:H strings', () {
      expect(videoFitProperties(VideoFit.ratio169, 1),
          containsPair('video-aspect-override', '16:9'));
      expect(videoFitProperties(VideoFit.ratio43, 1),
          containsPair('video-aspect-override', '4:3'));
      expect(videoFitProperties(VideoFit.ratio235, 1),
          containsPair('video-aspect-override', '2.35:1'));
    });

    test('degenerate surface aspect falls back to the video aspect', () {
      expect(videoFitProperties(VideoFit.stretch, 0),
          containsPair('video-aspect-override', 'no'));
      expect(
          videoFitProperties(VideoFit.stretch, double.nan),
          containsPair('video-aspect-override', 'no'));
    });
  });

  group('delays and speeds', () {
    test('delay labels sign and one decimal', () {
      expect(formatDelayLabel(0.5, persian: false), '+0.5s');
      expect(formatDelayLabel(-0.2, persian: false), '−0.2s');
      expect(formatDelayLabel(0, persian: false), '0.0s');
      expect(formatDelayLabel(1.24, persian: false), '+1.2s');
    });

    test('delay labels localize digits to Persian', () {
      expect(formatDelayLabel(0.5, persian: true), '+۰٫۵s');
      expect(formatDelayLabel(-1.24, persian: true), '−۱٫۲s');
    });

    test('delay clamping and property serialization', () {
      expect(clampDelay(31), 30);
      expect(clampDelay(-40), -30);
      expect(clampDelay(0.4), 0.4);
      expect(delayPropertyValue(1.234), '1.23');
      expect(delayPropertyValue(-0.5), '-0.50');
    });

    test('speed clamping', () {
      expect(clampSpeed(0.1), 0.25);
      expect(clampSpeed(9), 4.0);
      expect(clampSpeed(1.75), 1.75);
    });
  });

  group('gesture zones and drag math', () {
    test('physical halves map to brightness and volume', () {
      expect(gestureZoneFor(dx: 0, width: 400),
          PlayerGestureZone.brightness);
      expect(gestureZoneFor(dx: 199, width: 400),
          PlayerGestureZone.brightness);
      expect(gestureZoneFor(dx: 200, width: 400), PlayerGestureZone.volume);
      expect(gestureZoneFor(dx: 399, width: 400), PlayerGestureZone.volume);
      expect(gestureZoneFor(dx: 10, width: 0), PlayerGestureZone.none);
    });

    test('zone gating follows the persisted switches', () {
      const off = GestureSettings(
        volumeSwipe: false,
        brightnessSwipe: false,
      );
      expect(off.zoneEnabled(PlayerGestureZone.volume), isFalse);
      expect(off.zoneEnabled(PlayerGestureZone.brightness), isFalse);
      expect(off.zoneEnabled(PlayerGestureZone.none), isFalse);
      const on = GestureSettings();
      expect(on.zoneEnabled(PlayerGestureZone.volume), isTrue);
    });

    test('dragging up increases the value; clamped to the span', () {
      // Up by a quarter of the extent → +25 of a 100 span.
      expect(
        resolveDragValue(
            baseline: 50, totalDy: -100, dragExtent: 400, span: 100),
        75,
      );
      expect(
        resolveDragValue(
            baseline: 90, totalDy: -400, dragExtent: 400, span: 100),
        100, // clamped, not 190
      );
      expect(
        resolveDragValue(
            baseline: 10, totalDy: 400, dragExtent: 400, span: 100),
        0,
      );
    });

    test('degenerate drag extents keep the baseline', () {
      expect(
        resolveDragValue(baseline: 42, totalDy: -200, dragExtent: 0, span: 100),
        42,
      );
    });

    test('horizontal scrub maps to seconds and mirrors in RTL', () {
      // Full width = 180 s by default.
      expect(resolveDragSeek(totalDx: 200, width: 400, rtl: false), 90);
      expect(resolveDragSeek(totalDx: -200, width: 400, rtl: false), -90);
      // RTL mirrors: dragging toward physical left seeks forward.
      expect(resolveDragSeek(totalDx: -200, width: 400, rtl: true), 90);
      expect(resolveDragSeek(totalDx: 200, width: 400, rtl: true), -90);
      expect(resolveDragSeek(totalDx: 120, width: 0, rtl: false), 0);
    });

    test('gesture settings round-trip and reject bad values', () {
      const gestures = GestureSettings(
        volumeSwipe: false,
        doubleTapSeekSeconds: 30,
        longPressSpeedBoost: false,
      );
      expect(GestureSettings.fromPersisted(gestures.toPersisted()), gestures);
      final bad = GestureSettings.fromPersisted(const <String, String?>{
        'double_tap_seek_seconds': '7',
        'volume_swipe': '0',
      });
      expect(bad.doubleTapSeekSeconds, 10); // not a choice → default
      expect(bad.volumeSwipe, isFalse);
      expect(GestureSettings.fromPersisted(const <String, String?>{}),
          const GestureSettings());
    });
  });

  group('PlayerSettingsController', () {
    test('defaults are libass-friendly and all gestures on', () async {
      final store = FakeStoreSource();
      final controller = PlayerSettingsController(store: store);
      await controller.load();
      expect(controller.subtitleStyle, const SubtitleStyle());
      expect(controller.hwDecoding, isTrue);
      expect(controller.gestures, const GestureSettings());
      expect(controller.loaded, isTrue);
    });

    test('load reflects persisted values', () async {
      final store = FakeStoreSource();
      await store.setSetting('player.subs.font', 'serif');
      await store.setSetting('player.subs.size', '72');
      await store.setSetting('player.subs.bold', '1');
      await store.setSetting('player.subs.color', '#FFFFFF00');
      await store.setSetting('player.hwdec', '0');
      await store.setSetting('player.gestures.volume_swipe', '0');
      await store.setSetting('player.gestures.double_tap_seek_seconds', '30');
      final controller = PlayerSettingsController(store: store);
      await controller.load();
      expect(controller.subtitleStyle.fontFamily, 'serif');
      expect(controller.subtitleStyle.fontSize, 72);
      expect(controller.subtitleStyle.bold, isTrue);
      expect(controller.subtitleStyle.color, const Color(0xFFFFFF00));
      expect(controller.hwDecoding, isFalse);
      expect(controller.gestures.volumeSwipe, isFalse);
      expect(controller.gestures.doubleTapSeekSeconds, 30);
    });

    test('updates persist under the player.* namespace', () async {
      final store = FakeStoreSource();
      final controller = PlayerSettingsController(store: store);
      await controller.updateSubtitleStyle(
          const SubtitleStyle().copyWith(fontSize: 60, italic: true));
      await controller.setHwDecoding(false);
      await controller.updateGestures(
          const GestureSettings().copyWith(seekSwipe: false));

      expect(await store.getSetting('player.subs.size'), '60');
      expect(await store.getSetting('player.subs.italic'), '1');
      expect(await store.getSetting('player.subs.font'), 'Vazirmatn');
      expect(await store.getSetting('player.hwdec'), '0');
      expect(await store.getSetting('player.gestures.seek_swipe'), '0');
      // Everything else persisted alongside.
      expect(await store.getSetting('player.subs.position'), '100');
      expect(await store.getSetting('player.gestures.double_tap_seek'), '1');
    });

    test('resets return to defaults and persist them', () async {
      final store = FakeStoreSource();
      await store.setSetting('player.subs.size', '90');
      await store.setSetting('player.gestures.volume_swipe', '0');
      final controller = PlayerSettingsController(store: store);
      await controller.load();
      await controller.resetSubtitleStyle();
      await controller.resetGestures();
      expect(controller.subtitleStyle.fontSize, 38);
      expect(controller.gestures.volumeSwipe, isTrue);
      expect(await store.getSetting('player.subs.size'), '38');
      expect(await store.getSetting('player.gestures.volume_swipe'), '1');
    });
  });

  group('SubtitleAppearanceScreen', () {
    testWidgets('renders the preview and switches update the style',
        (tester) async {
      // A tall viewport keeps every section of the editor on-screen.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = FakeStoreSource();
      final controller = PlayerSettingsController(store: store);
      await controller.load();
      await tester.pumpWidget(testApp(
        store: store,
        playerSettings: controller,
        child: const SubtitleAppearanceScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ظاهر زیرنویس'), findsOneWidget);
      // Twice: the preview draws an outline stroke layer + the fill layer.
      expect(find.text('زیرنویس نمونه — سلام دنیا'), findsNWidgets(2));
      expect(find.text('ضخیم'), findsOneWidget);

      // Bold is the first switch on the screen.
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      expect(controller.subtitleStyle.bold, isTrue);
      expect(await store.getSetting('player.subs.bold'), '1');
    });
  });

  group('GestureSettingsScreen', () {
    testWidgets('toggles and jump distance update persisted gestures',
        (tester) async {
      final store = FakeStoreSource();
      final controller = PlayerSettingsController(store: store);
      await controller.load();
      await tester.pumpWidget(testApp(
        store: store,
        playerSettings: controller,
        child: const GestureSettingsScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ژست‌های پخش‌کننده'), findsOneWidget);
      expect(find.text('کشیدن برای صدا'), findsOneWidget);

      // Volume swipe is the first switch.
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      expect(controller.gestures.volumeSwipe, isFalse);
      expect(await store.getSetting('player.gestures.volume_swipe'), '0');

      // Double-tap jump distance: pick 30 s.
      await tester.tap(find.text('۳۰s'));
      await tester.pumpAndSettle();
      expect(controller.gestures.doubleTapSeekSeconds, 30);
      expect(
          await store.getSetting('player.gestures.double_tap_seek_seconds'),
          '30');
    });
  });

  group('SettingsScreen player section', () {
    testWidgets('exposes subtitle style, gestures and hardware decoding',
        (tester) async {
      final store = FakeStoreSource();
      final controller = PlayerSettingsController(store: store);
      await controller.load();
      await tester.pumpWidget(testApp(
        store: store,
        playerSettings: controller,
        child: const SettingsScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('پخش‌کننده'), findsOneWidget);
      expect(find.text('ظاهر زیرنویس'), findsOneWidget);
      expect(find.text('ژست‌های پخش‌کننده'), findsOneWidget);
      expect(find.text('رمزینه‌سازی سخت‌افزاری'), findsOneWidget);
    });
  });
}
