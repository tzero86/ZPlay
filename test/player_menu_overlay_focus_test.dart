/// Pins the player-overlay half of the 1.6.11 television fix.
///
/// Reported on a Chromecast with Google TV: "you open the subtitle menu and the
/// remote still controls the bar". Opening Subtitles, Audio or Speed left the
/// ring on the transport behind the menu, so arrows and the centre key kept
/// driving Play/Pause while the menu answered nothing. Three contracts follow
/// from that, and this file pins all three for each of the three popover menus:
///
/// 1. **Opening a menu moves the ring into it.** The overlay receives focus on
///    its first focusable control in document order - the Refresh button of the
///    subtitle header, the Close button of the audio and speed headers - not on
///    the trigger the menu was opened from.
/// 2. **The HUD leaves the traversal order while a menu is open.** The
///    transport stays mounted and painted under the popover, so
///    `IgnorePointer` alone would leave it traversable; the screen wraps it in
///    `ExcludeFocus(excluding: _overlayIsOpen)`. The assertion is the focus
///    system's own `canRequestFocus`, which folds in an ancestor's
///    `descendantsAreFocusable`, plus a key sweep that must never land on the
///    bar.
/// 3. **Back closes only the menu.** BACK inside a menu must not leave the
///    player. The screen's `PopScope` reports `canPop: !_overlayIsOpen`, closes
///    the overlay from `onPopInvokedWithResult`, and hands the ring back to the
///    HUD entry (Play/Pause).
///
/// `PlayerScreen` cannot be pumped - it owns a `media_kit` `Player` - so, as in
/// `player_transport_focus_test.dart` and `player_loading_overlay_test.dart`,
/// the real widgets are mounted whole ([PlayerTransport], [PlayerSubtitleMenu],
/// [PlayerAudioMenu], [PlayerSpeedMenu]) and only the page skeleton around them
/// is mirrored: the `Stack`, the `ExcludeFocus` gate, the `PopScope`, and the
/// document-order focus walk `_focusOverlayEntry` owns. Those lines are exactly
/// where the defect was.
///
/// The Episodes and Sources panels are handed the same walk and sit behind the
/// same gate in `PlayerScreen`, but they are full-screen scrim drawers with
/// their own scroll and image loading; this file pins the popover family the
/// report names.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/models/subtitle/subtitle_model.dart';
import 'package:zplay/services/layout/form_factor.dart';
import 'package:zplay/widgets/common/focusable_card.dart';
import 'package:zplay/widgets/player/player_audio_menu.dart';
import 'package:zplay/widgets/player/player_glass.dart';
import 'package:zplay/widgets/player/player_remote_keys.dart';
import 'package:zplay/widgets/player/player_seek_bar.dart';
import 'package:zplay/widgets/player/player_speed_menu.dart';
import 'package:zplay/widgets/player/player_subtitle_menu.dart';
import 'package:zplay/widgets/player/player_transport.dart';
import 'package:zplay/widgets/player/player_volume_control.dart';

/// The television's logical canvas: 1920x1080 physical at DPR 2.
const Size _tvCanvas = Size(960, 540);
const double _tvDpr = 2.0;

/// The three popover menus the report names, with the control a remote must
/// land on when each opens.
///
/// The first focusable node in document order is not the same in all three:
/// the subtitle header starts with its Refresh button, the other two headers
/// start with Close.
class _MenuSpec {
  const _MenuSpec({
    required this.name,
    required this.triggerTooltip,
    required this.firstControlTooltip,
  });

  final String name;
  final String triggerTooltip;
  final String firstControlTooltip;

  @override
  String toString() => name;
}

const List<_MenuSpec> _menus = <_MenuSpec>[
  _MenuSpec(
    name: 'subtitle',
    triggerTooltip: 'Subtitles',
    firstControlTooltip: 'Refresh Online Subtitles',
  ),
  _MenuSpec(
    name: 'audio',
    triggerTooltip: 'Audio Tracks',
    firstControlTooltip: 'Close',
  ),
  _MenuSpec(
    name: 'speed',
    triggerTooltip: 'Playback Speed',
    firstControlTooltip: 'Close',
  ),
];

final GlobalKey<_PlayerMenuHarnessState> _harness =
    GlobalKey<_PlayerMenuHarnessState>(debugLabel: 'PlayerMenuHarness');

/// `PlayerScreen`'s page skeleton, around the real transport and the real
/// menus: the `ExcludeFocus` gate, the single `KeyedSubtree` anchor the screen
/// reuses for every popover, and the `PopScope` that owns BACK.
class _PlayerMenuHarness extends StatefulWidget {
  const _PlayerMenuHarness({super.key});

  @override
  State<_PlayerMenuHarness> createState() => _PlayerMenuHarnessState();
}

