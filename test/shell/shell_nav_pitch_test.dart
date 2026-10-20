/// Guards the top nav's grouping.
///
/// The names used to be `Flexible` children of the bar's own `Row`, and a
/// flex child takes its share of the *leftover* width. The gap between two
/// names was therefore whatever the window had spare: on a wide desktop the
/// six destinations drifted to the far edge of the screen with the brand
/// stranded at the other, and the bar read as six things distributed over a
/// strip rather than as a menu.
///
/// The destinations are a group now, sized to their own content, and the
/// space goes after the group.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/shell/app_shell.dart';
import 'package:zplay/shell/shell_rail.dart';

/// The names the top bar carries, in the order it draws them.
const List<String> _destinations = <String>[
  'Home',
  'Browse',
  'Live TV',
  'Search',
  'Library',
  'Settings',
];

void main() {
  setUp(() => DeviceProfile.debugSetTelevision(value: false));
  tearDown(() => DeviceProfile.debugSetTelevision(value: false));

  Future<void> pumpRail(WidgetTester tester, Size canvas) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = canvas;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShellRail(
            current: ShellSlot.home,
            onSelect: (_) {},
            onLiveTv: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the destinations are a group against the brand', (
    tester,
  ) async {
    await pumpRail(tester, const Size(1920, 1080));

    final rects = <String, Rect>{};
    for (final name in _destinations) {
      final finder = find.text(name);
      expect(finder, findsWidgets, reason: '"$name" must be drawn');
      rects[name] = tester.getRect(finder.first);
    }

    // The group ends well before the middle of the bar. A bar whose
    // destinations are spread across it has no group to speak of, and the
    // user asked for them closer together - which is a statement about the
    // group, not about any one gap.
    final last = rects['Settings']!;
    expect(
      last.right,
      lessThan(1920 * 0.55),
      reason: 'the destinations must not drift to the far edge of the bar',
    );
  });

  testWidgets('the group starts at the brand, not in the middle', (
    tester,
  ) async {
    await pumpRail(tester, const Size(1920, 1080));

    final home = tester.getRect(find.text('Home').first);
    expect(
      home.left,
      lessThan(1920 * 0.12),
      reason: 'the destinations follow the brand from the left',
    );
  });

  testWidgets('the group does not grow with the window', (tester) async {
    // The same group at two widths: a bar whose pitch grew with the window
    // is the bug this guards.
    await pumpRail(tester, const Size(1920, 1080));
    final wide = tester.getRect(find.text('Settings').first).right -
        tester.getRect(find.text('Home').first).left;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await pumpRail(tester, const Size(1440, 900));
    final narrow = tester.getRect(find.text('Settings').first).right -
        tester.getRect(find.text('Home').first).left;

    expect(
      (narrow - wide).abs(),
      lessThan(2.0),
      reason: 'the group keeps its width when the window changes: '
          'wide=$wide narrow=$narrow',
    );
  });

  testWidgets('a narrow window shortens the names instead of overflowing', (
    tester,
  ) async {
    // The reason the names were flexible at all: six labelled destinations
    // plus the brand paint straight past the edge of a 600 dp window.
    await pumpRail(tester, const Size(600, 900));

    expect(tester.takeException(), isNull, reason: 'the bar must lay out');
    for (final name in _destinations) {
      final finder = find.text(name);
      if (finder.evaluate().isEmpty) continue;
      final rect = tester.getRect(finder.first);
      expect(
        rect.right,
        lessThanOrEqualTo(600),
        reason: '"$name" must not paint past the edge of the bar',
      );
    }
  });
}
