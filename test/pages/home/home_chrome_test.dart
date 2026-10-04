/// Home used to carry its own navigation chrome: a brand wordmark and, before
/// that, the slot destinations, on top of whatever else was on screen. The
/// shell's top bar owns both now, so the page keeps one control row and it holds
/// only what is the page's - the All/Movies/Series/Anime pills and Home's two
/// page-level actions.
///
/// These pin the two things a de-duplication can break, and both are things a
/// user sees rather than things a widget is called:
///
/// 1. **The brand coming back.** A second logo or wordmark in the page's row is
///    the "two navigation bars on a television" report, and it is easy to
///    reintroduce by copying the old bar back in.
/// 2. **The pills going with it.** They are the one control the row still owes
///    the user, and they have to be reachable and to actually change the filter.
///    The filter is read off the Continue Watching rail, which is what the
///    filter *does* - asking the pill whether it is selected would let the
///    control agree with itself.
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
import 'package:zplay/widgets/common/zplay_logo.dart';
import 'package:zplay/widgets/home/continue_watching_slider.dart';

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

/// The addon Home loads its rails from. Two catalogs, so the pills have more
/// than one type to filter between and there is a rail whose filter is visible.
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

/// The filter the page's Continue Watching rail was built with: `null` for All,
/// `'main'` for Movies and Series, `'anime'` for Anime.
///
/// `skipOffstage: false`, and that is not a detail: a rail with nothing to show
/// renders a zero-extent box, and a `Viewport`'s `debugVisitOnstageChildren`
/// skips a sliver that paints nothing - so the default finder cannot see the
/// rail exactly when the filter has emptied it, which is the case this test is
/// about.
String? _railFilter(WidgetTester tester) => tester
    .widget<ContinueWatchingSlider>(
      find.byType(ContinueWatchingSlider, skipOffstage: false),
    )
    .typeFilter;

/// Where a duplicated brand would have to be: anywhere on the page.
///
/// This used to be scoped to the page's control row - the `Row` above the
/// filter pills. That split belongs to Browse now, so there is no such row left
/// to scope to, and the regression this guards is a second navigation bar
/// anyway: a page-wide search catches it wherever it is put back.
Finder get _pageBrand =>
    find.descendant(of: find.byType(HomePage), matching: find.byType(ZplayLogo));

/// Any content filter strip. Home has none: Browse owns that split.
///
/// Matched by predicate rather than `find.byType`, because a strip is built as
/// `TabStrip<T>` and `byType` compares the runtime type exactly - so
/// `find.byType(TabStrip)` resolves to `TabStrip<dynamic>` and would match
/// nothing, passing whether or not the page had one.
Finder get _filterStrip => find.byWidgetPredicate(
      (w) => w.runtimeType.toString().startsWith('TabStrip<'),
    );

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

/// Pumps past the cold-start intro splash and the home stream's arrival.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
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

  testWidgets('the page carries no brand and no filter strip of its own',
      (tester) async {
    await _mountHome(tester);
    await _settle(tester);

    expect(
      _pageBrand,
      findsNothing,
      reason: 'the shell top bar draws the brand mark. A second one on the '
          'page is the duplicated navigation bar this removes.',
    );
    expect(
      find.descendant(of: find.byType(HomePage), matching: find.text('ZPlay')),
      findsNothing,
      reason: 'the wordmark belongs to the shell, not to the page',
    );
    expect(
      _filterStrip,
      findsNothing,
      reason: 'Home is one feed. The All/Movies/Series/Anime strip filtered '
          'the same catalogue Browse already splits into verticals, so the page '
          'draws no filter of its own',
    );
  });


  testWidgets('the Continue Watching rail is the unfiltered one',
      (tester) async {
    await _mountHome(tester);
    await _settle(tester);

    // The rail used to be handed `'main'` or `'anime'` to match the tab row it
    // sat under, and the tests that pinned *that* pinned a control rather than a
    // behaviour: the pills, their per-press traversal and their centre-key
    // activation. They are gone with the strip, and what is left to assert is
    // the thing the filter was for - which rail the user actually gets.
    expect(
      _railFilter(tester),
      isNull,
      reason: 'one feed means the rail shows everything watched',
    );
  });

  testWidgets('the reserved top inset is the chrome the page actually draws',
      (tester) async {
    await _mountHome(tester);
    await _settle(tester);

    // The scroll body's first content pixel is the page's chrome plus its own
    // gap. It was 4 + 28 + 4 + 8 while the pill row set the row's height, and it
    // is [_televisionAppBarHeight] + 8 now that the row's content is the page's
    // two actions and the row is pinned to the bar's own height - the same 44,
    // which is the sort of coincidence that makes this worth pinning rather than
    // recomputing.
    //
    // The invariant is the same either way: the hero starts exactly one gap
    // under the chrome. It is the one that breaks silently, because a smaller
    // inset clips the hero under the row and a larger one leaves a gap nobody
    // asked for.
    final heroTop = tester.getRect(find.byType(PageView)).top;
    expect(
      heroTop,
      36 + 8,
      reason: 'the hero must start exactly one gap under the page row',
    );
  });
}
