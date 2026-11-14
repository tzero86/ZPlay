import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/widgets/common/baked_gradient.dart';

/// [BakedGradient] replaces live gradient shaders on the full-bleed scrims
/// (they froze scrolling on large Linux windows), so it has to paint the same
/// ramp: the first colour at the start of its axis, the last at the end.
void main() {
  Future<List<int>> sample(
    WidgetTester tester,
    Axis axis,
    List<Offset> points,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 200,
            height: 200,
            child: ColoredBox(
              color: Colors.white,
              child: BakedGradient(
                axis: axis,
                gradient: const LinearGradient(
                  colors: [Colors.black, Color(0x00000000)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    });
    return [
      for (final p in points)
        bytes!.getUint8(((p.dy.toInt() * 200) + p.dx.toInt()) * 4),
    ];
  }

  testWidgets('a vertical bake runs dark at the top to clear at the bottom', (
    tester,
  ) async {
    final reds = await sample(tester, Axis.vertical, const [
      Offset(100, 2),
      Offset(100, 100),
      Offset(100, 197),
    ]);
    expect(reds[0], lessThan(30), reason: 'top is the first colour: $reds');
    expect(reds[1], inInclusiveRange(90, 165), reason: 'midway: $reds');
    expect(reds[2], greaterThan(225), reason: 'bottom is clear: $reds');
  });

  testWidgets('a horizontal bake runs dark at the left to clear at the right', (
    tester,
  ) async {
    final reds = await sample(tester, Axis.horizontal, const [
      Offset(2, 100),
      Offset(197, 100),
    ]);
    expect(reds[0], lessThan(30), reason: 'left is the first colour: $reds');
    expect(reds[1], greaterThan(225), reason: 'right is clear: $reds');
  });
}
