/// A remote on the hero could never reach the first rail, and the hero was the
/// only place on Home where DPAD_DOWN did anything useful.
///
/// Found on a Chromecast with Google TV and reproduced by two people
/// independently: start Home, focus is on the hero's "Watch Now" button, press
/// DOWN, and the hero carousel advances a slide instead of focus moving down
/// the page. A dozen more presses never leave the hero. A second report from the
/// same device reads as "the highlight gets lost, focus is erratic".
///
/// **The cause was the page's own key handler, not the carousel.** Home wrapped
/// its body in a `Focus` whose `onKeyEvent` took `arrowUp` and `arrowDown`
/// whenever the scroll view could still move, and returned
/// `KeyEventResult.handled`. A handled key stops there: it never reaches the
/// `Shortcuts` that bind those keys to `DirectionalFocusIntent`, and that intent
/// is the only thing in the app that moves focus at all. The handler was there
/// to fix "I can scroll down but never back up", and fixing it that way took
/// DOWN away from every card on the page.
///
/// The rule this pins is the one the fix is built on: **traversal owns the arrow
/// key, and the page only scrolls when traversal has nowhere to go** - which is
/// when the focused widget is already at the edge of the viewport.
///
/// These drive real key events through the real page rather than inspecting
/// widget types, because the failure is behavioural: the handler is present and
/// every focus node is correct in the build that ships the bug.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/models/movie/movie_section.dart';
import 'package:zplay/pages/home/home_page.dart';
import 'package:zplay/services/addon/addon_manager.dart';
import 'package:zplay/services/home/home_page_settings.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/services/layout/form_factor.dart';
import 'package:zplay/services/metadata/metadata_service.dart';
import 'package:zplay/shell/app_shell_scope.dart';
import 'package:zplay/widgets/movie/movie_slider_section.dart';

/// A television has no touch and no pointer, so a focus highlight must always be
/// drawn or the user is told nothing about where they are.
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
    final body = url.path.contains('/catalog/')
        ? _catalogJson(4, type)
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

/// The addon Home loads its rails from. Two catalogs, so the hero has more than
/// one source to pick a slide from and there is a rail below it to move into.
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

/// The ids the rails on screen are currently showing.
List<String> _railIds(WidgetTester tester) {
  final ids = <String>[];
  for (final element in find.byType(MovieSliderSection).evaluate()) {
    ids.addAll(
      (element.widget as MovieSliderSection).section.movies.map((m) => m.id),
    );
  }
  return ids;
}

/// Whether focus is inside one of the rails, asked of the focus node's own
/// position in the tree rather than of a descendant of the focused widget: a
/// `Focus` is the node, and the button inside it is not necessarily where the
/// widget was mounted.
bool _focusIsInARail() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.findAncestorWidgetOfExactType<MovieSliderSection>() != null;
}

/// The hero's own primary action, which is where a remote lands on a cold
/// start and the one control Home deliberately autofocuses.
Finder get _heroCta => find.widgetWithText(ElevatedButton, 'Watch Now');

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

/// Pumps past the cold-start intro splash and the home stream's arrival, then
/// focuses the hero CTA the way a remote arriving at Home would.
Future<void> _settleAtHeroCta(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 500));
  // A `pump()` with no frame time does not always lay the tree out again, and
  // the fade this rides on needs a second one to move from its placeholder to
  // the finished image. The band is absent, not empty, without it.
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
  // Asked of the button's own focus node, so it is a live, attached node.
  // Handing traversal an unattached one is an assert inside the framework, and
  // the test would be measuring that rather than the page.
  final focusNode = tester
      .widget<Focus>(
        find.descendant(of: _heroCta, matching: find.byType(Focus)).first,
      )
      .focusNode;
  if (focusNode != null) {
    FocusScope.of(tester.element(_heroCta)).autofocus(focusNode);
  }
  await tester.pump();
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
    // assertion here about which slide is showing, so it is off by default and
    // only the test that wants it turns it back on.
    HomePageSettings.heroAutoRotate.value = false;
  });

  tearDown(() {
    AddonManager.readStoredForTesting = null;
    DeviceProfile.debugSetTelevision(value: false);
    HomePageSettings.heroAutoRotate.value = true;
    MetadataService.clearCache();
    MetadataService.client = http.Client();
  });

  testWidgets('DOWN from the hero CTA moves focus into the rail, not the slide',
      (tester) async {
    await _mountHome(tester);
    await _settleAtHeroCta(tester);

    expect(_railIds(tester), isNotEmpty,
        reason: 'precondition: there is a rail below the hero to move into');

    final cta = tester.widget<ElevatedButton>(_heroCta);
    expect(cta.autofocus, isTrue,
        reason: 'the hero CTA is Home\'s deliberate D-pad entry point');

    // The press that shipped the bug: focus is on the hero and DOWN is sent.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 400));

    expect(_focusIsInARail(), isTrue,
        reason: 'DOWN from the hero must move focus into the first rail. It '
            'did not, because the page consumed the key before directional '
            'traversal could see it.');

    // And the page is still where it was: focus moved, nothing scrolled.
    expect(
      find.byType(MovieSliderSection),
      findsWidgets,
      reason: 'the rail that took focus must still be the one on screen',
    );
  });

  testWidgets('DOWN does not change which slide the hero is showing',
      (tester) async {
    // **Auto-rotation on.** This is the confound the device report rests on:
    // the carousel is advancing every six seconds on its own timer, and two
    // DOWN presses land inside that. So the assertion cannot be "the carousel
    // stopped" - nothing stops it, and nothing should. The assertion is that
    // one press does not move it *on top of* the rotation: the same title is
    // still current that was current before the key went down, and it is the
    // title the rail's first card belongs to rather than a later one.
    HomePageSettings.heroAutoRotate.value = true;
    await _mountHome(tester);
    await _settleAtHeroCta(tester);

    final before = _currentHeroTitle(tester);
    expect(before, isNotEmpty, reason: 'precondition: the hero shows a title');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 400));

    expect(_currentHeroTitle(tester), before,
        reason: 'DOWN is a focus key. Advancing the carousel with it is what '
            'left a viewer on the hero forever, and it is not the button\'s '
            'job.');
  });
}

/// The title the hero is currently showing, asked of the layout.
///
/// Read from where the title is drawn rather than from any index the carousel
/// keeps, so the test cannot agree with itself about what is on screen. The
/// leftmost title inside the band is the current slide's: a `PageView` builds
/// its neighbours a viewport to either side, so the ones waiting off-screen
/// are laid out past the band's own edges and never counted.
String _currentHeroTitle(WidgetTester tester) {
  final bands = find.byType(PageView);
  expect(bands, findsOneWidget, reason: 'precondition: a hero band is on screen');

  final band = tester.getRect(bands.first);
  String? leftmost;
  double leftmostX = double.infinity;
  for (final element in find.byType(Text).evaluate()) {
    final data = (element.widget as Text).data;
    if (data == null || !data.startsWith('Probe ')) continue;
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
