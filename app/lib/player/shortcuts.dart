/// Player keyboard mapping — pure and unit-testable.
///
/// Desktop gets the full shortcut set; TV only the keys that don't fight
/// D-pad focus traversal (arrows move focus there).

library aftab_player_shortcuts;

import 'package:flutter/services.dart';

enum PlayerAction {
  togglePlay,
  seekBack,
  seekForward,
  seekBackSmall,
  seekForwardSmall,
  volumeUp,
  volumeDown,
  toggleMute,
  toggleFullscreen,
  exit,
}

/// The mapping used on desktop (and inside focusable controls on TV).
///
/// `final` (not `const`): [LogicalKeyboardKey] overrides `==`, which the
/// analyzer rightly rejects as a const map key.
final Map<LogicalKeyboardKey, PlayerAction> desktopPlayerShortcuts =
    <LogicalKeyboardKey, PlayerAction>{
  LogicalKeyboardKey.space: PlayerAction.togglePlay,
  LogicalKeyboardKey.keyK: PlayerAction.togglePlay,
  LogicalKeyboardKey.keyJ: PlayerAction.seekBack,
  LogicalKeyboardKey.keyL: PlayerAction.seekForward,
  LogicalKeyboardKey.arrowLeft: PlayerAction.seekBackSmall,
  LogicalKeyboardKey.arrowRight: PlayerAction.seekForwardSmall,
  LogicalKeyboardKey.arrowUp: PlayerAction.volumeUp,
  LogicalKeyboardKey.arrowDown: PlayerAction.volumeDown,
  LogicalKeyboardKey.keyM: PlayerAction.toggleMute,
  LogicalKeyboardKey.keyF: PlayerAction.toggleFullscreen,
  LogicalKeyboardKey.escape: PlayerAction.exit,
};

/// Reduced set on TV: arrows must stay free for D-pad focus traversal.
final Map<LogicalKeyboardKey, PlayerAction> tvPlayerShortcuts =
    <LogicalKeyboardKey, PlayerAction>{
  LogicalKeyboardKey.space: PlayerAction.togglePlay,
  LogicalKeyboardKey.mediaPlayPause: PlayerAction.togglePlay,
  LogicalKeyboardKey.escape: PlayerAction.exit,
};

/// Media/hardware keys that always work.
final Map<LogicalKeyboardKey, PlayerAction> hardwarePlayerShortcuts =
    <LogicalKeyboardKey, PlayerAction>{
  LogicalKeyboardKey.mediaPlayPause: PlayerAction.togglePlay,
  LogicalKeyboardKey.mediaPlay: PlayerAction.togglePlay,
  LogicalKeyboardKey.mediaPause: PlayerAction.togglePlay,
};

/// Resolves the action for [key] under the given platform mode.
PlayerAction? playerActionFor(
  LogicalKeyboardKey key, {
  required bool tv,
}) {
  if (tv) {
    return tvPlayerShortcuts[key] ?? hardwarePlayerShortcuts[key];
  }
  return desktopPlayerShortcuts[key] ?? hardwarePlayerShortcuts[key];
}

/// How far a "small" seek jumps.
const Duration smallSeek = Duration(seconds: 5);

/// How far a "big" seek (J/L or double-tap) jumps.
const Duration bigSeek = Duration(seconds: 10);
