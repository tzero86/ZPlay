/// Home on every surface the app ships to: a phone in portrait, a tablet, a
/// desktop window and a television.
///
/// The page's rails, hero and chrome are sized from the surface, so a width or a
/// height that the layout arithmetic did not anticipate shows up as
/// `RenderFlex overflowed` rather than as a missing widget. The framework reports
/// that error through `FlutterError.onError`, which the test binding hands back
/// from `takeException()` - so draining it and asserting the list is empty *is*
/// the overflow check, and it covers the whole page rather than one `Row`.
///
/// The harness is the one `test/pages/home/home_chrome_test.dart` uses: the
/// addon answers Home's catalogs, the metadata client answers nothing else, and
/// the splash is switched off through its stored flag so it cannot cover the
/// page being measured.
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
import 'package:zplay/widgets/home/continue_watching_slider.dart';
import 'package:zplay/widgets/home/hero_banner.dart';
import 'package:zplay/widgets/movie/movie_slider_section.dart';

/// One logical canvas Home is measured on.
class _Surface {
  const _Surface(this.label, this.size, {this.television = false});

  final String label;
  final Size size;

  /// Whether the platform reports a remote, which is the only thing that makes
  /// a surface a television; see [FormFactorService].
  final bool television;
}

const List<_Surface> _surfaces = [
  _Surface('phone 320x640', Size(320, 640)),
  _Surface('tablet 768x1024', Size(768, 1024)),
  _Surface('desktop 1440x900', Size(1440, 900)),
  _Surface('television 1920x1080', Size(1920, 1080), television: true),
];

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

/// The addon Home loads its rails from. Two catalogs, so the page has more than
/// the Continue Watching rail to lay out.
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

AppShellController _shellFor(_Surface surface) {
  final slot = ValueNotifier(ShellSlot.home);
  return AppShellController(
    current: slot,
    onSelect: (next) {
      slot.value = next;
      return true;
    },
    formFactor: () => FormFactorService.resolve(
      shortestSide: surface.size.shortestSide,
      remoteInput: surface.television,
    ),
  );
}

/// A dpr of 1 makes [TestFlutterView.physicalSize] the logical size, so the
/// surfaces below read as the numbers they name rather than as numbers divided
/// by a device scale nobody is testing here.
Future<void> _mountHome(WidgetTester tester, _Surface surface) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = surface.size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppShellScope(
        controller: _shellFor(surface),
        child: const Scaffold(body: HomePage()),
      ),
    ),
  );
}

/// Pumps past the home stream's arrival. Bounded rather than `pumpAndSettle`:
/// the ambient background repeats forever, so settling would never return.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 600));
}

/// Every exception the framework recorded while pumping, in the order it
/// recorded them, and with the binding's slot cleared so one surface's error is
/// not blamed on the next.
List<Object> _takeExceptions(WidgetTester tester) {
  final found = <Object>[];
  for (Object? error = tester.takeException(); error != null;) {
    found.add(error);
    error = tester.takeException();
  }
  return found;
}

/// The hero is the page's focal point. `skipOffstage: false` because a hero
/// inside a zero-extent viewport is still built, and its absence from the tree
/// is the regression this looks for - not whether it happens to paint on the
/// first frame.
Finder get _hero => find.byType(HeroBanner, skipOffstage: false);

/// The Continue Watching rail - the page's own row, which is built for every
/// user whether they have history or not.
///
/// The same offstage reasoning as [_hero] applies, and more so: a rail with
/// nothing to show lays out at zero extent and the default finder cannot see
/// it.
Finder get _continueWatching =>
    find.byType(ContinueWatchingSlider, skipOffstage: false);

/// A rail of catalog titles, which is the row the addon stream fills and the
/// one whose cards have to fit the width this surface gives them.
Finder get _catalogRail => find.byType(MovieSliderSection, skipOffstage: false);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'zplay_p2p_warning_never_show': true,
      // The one-shot cold-start splash must not cover the page being measured.
      'home_intro_seen': true,
    });
    AddonManager.readStoredForTesting = () async => _probeAddon;
    await AddonManager.instance.reload();
    DeviceProfile.debugSetTelevision(value: false);
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

  for (final surface in _surfaces) {
    testWidgets('Home lays out on ${surface.label} without overflow', (
      tester,
    ) async {
      // Only the television surface reports a remote; every other size is
      // classified by its shortest side.
      DeviceProfile.debugSetTelevision(value: surface.television);

      await _mountHome(tester, surface);
      await _settle(tester);

      final exceptions = _takeExceptions(tester);
      final overflows = exceptions.where(
        (error) => '$error'.contains('overflowed'),
      );
      expect(
        overflows,
        isEmpty,
        reason:
            '${surface.label}: a RenderFlex overflowed. The widget that owns '
            'that flex is too wide or too tall for this surface.',
      );
      expect(
        exceptions,
        isEmpty,
        reason:
            '${surface.label}: Home must mount and settle without throwing. '
            'The framework records layout and paint errors here.',
      );

      expect(
        _hero,
        findsOneWidget,
        reason:
            '${surface.label}: the hero is Home\'s focal point and is built '
            'for every form factor.',
      );
      expect(
        _continueWatching,
        findsOneWidget,
        reason:
            '${surface.label}: Home always carries its Continue Watching rail.',
      );
      expect(
        _catalogRail,
        findsAtLeastNWidgets(1),
        reason:
            '${surface.label}: the addon stream must fill at least one rail of '
            'titles.',
      );
    });
  }
}
