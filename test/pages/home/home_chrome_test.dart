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
import 'package:flutter/services.dart';
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

/// The page's own control row, asked of the tree: the outermost `Row` above the
/// filter pills. Everything the row is allowed to contain is a descendant of it,
/// so this is where a duplicated brand would have to be.
Finder get _controlRow =>
    find.ancestor(of: find.text('All'), matching: find.byType(Row)).last;

/// The pills' own row: the innermost `Row` above the first label.
///
/// `_controlRow` above is the *outermost*, so the page's whole row is available
/// to the "no duplicated brand" assertions. This one is the narrowest, which is
/// what the height measurement below wants.
Finder get _pillRow =>
    find.ancestor(of: find.text('All'), matching: find.byType(Row)).first;

/// The focus node of one filter pill. A pill is a `FocusableCard`, so the
/// nearest `Focus` above its label is the node a remote would land on.
FocusNode? _pillNode(WidgetTester tester, String label) => tester
    .widget<Focus>(
      find.ancestor(of: find.text(label), matching: find.byType(Focus)).first,
    )
    .focusNode;

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

/// Focuses one pill the way a remote arriving at the row would.
Future<void> _focusPill(WidgetTester tester, String label) async {
  final node = _pillNode(tester, label);
  expect(node, isNotNull, reason: 'the "$label" pill must be a real focus node');
  node!.requestFocus();
  await tester.pump();
  expect(node.hasFocus, isTrue, reason: 'the "$label" pill must take focus');
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

  testWidgets('the page control row carries no brand of its own',
      (tester) async {
    await _mountHome(tester);
    await _settle(tester);

    expect(
      find.text('All'),
      findsOneWidget,
      reason: 'precondition: the filter pills are in the page row',
    );

    expect(
      find.descendant(of: _controlRow, matching: find.byType(ZplayLogo)),
      findsNothing,
      reason: 'the shell top bar draws the brand mark. A second one in the '
          'page row is the duplicated navigation bar this change removes.',
    );
    expect(
      find.descendant(of: _controlRow, matching: find.text('ZPlay')),
      findsNothing,
      reason: 'the wordmark belongs to the shell, not to the page row',
    );
  });


// **Why the pill row carries no explicit traversal order.**
//
// There is no test here for "RIGHT walks the pills one at a time" because a
// widget test cannot reproduce the thing that looked broken. A test that sends
// arrow keys and watches `primaryFocus` passes whether the row has a
// `FocusTraversalGroup` or not: the harness resolves directional focus by
// declared widget order, while the engine scores it geometrically on the
// device. Verified by deleting the group and re-running - still green.
//
// The device measurement that settled it, from logcat focus rects (logical dp,
// top then left of the focused node) on the 960x540 set:
//
//   DOWN  from the top bar -> top 71, left 52    (Movies - under "Home")
//   RIGHT                   -> top 71, left 152   (Series)
//   RIGHT                   -> top 71, left 226   (Anime)
//
// One pill per press, left to right, which is what it should be. The apparent
// skip was DOWN landing on Movies rather than All: "Movies" is what sits
// directly beneath the "Home" destination in the bar above. So DOWN, RIGHT,
// RIGHT visited Movies, Series, Anime and read as a row that had been jumped
// over. A `FocusTraversalGroup(OrderedTraversalPolicy)` was added on that
// reading, changed nothing on the device, and was removed rather than left in
// as decoration.

  testWidgets('a pill takes focus and its centre key switches the filter',
      (tester) async {
    await _mountHome(tester);
    await _settle(tester);

    // All is the landing filter, so the rail below the hero is unfiltered.
    expect(_railFilter(tester), isNull);

    await _focusPill(tester, 'Movies');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      _railFilter(tester),
      'main',
      reason: 'the centre key on a focused pill is what ActivateIntent sends, '
          'and it has to reach the filter',
    );

    await _focusPill(tester, 'Anime');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_railFilter(tester), 'anime');

    await _focusPill(tester, 'All');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_railFilter(tester), isNull, reason: 'All is the unfiltered page');
  });

  testWidgets('the reserved top inset is the chrome the page actually draws',
      (tester) async {
    await _mountHome(tester);
    await _settle(tester);

    // The pill row is the page's chrome, and it is the tallest thing in it.
    //
    // This was a `SegmentedTabs` and so was a 28 dp track with a 3 dp inset;
    // the row is now the pills themselves. The invariant that matters is
    // unchanged - the row is 28 dp and sits 4 dp down - because a `Border` in a
    // `BoxDecoration` is still charged to the container's box, so a hairline
    // would still take a dp off it.
    final track = tester.getRect(_pillRow);
    expect(
      track.height,
      28,
      reason: 'the ten-foot pill row is 28 dp. A `BoxDecoration` border is '
          'charged to the container padding, so a hairline drawn in '
          '`decoration` quietly takes a dp off this row.',
    );
    expect(
      track.top,
      4,
      reason: '4 dp of breathing room, and no shell bar above it inside the '
          'page - the shell reserves its own space as a layout child',
    );

    // And the scroll body's first content pixel is the row plus its gap: the
    // hero's top. A smaller inset clips the hero under the row, a larger one
    // leaves the second gap this change exists to remove.
    final heroTop = tester.getRect(find.byType(PageView)).top;
    expect(
      heroTop,
      4 + 28 + 4 + 8,
      reason: 'the hero must start exactly one gap under the page row',
    );
  });
}
