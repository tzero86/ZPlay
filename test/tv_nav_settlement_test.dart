/// Scroll/focus settlement rules for TV grids.
///
/// Pins the measurement lesson from `tv_dpad_focus_regression_test.dart` as
/// an executable rule, against a generic scaffold so the class stays guarded
/// without mounting the shell:
///
/// * the focused identity must advance on every DOWN (a new card each press);
/// * the grid scrolls under the focus (offset strictly increases);
/// * the settled rect may legitimately hold still - `ensureVisible` pins the
///   followed card to the viewport edge - so the rect must NEVER be used as
///   the progress signal. This test asserts identity+offset and documents the
///   rect hold as expected, so a future rewrite cannot "fix" it by chasing
///   rects.
///
/// Reads are settled (via [pressDpad]): the scroll jump and the focus change
/// land in the same frame, and a rect logged at notification time is
/// pre-layout and unstable within its own frame.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/common/focusable_card.dart';

import 'support/tv_nav_harness.dart';

Widget _tallGrid(int count) => GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        mainAxisExtent: 192,
      ),
      itemCount: count,
      itemBuilder: (context, i) => FocusableCard(
        autofocus: i == 0,
        builder: (context, state) => Center(child: Text('item-$i')),
      ),
    );

double _gridOffset(WidgetTester tester) {
  final state = tester.state<ScrollableState>(
    find.descendant(
      of: find.byType(GridView),
      matching: find.byType(Scrollable),
    ),
  );
  return state.position.pixels;
}

void main() {
  testWidgets('down advances identity and scrolls; rect may hold still',
      (tester) async {
    await pumpTelevision(tester, _tallGrid(30));
    await tester.pump(const Duration(milliseconds: 200));
    expect(focusedId(tester), 'item-0');

    final ids = <String>['item-0'];
    final offsets = <double>[_gridOffset(tester)];
    // Drive past the first screenful: the first presses move within the
    // viewport (offset 0), later ones must scroll.
    for (int i = 0; i < 8; i++) {
      await pressDpad(tester, LogicalKeyboardKey.arrowDown, step: 'D$i');
      expectFocusHeld(tester, reason: 'down must never drop focus (press $i)');
      ids.add(focusedId(tester));
      offsets.add(_gridOffset(tester));
    }

    // Identity advances every press: no repeats, no stalls.
    expect(ids.toSet().length, ids.length,
        reason: 'every DOWN must land on a new card, got $ids');

    // The grid scrolled under the focus.
    expect(offsets.last, greaterThan(offsets.first),
        reason: 'an 8-press walk down a 30-item grid must scroll, '
            'offsets=$offsets');

    // Rect discipline, documented not asserted as progress: the settled rect
    // of the last stop is informational only.
    final lastRect = FocusManager.instance.primaryFocus!.rect;
    debugPrint('[settle] final rect=${lastRect.left.toStringAsFixed(0)},'
        '${lastRect.top.toStringAsFixed(0)} '
        '${lastRect.width.toStringAsFixed(0)}x${lastRect.height.toStringAsFixed(0)} '
        'ids=${ids.sublist(ids.length - 3)} '
        'offsets=${offsets.sublist(offsets.length - 3)}');
  });
}
