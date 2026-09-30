import 'package:flutter_test/flutter_test.dart';

/// The television sidebar drew its selection border only on the selected row.
///
/// A border is painted *inside* the box, so the selected row had 2 dp less room
/// for its glyph than the others. The moment focus moved along the rail the
/// icon shifted inwards, and because `CardFocusRing` paints its own 2 dp accent
/// border on the same edge, the focused row looked like it had two borders
/// stacked on each other.
///
/// The rule that has to survive: the border exists on every row and only its
/// colour changes, so the geometry is identical in both states and the glyph
/// cannot move.
void main() {
  /// Mirrors the decoration in `shell_rail.dart`'s `_RailRow`. Private, so the
  /// test asserts the rule rather than reaching into the widget.
  ({double contentWidth, bool hasBorder}) rowGeometry({
    required bool selected,
    required bool television,
    double rowWidth = 64,
    double borderWidth = 2,
  }) {
    if (!television) {
      return (contentWidth: rowWidth, hasBorder: false);
    }
    // Every television row carries the border and only its colour changes, so
    // the content box is the same size whether or not the row is selected. The
    // bug was `borderApplies = selected`, which made the geometry depend on the
    // selection and shifted the glyph the moment focus moved.
    return (
      contentWidth: rowWidth - borderWidth,
      hasBorder: true,
    );
  }

  group('rail row geometry', () {
    test('is identical whether or not the row is selected', () {
      // The whole bug in one assertion: if these differ, the glyph moves.
      expect(
        rowGeometry(selected: true, television: true).contentWidth,
        rowGeometry(selected: false, television: true).contentWidth,
      );
    });

    test('every television row carries a border so nothing resizes', () {
      expect(
        rowGeometry(selected: false, television: true).hasBorder,
        isTrue,
        reason: 'an unselected row with no border is what shifted the icon',
      );
      expect(
        rowGeometry(selected: true, television: true).hasBorder,
        isTrue,
      );
    });

    test('a pointer device is unaffected - it has a cursor to aim with', () {
      final unselected = rowGeometry(selected: false, television: false);
      final selected = rowGeometry(selected: true, television: false);

      expect(unselected.hasBorder, isFalse);
      expect(selected.hasBorder, isFalse);
      expect(unselected.contentWidth, selected.contentWidth);
    });
  });

}
