import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/pages/settings/addons_settings_page.dart';
import 'package:zplay/services/addon/debrid_addon_catalog.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// A tall surface keeps the connect section inside the viewport, so the section
/// actually builds and the text assertions are exact.
Future<void> pumpPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(wrap(const AddonsSettingsPage()));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// The built-in provider records the app ships, so the page never falls back to
/// seeding Cinemeta over the network during a widget test.
const String _builtinRecords = '[{"baseUrl":"builtin:zplay","manifest":{"id":"builtin.zplay",'
    '"name":"ZPlay","version":"3.0.0","resources":["stream"]},"enabled":true,'
    '"enableCatalogs":false,"enableSearch":false,"enableSubtitles":false,"enableStreams":true,'
    '"adultRating":"sfw"},{"baseUrl":"builtin:zplayhttp","manifest":{"id":"builtin.zplayhttp",'
    '"name":"ZPlayHTTP","version":"3.0.0","resources":["stream"]},"enabled":true,'
    '"enableCatalogs":false,"enableSearch":false,"enableSubtitles":false,"enableStreams":true,'
    '"adultRating":"sfw"}]';

void main() {
  testWidgets('offers the debrid addon for the selected service', (tester) async {
    SharedPreferences.setMockInitialValues({
      'flutter.installed_addons_v5': _builtinRecords,
      'flutter.debrid_service': 'Real-Debrid',
      'flutter.rd_access_token': 'x' * 52,
      'flutter.use_debrid_for_streams': true,
    });

    await pumpPage(tester);

    expect(find.text('DEBRID ADDONS'), findsOneWidget);
    expect(find.text('Torrentio'), findsWidgets);
    expect(find.textContaining('Real-Debrid key'), findsOneWidget);
    expect(find.text('Connect'), findsWidgets);
  });

  testWidgets('explains itself and disables connect without a debrid service', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'flutter.installed_addons_v5': _builtinRecords,
      'flutter.debrid_service': 'None',
    });

    await pumpPage(tester);

    expect(find.text('DEBRID ADDONS'), findsOneWidget);
    expect(
      find.text('No Debrid provider is set up yet'),
      findsOneWidget,
      reason: 'the user must be told why Connect is dead, not left guessing',
    );
  });

  testWidgets('the pasted URL footnote names the placeholder form', (tester) async {
    SharedPreferences.setMockInitialValues({
      'flutter.installed_addons_v5': _builtinRecords,
      'flutter.debrid_service': 'Real-Debrid',
      'flutter.rd_access_token': 'x' * 52,
    });

    await pumpPage(tester);

    expect(find.textContaining('{realdebrid}'), findsOneWidget);
    expect(find.textContaining('base64'), findsOneWidget);
  });

  test('the shipped template resolves to a keyless URL with one placeholder', () {
    // Keeps the catalog honest: a template must never carry a real key.
    final template = DebridAddonCatalog.byId('torrentio');
    expect(template, isNotNull, reason: 'the shipped catalog must still list torrentio');

    for (final entry in template!.baseUrlByService.entries) {
      expect(entry.value.contains('{'), isTrue,
          reason: '${entry.key} must use a placeholder');
      expect(entry.value.startsWith('https://torrentio.strem.fun/'), isTrue);
      expect(entry.value.contains(RegExp(r'[A-Za-z0-9]{40,}')), isFalse,
          reason: 'no key material may be committed');
    }
    expect(template.baseUrlFor('Nope'), isNull);
    expect(template.plainUrl, 'https://torrentio.strem.fun');
  });
}
