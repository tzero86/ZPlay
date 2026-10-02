import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/theme/design_tokens.dart';
import 'package:zplay/widgets/common/zplay_logo.dart';

/// The mark is drawn, not loaded.
///
/// It used to be `assets/icon_small.png`, a raster with `#2FD0C0` baked in,
/// which is how a palette change ended up shipping a teal logo on a red app.
/// Drawing it means it takes its colour from the theme.
///
/// These assert the properties that make that true. They deliberately do *not*
/// try to read pixels back: `RenderRepaintBoundary.toImage` never completes
/// under the test binding, and a golden would have to be regenerated whenever
/// the mark is touched - which is the coupling this change exists to remove.
void main() {
  testWidgets('the mark fills the size it is given, at every size it is used at',
      (tester) async {
    // 16 through 64 covers every call site: the rail is 24, the Home bar 34 and
    // `iconSize * 1.5`, Anime 32, the player 30, Addons 26.
    for (final size in <double>[16, 24, 26, 30, 32, 34, 64]) {
      await tester.pumpWidget(
        MaterialApp(home: Center(child: ZplayLogo(size: size))),
      );
      await tester.pump();

      final box = tester.getSize(find.byType(ZplayLogo));
      expect(box.width, size, reason: 'width at $size');
      expect(box.height, size, reason: 'height at $size');
    }
  });

  testWidgets('the mark paints a rounded square in the accent colour',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: ZplayLogo(size: 32))),
    );
    await tester.pump();

    // The fill is what the old raster had `#2FD0C0` hardcoded into it, so this
    // is the assertion that says "it follows the theme now": the square's colour
    // has to come from a token, not a literal.
    final boxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
    final filled = boxes.where((b) {
      final d = b.decoration;
      return d is BoxDecoration && d.color != null && d.borderRadius != null;
    });
    expect(filled, isNotEmpty,
        reason: 'the mark must draw a filled rounded square');

    final decoration =
        filled.first.decoration as BoxDecoration;
    expect(decoration.color, isNot(const Color(0xFF2FD0C0)),
        reason: 'the mark must not be pinned to the old teal; its colour comes '
            'from tokens.accent');
  });

  test('the glyph is a Z, not its mirror image', () {
    // The diagonal is the entire letter. Drawn top-left to bottom-right it is an
    // S, which is exactly what the first version painted - and a test asking only
    // "is a CustomPaint present" agreed with it.
    //
    // So this asserts the *shape*: the stroke must cross from the top bar's right
    // end down to the bottom bar's left end.
    final path = ZplayLogo.glyphPath(const Size(64, 64));
    final samples = <Offset>[];
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d <= metric.length; d += 1) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent != null) samples.add(tangent.position);
      }
    }
    expect(samples.length, greaterThan(4), reason: 'the path must have points');

    final bounds = path.getBounds();
    final midY = bounds.center.dy;
    final upper = samples.where((p) => p.dy < midY);
    final lower = samples.where((p) => p.dy >= midY);
    expect(upper, isNotEmpty, reason: 'the top half of the glyph');
    expect(lower, isNotEmpty, reason: 'the bottom half of the glyph');

    double mean(Iterable<Offset> points) =>
        points.map((p) => p.dx).reduce((a, b) => a + b) / points.length;

    expect(
      mean(upper),
      greaterThan(mean(lower)),
      reason: 'a Z descends to the LEFT. If the upper half is centred further '
          'left than the lower one, the diagonal is mirrored and the glyph is '
          'an S.',
    );
  });

  testWidgets('the mark takes its fill from the accent it is given', (tester) async {
    // The point of drawing it, stated as a fact about the widget rather than
    // about a theme swap: the fill is `tokens.accent`, so a different accent
    // produces a different square.
    //
    // Asserted by deriving two token sets and handing one to each build. An
    // earlier version swapped `ThemeData` on a live tree instead and compared
    // two identical colours, because a `ThemeExtension` only updates when the
    // theme object it hangs off actually changes identity.
    Widget build(Color accent) {
      final tokens = ZplayTokens.derive(
        accent: accent,
        bg: const Color(0xFF0A0D12),
        surface: const Color(0xFF111621),
        surfaceRaised: const Color(0xFF161C29),
      );
      return MaterialApp(
        theme: ThemeData(extensions: <ThemeExtension<dynamic>>[tokens]),
        home: const Center(child: ZplayLogo(size: 32)),
      );
    }

    final green = await _fillFor(
      tester,
      KeyedSubtree(key: const ValueKey('a'), child: build(const Color(0xFF00FF00))),
    );
    final red = await _fillFor(
      tester,
      KeyedSubtree(key: const ValueKey('b'), child: build(const Color(0xFFFF0000))),
    );

    expect(green, isNotNull);
    expect(red, isNotNull);
    expect(red, isNot(green),
        reason: 'the mark must take its colour from the theme, not from a '
            'constant baked into a file');
  });
}

Future<Color?> _fillFor(WidgetTester tester, Widget tree) async {
  await tester.pumpWidget(tree);
  await tester.pump();
  return _fillOf(tester);
}


/// The colour of the mark's rounded square, read off the widget tree rather
/// than off its pixels.
Color? _fillOf(WidgetTester tester) {
  // Scoped to the mark. `find.byType(DecoratedBox)` across the whole tree also
  // matches whatever Material wraps a button in, and the first hit may be one of
  // those - which is how this test compared two Material colours and found them
  // identical.
  final scoped = find.descendant(
    of: find.byType(ZplayLogo),
    matching: find.byType(DecoratedBox),
  );
  for (final box in tester.widgetList<DecoratedBox>(scoped)) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration &&
        decoration.color != null &&
        decoration.borderRadius != null) {
      return decoration.color;
    }
  }
  return null;
}
