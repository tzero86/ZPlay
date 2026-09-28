/// The player's remote contract: which keys the player answers itself, and
/// which it leaves to the focus system.
///
/// Extracted from `player_screen.dart` so the whole contract is reachable from a
/// widget test. `PlayerScreen` owns a `media_kit` `Player`, which no widget test
/// can build, so anything left inside it can only be tested by a stand-in that
/// agrees with it by hand — and a stand-in is what this replaces.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What the player does with one key from a remote.
///
/// Every branch a television user can reach lives here, and the two rules that
/// make the transport controls reachable are:
///
/// **The arrows are not the player's.** On a television this returns `ignored`
/// for all four, so `WidgetsApp`'s default `DirectionalFocusIntent` binding
/// moves focus between the controls and `ActivateIntent` fires the one holding
/// it. Answering them here would `handled`-stop the event before the binding
/// saw it, which is the state a Chromecast with Google TV reported: the D-pad
/// changed volume and seeked instead of navigating.
///
/// **The hardware volume keys are answered before the focus gate.** They are
/// neither traversal nor activation keys, they arrive as `audioVolumeUp` /
/// `audioVolumeDown` on Android TV, and they have to keep working while a HUD
/// control holds focus - the gate below deliberately stands every other shortcut
/// down then, so leaving them inside it would mean a focused button costs the
/// viewer the volume rocker.
///
/// [pageHasPrimaryFocus] is that gate: while a transport control holds focus the
/// remaining shortcuts stand down, because `select`, `enter` and `space` are
/// `ActivateIntent` keys and the focused control needs them.
KeyEventResult handlePlayerRemoteKey(
  KeyEvent event, {
  required bool isTelevision,
  required bool pageHasPrimaryFocus,
  required bool controlsVisible,
  required bool escapeExitsFullscreen,
  required VoidCallback onShowControls,
  required VoidCallback onFocusControls,
  required VoidCallback onTogglePlayPause,
  required VoidCallback onToggleMute,
  required VoidCallback onToggleFullscreen,
  required VoidCallback onExitFullscreen,
  required VoidCallback onCycleVideoFit,
  required void Function(double delta) onAdjustVolume,
  required void Function(Duration offset) onSeekRelative,
}) {
  if (event is! KeyDownEvent) {
    return KeyEventResult.ignored;
  }
  final key = event.logicalKey;

  // Dedicated hardware keys, ahead of the gate on purpose. See above.
  if (key == LogicalKeyboardKey.audioVolumeUp) {
    onAdjustVolume(0.05);
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.audioVolumeDown) {
    onAdjustVolume(-0.05);
    return KeyEventResult.handled;
  }

  if (!pageHasPrimaryFocus) {
    return KeyEventResult.ignored;
  }

  // A remote's centre button has no pointer equivalent, so it is the only way to
  // raise a HUD that has auto-hidden, and then to step into it. The focus
  // request is what makes that second press land on a real control instead of
  // nowhere: a `FocusNode` no widget owns defers the request forever and never
  // moves focus at all (`focus_manager.dart`, `_doRequestFocus`: `_parent ==
  // null` -> `_requestFocusWhenReparented = true`, which is the state the player
  // shipped with a node it created, requested and disposed but never handed to a
  // widget).
  if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
    if (!controlsVisible) onShowControls();
    onFocusControls();
    return KeyEventResult.handled;
  }

  if (key == LogicalKeyboardKey.keyM) {
    onToggleMute();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
    onTogglePlayPause();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.keyF || key == LogicalKeyboardKey.f11) {
    onToggleFullscreen();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.keyC) {
    onCycleVideoFit();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.escape && escapeExitsFullscreen) {
    onExitFullscreen();
    return KeyEventResult.handled;
  }

  // A pointer device keeps the arrow-key map: there is no focus ring to follow
  // and a keyboard user expects up and down to be the volume. A television hands
  // the arrows to traversal, which is the fix this file exists for.
  if (isTelevision) {
    return KeyEventResult.ignored;
  }

  if (key == LogicalKeyboardKey.arrowUp) {
    onAdjustVolume(0.05);
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowDown) {
    onAdjustVolume(-0.05);
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyJ) {
    onSeekRelative(const Duration(seconds: -10));
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyL) {
    onSeekRelative(const Duration(seconds: 10));
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}