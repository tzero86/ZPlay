/// Pairing has to say what is missing, because what it used to report was the
/// end of the road.
///
/// Trakt answers `POST /oauth/device/code` with `400 client_id is required` when
/// the application id is empty - confirmed against the live endpoint, alongside
/// a Cloudflare `403 error code: 1010` for the same request sent with no
/// user-agent at all. An empty id is the normal state of a build that carries no
/// `.env`, so the page reported only "Failed to request Trakt pairing code." and
/// the user had nothing to act on. It now names the missing value and where it
/// comes from, *before* spending a request.
///
/// The second assertion is the one with teeth: the actionable message only
/// appears on the pre-check path, which returns before the request is built. If
/// the page had instead tried and failed, that text could not be on screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zplay/pages/settings/trakt_settings_page.dart';
import 'package:zplay/services/config/service_credentials.dart';
import 'package:zplay/services/trakt/trakt_constants.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ServiceCredentials.buildTimeOverridesForTesting.clear();
    await ServiceCredentials.initialize();
  });

  tearDown(() => ServiceCredentials.buildTimeOverridesForTesting.clear());

  testWidgets('pairing with no Client ID says so instead of failing blind',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TraktSettingsPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final pair = find.text('Pair Account');
    await tester.ensureVisible(pair);
    await tester.pump();
    await tester.tap(pair);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.textContaining(kTraktAppRegistrationUrl),
      findsOneWidget,
      reason: 'the page must name where the missing value comes from - and name '
          'the URL Trakt documents, which is not the one this used to carry',
    );
    expect(
      find.text('Failed to request Trakt pairing code.'),
      findsNothing,
      reason: 'that message was the dead end this replaces',
    );
  });
}
