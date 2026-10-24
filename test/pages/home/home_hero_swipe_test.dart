/// The hero carousel's own gesture, and which input device it belongs to.
///
/// The defect this pins, measured on a 1080x2400@420 phone build with no video
/// playing: byte-exact screenshot diffs of the same region against a 0.00%
/// baseline showed **0.00% of the hero band changed** for a horizontal finger
/// swipe across it, while the **Continue Watching rail changed 39.04%** for the
/// same swipe. The rails were never the problem - the hero's `PageView` was
/// pinned with `NeverScrollableScrollPhysics`, so the biggest slider on the
/// page's first screen could not be moved by the one gesture a phone user is
/// certain to try.
///
/// The pin was not arbitrary, and the reasoning is kept rather than deleted: on
/// a television there is no pointer, so a drag over the band was read as a page
/// change, the user could not scroll the page back up at all, and the dashes and
/// the rotation timer were left as the way between slides. That is sound on a
/// television and wrong on every device with a finger.
///
/// So the rule under test is that the pin follows the *input device*: a
/// remote-driven form factor keeps `NeverScrollableScrollPhysics` and its
/// dashes-and-timer route, and everywhere else the `PageView` default stands and
/// a drag is an ordinary carousel swipe. The swipe is asserted by dragging - a
/// hero whose physics permit a drag but whose page never changes is the same bug
/// wearing a different hat, and only a drag can see it.
///
/// The fourth test covers what re-enabling the swipe exposes: the rotation timer
/// ticking while a finger is down. `PageController.animateToPage` ends the drag
/// activity, so the hero leaves without the finger and the user is left pulling
/// at a carousel that has gone.
///
/// The last two tests pin the other half of the same report - "tapping or
/// swiping into the slider does nothing" - because a phone hero was frozen
/// twice: it could not be dragged, and it never advanced on its own either. The
/// rotation's guard treats focus inside the hero as "the remote is on the hero",
/// which is exactly right on a television and meaningless on a pointer device,
/// where the hero's call to action autofocuses at mount and then holds focus for
/// the whole session. So the guard's focus half applies only where
/// `FormFactorService.hasRemoteInput` is true, and the pair states it from both
/// sides: the pointer hero advances with focus sitting on its own CTA, the
/// television hero does not move under the remote.
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

/// A phone: 1080x2400 physical at DPR 3, i.e. 360x800 dp.
///
/// The classification is the point of the numbers. A 360 dp `shortestSide` is
/// [FormFactor.compact], and nothing here is a television, so
/// `FormFactorService.hasRemoteInput` is false and the hero is the pointer band
/// rather than the compact one.
const Size _phoneCanvas = Size(1080, 2400);
const double _phoneDpr = 3.0;

/// The television canvas the remote half needs: 1920x1080 physical at DPR 2,
/// the same 960x540 dp the TV harness uses.
const Size _tvCanvas = Size(1920, 1080);
const double _tvDpr = 2.0;

/// The hero's four slides, in the order the fixture's catalogs present them.
///
/// One catalog per title and one title per catalog, which is what makes the
/// slide order observable: `pickFeatured` takes one title per section, so the
/// hero is `[first, second, third, fourth]` whatever the hour's variation
/// bucket happens to be. The names are the observable - the hero draws the movie
/// name whenever no logo resolves, and every detail read here fails.
const List<String> _slideTitles = [
  'Orbit Probe One',
  'Orbit Probe Two',
  'Orbit Probe Three',
  'Orbit Probe Four',
];

/// One meta per catalog id, in the shape Cinemeta returns.
///
/// Deliberately without a `background`: the hero's backdrop report
/// (`_reportBackdrop` -> `_onHeroBackdropChanged`) rides along with every slide
/// change and is a different concern from the gestures these tests pin.
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
        {...meta, 'poster': 'https://example.invalid/$catalogId-poster.jpg'},
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
    final body = isCatalog
        ? _catalogJson(segments[2].replaceAll('.json', ''))
        : null;
    return http.StreamedResponse(
      body == null
          ? const Stream<List<int>>.empty()
          : Stream.value(utf8.encode(body)),
      body == null ? 503 : 200,
      request: request,
    );
  }
}

