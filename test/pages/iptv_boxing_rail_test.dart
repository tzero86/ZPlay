/// The Boxing rail is one row of the Live page's own category list, so it obeys
/// the two rules every other row obeys: it draws when the user's list contains
/// it, and it goes away when they hide it. Unlike every other row it also
/// carries feed health - a fight-night viewer is picking the source to press -
/// so what that rail is handed, and what its neighbours are not, is pinned here.
///
/// The rail's content is asserted against `HardcodedChannels.byCategory('Boxing')`
/// rather than against any specific channel: the category name is the contract,
/// the line-up behind it is free to change.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/pages/iptv/iptv_page.dart';
import 'package:zplay/services/iptv/hardcoded_channels.dart';
import 'package:zplay/services/iptv/iptv_settings.dart';
import 'package:zplay/services/theme/glass_settings.dart';
import 'package:zplay/widgets/iptv/iptv_health_badge.dart';
import 'package:zplay/widgets/iptv/iptv_slider_section.dart';

/// The rail titled [title], or null when the page did not draw it.
IptvSliderSection? _railOrNull(WidgetTester tester, String title) {
  for (final rail
      in tester.widgetList<IptvSliderSection>(find.byType(IptvSliderSection))) {
    if (rail.title == title) return rail;
  }
  return null;
}

/// Pumps until [read] yields a value, then returns it.
///
/// Bounded pumps rather than `pumpAndSettle`: this page mounts a rotating hero
/// and a live ambient background when they are enabled, so a settled frame is
/// not something a test may assume, and the rail's health map is read off
/// `SharedPreferences` in the page's own time. Sixty frames of twenty
/// milliseconds is a second of fake time - far past any of this - and the loop
/// gives up rather than hanging.
Future<T> _pumpFor<T>(
  WidgetTester tester,
  T? Function() read, {
  String because = 'the expected value never arrived',
}) async {
  for (var frame = 0; frame < 60; frame++) {
    final value = read();
    if (value != null) return value;
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail(because);
}

/// Mounts the Live page on a canvas tall enough to lay out more than its hero.
///
/// The spotlight is off for the same reason: a 400 dp hero would push the rail
/// under test below the fold, and a lazily built list never builds what it
/// cannot show.
Future<void> _pumpLivePage(
  WidgetTester tester,
  List<String> categories,
) async {
  // One verified portal, so the controller's init has nothing to go looking
  // for: this test is about a rail, and a scrape in the background would make
  // it a test about the network.
  SharedPreferences.setMockInitialValues(<String, Object>{
    'pt_iptv_verified_portals': jsonEncode([
      {
        'url': 'http://panel.example:8080',
        'username': 'john',
        'password': 'secret',
        'source': 'test',
        'name': 'Test panel',
        'expiry': '',
        'max': '1',
        'active': '0',
      },
    ]),
  });
  IptvSettings.visibleCategories.value = List<String>.from(categories);
  IptvSettings.enableSpotlight.value = false;
  // The plain path, as the other page and player tests take it: the rails under
  // test are the same either way, and this keeps the lens out of the picture.
  final glassWasEnabled = GlassSettings.enabled.value;
  GlassSettings.enabled.value = false;
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 2000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() {
    GlassSettings.enabled.value = glassWasEnabled;
    IptvSettings.visibleCategories.value =
        List.from(IptvSettings.defaultCategories);
    IptvSettings.enableSpotlight.value = true;
  });

  await tester.pumpWidget(const MaterialApp(home: IptvPage()));
  await tester.pump();
}

void main() {
  final boxing = HardcodedChannels.byCategory('Boxing');

  testWidgets('the Boxing rail draws when the user list contains it', (
    tester,
  ) async {
    await _pumpLivePage(tester, const ['Boxing', 'Kids & Family']);

    final rail = await _pumpFor(
      tester,
      () => _railOrNull(tester, 'Boxing'),
      because: 'visibleCategories contains Boxing, so the rail must draw',
    );

    expect(
      rail.channels,
      boxing,
      reason: 'the rail shows exactly the curated Boxing bucket',
    );
    expect(
      boxing,
      isNotEmpty,
      reason: 'a category with no channels would draw nothing at all',
    );
  });

  testWidgets('only the Boxing rail is given feed health', (tester) async {
    await _pumpLivePage(tester, const ['Boxing', 'Kids & Family']);

    final rail = await _pumpFor(
      tester,
      () {
        final rail = _railOrNull(tester, 'Boxing');
        if (rail?.healthByChannelId?.length != boxing.length) return null;
        return rail;
      },
      because: 'the Boxing rail never received a health entry per channel',
    );

    expect(
      rail.healthByChannelId!.keys.toSet(),
      boxing.map((channel) => channel.id).toSet(),
    );
    expect(
      rail.healthByChannelId!.values.toSet(),
      {IptvHitHealth.unknown},
      reason: 'nothing has probed these channels in this test, and an '
          'unprobed channel must read neutral rather than broken',
    );

    final neighbours = tester
        .widgetList<IptvSliderSection>(find.byType(IptvSliderSection))
        .where((rail) => rail.title != 'Boxing');
    expect(
      neighbours,
      isNotEmpty,
      reason: 'a second rail must be on screen, or "only Boxing" says nothing',
    );
    expect(
      neighbours.map((rail) => rail.healthByChannelId),
      everyElement(isNull),
      reason: 'every other rail keeps the cards it shipped with',
    );
  });

  testWidgets('the Boxing rail is gone when the user hides it', (tester) async {
    await _pumpLivePage(tester, const ['Kids & Family']);

    final kids = await _pumpFor(
      tester,
      () => _railOrNull(tester, 'Kids & Family'),
      because: 'the page must still draw the rails it was asked for, or the '
          'absence below proves nothing',
    );
    expect(kids.channels, isNotEmpty);
    expect(_railOrNull(tester, 'Boxing'), isNull);
    expect(
      find.text('Boxing', skipOffstage: false),
      findsNothing,
      reason: 'no heading, card or tag on the page may still say Boxing',
    );
  });
}
