/// Guards the desktop nav's grouping.
///
/// The destinations used to drift across a full-width bar; then they were a
/// group against the brand. On desktop and tablet they are now one floating
/// capsule in the bar's trailing corner, as in the streaming UIs the app is
/// measured against: labelled destinations, then search and settings as icons.
/// These pin that it is one compact group, at the trailing edge, whose size
/// does not depend on the window.
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
  'Library',
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

  testWidgets('the destinations are one compact group', (tester) async {
    await pumpRail(tester, const Size(1920, 1080));

    final rects = <String, Rect>{};
    for (final name in _destinations) {
      final finder = find.text(name);
      expect(finder, findsWidgets, reason: '"$name" must be drawn');
      rects[name] = tester.getRect(finder.first);
    }
    // Search and Settings are icons in the same capsule, named by tooltip.
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);

    final span = rects['Library']!.right - rects['Home']!.left;
    expect(
      span,
      lessThan(1920 * 0.35),
      reason: 'the destinations read as one menu, not spread over the bar',
    );
  });

  testWidgets('the capsule sits in the trailing corner', (tester) async {
    await pumpRail(tester, const Size(1920, 1080));

    final settings = tester.getRect(find.byTooltip('Settings'));
    expect(
      settings.right,
      greaterThan(1920 - 64),
      reason: 'the capsule ends at the trailing edge, after the brand',
    );
    expect(
      tester.getRect(find.text('Home').first).left,
      greaterThan(1920 * 0.5),
      reason: 'the destinations live in the capsule, not after the brand',
    );
  });

  testWidgets('the group does not grow with the window', (tester) async {
    // The same group at two widths: a capsule whose pitch grew with the
    // window is the bug this guards.
    await pumpRail(tester, const Size(1920, 1080));
    final wide =
        tester.getRect(find.text('Library').first).right -
        tester.getRect(find.text('Home').first).left;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await pumpRail(tester, const Size(1440, 900));
    final narrow =
        tester.getRect(find.text('Library').first).right -
        tester.getRect(find.text('Home').first).left;

    expect(
      (narrow - wide).abs(),
      lessThan(2.0),
      reason:
          'the group keeps its width when the window changes: '
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
