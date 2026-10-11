/// The details page must open with the remote on a control the user can see.
///
/// A pushed route with nothing inside it asking for focus opens on its own
/// [FocusScope], and this page did not ask: the sweep found it sitting at "no
/// focus" - no ring anywhere on a 960x540 canvas - with the next press either
/// doing nothing visible, or, one press later, leaving the page, because the
/// first thing a DOWN reached was the back control and its OK pops.
///
/// On a television the ring is the *only* proof that a control is reachable, so
/// these tests assert two things the widget tree cannot answer on its own:
/// that the element holding primary focus actually paints a focused
/// [CardFocusRing], and that the first activation runs the page's primary
/// action rather than popping the route.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/pages/details/details_page.dart';
import 'package:zplay/pages/player/watch_screen.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/services/metadata/metadata_service.dart';
import 'package:zplay/widgets/common/focusable_card.dart';
import 'package:zplay/widgets/common/pill_button.dart';

const _seriesMeta = '''
{"meta":{"id":"tt0903747","type":"series","name":"Breaking Bad",
 "releaseInfo":"2008","description":"A chemistry teacher turns to crime.",
 "runtime":"49 min","genres":["Crime","Drama"],"imdbRating":"9.5",
 "videos":[{"id":"tt0903747:1:1","season":1,"episode":1,"name":"Pilot",
            "released":"2008-01-20"}]}}''';

const _movieMeta = '''
{"meta":{"id":"tt0111161","type":"movie","name":"The Shawshank Redemption",
 "releaseInfo":"1994","description":"Two imprisoned men bond over the years.",
 "runtime":"142 min","genres":["Drama"],"imdbRating":"9.3","videos":[]}}''';

MockClient _metaClient(String body) => MockClient(
  (request) async => http.Response(
    body,
    200,
    headers: const {'content-type': 'application/json'},
  ),
);

Movie _row(String type) => Movie(
  id: type == 'series' ? 'tt0903747' : 'tt0111161',
  name: type == 'series' ? 'Breaking Bad' : 'The Shawshank Redemption',
  type: type,
  addonBaseUrl: 'https://v3-cinemeta.strem.io',
);

/// Pumps the real page on the 1920x1080 @ 2x television surface, past the meta
/// fetch and the 650 ms entrance animation.
Future<void> _pumpTvDetails(WidgetTester tester, String type) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(home: DetailsPage(movie: _row(type))));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Whether the element that holds primary focus paints a *focused* ring.
///
/// Walked down rather than looked up: `FocusableCard` installs the ring inside
/// its own builder, so the ring is a descendant of the focused node and never
/// an ancestor of it. A `find.byType(CardFocusRing)` here would find the rings
/// of unfocused cards too, which is the assertion that passes while the screen
/// shows nothing.
bool _focusIsRinged() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  var ringed = false;
  void walk(Element element) {
    final widget = element.widget;
    if (widget is CardFocusRing && widget.focused) ringed = true;
    element.visitChildren(walk);
  }

  walk(context as Element);
  return ringed;
}

/// The focused element itself, so a descendant finder can prove *what* is
/// focused rather than that something is.
Finder _focusedElement() => find.byElementPredicate(
  (element) => identical(element, FocusManager.instance.primaryFocus?.context),
);

/// The focus node a [FocusableCard] installs for itself.
///
/// Looked up rather than assumed: `FocusableActionDetector` is what creates the
/// node, so the first `Focus` under the card owns it, and requesting focus on
/// that node is the only way to ask the question "if the remote landed here,
/// would the user see it?" without simulating a traversal whose result depends
/// on where the card happens to sit.
FocusNode? _focusNodeOf(Element card) {
  FocusNode? node;
  void walk(Element element) {
    if (node != null) return;
    final widget = element.widget;
    if (widget is Focus && widget.focusNode != null) {
      node = widget.focusNode;
      return;
    }
    element.visitChildren(walk);
  }

  walk(card);
  return node;
}

