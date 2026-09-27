/// Guards that the ten-foot rail is icons only and sized for the canvas.
///
/// Found by putting the build on a television. The rail was a labelled 236 dp,
/// which is a desktop number: 12% of a 1920 dp window, and comfortable. A
/// Chromecast with Google TV reports 1920x1080 at density 320, so Flutter
/// divides by 2.0 and the canvas is 960x540 dp - the same 236 dp is then a
/// quarter of the screen, and the labels truncate to `H...` and `Br...` on a
/// canvas that is also below the 600 dp phone breakpoint.
///
/// A first attempt scaled the rail by canvas width, 236 to 172 dp. It helped
/// and was still wrong, because it treated width as the only axis. At DPR 2
/// every logical pixel is two physical ones, so 172 dp is 344 physical pixels
/// of a 3840 px panel - twice the physical width of the desktop rail it was
/// copied from, with 30 physical pixels of label height. The proportion read
/// fine in a screenshot; the physical size, which is what crosses the room, did
/// not.
///
/// Dropping the labels removes the problem rather than tuning it, so this pins
/// the outcome and the reason rather than a formula: the ten-foot rail is the
/// same width as the pointer-device rail, and it draws no text.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/shell/app_shell.dart';
import 'package:zplay/shell/shell_rail.dart';

void _noop(ShellSlot slot) {}

/// Pumps the rail on the television canvas.
///
/// The size is the one the device reports: 1920x1080 at density 320 is 960x540
/// dp, and 540 is also below the 600 dp phone breakpoint, which is why the
/// wrong rail looked the way it did. It is bound through `tester.view`, which
/// the framework resets between tests; wrapping a `MediaQuery` around
/// `MaterialApp` instead does nothing, because `MaterialApp` builds its own
/// from the view and discards an outer one, so the rail reads the harness
/// default of 800x600 and a test written against a television silently
/// measures a desktop.
Future<void> _pump(WidgetTester tester, {required bool television}) async {
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1.0;

  DeviceProfile.debugSetTelevision(value: television);
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: ShellRail(current: ShellSlot.home, onSelect: _noop),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(() => DeviceProfile.debugSetTelevision(value: false));

  testWidgets('a television rail draws no text', (tester) async {
    await _pump(tester, television: true);

    // Not "nothing at all": the brand mark stays. It is the wordmark that had
    // to go - 88 dp cannot hold a 48 px mark and a word beside it, which is
    // what the old comment on `_head` said while the code rendered both and
    // overflowed by 94 px.
    for (final label in ['Home', 'Browse', 'Search', 'Library', 'Settings']) {
      expect(find.text(label), findsNothing,
          reason: 'a 344 physical pixel rail of which two thirds is label is '
              'the thing this change exists to stop');
    }
    expect(find.text('ZPlay'), findsNothing);
    expect(find.byType(Image), findsWidgets,
        reason: 'the mark is the brand at this width');
  });

  testWidgets('and a desktop rail is 88 dp wide too', (tester) async {
    // Measured on a desktop canvas, not the television's. Below a 600 dp
    // shortest side the rail becomes a bottom bar, so measuring a "pointer
    // rail" on a 540 dp tall canvas compares a side rail against a bottom bar
    // and the assertion means nothing.
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    DeviceProfile.debugSetTelevision(value: false);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShellRail(current: ShellSlot.home, onSelect: _noop),
        ),
      ),
    );
    await tester.pump();
    final desktopWidth = tester.getSize(find.byType(ShellRail)).width;

    await _pump(tester, television: true);
    final tvWidth = tester.getSize(find.byType(ShellRail)).width;

    expect(tvWidth, desktopWidth,
        reason: 'icons only means the ten-foot rail no longer needs to be wider '
            'than a pointer rail, and matching it removes the canvas dependency '
            'that mis-sized it in the first place');
  });

  testWidgets('the rail still names every row for a screen reader',
      (tester) async {
    await _pump(tester, television: true);
    final handle = tester.ensureSemantics();

    // Dropping the pixels must not drop the name: `Semantics` is the only thing
    // left carrying it, and a rail a screen reader cannot name is not
    // icon-only, it is nameless.
    for (final label in ['Home', 'Browse', 'Search', 'Library', 'Settings']) {
      expect(find.bySemanticsLabel(label), findsWidgets,
          reason: '"$label" must survive as semantics, not as pixels');
    }
    handle.dispose();
  });

  testWidgets('and the rail is a fraction of the canvas, not a quarter',
      (tester) async {
    await _pump(tester, television: true);
    final width = tester.getSize(find.byType(ShellRail)).width;

    // 88 dp of 960 dp. At DPR 2 that is 176 physical pixels of a 3840 px
    // panel, against 344 before.
    expect(width, 88);
    expect(width / 960, lessThan(0.1));
  });
}
