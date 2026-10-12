/// Guards the two controls a dead stream leaves a television viewer.
///
/// Reported on the 1.5.5 build (960x540 dp, Chromecast with Google TV): the
/// player raised its "This stream is not responding" overlay, and neither escape
/// action took the ring nor answered the centre button (`accent_px=0`), so a
/// viewer whose source had died had no remote way out of the overlay or onto
/// another source.
///
/// Both buttons were Material buttons, which *are* focusable — the defect was
/// that nothing ever moved focus onto them, and that the player's own shortcuts
/// answered every key before the focus system saw it. The gate that stands those
/// shortcuts down knew only about the transport bar; the overlay is outside it,
/// so the arrows and the centre button were consumed by the player itself. The
/// overlay now takes focus when it appears, and the gate asks about both anchors.
///
/// `PlayerScreen` cannot be pumped — it owns a `media_kit` `Player` — so this
/// file takes the shipped halves whole: `PlayerLoadingOverlay`, which is the
/// overlay's own widget, and `handlePlayerRemoteKey`, which is the shipped
/// contract. Only the page skeleton between them is mirrored, and those ~15 lines
/// are where the defect was.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/theme/design_tokens.dart';
import 'package:zplay/widgets/common/focusable_card.dart';
import 'package:zplay/widgets/player/player_loading_overlay.dart';
import 'package:zplay/widgets/player/player_remote_keys.dart';

import '../support/tv_nav_harness.dart';

/// Whether any ring on screen is painting the focus state.
///
/// The assertion this whole file turns on: on a television a control that cannot
/// show where the remote is, is a control the user cannot find.
bool _focusedRing(WidgetTester tester) => tester
    .widgetList<CardFocusRing>(find.byType(CardFocusRing))
    .any((ring) => ring.focused);

Finder _filledAction() => find.byType(FilledButton);

/// The colour of the line painted over [control], or null when it has no ring.
///
/// Read off the ring's own border rather than off the `CardFocusRing` widget,
/// because the colour it ends up drawing is the widget's answer plus the
/// palette's, and the painted line is what a viewer sees.
Color? _ringColour(WidgetTester tester, Finder control) {
  final Finder rings = find.ancestor(
    of: control,
    matching: find.byType(CardFocusRing),
  );
  for (final Element element in rings.evaluate()) {
    if (!(element.widget as CardFocusRing).focused) continue;
    final Finder line = find.descendant(
      of: find.byWidget(element.widget),
      matching: find.byWidgetPredicate(
        (Widget w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).border != null,
        description: 'the ring\'s painted line',
      ),
    );
    expect(line, findsOneWidget,
        reason: 'a lit ring draws exactly one line over its control');
    return ((tester.widget<DecoratedBox>(line).decoration as BoxDecoration)
            .border!
            .top
            .color);
  }
  return null;
}

/// The fill the filled action is painted with.
///
/// `FilledButton`'s Material 3 default fill is the scheme's primary and the app
/// sets no theme for it, so this is the colour the ring has to separate from.
Color _filledActionFill(WidgetTester tester) {
  final BuildContext context = tester.element(_filledAction());
  return Theme.of(context).colorScheme.primary;
}

const String _message =
    'This stream is not responding - the source may be expired.';

/// The overlay as the screen builds it, with both actions recorded.
Widget _overlay({
  required FocusNode entry,
  required void Function(String) onAction,
  Key? key,
  bool stalled = true,
}) {
  return PlayerLoadingOverlay(
    key: key,
    message: _message,
    stalled: stalled,
    entryFocusNode: entry,
    onChooseSource: () => onAction('choose-source'),
    onGoBack: () => onAction('go-back'),
  );
}