class _PlayerMenuHarnessState extends State<_PlayerMenuHarness> {
  /// The page node, which covers the whole body and is therefore skipped on a
  /// television - the same dead-end answer `player_transport_focus_test.dart`
  /// pins.
  final FocusNode page = FocusNode(debugLabel: 'PlayerPage');

  /// The control the HUD hands focus to; attached to Play/Pause by
  /// `PlayerTransport`.
  final FocusNode entry = FocusNode(debugLabel: 'PlayerHudEntry');

  /// Anchors the transport, so "is the ring on the HUD?" is asked of its own
  /// controls rather than of the page node (whose rect is the whole screen).
  final GlobalKey transportKey = GlobalKey(debugLabel: 'PlayerTransportAnchor');

  /// The anchor every popover is built under, reused exactly as `PlayerScreen`
  /// reuses `_activeMenuKey`.
  final GlobalKey menuKey = GlobalKey(debugLabel: 'PlayerActiveMenuAnchor');

  /// Which popover is open: `null`, `subtitle`, `audio` or `speed`.
  String? activeMenu;

  @override
  void initState() {
    super.initState();
    // `PlayerScreen.initState`, same order: the page node stops being a
    // traversal destination on a television, and the open HUD hands the ring to
    // the transport once the node is attached.
    if (FormFactorService.hasRemoteInput) {
      page.skipTraversal = true;
      _focusHudEntry();
    }
  }

  @override
  void dispose() {
    page.dispose();
    entry.dispose();
    super.dispose();
  }

  /// `_PlayerScreenState._toggleMenu`, unchanged in substance: a newly opened
  /// menu takes the ring on the next frame, a closed one hands it back to the
  /// bar because the control that held it is gone.
  void _toggleMenu(String menuName) {
    final closing = activeMenu == menuName;
    setState(() {
      activeMenu = closing ? null : menuName;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (closing && activeMenu == null) {
        _focusHudEntry();
        return;
      }
      if (!closing && activeMenu == menuName) {
        _focusOverlayEntry(menuKey);
      }
    });
  }

  /// `_PlayerScreenState._focusHudEntry`: a no-op without a remote, because a
  /// pointer device keeps the page node and its own arrow-key shortcuts.
  void _focusHudEntry() {
    if (!FormFactorService.hasRemoteInput) return;
    entry.requestFocus();
  }

  /// `_PlayerScreenState._focusOverlayEntry`, copied so the real menus are
  /// handed the ring the way the shipped screen hands it.
  ///
  /// Document order over the focus tree, restricted to nodes whose element is
  /// genuinely inside the anchor: `Focus.maybeOf` would answer with the nearest
  /// *ancestor* (the page node) and the ring would never leave the bar.
  void _focusOverlayEntry(GlobalKey anchor) {
    final anchorElement = anchor.currentContext;
    if (anchorElement is! Element) return;

    bool insideAnchor(FocusNode node) {
      var found = false;
      node.context?.visitAncestorElements((ancestor) {
        if (identical(ancestor, anchorElement)) {
          found = true;
          return false;
        }
        return true;
      });
      return found;
    }

    final anchorBox = anchorElement.renderObject;
    Rect? anchorRect;
    if (anchorBox is RenderBox && anchorBox.hasSize) {
      anchorRect = MatrixUtils.transformRect(
        anchorBox.getTransformTo(null),
        Offset.zero & anchorBox.size,
      );
    }

    FocusNode? target;
    for (final node in FocusManager.instance.rootScope.descendants) {
      if (!insideAnchor(node)) continue;
      if (!_isOverlayEntry(node, within: anchorRect)) continue;
      target = node;
      break;
    }
    target?.requestFocus();
  }

  /// `_PlayerScreenState._isOverlayEntry`: focusable, traversable, attached,
  /// and drawing a real box inside the panel.
  bool _isOverlayEntry(FocusNode node, {Rect? within}) {
    if (node.context == null || !node.canRequestFocus || node.skipTraversal) {
      return false;
    }
    final rect = node.rect;
    if (rect == Rect.zero || !rect.isFinite) return false;
    if (within == null) return true;
    final slack = within.inflate(0.5);
    return slack.contains(rect.topLeft) &&
        slack.contains(rect.bottomRight - const Offset(0.01, 0.01));
  }

