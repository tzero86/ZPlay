/// The hero carousel must survive its parent rebuilding.
///
/// The hero was permanently stuck on its first slide: every visit showed the
/// same title, and no press of the indicator ever moved it. The cause was
/// `_HeroCarouselState.didUpdateWidget`, which reset the carousel to slide 0
/// whenever `oldWidget.movies != widget.movies`. Dart's `List` `!=` is
/// *identity*, and the page hands the carousel `pickFeatured(_visibleSections)`
/// through a getter that rebuilds the list on every read - so every parent
/// rebuild looked like "the slide list changed" and the carousel snapped home.
/// Worse, changing slide reports its backdrop (`_reportBackdrop` ->
/// `_onHeroBackdropChanged` -> the page's own `setState`), so the rebuild that a
/// slide change *causes* snapped it straight back: the carousel could never
/// leave slide 0 at all.
///
/// The rule this pins is the one the fix is built on: **the carousel resets
/// only when the titles actually changed** - compared by `id` and `type` per
/// index (see `_HeroCarouselState._sameSlides`) - and any other rebuild of the
/// page leaves the current slide exactly where it is.
///
/// These drive the real `HomePage` with the real carousel and read which slide
/// is showing from the title drawn inside the hero band, because the failure is
/// behavioural: every list, cache and controller is correct in the build that
/// ships the bug, and only a slide surviving a rebuild distinguishes it.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/pages/home/home_page.dart';
import 'package:zplay/services/addon/addon_manager.dart';
import 'package:zplay/services/collections/collections_service.dart';
import 'package:zplay/services/home/home_page_settings.dart';
import 'package:zplay/services/layout/form_factor.dart';
import 'package:zplay/services/metadata/metadata_service.dart';
import 'package:zplay/shell/app_shell_scope.dart';
import 'package:zplay/widgets/common/focusable_card.dart';
import 'package:zplay/widgets/common/tab_strip.dart';

/// A television has no touch and no pointer, so a focus highlight must always
/// be drawn or the user is told nothing about where they are.
void _useTelevisionHighlight() {
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
}

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

/// The hero's four slides, in the order the fixture's catalogs present them.
///
/// One catalog per title and one title per catalog, which is what makes the
/// slide order observable: `pickFeatured` takes one title per section, so the
/// hero is `[first, second, third, fourth]` whatever the hour's variation
/// bucket happens to be. The names are the observable - the hero draws the
/// movie name whenever no logo resolves, and every detail read here fails.
const List<String> _slideTitles = [
  'Orbit Probe One',
  'Orbit Probe Two',
  'Orbit Probe Three',
  'Orbit Probe Four',
];

/// One meta per catalog id, in the shape Cinemeta returns.
///
/// Deliberately without a `background`: with wide artwork in play the hero's
/// backdrop report (`_reportBackdrop` -> `_onHeroBackdropChanged`) rides along
/// with every slide change and reset, and that is a different concern from the
/// update guard these tests pin. With no candidate at all the report de-dupes
/// to null and the titles - the actual observable - stand alone.
const Map<String, Map<String, String>> _metasByCatalog = {
  'probe-featured-one': {
    'id': 'tt-orbit-1',
    'name': 'Orbit Probe One',
    'type': 'movie',
    'releaseInfo': '2026',
  },
  'probe-featured-two': {
    'id': 'tt-orbit-2',
    'name': 'Orbit Probe Two',
    'type': 'movie',
    'releaseInfo': '2025',
  },
  'probe-story-one': {
    'id': 'tt-orbit-3',
    'name': 'Orbit Probe Three',
    'type': 'series',
    'releaseInfo': '2024',
  },
  'probe-story-two': {
    'id': 'tt-orbit-4',
    'name': 'Orbit Probe Four',
    'type': 'series',
    'releaseInfo': '2023',
  },
};

String _catalogJson(String catalogId) {
  final meta = _metasByCatalog[catalogId];
  return jsonEncode({
    'metas': [
      if (meta != null)
        {
          ...meta,
          'poster': 'https://example.invalid/$catalogId-poster.jpg',
        },
    ],
  });
}

/// Answers catalog reads with test data and everything else with a 503, so a
/// detail fetch fails fast and the hero falls back to the plain title text -
/// the observable these tests read - rather than hanging on a fake clock.
class _RouteCatalogs extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final segments = request.url.pathSegments;
    // `/catalog/{type}/{catalogId}.json`, and nothing else.
    final isCatalog = segments.length == 3 && segments.first == 'catalog';
    final body =
        isCatalog ? _catalogJson(segments[2].replaceAll('.json', '')) : null;
    return http.StreamedResponse(
      body == null
          ? const Stream<List<int>>.empty()
          : Stream.value(utf8.encode(body)),
      body == null ? 503 : 200,
      request: request,
    );
  }
}

