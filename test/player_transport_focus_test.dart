/// Guards that a remote can reach the player's transport controls.
///
/// The player claimed every arrow key for itself: up and down adjusted volume,
/// left and right seeked, and every branch ended in `KeyEventResult.handled`.
/// `handled` stops the event dead, so the `DirectionalFocusIntent` binding that
/// `WidgetsApp` installs for the arrow keys never saw it, and a remote could not
/// move between the play, seek, volume and fullscreen buttons at all.
///
/// Reported on a Chromecast with Google TV: the D-pad adjusted volume and
/// seeked instead of navigating.
///
/// The buttons were never at fault. `PlayerIconButton` is built on
/// `FocusableCard`, so every control in `player_transport.dart` was already a
/// focus node with a ring. The handler consumed the keys before traversal got a
/// look, which is why a test that only counted focus nodes would have passed
/// over this.
///
/// Focus is read from the primary node's own `hasFocus` rather than by walking
/// the tree: the label is rendered *below* the focus node, and a `Text` identity
/// check against the focused node reports `none` - a test that quietly asserts
/// nothing, which is how the first two attempts at this file failed.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/common/focusable_card.dart';

const _labels = ['back', 'play', 'seek', 'volume'];

/// Four focusable controls in a row, like the transport bar.
///
/// [claimsArrows] reproduces the two handlers side by side: the shipped one
/// returns `handled` for the arrows, the fix returns `ignored` so the default
/// binding runs.
Widget _transport({required bool claimsArrows}) => MaterialApp(
      home: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (!claimsArrows) return KeyEventResult.ignored;
          const arrows = [
            LogicalKeyboardKey.arrowUp,
            LogicalKeyboardKey.arrowDown,
            LogicalKeyboardKey.arrowLeft,
            LogicalKeyboardKey.arrowRight,
          ];
          if (arrows.any((k) => k.keyId == event.logicalKey.keyId)) {
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          body: Row(
            children: [
              for (var i = 0; i < _labels.length; i++) ...[
                FocusableCard(
                  autofocus: i == 0,
                  onTap: () {},
                  builder: (context, state) => Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(_labels[i]),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );

/// The label inside the control that holds focus, or `none`.
String _focused() {
  final node = FocusManager.instance.primaryFocus;
  if (node == null || !node.hasFocus) return 'none';
  // The label lives under the focused node, so ask the node's own subtree.
  final texts = find
      .descendant(of: find.byElementPredicate((e) => e == node.context), matching: find.byType(Text))
      .evaluate();
  for (final e in texts) {
    final data = (e.widget as Text).data;
    if (data != null && _labels.contains(data)) return data;
  }
  return 'focused-unnamed';
}

void main() {
  testWidgets('a handler that claims the arrows traps focus', (tester) async {
    // The control case: this is what shipped, and it is the whole reason a
    // remote could not move. Pinned so the fix cannot be undone silently.
    await tester.pumpWidget(_transport(claimsArrows: true));
    await tester.pump();
    final start = _focused();
    expect(start, isNot('none'),
        reason: 'precondition: a control holds the starting focus');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(_focused(), start,
        reason: 'a claimed arrow key never reaches directional traversal');
  });

  testWidgets('ignoring the arrows lets the default binding move focus',
      (tester) async {
    await tester.pumpWidget(_transport(claimsArrows: false));
    await tester.pump();
    final start = _focused();
    expect(start, isNot('none'),
        reason: 'precondition: the first control takes the starting focus');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_focused(), isNot(start), reason: 'right must move focus');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(_focused(), start, reason: 'and left must come back');
  });
}
