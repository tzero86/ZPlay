/// Drives the player with the key events a remote sends, and pins what each one
/// does.
///
/// Reported on a Chromecast with Google TV: "when you get to the player the
/// remote button just stops working, except to go back - you cannot control the
/// player timeline, subs, volume, etc". Back still worked because it is the
/// Android navigation channel, not the focus system; every other key went
/// nowhere.
///
/// Two causes, both in `lib/pages/player/player_screen.dart`:
///
/// 1. The page's own `Focus` node wraps the whole body, so its rect is the whole
///    screen, and it held primary focus on entry. Directional traversal from a
///    node searches for a neighbour *outside* that node's rectangle
///    (`_sortAndFilterHorizontally` / `_sortAndFilterVertically` in
///    `focus_traversal.dart`), and every transport control is *inside* it. The
///    search finds nothing, `FocusScopeNode`'s default
///    `TraversalEdgeBehavior.stop` declines to wrap, and the arrow key does
///    nothing at all. `skipTraversal` on that node is the fix, exactly as
///    `lib/shell/skip_page_shell_focus.dart` fixed the same shape for slot pages.
/// 2. The centre button handed focus to a `FocusNode` no widget ever owned, and
///    `_doRequestFocus` defers that request forever when `_parent == null`
///    (`focus_manager.dart`), so the press did nothing.
///
/// `PlayerScreen` itself cannot be pumped - it owns a `media_kit` `Player` - so
/// this file takes both halves that matter whole: `handlePlayerRemoteKey` is the
/// shipped handler and `PlayerTransport` is the shipped bar. Only the ~30 lines
/// of skeleton around them are mirrored, and those lines are where the bug was.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/widgets/common/focusable_card.dart';
import 'package:zplay/widgets/player/player_glass.dart';
import 'package:zplay/widgets/player/player_remote_keys.dart';
import 'package:zplay/widgets/player/player_seek_bar.dart';
import 'package:zplay/widgets/player/player_transport.dart';
import 'package:zplay/widgets/player/player_volume_control.dart';

/// The screen's own state, stood in for: `PlayerScreen` needs a `media_kit`
/// player and a real stream, and none of that plays any part in a focus test.
class _Screen {
  _Screen({required this.television, this.skipPageTraversal = true});

  final bool television;

  /// Whether the page node is marked skipped, the way `PlayerScreen.initState`
  /// does on a television. False reproduces the shipped bug.
  final bool skipPageTraversal;

  final FocusNode page = FocusNode(debugLabel: 'PlayerPage');
  final FocusNode entry = FocusNode(debugLabel: 'PlayerHudEntry');
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration?> buffered = ValueNotifier(null);

  /// Every action a control fired, in order.
  final List<String> calls = <String>[];

  Duration duration = const Duration(minutes: 10);
  double volume = 1.0;
  bool playing = true;
  bool muted = false;
  bool fullscreen = false;
  bool subtitlesActive = false;

  void dispose() {
    page.dispose();
    entry.dispose();
    position.dispose();
    buffered.dispose();
  }
}

/// The player's HUD skeleton around the real transport bar.
class _PlayerHarness extends StatefulWidget {
  const _PlayerHarness({required this.screen});

  final _Screen screen;

  @override
  State<_PlayerHarness> createState() => _PlayerHarnessState();
}

class _PlayerHarnessState extends State<_PlayerHarness> {
  _Screen get _s => widget.screen;

  @override
  void initState() {
    super.initState();
    // `PlayerScreen.initState`, in the same order. `skipPageTraversal: false` is
    // the shipped state, kept as the control case: the page node took focus and
    // nothing ever handed it to a control.
    if (_s.television && _s.skipPageTraversal) {
      _s.page.skipTraversal = true;
      _s.entry.requestFocus();
    }
  }