/// The addon Home loads its rails from. Four one-title catalogs, so the hero
/// has four distinct slides in a fixed order and the filter tabs have two
/// titles per partition to swap between.
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
        {
          'type': 'movie',
          'id': 'probe-featured-one',
          'name': 'Probe Featured One',
        },
        {
          'type': 'movie',
          'id': 'probe-featured-two',
          'name': 'Probe Featured Two',
        },
        {'type': 'series', 'id': 'probe-story-one', 'name': 'Probe Story One'},
        {'type': 'series', 'id': 'probe-story-two', 'name': 'Probe Story Two'},
      ],
    },
  },
]);

/// The page as the shell mounts it.
///
/// Deliberately built fresh on every call and deliberately not `const`: a
/// canonicalized tree short-circuits in `Element.updateChild` (`child.widget ==
/// newWidget` is identity) and rebuilds nothing at all, while a real parent
/// `setState` rebuilds the page and hands the carousel a freshly picked -
/// equal, but not identical - list. That fresh-equal-list rebuild is exactly
/// what the carousel's update guard has to survive.
Widget _homeTree(AppShellController shell) => MaterialApp(
      home: AppShellScope(
        controller: shell,
        // The `ignore` below is load-bearing, not cosmetic: `const` here would
        // canonicalize the whole subtree into one shared instance, and the
        // identical widget would short-circuit in `Element.updateChild` and
        // rebuild nothing at all - the opposite of a parent `setState`.
        // ignore: prefer_const_constructors
        child: Scaffold(body: HomePage()),
      ),
    );

Future<void> _mountHome(WidgetTester tester, AppShellController shell) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_homeTree(shell));
}