  /// BACK with an overlay open: close it and hand the ring back to the bar.
  void _closeOverlaysAndRefocus() {
    setState(() => activeMenu = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusHudEntry();
    });
  }

  Widget? _buildMenu() {
    switch (activeMenu) {
      case 'subtitle':
        return PlayerSubtitleMenu(
          groups: <SubtitleLanguageGroup>[
            SubtitleLanguageGroup(
              language: 'English',
              variants: <SubtitleVariant>[
                SubtitleVariant(
                  providerName: 'OpenSubtitles',
                  language: 'English',
                  title: 'English',
                  downloadUrl: 'https://example.invalid/en.srt',
                  format: 'srt',
                ),
              ],
            ),
          ],
          isSubtitleEnabled: true,
          movieTitle: 'A title',
          delaySec: 0,
          onSelectVariant: (_) {},
          onSelectEmbedded: (_) {},
          onToggleOff: () {},
          onOpenSyncBar: () {},
          onOpenStyleBar: () {},
          onOpenTextSync: () {},
          onClose: () => setState(() => activeMenu = null),
        );
      case 'audio':
        return PlayerAudioMenu(
          audioTracks: const <PlayerAudioTrack>[
            PlayerAudioTrack(index: 0, title: 'English', language: 'en'),
            PlayerAudioTrack(index: 1, title: 'Arabic', language: 'ar'),
          ],
          selectedIndex: 0,
          delaySec: 0,
          onTrackSelected: (_) {},
          onDelayChanged: (_) {},
          onClose: () => setState(() => activeMenu = null),
        );
      case 'speed':
        return PlayerSpeedMenu(
          currentRate: 1.0,
          onRateSelected: (_) {},
          onClose: () => setState(() => activeMenu = null),
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final menu = _buildMenu();
    return PopScope(
      // `_PlayerScreenState`'s gate, verbatim: BACK inside an overlay belongs
      // to the overlay, not to the route.
      canPop: activeMenu == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (activeMenu != null) _closeOverlaysAndRefocus();
      },
      child: Focus(
        focusNode: page,
        autofocus: true,
        child: Stack(
          children: <Widget>[
            const Positioned.fill(child: ColoredBox(color: Colors.black)),

            // The HUD. It paints behind the popover, and leaves the focus tree
            // while one is open - the second contract under test.
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ExcludeFocus(
                excluding: activeMenu != null,
                child: PlayerTransport(
                  key: transportKey,
                  isPlaying: true,
                  position: Duration.zero,
                  duration: const Duration(minutes: 2),
                  volume: 1.0,
                  isMuted: false,
                  playbackRate: 1.0,
                  isSubtitlesActive: false,
                  isSubSyncActive: false,
                  isAudioActive: false,
                  isFullscreen: false,
                  entryFocusNode: entry,
                  onPlayPause: () {},
                  onSeek: (_) {},
                  onSeekBack10: () {},
                  onSeekForward10: () {},
                  onVolumeChanged: (_) {},
                  onToggleMute: () {},
                  onToggleAspectMenu: () => _toggleMenu('aspect'),
                  onToggleSpeedMenu: () => _toggleMenu('speed'),
                  onToggleAudioMenu: () => _toggleMenu('audio'),
                  onToggleSubtitleMenu: () => _toggleMenu('subtitle'),
                  onToggleSubSync: () {},
                  onToggleFullscreen: () {},
                ),
              ),
            ),

            // The popover, at the screen's own placement for a wide canvas.
            if (menu != null)
              Positioned(
                bottom: 96,
                right: 28,
                child: KeyedSubtree(key: menuKey, child: menu),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pumps the harness on the television's own canvas at DPR 2.
Future<void> _pump(WidgetTester tester) async {
  DeviceProfile.debugSetTelevision(value: true);
  tester.view.devicePixelRatio = _tvDpr;
  tester.view.physicalSize = _tvCanvas * _tvDpr;
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() {
    DeviceProfile.debugSetTelevision(value: false);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: _PlayerMenuHarness(key: _harness)),
    ),
  );
  await tester.pump();
}

_PlayerMenuHarnessState _state() => _harness.currentState!;

/// Opens [spec]'s menu through its real transport trigger, then settles the
/// post-frame hand-off.
Future<void> _open(WidgetTester tester, _MenuSpec spec) async {
  await tester.tap(find.byTooltip(spec.triggerTooltip));
  await tester.pump();
  await tester.pump();
}

/// The control holding primary focus, named the way the player names it: by
/// the ancestor `PlayerIconButton`'s tooltip, or Play/Pause for the HUD entry
/// whose `FocusableCard` owns the transport's entry node.
String _focusedControl(WidgetTester tester) {
  final node = FocusManager.instance.primaryFocus;
  if (node == null) return 'none';
  final of = find.byElementPredicate((e) => e == node.context);

  if (tester.any(
    find.ancestor(
      of: of,
      matching: find.byWidgetPredicate(
        (w) => w is FocusableCard && identical(w.focusNode, _state().entry),
      ),
    ),
  )) {
    return 'Play/Pause';
  }
  final icon = find.ancestor(of: of, matching: find.byType(PlayerIconButton));
  if (tester.any(icon)) {
    return tester.widget<PlayerIconButton>(icon.first).tooltip ??
        'unnamed-icon';
  }
  if (tester.any(find.ancestor(of: of, matching: find.byType(PlayerSeekBar)))) {
    return 'Seek';
  }
  if (tester.any(
    find.ancestor(of: of, matching: find.byType(PlayerVolumeControl)),
  )) {
    return 'Volume';
  }
  return 'other';
}

/// The focus nodes whose element sits under the transport anchor.
Iterable<FocusNode> _transportNodes() {
  final state = _state();
  final anchor = state.transportKey.currentContext;
  return FocusManager.instance.rootScope.descendants.where((node) {
    var inside = false;
    node.context?.visitAncestorElements((ancestor) {
      if (identical(ancestor, anchor)) {
        inside = true;
        return false;
      }
      return true;
    });
    return inside;
  });
}

bool _focusIsUnder(GlobalKey anchor) => focusedElementIsUnder(
  focused: FocusManager.instance.primaryFocus?.context,
  ancestor: anchor.currentContext,
);

/// The number of controls in the bar a remote could stand on right now.
int _focusableTransportNodes() =>
    _transportNodes().where((node) => node.canRequestFocus).length;

/// Android delivers BACK as `popRoute` on `flutter/navigation`, decoded by the
/// binding and walked through the route's `PopScope`. A key event would not do:
/// the platform message is the delivery `PopScope` actually answers.
Future<void> _pressPlatformBack(WidgetTester tester) async {
  final ByteData message = const JSONMethodCodec().encodeMethodCall(
    const MethodCall('popRoute'),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    message,
    (_) {},
  );
  await tester.pump();
}

void main() {
  for (final spec in _menus) {
    group('the ${spec.name} menu', () {
      testWidgets('opening it puts the remote on its first control', (
        tester,
      ) async {
        await _pump(tester);
        expect(
          _focusedControl(tester),
          'Play/Pause',
          reason: 'precondition: the open HUD starts on the transport',
        );

        await _open(tester, spec);

        expect(
          _state().activeMenu,
          spec.name,
          reason: 'the trigger must open the menu under test',
        );
        expect(
          _focusIsUnder(_state().menuKey),
          isTrue,
          reason:
              'the ring must move into the menu that just opened; '
              'leaving it on the bar is the reported defect',
        );
        expect(
          _focusedControl(tester),
          spec.firstControlTooltip,
          reason:
              'the menu receives the ring on its first control in '
              'document order, the same node the screen walks to',
        );
        expect(
          _focusIsUnder(_state().transportKey),
          isFalse,
          reason: 'the trigger behind the menu must not keep the ring',
        );
      });

      testWidgets('the HUD behind it leaves the traversal order', (
        tester,
      ) async {
        await _pump(tester);
        expect(
          _focusableTransportNodes(),
          greaterThan(0),
          reason:
              'control case: the bar is traversable while nothing is '
              'open, so the assertion below is not vacuous',
        );

        await _open(tester, spec);

        expect(
          _focusableTransportNodes(),
          0,
          reason:
              'ExcludeFocus takes every transport control out of the '
              'order while the overlay owns the screen',
        );
        expect(_focusIsUnder(_state().transportKey), isFalse);

        // The user-facing half: a remote sweeping from the menu must never
        // reach the controls painted behind it.
        for (final key in <LogicalKeyboardKey>[
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowDown,
        ]) {
          await tester.sendKeyEvent(key);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            _focusIsUnder(_state().menuKey),
            isTrue,
            reason: 'every arrow press stays inside the open menu',
          );
          expect(
            _focusIsUnder(_state().transportKey),
            isFalse,
            reason: 'the HUD behind the menu must not be traversable',
          );
        }
      });

      testWidgets('Back closes only the menu and returns the ring to the HUD', (
        tester,
      ) async {
        await _pump(tester);
        await _open(tester, spec);
        expect(_state().activeMenu, spec.name);
        expect(_focusIsUnder(_state().menuKey), isTrue);

        await _pressPlatformBack(tester);
        await tester.pump();

        expect(
          _state().activeMenu,
          isNull,
          reason: 'BACK closes the overlay it was pressed in',
        );
        expect(
          find.byTooltip(spec.triggerTooltip),
          findsOneWidget,
          reason:
              'the player route survives: BACK closed the menu, not the '
              'screen',
        );
        expect(
          FocusManager.instance.primaryFocus,
          same(_state().entry),
          reason:
              'the ring goes back to the HUD entry, so the next arrow '
              'has somewhere to go',
        );
        expect(_focusIsUnder(_state().transportKey), isTrue);
        expect(
          _state().page.skipTraversal,
          isTrue,
          reason: 'the page node must never take the ring back',
        );
      });
    });
  }
}