  void _say(String call) => _s.calls.add(call);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Focus(
          focusNode: _s.page,
          autofocus: true,
          onKeyEvent: (node, event) => handlePlayerRemoteKey(
            event,
            isTelevision: _s.television,
            pageHasPrimaryFocus: node.hasPrimaryFocus,
            controlsVisible: true,
            escapeExitsFullscreen: _s.fullscreen,
            onShowControls: () => _say('show-controls'),
            onFocusControls: () => _s.entry.requestFocus(),
            onTogglePlayPause: () {
              setState(() => _s.playing = !_s.playing);
              _say('playpause');
            },
            onToggleMute: () {
              setState(() {
                _s.muted = !_s.muted;
                _s.volume = _s.muted ? 0 : 1;
              });
              _say('mute');
            },
            onToggleFullscreen: () {
              setState(() => _s.fullscreen = !_s.fullscreen);
              _say('fullscreen');
            },
            onExitFullscreen: () {
              setState(() => _s.fullscreen = false);
              _say('exit-fullscreen');
            },
            onCycleVideoFit: () => _say('fit'),
            onAdjustVolume: (delta) {
              setState(() => _s.volume += delta);
              _say('volume:${_s.volume.toStringAsFixed(2)}');
            },
            onSeekRelative: (offset) {
              _say('relative:${offset.inSeconds}');
            },
          ),
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.black)),
              // The bottom transport bar, behind the same
              // IgnorePointer + AnimatedOpacity the player hides the HUD with.
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: false,
                  child: AnimatedOpacity(
                    opacity: 1,
                    duration: Duration.zero,
                    child: PlayerTransport(
                      isPlaying: _s.playing,
                      position: _s.position.value,
                      duration: _s.duration,
                      buffered: _s.buffered.value,
                      positionListenable: _s.position,
                      bufferedListenable: _s.buffered,
                      volume: _s.volume,
                      isMuted: _s.muted,
                      playbackRate: 1.0,
                      isSubtitlesActive: _s.subtitlesActive,
                      isSubSyncActive: false,
                      isAudioActive: false,
                      isFullscreen: _s.fullscreen,
                      entryFocusNode: _s.entry,
                      onPlayPause: () {
                        setState(() => _s.playing = !_s.playing);
                        _say('playpause');
                      },
                      onSeek: (target) {
                        _s.position.value = target;
                        _say('seek:${target.inSeconds}');
                      },
                      onSeekBack10: () => _say('seek-10'),
                      onSeekForward10: () => _say('seek+10'),
                      onVolumeChanged: (value) {
                        setState(() => _s.volume = value);
                        _say('volume:${value.toStringAsFixed(2)}');
                      },
                      onToggleMute: () {
                        setState(() => _s.muted = !_s.muted);
                        _say('mute');
                      },
                      onToggleAspectMenu: () => _say('menu:aspect'),
                      onToggleSpeedMenu: () => _say('menu:speed'),
                      onToggleAudioMenu: () => _say('menu:audio'),
                      onToggleSubtitleMenu: () => _say('menu:subtitle'),
                      onToggleSubSync: () => _say('menu:subsync'),
                      onToggleFullscreen: () {
                        setState(() => _s.fullscreen = !_s.fullscreen);
                        _say('fullscreen');
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pumps the harness on the canvas a Chromecast with Google TV reports.
///
/// 1920x1080 at device pixel ratio 2 is 960x540 dp, so `PlayerTransport` is not
/// `isCompact` and draws the full volume control and the whole right-hand row.
/// Bound through `tester.view`, because a `MediaQuery` wrapped around
/// `MaterialApp` is discarded by it.
Future<void> _pump(
  WidgetTester tester,
  _Screen screen, {
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 2.0;
  DeviceProfile.debugSetTelevision(value: screen.television);
  await tester.pumpWidget(_PlayerHarness(screen: screen));
  if (settle) await tester.pump();
}

/// The control holding primary focus, named the way a person would name it.
///
/// Read from the primary node's own ancestors rather than by watching a label:
/// `PlayerIconButton` keeps its name in `tooltip`, which is what the player
/// shows on a pointer and what names the button on a television.
String _focused(WidgetTester tester, _Screen screen) {
  final node = FocusManager.instance.primaryFocus;
  if (node == null) return 'none';
  final of = find.byElementPredicate((e) => e == node.context);

  if (tester.any(
    find.ancestor(
      of: of,
      matching: find.byWidgetPredicate(
        (w) => w is FocusableCard && w.focusNode == screen.entry,
      ),
    ),
  )) {
    return 'Play/Pause';
  }
  final icon = find.ancestor(of: of, matching: find.byType(PlayerIconButton));
  if (tester.any(icon)) {
    return tester.widget<PlayerIconButton>(icon.first).tooltip ?? 'unnamed-icon';
  }
  if (tester.any(find.ancestor(of: of, matching: find.byType(PlayerVolumeControl)))) {
    return 'Volume';
  }
  if (tester.any(find.ancestor(of: of, matching: find.byType(PlayerSeekBar)))) {
    return 'Seek';
  }
  if (tester.any(find.ancestor(of: of, matching: find.byType(PlayerTransport)))) {
    return 'unclassified-transport-control';
  }
  return 'page';
}

Future<void> _tap(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

/// Walks the transport from the entry control, one step per arrow press, and
/// reports the controls focus landed on in order.
Future<List<String>> _sweep(WidgetTester tester, _Screen screen, {int steps = 12}) async {
  final seen = <String>[_focused(tester, screen)];
  for (var i = 0; i < steps; i++) {
    await _tap(tester, LogicalKeyboardKey.arrowRight);
    final label = _focused(tester, screen);
    if (label == seen.first) break;
    if (!seen.contains(label)) seen.add(label);
  }
  return seen;
}

/// Walks right from the play button until [label] holds focus.
///
/// Restarted from the entry every time, because the row does not wrap; every
/// control is therefore reached by moving the D-pad from the control the HUD
/// opens on, not from wherever the previous assertion left focus.
Future<void> _walkTo(WidgetTester tester, _Screen screen, String label) async {
  screen.entry.requestFocus();
  await tester.pump();
  for (var step = 0; step < 24; step++) {
    if (_focused(tester, screen) == label) return;
    await _tap(tester, LogicalKeyboardKey.arrowRight);
  }
  expect(_focused(tester, screen), label,
      reason: '$label is not reachable by moving right from the play button');
}

/// The colour the ring around [of] is painted in, or null when it paints none.
///
/// The seek bar and the volume track both draw their ring as a
/// `foregroundDecoration` border that is transparent until the track holds focus,
/// which is the whole indicator a remote user gets on a slider.
Color? _ringColour(WidgetTester tester, Finder of) {
  for (final container in tester.widgetList<Container>(
    find.descendant(of: of, matching: find.byType(Container)),
  )) {
    final decoration = container.foregroundDecoration;
    if (decoration is BoxDecoration && decoration.border is Border) {
      return (decoration.border! as Border).top.color;
    }
  }
  return null;
}

/// The colour an icon is drawn in, which is how [PlayerIconButton] answers focus
/// on a television: there is no hover for it to look the same as.
Color? _iconColour(WidgetTester tester, IconData icon) =>
    IconTheme.of(tester.element(find.byIcon(icon))).color;

void main() {
  tearDown(() => DeviceProfile.debugSetTelevision(value: false));

  testWidgets('a page node covering the screen is a dead end for the D-pad', (tester) async {
    // The shipped state, kept as the control: this is what the report describes.
    // A node whose rect is the whole screen has no neighbour outside it, so the
    // arrow finds nothing and the D-pad does nothing at all.
    final screen = _Screen(television: true, skipPageTraversal: false);
    addTearDown(screen.dispose);
    await _pump(tester, screen);

    expect(FocusManager.instance.primaryFocus, same(screen.page),
        reason: 'precondition: the page node covers the body and took focus');

    for (final key in [LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowLeft]) {
      await _tap(tester, key);
    }
    expect(FocusManager.instance.primaryFocus, same(screen.page),
        reason: 'nothing on the transport can be reached from a full-screen node');
  });

  testWidgets('opening the HUD puts primary focus on the play button', (tester) async {
    final screen = _Screen(television: true);
    addTearDown(screen.dispose);
    await _pump(tester, screen);

    expect(screen.entry.hasPrimaryFocus, isTrue,
        reason: 'the overlay must open on a real control, not on the page node');
    expect(_focused(tester, screen), 'Play/Pause');

    // Not merely focused: on screen, and wired to an action.
    final rect = tester.getRect(find.byIcon(Icons.pause_rounded));
    final bounds = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(bounds.contains(rect.center), isTrue,
        reason: 'the focused control must be inside the canvas, not off-screen');
    final before = screen.playing;
    await _tap(tester, LogicalKeyboardKey.select);
    expect(screen.playing, isNot(before),
        reason: 'the centre key must activate the control that holds focus');
  });

  testWidgets('every transport control is reachable by D-pad and activatable',
      (tester) async {
    final screen = _Screen(television: true);
    addTearDown(screen.dispose);
    await _pump(tester, screen);

    final seen = await _sweep(tester, screen);
    // The controls the report names, each of which must be individually
    // reachable: play/pause, the timeline, volume, subtitles, audio, fullscreen.
    for (final expected in [
      'Play/Pause',
      'Seek -10s',
      'Seek +10s',
      'Mute',
      'Volume',
      'Subtitles',
      'Audio Tracks',
      'Fullscreen (F)',
    ]) {
      expect(seen, contains(expected),
          reason: '$expected must be reachable by moving the D-pad');
    }

    // And each one acts when the centre key is pressed. The sweep above left
    // focus on the last control it reached, so walk back through the list.
    final actions = <String, String>{
      'Play/Pause': 'playpause',
      'Seek -10s': 'seek-10',
      'Seek +10s': 'seek+10',
      'Mute': 'mute',
      'Aspect Ratio (C)': 'menu:aspect',
      'Playback Speed': 'menu:speed',
      'Audio Tracks': 'menu:audio',
      'Subtitles': 'menu:subtitle',
      'Subtitle Sync': 'menu:subsync',
      'Fullscreen (F)': 'fullscreen',
    };
    for (final entry in actions.entries) {
      await _walkTo(tester, screen, entry.key);
      screen.calls.clear();
      await _tap(tester, LogicalKeyboardKey.select);
      expect(screen.calls, contains(entry.value),
          reason: 'the centre key on ${entry.key} must run its action');
    }
  });

  testWidgets('the timeline takes left and right and the position moves',
      (tester) async {
    final screen = _Screen(television: true);
    addTearDown(screen.dispose);
    await _pump(tester, screen);

    // Up from the play button is the timeline.
    await _tap(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(tester, screen), 'Seek',
        reason: 'the transport row sits under the timeline, so up reaches it');

    expect(find.text('0:00'), findsOneWidget);
    await _tap(tester, LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(screen.position.value, const Duration(seconds: 10),
        reason: 'right on the timeline seeks ten seconds forward');
    expect(find.text('0:10'), findsOneWidget,
        reason: 'the new position has to be visible in the timeline readout');
    expect(find.text('0:00'), findsNothing);

    await _tap(tester, LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(screen.position.value, Duration.zero);
    expect(find.text('0:00'), findsOneWidget);
  });

  testWidgets('the volume slider takes up and down', (tester) async {
    final screen = _Screen(television: true);
    addTearDown(screen.dispose);
    await _pump(tester, screen);

    await _walkTo(tester, screen, 'Volume');

    final before = screen.volume;
    await _tap(tester, LogicalKeyboardKey.arrowUp);
    expect(screen.volume, greaterThan(before),
        reason: 'up on the volume track must raise the volume');
    await _tap(tester, LogicalKeyboardKey.arrowDown);
    expect(screen.volume, closeTo(before, 0.001));

    // And left and right still walk the row from the track: a control that ate
    // an arrow along the row would put the right-hand buttons out of reach.
    await _tap(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused(tester, screen), isNot('Volume'),
        reason: 'the track must not swallow the row-walking arrows');
    expect(screen.volume, closeTo(before, 0.001),
        reason: 'right is traversal here, not a volume change');
  });

  testWidgets('the focused control is visibly focused', (tester) async {
    final screen = _Screen(television: true);
    addTearDown(screen.dispose);
    await _pump(tester, screen);

    // The timeline paints a ring only while it holds focus.
    final seekBar = find.byType(PlayerSeekBar);
    expect(_ringColour(tester, seekBar)?.a, 0,
        reason: 'an unfocused timeline must not draw a ring');
    await _tap(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(tester, screen), 'Seek');
    expect(_ringColour(tester, seekBar)?.a, greaterThan(0),
        reason: 'a focused timeline must draw the ring, or nobody can see where '
            'the arrows will seek');

    // The volume track answers focus the same way.
    final volume = find.byType(PlayerVolumeControl);
    await _walkTo(tester, screen, 'Volume');
    expect(_ringColour(tester, volume)?.a, greaterThan(0),
        reason: 'the volume track must show focus, it has no hover on a remote');

    // And a button brightens its icon, the only signal a ten-foot user gets.
    await _walkTo(tester, screen, 'Subtitles');
    final focused = _iconColour(tester, Icons.subtitles_rounded);
    await _tap(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused(tester, screen), isNot('Subtitles'));
    final unfocused = _iconColour(tester, Icons.subtitles_rounded);
    expect(focused, isNot(unfocused),
        reason: 'the focused button must read differently from its neighbours');
  });

  testWidgets('the dedicated volume keys work whatever holds focus', (tester) async {
    final screen = _Screen(television: true);
    addTearDown(screen.dispose);
    await _pump(tester, screen);

    // With the page node focused, the HUD's own focus gate must not be in the way.
    FocusManager.instance.primaryFocus?.unfocus();
    screen.page.requestFocus();
    await tester.pump();
    expect(screen.page.hasPrimaryFocus, isTrue);

    var volume = screen.volume;
    await _tap(tester, LogicalKeyboardKey.audioVolumeUp);
    expect(screen.volume, greaterThan(volume),
        reason: 'the hardware volume key must survive the remote taking over the transport');
    volume = screen.volume;
    await _tap(tester, LogicalKeyboardKey.audioVolumeDown);
    expect(screen.volume, lessThan(volume));

    // And with a transport control focused, which is where this change puts
    // focus: a focused button must not cost the viewer the volume rocker.
    screen.entry.requestFocus();
    await tester.pump();
    expect(screen.entry.hasPrimaryFocus, isTrue);
    volume = screen.volume;
    await _tap(tester, LogicalKeyboardKey.audioVolumeUp);
    expect(screen.volume, greaterThan(volume),
        reason: 'a HUD control holding focus must not swallow the volume rocker');
  });

  testWidgets('a pointer device keeps the arrow-key map', (tester) async {
    final screen = _Screen(television: false, skipPageTraversal: false);
    addTearDown(screen.dispose);
    await _pump(tester, screen);

    expect(screen.page.hasPrimaryFocus, isTrue,
        reason: 'a desktop keeps the page node focused and draws no ring');

    final volume = screen.volume;
    await _tap(tester, LogicalKeyboardKey.arrowUp);
    expect(screen.volume, greaterThan(volume),
        reason: 'up is still the volume on a pointer device');
    expect(FocusManager.instance.primaryFocus, same(screen.page),
        reason: 'and the arrow must not have moved focus');

    await _tap(tester, LogicalKeyboardKey.arrowRight);
    expect(screen.calls, contains('relative:10'),
        reason: 'right is still a ten second seek on a pointer device');

    screen.calls.clear();
    await _tap(tester, LogicalKeyboardKey.space);
    expect(screen.calls, contains('playpause'),
        reason: 'space is still play/pause');
  });
}
