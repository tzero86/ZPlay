/// Guards that Live TV keeps the shared shell chrome.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/pages/browse/browse_page.dart';
import 'package:zplay/pages/iptv/iptv_page.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/shell/app_shell.dart';
import 'package:zplay/shell/app_shell_scope.dart';
import 'package:zplay/shell/shell_rail.dart';
import 'package:zplay/widgets/common/tab_strip.dart';
import '../support/tv_nav_harness.dart';

Finder _browseVerticals() => find.byWidgetPredicate(
  (w) => w is TabStrip && w.semanticsLabel == 'Browse verticals',
  skipOffstage: false,
);

AppShellController _shell(WidgetTester tester) =>
    tester.widget<AppShellScope>(find.byType(AppShellScope)).controller;

Future<void> _openLiveTv(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  DeviceProfile.debugSetTelevision(value: true);
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = const Size(960, 540) * 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => DeviceProfile.debugSetTelevision(value: false));
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  await tester.pumpWidget(const MaterialApp(home: AppShell()));
  await tester.pump(const Duration(seconds: 2));
  _shell(tester).goBrowseVertical(BrowseVertical.liveTv);
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('Live TV keeps the shared top bar mounted', (tester) async {
    await _openLiveTv(tester);

    // The shared menu stays painted, and the page under it is the Live TV
    // vertical rather than a separate app with its own chrome.
    expect(find.byType(ShellRail), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ShellRail),
        matching: find.text('Live TV'),
      ),
      findsOneWidget,
      reason: 'the shared bar still names the destination it opened',
    );
    expect(find.byType(IptvPage, skipOffstage: false), findsWidgets);
    expect(
      tester.widget<TabStrip<BrowseVertical>>(_browseVerticals()).selected,
      BrowseVertical.liveTv,
    );
    // Live TV draws no second back button: the shell's own back guard is the
    // way out, so a stray press returns to the previous slot instead of
    // exiting the app.
    expect(
      find.descendant(
        of: find.byType(IptvPage),
        matching: find.byTooltip('Back'),
      ),
      findsNothing,
    );
  });

  testWidgets('UP from Live TV content reaches the shared menu', (
    tester,
  ) async {
    await _openLiveTv(tester);

    // The shell autofocuses its menu row on a television, so drive the tree
    // the way the remote does: DOWN into the page, then UP must return to
    // the menu it came from rather than stopping on a page-level trap. The
    // walk is logged by identity (the harness prints every press), and the
    // verdict is structural: the focused node sits under the shared rail.
    final intoPage = await pressDpad(
      tester,
      LogicalKeyboardKey.arrowDown,
      step: 'intoPage',
    );
    expect(intoPage.contains('focus=null'), isFalse,
        reason: 'down must leave the menu ($intoPage)');

    var inMenu = false;
    String last = intoPage;
    for (var i = 0; i < 40 && !inMenu; i++) {
      last = await pressDpad(
        tester,
        LogicalKeyboardKey.arrowUp,
        step: 'backUp$i',
      );
      final node = FocusManager.instance.primaryFocus;
      if (node == null) continue;
      node.context?.visitAncestorElements((ancestor) {
        if (ancestor.widget is ShellRail) {
          inMenu = true;
          return false;
        }
        return true;
      });
    }
    expect(
      inMenu,
      isTrue,
      reason: 'UP from Live TV content must reach the shared menu, landed $last',
    );
  });
}
