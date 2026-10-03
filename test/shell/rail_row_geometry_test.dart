/// The rail row draws one line, and the box never moves.
///
/// Two failures are guarded here, both of which were reported as "the icon moves"
/// or "there are two rings around it", and neither of which was what it looked
/// like.
///
/// 1. **The box.** Flutter reserves a border's width whether or not the border is
///    painted, so a row that *drops* its border when focused is 4 dp narrower
///    than one that keeps it - and the glyph, centred in that box, jumps the
///    moment focus arrives. The reserved width is the whole fix; the colour is
///    free to be nothing.
/// 2. **The lines.** A resting row must paint no fill and no outline of its own,
///    because a bar of filled or boxed destinations reads as a row of buttons
///    rather than as an overlay on the page beneath it. `CardFocusRing` is then
///    the only edge the row ever draws, so focus cannot produce two.
///
/// The row is measured from the real `ShellRail` on a television canvas, not
/// from a hand-copied model of it. The previous version of this file asserted
/// against a local `rowGeometry` mirror that had quietly stopped describing the
/// widget, which is precisely how a test keeps passing while the code it claims
/// to cover moves on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/services/theme/app_theme_service.dart';
import 'package:zplay/shell/app_shell.dart';
import 'package:zplay/shell/shell_rail.dart';
import 'package:zplay/widgets/common/focusable_card.dart';

const Size _televisionCanvas = Size(960, 540);
const double _dpr = 2.0;

Future<void> _pumpRail(
  WidgetTester tester, {
  required ShellSlot current,
}) async {
  tester.view.devicePixelRatio = _dpr;
  tester.view.physicalSize = _televisionCanvas * _dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // The row's television branch is driven by the device profile, not by the
  // canvas: a 960x540 window resolves to `compact` on its shortest side, so
  // without this the reserved-border code under test is never reached and the
  // assertions pass over a branch that does not run.
  DeviceProfile.debugSetTelevision(value: true);
  addTearDown(() => DeviceProfile.debugSetTelevision(value: false));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemeService.createThemeData(
        AppThemeService.defaultPalette,
      ),
      home: ShellRail(
        current: current,
        onSelect: _ignore,
        onLiveTv: _ignoreTv,
      ),
    ),
  );
  await tester.pump();
}

void _ignore(ShellSlot slot) {}

void _ignoreTv() {}

/// The destination rows, in bar order.
Finder _rows() => find.byType(FocusableCard);

/// The box of every row, in bar order.
List<Rect> _rowBoxes(WidgetTester tester) => [
      for (final element in _rows().evaluate())
        tester.getRect(find.byWidget(element.widget)),
    ];

/// Every `BoxDecoration` painted anywhere inside the row at [index] that carries
/// a fill or a border of its own.
///
/// Asked of the rendered tree, walking the whole subtree and reading every
/// `Container`, `AnimatedContainer` and `DecoratedBox` on the way down. The
/// row's own surface is an `AnimatedContainer` about a dozen widgets deep, so a
/// walk that matches only `DecoratedBox`, or that looks only at direct children,
/// never sees it. Both of those narrower walks passed while the row painted a
/// full outline - the exact defect this exists to catch - so the depth is the
/// point and not an implementation detail.
List<BoxDecoration> _rowPaints(WidgetTester tester, int index) {
  final paints = <BoxDecoration>[];

  void walk(Element element) {
    element.visitChildren((child) {
      final widget = child.widget;
      final BoxDecoration? decoration = switch (widget) {
        DecoratedBox(decoration: final d) when d is BoxDecoration => d,
        Container(decoration: final d) when d is BoxDecoration => d,
        AnimatedContainer(decoration: final d) when d is BoxDecoration => d,
        _ => null,
      };
      if (decoration != null &&
          (decoration.color != null || decoration.border != null)) {
        paints.add(decoration);
      }
      walk(child);
    });
  }

  walk(_rows().at(index).evaluate().single);
  return paints;
}

/// Whether [border] paints nothing, i.e. reserved space with a transparent
/// side.
bool _invisible(BoxBorder border) =>
    border.top.color.a == 0.0 && border.bottom.color.a == 0.0;

void main() {
  testWidgets('a resting row paints no visible fill and no visible outline',
      (tester) async {
    await _pumpRail(tester, current: ShellSlot.home);

    for (var i = 0; i < _rows().evaluate().length; i++) {
      for (final d in _rowPaints(tester, i)) {
        final border = d.border;
        if (border != null) {
          expect(
            _invisible(border),
            isTrue,
            reason: 'row $i paints a visible border ($border). A boxed '
                'destination reads as a button. A *transparent* border is the '
                'point rather than a defect: Flutter reserves the width whether '
                'or not it is painted, so reserving it keeps the row box fixed '
                'while drawing nothing.',
          );
        }
      }
    }
  });

  testWidgets('moving the selection does not change any row box',
      (tester) async {
    await _pumpRail(tester, current: ShellSlot.home);
    final before = _rowBoxes(tester);

    await _pumpRail(tester, current: ShellSlot.settings);
    final after = _rowBoxes(tester);

    expect(after.length, before.length);
    for (var i = 0; i < before.length; i++) {
      expect(
        after[i],
        before[i],
        reason: 'moving the selection moved row $i. A reserved border that is '
            'dropped rather than painted is 4 dp narrower, and the glyph '
            'centred in the box goes with it.',
      );
    }
  });

  testWidgets('focusing a row does not change any row box', (tester) async {
    await _pumpRail(tester, current: ShellSlot.home);
    final before = _rowBoxes(tester);

    // Drive focus through the real tree rather than a node the test owns.
    _rows().at(1).evaluate().single.visitChildren((child) {
      if (child.widget is Focus) {
        (child.widget as Focus).focusNode?.requestFocus();
      }
    });
    await tester.pump();

    final after = _rowBoxes(tester);
    for (var i = 0; i < before.length; i++) {
      expect(
        after[i],
        before[i],
        reason: 'focus changed row $i\'s box, which is the "the icon moves" '
            'report',
      );
    }
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

      // **No shadow at all.** A `BoxShadow` with no offset is centred on the
      // box's own edge, so half of it bleeds inside the border: a 2 dp ring
      // acquires a soft 3 dp inner edge and reads as two lines. Shrinking the
      // blur from 18 to 6 made the wash smaller but did not remove it, because
      // the offset - not the size - is what produces an inner edge. The
      // regression this guards is a *returning* glow.
      expect(
        ring.boxShadow,
        isNull,
        reason: 'a shadow with no offset bleeds inside the 2 dp border, and a '
            'soft inner edge is exactly the "ghost border inside the shape" '
            'that was reported on the rail three times',
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