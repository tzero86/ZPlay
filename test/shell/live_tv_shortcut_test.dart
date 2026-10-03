/// Guards the top bar's Live TV destination.
///
/// Live TV is the one destination in the prototype's top bar that is not a
/// [ShellSlot]: it is Browse with its `liveTv` vertical already selected. The
/// shell therefore cannot express it as a slot switch - Browse owns which
/// vertical it shows - so the shell publishes a request
/// (`AppShellController.goBrowseVertical`) and Browse listens. This drives the
/// real shell through the real tap, because the failure it guards is a broken
/// wire between the two: a bar row that switches to Browse but leaves the old
/// vertical on screen looks like it worked.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/pages/browse/browse_page.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/shell/app_shell.dart';
import 'package:zplay/shell/shell_rail.dart';
import 'package:zplay/widgets/common/tab_strip.dart';

/// Browse's own vertical switcher, which is offstage while another slot is on
/// screen: `IndexedStack` keeps every slot mounted but hides the inactive ones,
/// so the finder has to ask for offstage widgets too.
Finder _browseVerticals() => find.byWidgetPredicate(
  (w) => w is TabStrip && w.semanticsLabel == 'Browse verticals',
  skipOffstage: false,
);

void main() {
  tearDown(() => DeviceProfile.debugSetTelevision(value: false));

  testWidgets('the bar\'s Live TV destination selects the liveTv vertical',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    DeviceProfile.debugSetTelevision(value: true);
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(960, 540) * 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: AppShell()));
    // The cold-start splash holds a 1.8 s timer; let it fire rather than leave
    // the harness with a pending timer when the tree comes down.
    await tester.pump(const Duration(seconds: 2));

    expect(
      tester.widget<TabStrip<BrowseVertical>>(_browseVerticals()).selected,
      BrowseVertical.moviesAndTv,
      reason: 'Browse opens on Movies & TV',
    );

    final liveTv = find.descendant(
      of: find.byType(ShellRail),
      matching: find.text('Live TV'),
    );
    expect(liveTv, findsOneWidget, reason: 'the bar carries the shortcut');
    await tester.tap(liveTv);
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<TabStrip<BrowseVertical>>(_browseVerticals()).selected,
      BrowseVertical.liveTv,
      reason: 'the shell asked Browse for the liveTv vertical, and Browse '
          'switched to it rather than staying on the old one',
    );
  });
}