/// The first label under a card, for a failure message that names the control.
String _labelOf(Element card) {
  String? label;
  void walk(Element element) {
    if (label != null) return;
    final widget = element.widget;
    if (widget is Text && widget.data != null) {
      label = widget.data;
      return;
    }
    element.visitChildren(walk);
  }

  walk(card);
  return label ?? 'an unlabelled control';
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The real device reports itself a television: the ring is only claimed
    // where there is a remote, and the pill's height is read from there too.
    DeviceProfile.debugSetTelevision(value: true);
    // Focus highlights are suppressed while the framework believes the last
    // input was a touch, and the remote's own key events are what put it in
    // `traditional` on the device - the sweep's flow presses OK on a Home card
    // before this page ever opens. A widget test presses nothing, so the mode
    // is asked for directly; otherwise every ring assertion here would be
    // measuring the harness's input history instead of the page.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });

  tearDown(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    MetadataService.clearCache();
    MetadataService.client = http.Client();
    DeviceProfile.debugSetTelevision(value: false);
  });

  for (final type in ['series', 'movie']) {
    final label = type == 'series' ? 'Play Episodes' : 'Play Movie';

    testWidgets('a $type page opens on its primary action, ringed', (
      tester,
    ) async {
      MetadataService.client = _metaClient(
        type == 'series' ? _seriesMeta : _movieMeta,
      );
      await _pumpTvDetails(tester, type);

      expect(
        find.text(label),
        findsOneWidget,
        reason: 'the page is still loading or showing "Details unavailable." '
            'if its primary action is absent, and then nothing below is '
            'measuring the entry state',
      );

      expect(
        _focusIsRinged(),
        isTrue,
        reason: 'the page opened with focus on the route\'s FocusScope, which '
            'paints nothing: at ten feet a television with no ring reads as a '
            'screen with no controls on it',
      );
      expect(
        find.descendant(of: _focusedElement(), matching: find.text(label)),
        findsOneWidget,
        reason: 'the remote must land on the primary action, not on the '
            'unmarked back control one press away',
      );

      // One press up is the header row, which is where the sweep's other
      // ringless stop was: the control that leaves the page. It is a ringed
      // card now, and this is the assertion that keeps it one - a bare
      // `IconButton` here is invisible on this scrim and its OK pops.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        _focusIsRinged(),
        isTrue,
        reason: 'the way off the page is a focus stop, so it has to be '
            'visible; the sweep pressed OK on an unmarked one and left',
      );
      expect(
        find.descendant(of: _focusedElement(), matching: find.text(label)),
        findsNothing,
        reason: 'up has to move off the primary action, or the stop above it '
            'is never exercised and this guard proves nothing',
      );
    });

    testWidgets('the first activation on a $type page takes the primary '
        'action', (tester) async {
      MetadataService.client = _metaClient(
        type == 'series' ? _seriesMeta : _movieMeta,
      );
      await _pumpTvDetails(tester, type);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byType(WatchScreen),
        findsOneWidget,
        reason: 'OK on the opening state must do the page\'s primary action',
      );
      expect(
        // `skipOffstage: false`: the page is still mounted, it is simply under
        // the route that just opened. A default finder would report it gone and
        // that is not the same claim.
        find.byType(DetailsPage, skipOffstage: false),
        findsOneWidget,
        reason: 'the sweep\'s failure was OK *leaving* the page, because the '
            'control it activated was the back control',
      );
    });

    testWidgets('every focusable a $type page renders paints the ring', (
      tester,
    ) async {
      MetadataService.client = _metaClient(
        type == 'series' ? _seriesMeta : _movieMeta,
      );
      await _pumpTvDetails(tester, type);

      // Every card the page has mounted, asked one at a time: requesting a
      // node's focus is exactly what a D-pad press that reaches it does, so a
      // card that paints nothing here is a card the user cannot see themselves
      // on. The sweep found two such stops on this page - the back control and
      // the genre pills - and neither is reachable by a fixed sequence of
      // presses that would keep working after the layout changes.
      final cards = find.byType(FocusableCard).evaluate().toList();
      expect(
        cards.length,
        greaterThanOrEqualTo(4),
        reason: 'the probe must be looking at a page with content on it: the '
            'primary action, the library action, an episode and a genre pill '
            'are the four a series page is guaranteed to have',
      );

      final ringless = <String>[];
      for (final card in cards) {
        final node = _focusNodeOf(card);
        if (node == null) continue;
        node.requestFocus();
        // Two frames: the first delivers the focus change and the card's own
        // highlight callback, the second paints the ring the callback asked
        // for.
        await tester.pump();
        await tester.pump();
        if (!_focusIsRinged()) ringless.add(_labelOf(card));
      }

      expect(
        ringless,
        isEmpty,
        reason: 'a focus stop that paints no ring reads as the end of the '
            'page: the user presses on, or presses OK, without ever having '
            'been told where the remote was',
      );
    });
  }

  testWidgets('a pointer surface is left alone', (tester) async {
    DeviceProfile.debugSetTelevision(value: false);
    MetadataService.client = _metaClient(_movieMeta);
    await _pumpTvDetails(tester, 'movie');

    expect(
      _focusIsRinged(),
      isFalse,
      reason: 'the ring is the television\'s model of "where am I"; a phone '
          'or a desktop window must not open with one drawn',
    );
    expect(find.byType(PillButton), findsWidgets);
  });
}
