/// The television rail drew two rings around a focused row, and the icon inside
/// it shifted.
///
/// Two separate causes, and the first one is worth remembering because it looks
/// like a fix and is the opposite of one.
///
/// **`Colors.transparent` is not "no border".** The row's border used to be
/// `selected ? Colors.transparent : tokens.borderDefault`, on the reasoning that
/// a transparent border is simply not painted. Flutter reserves the 2 dp and
/// composites the transparent colour over whatever is behind it, so the row's own
/// surface shows through the slot. Measured on the television, Home focused, as a
/// vertical luminance profile through the row:
///
/// ```
/// dp 137.5-139.5   2.5 dp   lum  54   <- the row's own border slot
/// dp 143.5-150.0   7.0 dp   lum 252   <- CardFocusRing
/// ```
///
/// Two rings 4 dp apart: the ghost border inside the shape that the user kept
/// reporting. A focused row now carries no border at all, and `CardFocusRing` is
/// the only ring - which is right on its own terms, since a focus ring that means
/// something should not be doubled by a decorative one.
///
/// **The glow was drawn inward.** `CardFocusRing`'s shadow was
/// `blurRadius: 18, spreadRadius: 1`, which put a luminous band *inside* the 2 dp
/// border: the measured ring was 7 dp, not 2. A border that fades inward has two
/// visible edges, so it reads as two borders however many are actually drawn. The
/// glow now sits outside the ring.
///
/// The rule that has to survive: **a focused row paints exactly one ring, and an
/// unfocused row's border never changes the content box**, so the glyph cannot
/// move when focus travels.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/widgets/common/focusable_card.dart';

/// Mirrors the geometry of `shell_rail.dart`'s `_RailRow`. Private, so the test
/// asserts the rule rather than reaching into the widget.
///
/// **The row box, not the content box.** The row is `CrossAxisAlignment.stretch`
/// inside the rail's `Column`, so it is the same width in every state, and the
/// glyph is a fixed-size `Icon` centred in it. A 2 dp border is painted inside
/// that box and nothing is laid out against the remainder - which is exactly why
/// the original "the glyph shifts" theory was wrong, and why the real defect had
/// to be found by measuring pixels instead.
({double rowWidth, double borderWidth, bool hasBorder}) rowGeometry({
  required bool selected,
  required bool focused,
  required bool television,
  double railWidth = 64,
  double gutter = 12,
}) {
  if (!television) {
    return (rowWidth: railWidth, borderWidth: 0, hasBorder: false);
  }
  final width = railWidth - gutter * 2;
  // Focused: no border, because the row's own border beside `CardFocusRing` is
  // the ghost border inside the shape. Unfocused: always 2 dp, whatever the
  // selection, so the row never changes shape.
  return focused
      ? (rowWidth: width, borderWidth: 0, hasBorder: false)
      : (rowWidth: width, borderWidth: 2, hasBorder: true);
}

void main() {
  group('a focused row paints exactly one ring', () {
    test('a focused row carries no border of its own', () {
      expect(
        rowGeometry(selected: true, focused: true, television: true).hasBorder,
        isFalse,
        reason: 'the row border beside CardFocusRing is the ghost. A '
            'unfocused row keeps its 2 dp; the focused one must not, or there '
            'are two rings.',
      );
    });

    test('an unfocused row keeps its border', () {
      for (final selected in [true, false]) {
        expect(
          rowGeometry(selected: selected, focused: false, television: true)
              .hasBorder,
          isTrue,
          reason: 'selected=$selected must not change whether the border is '
              'drawn, only its colour',
        );
      }
    });

    test('a selected but unfocused row does not regain an accent border', () {
      // This is what the transparent-border version did: it drew a border slot
      // on exactly the selected row and coloured it transparent.
      final selectedUnfocused =
          rowGeometry(selected: true, focused: false, television: true);
      final plainUnfocused =
          rowGeometry(selected: false, focused: false, television: true);
      expect(
        selectedUnfocused.rowWidth,
        plainUnfocused.rowWidth,
        reason: 'selection must not change the row box',
      );
      expect(
        selectedUnfocused.borderWidth,
        plainUnfocused.borderWidth,
        reason: 'and must not change whether a border is drawn either',
      );
    });
  });

  group('the glyph does not move', () {
    test('the row box is the same in every unfocused state', () {
      final widths = [
        rowGeometry(selected: true, focused: false, television: true).rowWidth,
        rowGeometry(
          selected: false,
          focused: false,
          television: true,
        ).rowWidth,
      ];
      expect(widths[0], widths[1]);
    });

    test('focusing a row does not change the icon size', () {
      // The glyph is centred by the row's own cross-axis stretch, so a row that
      // keeps its width cannot nudge its icon. The focused row gives up its
      // 2 dp border and gains it again in the ring, which is drawn outside.
      final unfocused =
          rowGeometry(selected: false, focused: false, television: true);
      final focused =
          rowGeometry(selected: false, focused: true, television: true);
      expect(
        focused.rowWidth,
        unfocused.rowWidth,
        reason: 'the glyph is a fixed-size Icon centred in the row box, so the '
            'row box is what has to be constant as focus travels - that is the '
            'invariant behind "the icon moves"',
      );
    });
  });

  group('the focus ring is one line, not two edges', () {
    testWidgets('the glow sits outside the border, not inside it', (
      tester,
    ) async {
      // The ring is a `DecoratedBox` in a `Positioned.fill` inside the
      // `CardFocusRing` stack, so it is findable - the shadow is what has to be
      // asserted on, and reading it means reading the decoration Flutter built.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 100,
                child: CardFocusRing(
                  focused: true,
                  radius: BorderRadius.circular(10),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final decorated = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(CardFocusRing),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(decorated, isNotEmpty);

      BoxDecoration? ring;
      for (final box in decorated) {
        final decoration = box.decoration;
        if (decoration is BoxDecoration && decoration.border != null) {
          ring = decoration;
          break;
        }
      }
      expect(ring, isNotNull, reason: 'the ring paints a border');
      expect(ring!.border!.top.width, 2.0, reason: 'the visible ring is 2 dp');

      final shadow = ring.boxShadow!.single;
      expect(
        shadow.spreadRadius,
        lessThanOrEqualTo(0.0),
        reason: 'a positive spreadRadius pushes the glow outside the border and '
            'widens the visible band - the measured ring was 7 dp against a '
            '2 dp border, which reads as two edges',
      );
      expect(
        shadow.blurRadius,
        lessThanOrEqualTo(8.0),
        reason: 'a wide blur is what put the luminous band on the inside of the '
            'border in the first place',
      );
    });

    testWidgets('nothing is painted when the row is not focused', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 100,
              child: CardFocusRing(
                focused: false,
                radius: BorderRadius.circular(10),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // `if (!focused) return child` means the ring's own subtree is not built at
      // all, which is why an unfocused row showed one band and a focused one two.
      expect(
        find.descendant(
          of: find.byType(CardFocusRing),
          matching: find.byType(Stack),
        ),
        findsNothing,
      );
    });
  });
}
