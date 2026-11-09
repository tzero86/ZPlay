/// The cold-start splash used to be process state: a `static` flag in the page
/// state. That flag is gone after a restart, so every launch replayed 1.8 s of
/// logo over an app the user had already opened, and it could not be dismissed
/// at all. Both are user-visible bugs, so both are pinned here as behaviour:
///
/// 1. **A fresh install shows it exactly once, and a tap ends it.** The stored
///    flag is asserted after the splash has appeared, because that is when it is
///    written - a flag written on dismissal would replay the splash if the app
///    were killed while it was showing.
/// 2. **An install that has seen it never shows it.** The finder is the overlay
///    key rather than the wordmark, so the assertion cannot pass merely because
///    the text moved somewhere else on the page.
///
/// Every wait is a bounded `pump`: the splash runs an 1800 ms timer plus a
/// loading poll, and `pumpAndSettle` would either deadlock on the poll or race
/// the first catalog response. The harness - addon, catalog routing and the
/// shell scope - is the one Home's other page tests use.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/pages/home/home_page.dart';
import 'package:zplay/services/addon/addon_manager.dart';
import 'package:zplay/services/home/home_page_settings.dart';
import 'package:zplay/services/layout/form_factor.dart';
import 'package:zplay/services/metadata/metadata_service.dart';
import 'package:zplay/shell/app_shell_scope.dart';

/// The overlay's own handle. It exists only while the splash is on screen, so
/// `findsNothing` means "not covering the page", which is the property that
/// matters: a mounted-but-transparent overlay still swallows every tap.
const Key _introOverlay = Key('home-intro');

/// The preference the splash is gated on.
const String _introSeenKey = 'home_intro_seen';

/// A catalog payload with [count] titles, in the shape Cinemeta returns.
String _catalogJson(int count, String type) {
  return jsonEncode({
    'metas': [
      for (var i = 0; i < count; i++)
        {
          'id': 'tt-probe-$type-$i',
          'name': 'Probe $i',
          'type': type,
          'releaseInfo': '2024',
          'poster': 'https://example.invalid/p$i.jpg',
        },
    ],
  });
}

/// Answers catalog reads with test data and everything else with a 503, so a
/// page that reaches for the network without an addon installed fails fast
/// rather than hanging on a fake clock.
class _RouteCatalogs extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url;
    final type = url.queryParameters['type'] ?? 'movie';
    final body = url.path.contains('/catalog/') ? _catalogJson(4, type) : null;
    return http.StreamedResponse(
      body == null
          ? const Stream<List<int>>.empty()
          : Stream.value(utf8.encode(body)),
      body == null ? 503 : 200,
      request: request,
    );
  }
}

/// The addon Home loads its rails from. One catalog is enough: the splash does
/// not depend on what the page ends up showing behind it.
final String _probeAddon = jsonEncode([
  {
    'id': 'com.probe.stremio',
    'baseUrl': 'https://v3-cinemeta.strem.io',
    'enabled': true,
    'enableCatalogs': true,
    'name': 'Probe',
    'manifest': {
      'id': 'com.probe.stremio',
      'name': 'Probe',
      'version': 'v1.0.0',
      'description': 'test',
      'catalogs': [
        {'type': 'movie', 'id': 'zplay-probe-movies', 'name': 'Probe Movies'},
        {'type': 'series', 'id': 'zplay-probe-series', 'name': 'Probe Series'},
      ],
    },
  },
]);

AppShellController _shellReportingHome() {
  final slot = ValueNotifier(ShellSlot.home);
  return AppShellController(
    current: slot,
    onSelect: (next) {
      slot.value = next;
      return true;
    },
    formFactor: () => FormFactor.television,
  );
}

Future<void> _mountHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppShellScope(
        controller: _shellReportingHome(),
        child: const Scaffold(body: HomePage()),
      ),
    ),
  );
}

/// Lets the asynchronous preference read finish and settle the page's first
/// catalog response. Bounded, because the splash's own timer would keep
/// `pumpAndSettle` from ever returning while it is up.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<bool?> _storedIntroSeen() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_introSeenKey);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'zplay_p2p_warning_never_show': true,
    });
    AddonManager.readStoredForTesting = () async => _probeAddon;
    await AddonManager.instance.reload();
    DeviceProfile.debugSetTelevision(value: true);
    MetadataService.client = _RouteCatalogs();
    HomePageSettings.heroAutoRotate.value = false;
  });

  tearDown(() {
    AddonManager.readStoredForTesting = null;
    DeviceProfile.debugSetTelevision(value: false);
    HomePageSettings.heroAutoRotate.value = true;
    MetadataService.clearCache();
    MetadataService.client = http.Client();
  });

  testWidgets('a fresh install shows the splash once, and a tap dismisses it', (
    tester,
  ) async {
    await _mountHome(tester);
    final semantics = tester.ensureSemantics();
    // The read is asynchronous by design, so the splash is a frame or two late;
    // what must not happen is it being late enough to be missed entirely.
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(_introOverlay),
      findsOneWidget,
      reason: 'no stored flag means this install has never seen the splash',
    );
    expect(
      find.text('ZPlay'),
      findsOneWidget,
      reason: 'the splash is what the user actually sees, not just a key',
    );
    expect(
      find.bySemanticsLabel('Skip intro'),
      findsOneWidget,
      reason:
          'a splash that only responds to a tap is not skippable by '
          'anything that cannot tap',
    );
    // Disposed here rather than in a teardown: the test binding checks for
    // leaked handles before teardowns run.
    semantics.dispose();
    expect(
      await _storedIntroSeen(),
      isTrue,
      reason:
          'the flag is written when the splash is shown, so an app killed '
          'mid-splash does not replay it',
    );

    await tester.tap(find.byKey(_introOverlay));
    await tester.pump();

    expect(
      find.byKey(_introOverlay),
      findsNothing,
      reason: 'a tap is the skip control; the splash must not need the timer',
    );

    // The intro's 1800 ms wait is still pending here. It must not bring the
    // splash back, and it must not re-run the startup dialogs.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(_introOverlay),
      findsNothing,
      reason: 'the late intro completion must be inert after a skip',
    );

    expect(await _storedIntroSeen(), isTrue);
  });

  testWidgets('an install that has seen the splash never shows it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'zplay_p2p_warning_never_show': true,
      _introSeenKey: true,
    });

    await _mountHome(tester);

    // Sample the whole window the splash would occupy, not just the end of it:
    // showing for one frame is exactly the flash this flag removes.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(_introOverlay),
        findsNothing,
        reason: 'the stored flag means the splash is skipped on this launch',
      );
    }

    await _settle(tester);
    expect(find.byKey(_introOverlay), findsNothing);
    // The page behind it is the one that was actually mounted, not an empty
    // tree that happens to have no splash.
    expect(find.byType(HomePage), findsOneWidget);
    expect(await _storedIntroSeen(), isTrue);
  });
}
