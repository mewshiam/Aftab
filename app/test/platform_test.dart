/// Platform adaptation logic: form-factor resolution and player
/// keyboard mappings.

library aftab_platform_test;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aftab_media/platform/form_factor.dart';
import 'package:aftab_media/player/shortcuts.dart';

void main() {
  group('FormFactorResolver.bySize', () {
    test('compact widths are phones', () {
      expect(
        FormFactorResolver.bySize(360, desktopOs: false),
        FormFactor.phone,
      );
      expect(
        FormFactorResolver.bySize(599, desktopOs: false),
        FormFactor.phone,
      );
    });

    test('medium and expanded widths are tablets', () {
      expect(
        FormFactorResolver.bySize(600, desktopOs: false),
        FormFactor.tablet,
      );
      expect(
        FormFactorResolver.bySize(1280, desktopOs: false),
        FormFactor.tablet,
      );
    });

    test('desktop OS is desktop regardless of width', () {
      expect(
        FormFactorResolver.bySize(400, desktopOs: true),
        FormFactor.desktop,
      );
    });
  });

  group('FormFactorResolver.syncGuess', () {
    test('desktop OS wins', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(FormFactorResolver.syncGuess(300), FormFactor.desktop);
      debugDefaultTargetPlatformOverride = null;
    });

    test('very large Android displays guess TV', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(FormFactorResolver.syncGuess(960), FormFactor.tv);
      expect(FormFactorResolver.syncGuess(500), FormFactor.phone);
      debugDefaultTargetPlatformOverride = null;
    });

    test('medium Android sizes are tablets, not TV', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(FormFactorResolver.syncGuess(700), FormFactor.tablet);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('FormFactorX', () {
    test('flags', () {
      expect(FormFactor.tv.isTv, isTrue);
      expect(FormFactor.tv.needsTvFocus, isTrue);
      expect(FormFactor.phone.isTouch, isTrue);
      expect(FormFactor.desktop.hasPointer, isTrue);
      expect(FormFactor.tv.textScaleFactor, 1.12);
      expect(FormFactor.phone.textScaleFactor, 1.0);
    });
  });

  group('playerActionFor', () {
    test('desktop: arrows seek, space plays', () {
      expect(
        playerActionFor(LogicalKeyboardKey.arrowLeft, tv: false),
        PlayerAction.seekBackSmall,
      );
      expect(
        playerActionFor(LogicalKeyboardKey.space, tv: false),
        PlayerAction.togglePlay,
      );
      expect(
        playerActionFor(LogicalKeyboardKey.keyM, tv: false),
        PlayerAction.toggleMute,
      );
      expect(
        playerActionFor(LogicalKeyboardKey.escape, tv: false),
        PlayerAction.exit,
      );
    });

    test('TV: arrows stay free for D-pad traversal', () {
      expect(playerActionFor(LogicalKeyboardKey.arrowLeft, tv: true), isNull);
      expect(playerActionFor(LogicalKeyboardKey.arrowUp, tv: true), isNull);
      expect(
        playerActionFor(LogicalKeyboardKey.space, tv: true),
        PlayerAction.togglePlay,
      );
    });

    test('hardware media keys always work', () {
      expect(
        playerActionFor(LogicalKeyboardKey.mediaPlayPause, tv: true),
        PlayerAction.togglePlay,
      );
      expect(
        playerActionFor(LogicalKeyboardKey.mediaPlayPause, tv: false),
        PlayerAction.togglePlay,
      );
    });

    test('unmapped keys resolve to nothing', () {
      expect(playerActionFor(LogicalKeyboardKey.keyZ, tv: false), isNull);
    });

    test('seek magnitudes', () {
      expect(smallSeek, const Duration(seconds: 5));
      expect(bigSeek, const Duration(seconds: 10));
    });
  });
}
