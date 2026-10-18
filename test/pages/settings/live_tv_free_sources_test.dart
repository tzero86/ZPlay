/// Free public sources are a switch the user owns, and it has to survive a
/// restart.
///
/// The Boxing row now draws hits from public M3U playlists as well as the
/// user's own panels, and the switch is the only place that can be refused. It
/// is a plain row in this page's own idiom - `Switch.adaptive` beside a title
/// and a caption, like every neighbouring toggle - so it is focusable and
/// D-pad reachable for exactly the same reason they are, and its value is
/// persisted through `IptvSettings`' own setter rather than a second store.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zplay/pages/settings/appearance/live_tv_settings_page.dart';
import 'package:zplay/services/iptv/iptv_settings.dart';

const _title = 'Include Free Public Sources';

/// Mounts the page on a television-sized canvas and scrolls the switch's row
/// into view.
Future<void> _pumpPage(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const MaterialApp(home: LiveTvSettingsPage()));
  await tester.pump();

  await tester.scrollUntilVisible(
    find.text(_title),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

/// The switch inside the row titled [_title].
Finder _switchOfTheRow() => find.descendant(
      of: find
          .ancestor(of: find.text(_title), matching: find.byType(Row))
          .first,
      matching: find.byType(Switch),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('the row draws under its section and reflects the setting', (
    tester,
  ) async {
    await IptvSettings.initialize();
    await _pumpPage(tester);

    expect(
      find.text('STREAM SOURCES'),
      findsOneWidget,
      reason: 'the switch lives in its own section of the Live TV page',
    );
    expect(
      tester.widget<Switch>(_switchOfTheRow()).value,
      IptvSettings.includeFreeSources.value,
      reason: 'the switch reports the setting, it does not hold its own copy',
    );
    expect(
      IptvSettings.includeFreeSources.value,
      isTrue,
      reason: 'free public sources ship enabled',
    );
  });

  testWidgets('turning it off survives a restart', (tester) async {
    await IptvSettings.initialize();
    await _pumpPage(tester);

    await tester.ensureVisible(_switchOfTheRow());
    await tester.pump();
    await tester.tap(_switchOfTheRow());
    await tester.pump();

    expect(
      IptvSettings.includeFreeSources.value,
      isFalse,
      reason: 'the tap goes through the setting\'s own setter',
    );
    expect(
      tester.widget<Switch>(_switchOfTheRow()).value,
      isFalse,
      reason: 'the row re-reads the setting, so it shows the new value',
    );

    // The restart: a fresh load off disk, as the app does on boot.
    await IptvSettings.initialize();
    expect(
      IptvSettings.includeFreeSources.value,
      isFalse,
      reason: 'the setter persisted it; a restart must not bring it back',
    );

    await tester.pump();
    expect(tester.widget<Switch>(_switchOfTheRow()).value, isFalse);
  });

  testWidgets('a session that had it off opens with it off', (tester) async {
    await IptvSettings.setIncludeFreeSources(false);
    await IptvSettings.initialize();

    await _pumpPage(tester);

    expect(
      tester.widget<Switch>(_switchOfTheRow()).value,
      isFalse,
      reason: 'the page must read the stored value, not the shipped default',
    );
  });
}
