/// The Boxing row's second source family has to be visible, and honest about
/// being free.
///
/// A hit can now come from a public M3U playlist or the user's own import, not
/// just their Xtream panels. Those two families name themselves in the hit's
/// own source label (`Free Sports (iptv-org)`, `Your playlist: My Boxing`), so
/// the sheet renders that label as it always rendered a portal name - the
/// duplicate the ticket warned about is not there to add - and marks the row
/// with a neutral FREE chip. The chip is derived from the label's own words,
/// which is what keeps a paid panel from ever wearing one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zplay/pages/iptv/iptv_channel_sheet.dart';
import 'package:zplay/services/iptv/hardcoded_channels.dart';
import 'package:zplay/services/iptv/iptv_storage.dart';

/// The one channel this file seeds hits for. Its keywords are the `matches`
/// contract the controller re-checks a restored hit against.
final _channel = HardcodedChannels.byId('boxing_fight_sports')!;

/// A stored hit carrying [sourceLabel] as its portal name, the way the scan
/// persists a hit that did not come from an Xtream panel (no username).
StoredHit _storedFreeHit(String sourceLabel, {String url = 'http://free.example/fightbox.m3u8'}) =>
    StoredHit(
      portalUrl: url,
      portalUser: '',
      portalPass: '',
      portalName: sourceLabel,
      streamId: url,
      streamName: 'Fight Sports HD',
      streamIcon: '',
      streamCategoryId: '',
      streamContainerExt: 'm3u8',
      streamKind: 'live',
      streamUrl: url,
    );

/// A stored hit from a real panel: a username to show, so it is not mistaken
/// for a playlist label.
StoredHit _storedPortalHit() => const StoredHit(
      portalUrl: 'http://panel.example:8080',
      portalUser: 'john',
      portalPass: 'secret',
      portalName: 'Test panel',
      streamId: '4242',
      streamName: 'Fight Sports HD',
      streamIcon: '',
      streamCategoryId: '',
      streamContainerExt: 'ts',
      streamKind: 'live',
      streamUrl: 'http://panel.example:8080/live/john/secret/4242.ts',
    );

/// Pumps the sheet and waits - bounded, never settled - for [text] to appear.
///
/// The sheet restores its hits from storage in its own time, and its ambient
/// background never stops animating, so a settled frame is not something this
/// may assume.
Future<void> _pumpSheet(WidgetTester tester, String text) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: IptvChannelSheet(channel: _channel))),
  );

  for (var frame = 0; frame < 60; frame++) {
    if (find.text(text).evaluate().isNotEmpty) {
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('the row for "$text" never drew');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await IptvDeadUrlStore.instance.initialize();
  });

  testWidgets('a public playlist hit shows its label with a FREE chip', (
    tester,
  ) async {
    await IptvChannelResultsStore.save(_channel.id, [
      _storedFreeHit('Free Sports (iptv-org)'),
    ]);

    await _pumpSheet(tester, 'Free Sports (iptv-org)');

    expect(
      find.text('Free Sports (iptv-org)'),
      findsOneWidget,
      reason: 'the source label is the hit\'s own portal name, shown once',
    );
    expect(
      find.text('FREE'),
      findsOneWidget,
      reason: 'a public playlist source is free-to-air, so it is marked',
    );
  });

  testWidgets('a user playlist hit shows its label with a FREE chip', (
    tester,
  ) async {
    await IptvChannelResultsStore.save(_channel.id, [
      _storedFreeHit('Your playlist: My Boxing', url: 'http://mine.example/box.m3u8'),
    ]);

    await _pumpSheet(tester, 'Your playlist: My Boxing');

    expect(find.text('Your playlist: My Boxing'), findsOneWidget);
    expect(
      find.text('FREE'),
      findsOneWidget,
      reason: 'a playlist the user imported is free too',
    );
  });

  testWidgets('a paid portal hit wears no FREE chip', (tester) async {
    await IptvChannelResultsStore.save(_channel.id, [_storedPortalHit()]);

    await _pumpSheet(tester, 'john');

    expect(
      find.text('john'),
      findsOneWidget,
      reason: 'a panel hit still names the panel account, as it always did',
    );
    expect(
      find.text('FREE'),
      findsNothing,
      reason: 'nothing about a paid panel is free, and the label does not say so',
    );
  });
}