/// Pumps past the cold-start intro splash and the home stream's arrival, so
/// the hero band and all four slides are up before anything is asserted.
Future<void> _settleAtHero(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

/// The hero's slide indicator segments: the `FocusableCard`s the indicator row
/// keeps out of the traversal order (its `Focus` carries `skipTraversal` on a
/// television, so a remote never lands on these), that sit inside the hero
/// band, and that sit *beside* the `PageView` rather than inside it - a slide's
/// own buttons ride the same traversal guard but are not the carousel's
/// controls. A pointer still taps the segments, and they are the intended
/// control for moving between slides by hand.
List<Element> _slideSegments(WidgetTester tester) {
  final bands = find.byType(PageView);
  expect(bands, findsOneWidget, reason: 'precondition: a hero band is on screen');
  final band = tester.getRect(bands.first);
  final pageViews = bands.evaluate().toSet();

  bool insideASlide(Element element) {
    var found = false;
    element.visitAncestorElements((ancestor) {
      if (pageViews.contains(ancestor)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  final hidden = find.descendant(
    of: find.byWidgetPredicate((w) => w is Focus && w.skipTraversal == true),
    matching: find.byType(FocusableCard),
  );
  final inBand = <Element>[];
  for (final element in hidden.evaluate()) {
    if (insideASlide(element)) continue;
    final box = element.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) continue;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (rect.width <= 0) continue;
    if (!band.contains(rect.topLeft) || !band.contains(rect.bottomRight)) {
      continue;
    }
    inBand.add(element);
  }
  // Row order is slide order; sorted so the mapping cannot depend on how the
  // row happens to be laid out.
  inBand.sort((a, b) {
    final boxA = a.findRenderObject()! as RenderBox;
    final boxB = b.findRenderObject()! as RenderBox;
    return boxA
        .localToGlobal(Offset.zero)
        .dx
        .compareTo(boxB.localToGlobal(Offset.zero).dx);
  });
  return inBand;
}

/// Moves the hero to [index] through its own indicator, the way a pointer
/// would, and lets the page animation and the slide change land.
Future<void> _advanceToSlide(
  WidgetTester tester, {
  required int index,
  required int slideCount,
}) async {
  final segments = _slideSegments(tester);
  expect(
    segments.length,
    slideCount,
    reason: 'precondition: the hero shows one indicator segment per slide',
  );
  final box = segments[index].findRenderObject()! as RenderBox;
  await tester.tapAt(box.localToGlobal(box.size.center(Offset.zero)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 200));
}

/// Switches the home filter through its real filter strip, which is how a
/// genuinely different set of sections reaches the hero.
Future<void> _switchFilter(WidgetTester tester, String label) async {
  final tab = find.descendant(
    of: find.byWidgetPredicate((w) => w is TabStrip),
    matching: find.text(label),
  );
  expect(
    tab,
    findsOneWidget,
    reason: 'precondition: the "$label" filter tab is on screen',
  );
  await tester.tap(tab);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 200));
}

/// The title the hero is currently showing, asked of the layout.
///
/// Read from where the title is drawn rather than from any index the carousel
/// keeps, so the test cannot agree with itself about what is on screen. The
/// leftmost slide title inside the band is the current slide's: a `PageView`
/// builds its neighbours a viewport to either side, so the ones waiting
/// off-screen are laid out past the band's own edges and never counted. Titles
/// also appear in the rails below, which is why the band bounds the search.
String _currentHeroTitle(WidgetTester tester) {
  final bands = find.byType(PageView);
  expect(bands, findsOneWidget, reason: 'precondition: a hero band is on screen');

  final band = tester.getRect(bands.first);
  String? leftmost;
  double leftmostX = double.infinity;
  for (final element in find.byType(Text).evaluate()) {
    final data = (element.widget as Text).data;
    if (data == null || !_slideTitles.contains(data)) continue;
    final box = element.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) continue;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (!band.overlaps(rect)) continue;
    if (rect.left < leftmostX) {
      leftmostX = rect.left;
      leftmost = data;
    }
  }
  return leftmost ?? '';
}

void main() {
  setUp(() async {
    _useTelevisionHighlight();
    SharedPreferences.setMockInitialValues({});
    // One probe addon, so Home has a hero and rails driven entirely by this
    // file's scripted client and nothing else.
    AddonManager.readStoredForTesting = () async => _probeAddon;
    await AddonManager.instance.reload();
    DeviceProfile.debugSetTelevision(value: true);
    MetadataService.client = _RouteCatalogs();
    // The hero rotates on its own timer. That is the confound for every
    // assertion here about which slide is showing, so it is off - the slides
    // are moved by hand through the indicator instead.
    HomePageSettings.heroAutoRotate.value = false;
    // Curated rails are appended to the same `pickFeatured` pool the hero is
    // picked from and carry titles this file does not own. Off, so the hero is
    // exactly the four slides above.
    CollectionsService.showOnHome.value = false;
  });

  tearDown(() {
    AddonManager.readStoredForTesting = null;
    DeviceProfile.debugSetTelevision(value: false);
    HomePageSettings.heroAutoRotate.value = true;
    CollectionsService.showOnHome.value = true;
    MetadataService.clearCache();
    MetadataService.client = http.Client();
  });

  testWidgets('a parent rebuild with unchanged titles keeps the reached slide',
      (tester) async {
    final shell = _shellReportingHome();
    await _mountHome(tester, shell);
    await _settleAtHero(tester);

    final first = _currentHeroTitle(tester);
    expect(
      first,
      _slideTitles.first,
      reason: 'precondition: the hero leads with the first slide',
    );

    await _advanceToSlide(tester, index: 1, slideCount: _slideTitles.length);
    final reached = _currentHeroTitle(tester);
    expect(
      reached,
      _slideTitles[1],
      reason: 'precondition: the hero left its first slide. A hero that never '
          'leaves "$first" is the bug this test pins.',
    );

    // The parent rebuild the bug could not survive. Every cause looks like
    // this one to the carousel - a slide change reporting its backdrop, a
    // detail landing, a height report, a settings tick - because all of them
    // end in the page rebuilding and re-reading `_visibleFeaturedMovies`,
    // whose getter re-picks a fresh but equal list on every build.
    await tester.pumpWidget(_homeTree(shell));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      _currentHeroTitle(tester),
      reached,
      reason: 'A parent rebuild with the same titles reset the hero: it is '
          'back on slide 0 ("$first") instead of staying on "$reached". '
          'Lists compare by content here, not by identity - otherwise the '
          'rebuild a slide change causes snaps the carousel straight back '
          'and the hero can never leave its first slide.',
    );
  });

  testWidgets('a genuinely different title list resets to its first slide',
      (tester) async {
    final shell = _shellReportingHome();
    await _mountHome(tester, shell);
    await _settleAtHero(tester);

    // Off slide 0 first, so "reset to the new first slide" has something to
    // reset *from* - a list change must move the hero even though every
    // rebuild in the previous test must not.
    await _advanceToSlide(tester, index: 1, slideCount: _slideTitles.length);
    expect(
      _currentHeroTitle(tester),
      _slideTitles[1],
      reason: 'precondition: the hero is off its first slide before the '
          'titles change',
    );

    // The Series filter drops the two movie catalogs: the hero's slide list is
    // genuinely different, so the carousel must reset onto it.
    await _switchFilter(tester, 'Series');

    expect(
      _currentHeroTitle(tester),
      _slideTitles[2],
      reason: 'A new slide list must land on its own first slide. Showing '
          '"${_slideTitles[1]}" or "${_slideTitles[3]}" means the reset was '
          'disabled outright rather than narrowed to real list changes.',
    );
  });
}