String _addonWith(List<({String type, String id, String name})> catalogs) =>
    jsonEncode([
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
            for (final catalog in catalogs)
              {'type': catalog.type, 'id': catalog.id, 'name': catalog.name},
          ],
        },
      },
    ]);

/// The addon Home loads its rails from: four one-title catalogs, so the hero has
/// four distinct slides in a fixed order.
final String _probeAddon = _addonWith(const [
  (type: 'movie', id: 'probe-featured-one', name: 'Probe Featured One'),
  (type: 'movie', id: 'probe-featured-two', name: 'Probe Featured Two'),
  (type: 'series', id: 'probe-story-one', name: 'Probe Story One'),
  (type: 'series', id: 'probe-story-two', name: 'Probe Story Two'),
]);

AppShellController _shellReportingHome() {
  final slot = ValueNotifier(ShellSlot.home);
  return AppShellController(
    current: slot,
    onSelect: (next) {
      slot.value = next;
      return true;
    },
    formFactor: () => FormFactor.compact,
  );
}

Widget _homeTree(AppShellController shell) => MaterialApp(
  home: AppShellScope(
    controller: shell,
    child: const Scaffold(body: HomePage()),
  ),
);

Future<void> _mountHome(
  WidgetTester tester,
  AppShellController shell, {
  Size canvas = _phoneCanvas,
  double dpr = _phoneDpr,
}) async {
  tester.view.physicalSize = canvas;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_homeTree(shell));
}

