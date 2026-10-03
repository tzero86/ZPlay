/// Pins the one setting every focus ring in the app depends on.
///
/// The report was "the remote works but I cannot see where I am": cards, rail
/// rows, settings rows and the filter pills all took focus and none of them
/// painted anything. Traversal was never broken.
///
/// `FocusManager.highlightMode` derives to `FocusHighlightMode.touch` unless the
/// app says otherwise, and in that mode `FocusableActionDetector` never raises
/// `onShowFocusHighlight` - the platform reports a focus highlight only for
/// keyboard-style traversal, which is a mouse-and-keyboard heuristic and not one
/// a Chromecast remote satisfies. So every `FocusableCard` in the tree was built
/// with `state.focused == false` at all times, and `CardFocusRing` returned its
/// child unmarked.
///
/// **Why this file does not pump `ZPlayApp`.** Two earlier versions of this test
/// did. One set the strategy itself and passed whether or not `main.dart` still
/// assigned it; the other pumped the real root and inherited every service timer
/// the app schedules at startup, which the binding fails on. Neither could fail
/// for the right reason. This instead pins the *contract* - the value `main.dart`
/// assigns, and what that value has to do for a ring to appear - and
/// `test/pages/home/home_page_test.dart`'s neighbours cover the rendering. If
/// the assignment in `main.dart` is ever dropped, this test cannot see it, which
/// is a real gap and the reason the television re-check after the next deploy is
/// not optional.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/common/focusable_card.dart';

/// What `_ZPlayAppState.initState` assigns.
///
/// Kept as a named constant so the two facts this file asserts - the value and
/// the mode it derives - sit next to each other and are read as one contract.
const _appStrategy = FocusHighlightStrategy.alwaysTraditional;

/// A card that reports what its builder was told, and paints whatever the ring
/// decides. `CardFocusRing` returns its child untouched when unfocused, so the
/// 2 dp accent border exists only when the ring is actually drawn.
class _RingProbe extends StatelessWidget {
  const _RingProbe({required this.focusNode});

  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: FocusableCard(
            focusNode: focusNode,
            onTap: () {},
            builder: (context, state) => CardFocusRing(
              focused: state.focused,
              radius: BorderRadius.circular(8),
              child: const SizedBox(width: 120, height: 180),
            ),
          ),
        ),
      ),
    );
  }
}

Finder _ringBorder() => find.descendant(
      of: find.byType(CardFocusRing),
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).border != null,
        description: 'a painted card border',
      ),
    );

void main() {
  testWidgets('a focused card paints no ring while the mode is touch',
      (tester) async {
    expect(
      FocusManager.instance.highlightStrategy,
      FocusHighlightStrategy.automatic,
      reason: 'precondition: a bare harness starts on the automatic strategy',
    );
    expect(
      FocusManager.instance.highlightMode,
      FocusHighlightMode.touch,
      reason: 'precondition: the mode that never raises a focus highlight, and '
          'so never paints a ring - this is what a television was running',
    );

    final node = FocusNode();
    addTearDown(node.dispose);

    await tester.pumpWidget(_RingProbe(focusNode: node));
    node.requestFocus();
    await tester.pump();

    expect(node.hasFocus, isTrue,
        reason: 'precondition: focus itself works. It is the ring that does not, '
            'which is what made a working D-pad read as a dead one.');
    expect(
      _ringBorder(),
      findsNothing,
      reason: 'unpinned, the card is focused and paints nothing',
    );
  });

  testWidgets('pinning the mode the app pins makes that card paint its ring',
      (tester) async {
    FocusManager.instance.highlightStrategy = _appStrategy;
    addTearDown(() {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic;
    });

    final node = FocusNode();
    addTearDown(node.dispose);

    await tester.pumpWidget(_RingProbe(focusNode: node));
    node.requestFocus();
    await tester.pump();

    expect(
      FocusManager.instance.highlightMode,
      FocusHighlightMode.traditional,
      reason: 'the derived mode follows the pinned strategy, so a mouse on the '
          'desktop build cannot put the television\'s rings back to sleep',
    );
    expect(
      _ringBorder(),
      findsOneWidget,
      reason: 'this is the fix: the same focus request now paints the ring',
    );
  });
}