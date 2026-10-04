/// TV navigation regression suite: D-pad traversal, focus identity, and the
/// expansion/misplacement guard.
///
/// Every test drives real `LogicalKeyboardKey.arrow*` events (plus `select`
/// for activation) through generic [FocusableCard] scaffolds on the
/// television canvas, using `test/support/tv_nav_harness.dart`. Identity -
/// label/id plus rect - is asserted, never rect-only, because once
/// `ensureVisible(alignment: 1)` pins a followed card to the viewport edge
/// the rect is identical whether focus advances or is stuck.
///
/// What each test pins:
/// * arrow-key predictability - LEFT/RIGHT walk a row in order, UP/DOWN walk
///   a column in order, no skips or reversals;
/// * no hidden traps - pressing past an edge keeps focus held (it stops, it
///   never drops to null or leaves the tree);
/// * focus restoration - walking away and back lands on the same identity;
/// * rail-to-menu reachability - DOWN leaves a top menu row for the content
///   below it and UP returns (the bar<->page contract `top_bar_traversal`
///   pins against the real shell, reproduced here generically so the class
///   is guarded even when the shell is not mounted);
/// * expansion/misplacement - focusing a card never moves its layout box or
///   any sibling's (focus may repaint, it must never re-flow; the overlay
///   pop the production cards paint is covered by
///   `movie_card_focus_expansion_test.dart`, this guards the invariant at
///   the traversal layer so a re-layout regresses here too).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/common/focusable_card.dart';

import 'support/tv_nav_harness.dart';

Widget _card(String label, {bool autofocus = false}) => FocusableCard(
      autofocus: autofocus,
      builder: (context, state) => SizedBox(
        width: 160,
        height: 120,
        child: Center(child: Text(label)),
      ),
    );

Widget _row(List<String> labels) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < labels.length; i++)
          _card(labels[i], autofocus: i == 0),
      ],
    );

Widget _column(List<String> labels) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < labels.length; i++)
          _card(labels[i], autofocus: i == 0),
      ],
    );