void main() {
  late FocusNode entry;

  setUp(() {
    entry = FocusNode(debugLabel: 'PlayerStallChooseSource');
  });

  tearDown(() {
    entry.dispose();
  });

  testWidgets('a stall lands the remote on "Choose another source"', (
    tester,
  ) async {
    final actions = <String>[];

    await pumpTelevision(
      tester,
      _overlay(entry: entry, onAction: actions.add),
    );

    expect(
      entry.hasPrimaryFocus,
      isTrue,
      reason: 'the overlay is the only way off a dead source, so it has to take '
          'focus itself: the page underneath it holds the D-pad otherwise',
    );
    expect(
      _focusedRing(tester),
      isTrue,
      reason: 'a remote user has to see which action the centre button will take',
    );
  });

  testWidgets('the centre button takes the action that holds focus', (
    tester,
  ) async {
    final actions = <String>[];

    await pumpTelevision(
      tester,
      _overlay(entry: entry, onAction: actions.add),
    );
    await pressDpad(tester, LogicalKeyboardKey.select);

    expect(
      actions,
      ['choose-source'],
      reason: 'the centre button has to reach the source picker, or a dead '
          'stream is still a dead end',
    );
  });

  testWidgets('an arrow reaches the second action and activates it', (
    tester,
  ) async {
    final actions = <String>[];

    await pumpTelevision(
      tester,
      _overlay(entry: entry, onAction: actions.add),
    );
    await pressDpad(tester, LogicalKeyboardKey.arrowRight);
    expectFocusHeld(tester, reason: 'right from the first action must land on one');
    expect(
      focusedId(tester),
      'Go back',
      reason: 'the two actions are one row: the arrows move between them',
    );

    await pressDpad(tester, LogicalKeyboardKey.select);
    expect(actions, ['go-back']);
  });

  testWidgets('the ring separates from the filled action it marks', (
    tester,
  ) async {
    await pumpTelevision(
      tester,
      _overlay(entry: entry, onAction: (_) {}),
    );

    // Drawn is not the same as visible. The filled action's own fill is the
    // accent, so an accent ring painted on it is the same colour as the shape it
    // marks, and the sweep reported exactly that: "the ember ring is painted over
    // an accent-tinted pill and the two read as one shape". The two have to be
    // different colours to be distinguishable, the same rule the See All pills
    // were held to.
    expect(
      _ringColour(tester, _filledAction()),
      isNot(_filledActionFill(tester)),
      reason: 'the ring has to be visible against the fill it is drawn on',
    );

    // The neighbour is the control that already read clearly, and it keeps the
    // app's one accent ring: only the button the ring could not be seen on
    // changed, and both buttons' sizes, fills and hit targets are untouched.
    await pressDpad(tester, LogicalKeyboardKey.arrowRight);
    final BuildContext context = tester.element(find.byType(OutlinedButton));
    expect(
      _ringColour(tester, find.byType(OutlinedButton)),
      ZplayTokens.of(context).accent,
      reason: 'the outlined action still wears the accent every other control '
          'in the app is marked with',
    );
  });

  testWidgets('the overlay ring is painted over the button, not around it', (
    tester,
  ) async {
    await pumpTelevision(
      tester,
      _overlay(entry: entry, onAction: (_) {}),
    );

    final Rect ring = tester.getRect(find.byType(CardFocusRing).first);
    final Rect button = tester.getRect(find.byType(FilledButton).first);
    expect(
      ring.size,
      button.size,
      reason: 'the ring has to hug the button it marks; a wrapper that grew the '
          'control would also re-flow the overlay when focus arrived',
    );
  });

  group('the player stands its shortcuts down for the overlay', () {
    /// The page skeleton, mirroring `PlayerScreen`'s ~15 lines.
    ///
    /// [widenedGate] selects the gate the contract is given: `true` is the
    /// shipped one, which asks whether the overlay's actions hold focus as well
    /// as the transport bar; `false` is the one it replaced, which knew only
    /// about the bar. The second is a negative control — it is the state the
    /// sweep measured, and it proves the first test can see the defect at all.
    Widget page({
      required GlobalKey overlayKey,
      required FocusNode pageNode,
      required bool widenedGate,
      required void Function(String) onShortcut,
      required void Function(String) onAction,
    }) {
      return Focus(
        focusNode: pageNode,
        autofocus: true,
        onKeyEvent: (node, event) => handlePlayerRemoteKey(
          event,
          isTelevision: true,
          hudHasFocus: widenedGate &&
              focusedElementIsUnder(
                focused: FocusManager.instance.primaryFocus?.context,
                ancestor: overlayKey.currentContext,
              ),
          controlsVisible: true,
          escapeExitsFullscreen: false,
          onShowControls: () => onShortcut('show-controls'),
          onFocusControls: () => onShortcut('focus-controls'),
          onTogglePlayPause: () => onShortcut('play-pause'),
          onToggleMute: () => onShortcut('mute'),
          onToggleFullscreen: () => onShortcut('fullscreen'),
          onExitFullscreen: () => onShortcut('exit-fullscreen'),
          onCycleVideoFit: () => onShortcut('fit'),
          onAdjustVolume: (_) => onShortcut('volume'),
          onSeekRelative: (_) => onShortcut('seek'),
        ),
        child: _overlay(
          key: overlayKey,
          entry: entry,
          onAction: onAction,
        ),
      );
    }

    testWidgets('the centre button reaches the focused action, not the HUD', (
      tester,
    ) async {
      final overlayKey = GlobalKey();
      final pageNode = FocusNode(debugLabel: 'PlayerPage');
      addTearDown(pageNode.dispose);
      final shortcuts = <String>[];
      final actions = <String>[];

      await pumpTelevision(
        tester,
        page(
          overlayKey: overlayKey,
          pageNode: pageNode,
          widenedGate: true,
          onShortcut: shortcuts.add,
          onAction: actions.add,
        ),
      );
      expect(entry.hasPrimaryFocus, isTrue);

      await pressDpad(tester, LogicalKeyboardKey.select);

      expect(
        shortcuts,
        isEmpty,
        reason: 'the shortcut gate has to stand down while a control other than '
            'the transport holds focus',
      );
      expect(actions, ['choose-source']);
    });

    testWidgets('without the overlay in the gate the same press is eaten', (
      tester,
    ) async {
      final overlayKey = GlobalKey();
      final pageNode = FocusNode(debugLabel: 'PlayerPage');
      addTearDown(pageNode.dispose);
      final shortcuts = <String>[];
      final actions = <String>[];

      await pumpTelevision(
        tester,
        page(
          overlayKey: overlayKey,
          pageNode: pageNode,
          widenedGate: false,
          onShortcut: shortcuts.add,
          onAction: actions.add,
        ),
      );
      expect(entry.hasPrimaryFocus, isTrue);

      await pressDpad(tester, LogicalKeyboardKey.select);

      expect(
        shortcuts,
        ['focus-controls'],
        reason: 'this is the recorded defect: the centre button moved focus into '
            'the transport instead of reaching the button under it',
      );
      expect(actions, isEmpty, reason: 'the action under the finger never fired');
    });

    testWidgets('an arrow moves focus inside the overlay instead of the HUD', (
      tester,
    ) async {
      final overlayKey = GlobalKey();
      final pageNode = FocusNode(debugLabel: 'PlayerPage');
      addTearDown(pageNode.dispose);
      final shortcuts = <String>[];
      final actions = <String>[];

      await pumpTelevision(
        tester,
        page(
          overlayKey: overlayKey,
          pageNode: pageNode,
          widenedGate: true,
          onShortcut: shortcuts.add,
          onAction: actions.add,
        ),
      );

      await pressDpad(tester, LogicalKeyboardKey.arrowRight);

      expect(shortcuts, isEmpty);
      expect(focusedId(tester), 'Go back');
    });
  });
}