/// Pumps past the cold-start intro splash and the home stream's arrival, so the
/// hero band and all four slides are up before anything is asserted.
Future<void> _settleAtHero(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Lets a gesture the hero started finish, without settling: `pumpAndSettle`
/// would drain the rotation this file deliberately arms in one test.
///
/// Long enough for the page's own snap spring to come to rest - a swipe that
/// lands travels under a page, and the simulation runs for about 0.8 s at that
/// displacement - so the test ends with no animation still running.
Future<void> _settleGesture(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Rect _heroBand(WidgetTester tester) {
  final bands = find.byType(PageView);
  expect(
    bands,
    findsOneWidget,
    reason: 'precondition: a hero band is on screen',
  );
  return tester.getRect(bands.first);
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
  final band = _heroBand(tester);

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

/// The page's own vertical scroll offset - the `ListView` the hero sits in, not
/// the carousel inside it. Found by walking up from the hero, so the rails'
/// horizontal scrollables below cannot be mistaken for it.
double _pageScrollOffset(WidgetTester tester) {
  final pageScroll = find.ancestor(
    of: find.byType(PageView),
    matching: find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    ),
  );
  expect(
    pageScroll,
    findsWidgets,
    reason: 'precondition: the hero sits inside the page\'s vertical list',
  );
  return tester.state<ScrollableState>(pageScroll.first).position.pixels;
}

PageView _heroView(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView));

/// Whether focus sits inside the hero band right now.
///
/// The carousel's own `_startTimer` refuses to rotate while it does - for a
/// remote that is the whole point of focusing the hero, and the hero's "Play"
/// pill carries `autofocus: true`, so a freshly mounted Home is born with the
/// rotation paused. A test about the rotation therefore has to ask this first:
/// "the hero did not move" means something entirely different when the
/// carousel was never running.
///
/// Asked with the band's own element as the marker rather than
/// `_HeroCarousel` (private to the page), which is the same test from below.
bool _heroHasFocus(WidgetTester tester) {
  final node = FocusManager.instance.primaryFocus;
  final context = node?.context;
  if (context == null) return false;
  final band = find.byType(PageView).evaluate().first;
  var inside = false;
  context.visitAncestorElements((ancestor) {
    if (identical(ancestor, band)) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

/// The hero's own call to action, matched on its label rather than on a button
/// type - the restyle-proof way `home_hero_focus_traversal_test.dart` finds the
/// same control.
Finder get _heroCta =>
    find.ancestor(of: find.text('Play'), matching: find.byType(FocusableCard));

/// Puts focus on the hero CTA the way a remote arriving at Home does.
///
/// Asked of the button's own focus node, so it is a live, attached node: handing
/// the focus system an unattached one is an assert inside the framework, and the
/// test would be measuring that rather than the page.
Future<void> _focusHeroCta(WidgetTester tester) async {
  final node = tester
      .widget<Focus>(
        find.descendant(of: _heroCta, matching: find.byType(Focus)).first,
      )
      .focusNode;
  if (node != null) {
    FocusScope.of(tester.element(_heroCta.first)).autofocus(node);
  }
  await tester.pump();
}

/// Arms the rotation the way the settings page does - a change notification is
/// what the carousel arms its countdown on - on the shortest interval, so the
/// tick is one pump away rather than a coincidence of where the mount happened
/// to land in the cycle.
void _armRotation() {
  HomePageSettings.heroRotateSeconds.value = 1;
  HomePageSettings.heroAutoRotate.value = true;
  HomePageSettings.changeNotifier.value++;
}

/// Watches the hero for up to [steps] quarter-interval pumps and answers with the
/// first slide title that is not [from] - [from] itself when it never moved.
///
/// Stepped rather than one long pump because a read can land in the middle of a
/// slide change, where the outgoing slide is still the leftmost one in the band
/// and its title is what a single coarse read would report.
Future<String> _heroAfterPumps(
  WidgetTester tester, {
  required String from,
  int steps = 16,
}) async {
  var current = from;
  for (var step = 0; step < steps && current == from; step++) {
    await tester.pump(const Duration(milliseconds: 250));
    current = _currentHeroTitle(tester);
  }
  return current;
}

/// Leaves nothing armed, so a test that armed the rotation ends with no animation
/// still running: the switch goes off and the change is signalled, which is the
/// path the carousel cancels its countdown on, and the pumps below drain a slide
/// change the rotation had already started.
Future<void> _disarmRotation(WidgetTester tester) async {
  HomePageSettings.heroAutoRotate.value = false;
  HomePageSettings.changeNotifier.value++;
  await tester.pump();
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'zplay_p2p_warning_never_show': true,
    });
    // One probe addon, so Home has a hero and rails driven entirely by this
    // file's scripted client and nothing else.
    AddonManager.readStoredForTesting = () async => _probeAddon;
    await AddonManager.instance.reload();
    DeviceProfile.debugSetTelevision(value: false);
    MetadataService.client = _RouteCatalogs();
    // The rotation is the confound for every assertion here about which slide is
    // showing, so it is off except in the one test that is about the rotation.
    HomePageSettings.heroAutoRotate.value = false;
    // Curated rails are appended to the same `pickFeatured` pool the hero is
    // picked from; off, so the hero is exactly the four slides above.
    CollectionsService.showOnHome.value = false;
  });

  tearDown(() {
    AddonManager.readStoredForTesting = null;
    DeviceProfile.debugSetTelevision(value: false);
    HomePageSettings.heroAutoRotate.value = true;
    HomePageSettings.heroRotateSeconds.value = 6;
    CollectionsService.showOnHome.value = true;
    MetadataService.clearCache();
    MetadataService.client = http.Client();
  });

  testWidgets('a finger drag moves a pointer hero between slides', (
    tester,
  ) async {
    final shell = _shellReportingHome();
    await _mountHome(tester, shell);
    await _settleAtHero(tester);

    expect(
      _currentHeroTitle(tester),
      _slideTitles.first,
      reason: 'precondition: the hero leads with the first slide',
    );
    expect(
      _heroView(tester).physics,
      isNot(isA<NeverScrollableScrollPhysics>()),
      reason:
          'A pointer form factor must not pin the hero. '
          'NeverScrollableScrollPhysics here is the phone bug itself: the band '
          'must take a finger drag.',
    );

    // Four fifths of the band, the way a thumb crosses it: past the page's own
    // half-way snap, so the swipe lands on the next slide instead of springing
    // back to this one.
    final band = _heroBand(tester);
    await tester.dragFrom(band.center, Offset(-band.width * 0.8, 0));
    await _settleGesture(tester);

    expect(
      _currentHeroTitle(tester),
      _slideTitles[1],
      reason:
          'The drag did not move the hero: it is still on '
          '"${_slideTitles.first}". A carousel whose physics allow the drag but '
          'whose page never changes is the same defect with a different cause, '
          'and a test that only reads `physics` back cannot see it.',
    );
  });

  testWidgets('a remote-driven hero stays pinned, and a drag does not move it', (
    tester,
  ) async {
    DeviceProfile.debugSetTelevision(value: true);
    final shell = _shellReportingHome();
    await _mountHome(tester, shell, canvas: _tvCanvas, dpr: _tvDpr);
    await _settleAtHero(tester);

    expect(
      _heroView(tester).physics,
      isA<NeverScrollableScrollPhysics>(),
      reason:
          'A remote-driven form factor must keep the hero pinned: with no '
          'pointer, a drag over the band that becomes a page change is the way '
          'the user loses their route back up the page.',
    );

    final before = _currentHeroTitle(tester);
    expect(
      before,
      _slideTitles.first,
      reason: 'precondition: the hero leads with the first slide',
    );

    final band = _heroBand(tester);
    await tester.dragFrom(band.center, Offset(-band.width * 0.8, 0));
    await _settleGesture(tester);

    expect(
      _currentHeroTitle(tester),
      before,
      reason:
          'A drag changed the slide on a remote-driven hero. On a '
          'television the dashes select a slide and the timer rotates them; a '
          'drag there is a trap, not an affordance.',
    );
  });

  testWidgets('a vertical drag over the hero still scrolls the page', (
    tester,
  ) async {
    final shell = _shellReportingHome();
    await _mountHome(tester, shell);
    await _settleAtHero(tester);

    final before = _pageScrollOffset(tester);
    final band = _heroBand(tester);

    // Straight up from the middle of the band, so the whole gesture is over the
    // hero: the carousel's own slab of the page must not swallow it.
    await tester.dragFrom(band.center, const Offset(0, -260));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      _pageScrollOffset(tester),
      greaterThan(before),
      reason:
          'A vertical drag that starts on the hero did not scroll the page. '
          'The carousel must only take the horizontal axis, or the biggest '
          'region of the first screen becomes dead space to a thumb.',
    );
  });

  testWidgets('a hand on the hero holds the rotation off until it leaves', (
    tester,
  ) async {
    final shell = _shellReportingHome();
    await _mountHome(tester, shell);
    await _settleAtHero(tester);

    // The carousel does not rotate while focus is inside it, and the hero's
    // "Play" pill carries `autofocus: true` - so Home mounts with the rotation
    // already paused, and arming the timer without noticing would leave this
    // test asserting that a stopped carousel stayed stopped. Focus is dropped
    // to the enclosing scope first, which is where it sits after any tap on
    // something that is not the hero.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(
      _heroHasFocus(tester),
      isFalse,
      reason:
          'precondition: the rotation is only live with focus outside the '
          'hero (`_HeroCarouselState._startTimer` waits while it is inside), '
          'and the hero\'s own "Play" pill autofocuses at mount.',
    );

    final start = _currentHeroTitle(tester);
    expect(
      start,
      _slideTitles.first,
      reason:
          'precondition: the hero leads with the first slide, with the '
          'rotation off for the mount so it cannot have moved',
    );

    // Arm the rotation as the settings page would, on the shortest interval, so
    // the tick is one pump away rather than a coincidence of where the mount
    // happened to land in the cycle.
    _armRotation();
    await tester.pump();

    final band = _heroBand(tester);
    final gesture = await tester.startGesture(band.center);
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();

    // A finger on the hero is not hovering, and on a phone it is not focus
    // either, so both of the timer's existing reasons to wait are false here.
    // Two intervals pass with the finger still down; a tick in that window ends
    // the drag activity and animates the hero off to the next slide.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      _currentHeroTitle(tester),
      start,
      reason:
          'The rotation advanced the hero while a finger was dragging it. '
          '`animateToPage` ends the drag activity, so the user is left pulling '
          'at a carousel that has left without them.',
    );

    // The hand leaves - and the carousel is allowed to rotate again, which is
    // the other half of the same rule. A drag that never gave the countdown
    // back would end the hero's rotation for the rest of the session.
    await gesture.up();

    // First the pull springs back to the slide it started on: 60 dp of a 360 dp
    // band is under the page's half-way snap, so it must not change slides.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      _currentHeroTitle(tester),
      start,
      reason:
          'Sixty dp of a 360 dp band is a pull, not a swipe: the carousel '
          'must spring back to the slide it was on.',
    );

    // Then the countdown comes back. The hero's scroll ends when the pull has
    // settled and the timer is armed again from there, so the interval after
    // that moves the hero - and it is the *drawn slide* that says so, not the
    // timer being re-armed: a drag that leaves the carousel paused forever looks
    // exactly like this from inside the widget.
    final rotated = await _heroAfterPumps(tester, from: start);
    expect(
      rotated,
      isNot(start),
      reason:
          'The hero never rotated again after the drag, so the countdown '
          'the drag paused was never handed back.',
    );

    await _disarmRotation(tester);
  });

  testWidgets('a pointer hero rotates while its own call to action has focus', (
    tester,
  ) async {
    final shell = _shellReportingHome();
    await _mountHome(tester, shell);
    await _settleAtHero(tester);

    // The state a phone is actually in: focus is inside the hero because the
    // CTA's card autofocuses at mount, not because a user went looking for it.
    // On a television that is "the remote is on the hero" and the carousel must
    // hold still; on a pointer device focus is not the user's position at all,
    // and reading it as one left Home opening on a hero that never advanced by
    // itself - frozen twice over, with the manual swipe gone as well.
    expect(
      _heroHasFocus(tester),
      isTrue,
      reason:
          'precondition: the hero\'s own call to action holds focus at '
          'mount, which is the state this rule is about',
    );

    final start = _currentHeroTitle(tester);
    expect(
      start,
      _slideTitles.first,
      reason:
          'precondition: the hero leads with the first slide, with the '
          'rotation off for the mount so it cannot have moved',
    );

    _armRotation();
    await tester.pump();

    final rotated = await _heroAfterPumps(tester, from: start);
    expect(
      rotated,
      isNot(start),
      reason:
          'The hero never rotated while focus sat on its own call to '
          'action. A pointer device has no remote to be on the hero, so focus '
          'must not gate the rotation there - it is the hero\'s second freeze.',
    );

    await _disarmRotation(tester);
  });

  testWidgets('a remote-driven hero stands down while the remote is on it', (
    tester,
  ) async {
    DeviceProfile.debugSetTelevision(value: true);
    final shell = _shellReportingHome();
    await _mountHome(tester, shell, canvas: _tvCanvas, dpr: _tvDpr);
    await _settleAtHero(tester);
    await _focusHeroCta(tester);

    expect(
      _heroHasFocus(tester),
      isTrue,
      reason: 'precondition: the remote is on the hero',
    );

    final start = _currentHeroTitle(tester);
    expect(
      start,
      _slideTitles.first,
      reason:
          'precondition: the hero leads with the first slide, with the '
          'rotation off for the mount so it cannot have moved',
    );

    _armRotation();
    await tester.pump();

    // The same interval and the same window the pointer hero is allowed to move
    // in. Here the slide must not move under the viewer.
    final rotated = await _heroAfterPumps(tester, from: start);
    expect(
      rotated,
      start,
      reason:
          'The hero rotated with the remote on it. On a television focus is '
          'where the user is: a slide that advances under them is the hero '
          'running away from the viewer, which is what left them chasing it '
          'instead of moving past it.',
    );

    await _disarmRotation(tester);
  });
}