void main() {
  testWidgets('arrows walk a row and a column in order', (tester) async {
    await pumpTelevision(tester, _row(const ['A', 'B', 'C']));
    await tester.pump(const Duration(milliseconds: 200));
    expect(focusedId(tester), 'A');

    await pressDpad(tester, LogicalKeyboardKey.arrowRight, step: 'R1');
    expect(focusedId(tester), 'B');
    await pressDpad(tester, LogicalKeyboardKey.arrowRight, step: 'R2');
    expect(focusedId(tester), 'C');
    await pressDpad(tester, LogicalKeyboardKey.arrowLeft, step: 'L1');
    expect(focusedId(tester), 'B',
        reason: 'left must reverse right, not jump or stall');

    await pumpTelevision(tester, _column(const ['T', 'M', 'Btm']));
    await tester.pump(const Duration(milliseconds: 200));
    expect(focusedId(tester), 'T');
    await pressDpad(tester, LogicalKeyboardKey.arrowDown, step: 'D1');
    expect(focusedId(tester), 'M');
    await pressDpad(tester, LogicalKeyboardKey.arrowDown, step: 'D2');
    expect(focusedId(tester), 'Btm');
    await pressDpad(tester, LogicalKeyboardKey.arrowUp, step: 'U1');
    expect(focusedId(tester), 'M');
  });

  testWidgets('no hidden traps: past-edge presses keep focus held',
      (tester) async {
    await pumpTelevision(
      tester,
      GridView.count(
        shrinkWrap: true,
        crossAxisCount: 3,
        children: [
          for (int i = 0; i < 6; i++) _card('${i + 1}', autofocus: i == 0),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expectFocusHeld(tester, reason: 'a remote must land somewhere in the grid');
    final seen = <String>{focusedId(tester)};
    // Walk the whole grid right-then-down; every stop must hold focus and
    // every identity must be a labelled card, never null or a page-size node.
    for (int i = 0; i < 8; i++) {
      await pressDpad(tester, LogicalKeyboardKey.arrowRight, step: 'R$i');
      expectFocusHeld(tester, reason: 'right must never drop focus (press $i)');
      seen.add(focusedId(tester));
      await pressDpad(tester, LogicalKeyboardKey.arrowDown, step: 'D$i');
      expectFocusHeld(tester, reason: 'down must never drop focus (press $i)');
      seen.add(focusedId(tester));
    }
    expect(seen.length, greaterThan(1),
        reason: 'traversal must visit distinct identities, not sit on one node');
    expect(seen.contains('focus=null'), isFalse);

    // Past the far edge: focus stops, it does not vanish.
    for (int i = 0; i < 3; i++) {
      await pressDpad(tester, LogicalKeyboardKey.arrowRight, step: 'edgeR$i');
      expectFocusHeld(tester,
          reason: 'past-edge right must stop on the last card, not drop focus');
    }
    for (int i = 0; i < 3; i++) {
      await pressDpad(tester, LogicalKeyboardKey.arrowDown, step: 'edgeD$i');
      expectFocusHeld(tester,
          reason: 'past-edge down must stop on the last row, not drop focus');
    }
  });

  testWidgets('centre key activates the focused card', (tester) async {
    var taps = 0;
    await pumpTelevision(
      tester,
      FocusableCard(
        autofocus: true,
        onTap: () => taps++,
        builder: (context, state) => const SizedBox(
          width: 160,
          height: 120,
          child: Center(child: Text('go')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(focusedId(tester), 'go');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(taps, 1,
        reason: 'the remote centre key must activate the focused card');
  });

  testWidgets('focus restoration: away and back lands on the same card',
      (tester) async {
    await pumpTelevision(tester, _row(const ['A', 'B', 'C']));
    await tester.pump(const Duration(milliseconds: 200));
    expect(focusedId(tester), 'A');
    await pressDpad(tester, LogicalKeyboardKey.arrowRight, step: 'toB');
    expect(focusedId(tester), 'B');
    await pressDpad(tester, LogicalKeyboardKey.arrowRight, step: 'toC');
    expect(focusedId(tester), 'C');
    await pressDpad(tester, LogicalKeyboardKey.arrowLeft, step: 'backB');
    expect(focusedId(tester), 'B',
        reason: 'returning must restore the exact card left behind');
    await pressDpad(tester, LogicalKeyboardKey.arrowLeft, step: 'backA');
    expect(focusedId(tester), 'A');
  });

  testWidgets('rail-to-menu reachability: down enters content, up returns',
      (tester) async {
    await pumpTelevision(
      tester,
      Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [_card('menu1', autofocus: true), _card('menu2')],
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              children: [for (final l in ['c1', 'c2', 'c3']) _card(l)],
            ),
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(focusedId(tester), 'menu1');

    await pressDpad(tester, LogicalKeyboardKey.arrowRight, step: 'menuR');
    expect(focusedId(tester), 'menu2',
        reason: 'right must walk along the menu row');
    await pressDpad(tester, LogicalKeyboardKey.arrowDown, step: 'menuD');
    final inContent = focusedId(tester);
    expect(['c1', 'c2', 'c3'], contains(inContent),
        reason: 'down must leave the menu for the content below it, '
            'landed on $inContent');
    await pressDpad(tester, LogicalKeyboardKey.arrowUp, step: 'backUp');
    final back = focusedId(tester);
    expect(['menu1', 'menu2'], contains(back),
        reason: 'up must return to the menu row, landed on $back');
  });

  testWidgets(
      'expansion guard: focusing a card moves no layout box in the row',
      (tester) async {
    await pumpTelevision(tester, _row(const ['A', 'B', 'C']));
    await tester.pump(const Duration(milliseconds: 200));
    final before = {
      for (final l in ['A', 'B', 'C']) l: cardLayoutRect(tester, l),
    };
    await pressDpad(tester, LogicalKeyboardKey.arrowRight, step: 'focusB');
    expect(focusedId(tester), 'B');
    await tester.pump(const Duration(milliseconds: 300));
    for (final l in ['A', 'B', 'C']) {
      expect(cardLayoutRect(tester, l), before[l],
          reason: 'focusing B must not re-flow $l (expansion/misplacement)');
    }
    await pressDpad(tester, LogicalKeyboardKey.arrowRight, step: 'focusC');
    expect(focusedId(tester), 'C');
    await tester.pump(const Duration(milliseconds: 300));
    for (final l in ['A', 'B', 'C']) {
      expect(cardLayoutRect(tester, l), before[l],
          reason: 'focusing C must not re-flow $l (expansion/misplacement)');
    }
  });
}
