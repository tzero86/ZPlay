/// Guards that nothing overflows at a phone width.
///
/// `IndexedStack` lays out every slot, not just the painted one, so an
/// over-wide row on one page draws its yellow and black stripes on all five
/// screens and looks like the whole app is broken. The hero's action row was
/// exactly that: three pills on a `Row` that wanted 492 dp, overflowing by 80
/// at 360 dp and by 28 at 412 dp.
///
/// A layout overflow is a consumer-visible defect the moment it happens, so it
/// is worth sweeping the whole shell at real phone widths rather than waiting
/// for someone to notice the stripes on their device. The widths are the two
/// most common phone buckets; a smaller one is a smaller screen, not a
/// different problem.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/shell/app_shell.dart';
import 'package:zplay/shell/shell_rail.dart';

void main() {
  tearDown(() => DeviceProfile.debugSetTelevision(value: false));

  for (final width in const [360.0, 412.0]) {
    testWidgets('the shell fits a $width dp phone without overflowing',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = Size(width * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final overflows = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.summary.toString();
        if (text.contains('overflowed')) overflows.add(text);
      };

      await tester.pumpWidget(const MaterialApp(home: AppShell()));
      await tester.pump(const Duration(seconds: 2));

      // Walk every slot so the painted screen is covered too. The overflow the
      // `IndexedStack` hides is still laid out and still asserted on above, so
      // this is belt and braces rather than the only path that finds it.
      for (final icon in const [
        Icons.home_rounded,
        Icons.grid_view_rounded,
        Icons.search_rounded,
        Icons.bookmark_rounded,
        Icons.settings_rounded,
      ]) {
        final row = find.descendant(
          of: find.byType(ShellRail),
          matching: find.byIcon(icon),
        );
        expect(row, findsOneWidget, reason: 'every slot has a rail row');
        await tester.tap(row, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      FlutterError.onError = previous;

      expect(
        overflows,
        isEmpty,
        reason: 'an over-wide row is painted over every screen, not just the '
            'page it lives on, so it must not be tolerated at any width',
      );
    });
  }
}
