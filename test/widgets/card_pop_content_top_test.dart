/// The band a page leaves the focus pop.
///
/// `movie_card_focus_expansion_viewport_test.dart` pins that the popped surface
/// stays inside the *window*. This file pins the thing a page with chrome of its
/// own needs on top of that: on a grid the focused cell is in the *first* row, so
/// a copy pinned to the window's edge paints over the toolbar, the pill row or
/// the tab row above it - the reported defect, where the genre pills were left
/// half-visible beside the pop and the page read as broken rather than layered.
/// The page is the only thing that knows how tall its chrome is, and
/// [PageContentTop] is how it says so.
///
/// Four things are pinned here:
///
/// 1. **The declaration bounds the copy.** With a page declaring a content top,
///    the copy's painted top is never above that line plus the expansion's own
///    edge margin, whatever the fit wanted to do.
/// 2. **The band is what the fit spends.** A page with chrome above it therefore
///    lets the card grow less - and on a page whose band is exactly enough, the
///    copy opens onto the band's top edge and lands on its bottom one, card plus
///    panel equal to the band.
/// 3. **Nothing changes without one.** A page that declares nothing and a page
///    that declares 0 are the same pop they have always been, to the pixel: the
///    copy is fitted to the whole window and pinned to its 12 dp margin.
/// 4. **The panel answers a tight page.** Where a page declared chrome, the
///    details drop the genres line and half their synopsis reserve.
///
/// The harness is the device's own window - 960x540 logical dp at density 320,
/// through `pumpTelevision` - and the card is the *box* both grids give it, so
/// the arithmetic under test is the arithmetic the device was measured with. No
/// test here touches the network except the one that mocks
/// [MetadataService.client] to give the panel genres and a synopsis; the fixtures
/// whose ids are not `tt...` fall back to `MissingPoster` and the details skip
/// their read, the seam the other two expansion test files stand on. The
/// synopsis placeholder pulses forever, so settling is explicit pumps and
/// `pumpAndSettle` is never used.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/services/metadata/metadata_service.dart';
import 'package:zplay/widgets/common/card_focus_expansion.dart';
import 'package:zplay/widgets/movie/movie_card.dart';

import '../support/tv_nav_harness.dart';

/// The window the television lays out against.
const Size _window = tvLogicalCanvas;

/// The edge margin the pop keeps - `_edgeMargin` in
/// `lib/widgets/common/card_focus_expansion.dart`, which is private. Spelled out
/// here because every assertion below is about the copy's distance from an edge,
/// and a test that reads the constant out of the code it is checking would not
/// be checking it.
const double _margin = 12;

/// See All's own grid cell: 220 dp of column for a 176 dp nominal card - the
/// poster (260.48) plus the measured caption block (47.1), i.e. 307.58 dp tall.
const Size _seeAllCell = Size(220, 307.58);

/// The chrome See All stacks above its first row - 56 dp of toolbar, 60 dp of
/// genre pill row and a 20 dp gap - which is what `catalog_page.dart` declares.
const double _seeAllChrome = 136;

/// A rail card's box, the shape a page with less chrome leaves the fit.
const Size _railCell = Size(176, 307.58);

/// The synopsis the mocked info response carries, and the genres that go with
/// it. Long enough that the panel's own `maxLines` is what clips it.
const String _synopsis =
    'A probe walks into a catalog and finds more words than any four lines can '
    'hold, which is the only thing this fixture needs from it.';

/// A movie whose id is not `tt...`, so the details panel skips its info read and
/// the panel is measured with no genres and an empty synopsis.
Movie _silent({String name = 'Probe'}) => Movie(
      id: 'probe-1',
      name: name,
      year: '2024',
      type: 'movie',
      addonBaseUrl: 'https://example.invalid',
    );

/// A movie the mocked client can answer for, so the panel has genres and a
/// synopsis to render - or to drop.
Movie _withMeta() => Movie(
      id: 'tt0000001',
      name: 'Probe',
      year: '2024',
      type: 'movie',
      addonBaseUrl: 'https://example.invalid',
    );

/// A page in the shape both grids ship: a chrome band at the top, painted, and
/// one card under it in its own cell box.
///
/// [declare] is whether the page tells the pop where its content starts. It is
/// the only variable between the runs below, so a difference in what the copy
/// paints is the declaration and nothing else.
Widget _page({
  required double contentTop,
  required Size cell,
  required double cardTop,
  required Movie movie,
  bool declare = true,
}) {
  final body = SizedBox.fromSize(
    size: _window,
    child: Stack(
      children: [
        // The page's chrome: the strip the pop must not paint over. Painted, so
        // a screenshot of this harness shows the bug the assertions describe.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: contentTop,
          child: const ColoredBox(color: Color(0xFF121212)),
        ),
        Positioned(
          left: 16,
          top: cardTop,
          width: cell.width,
          height: cell.height,
          child: MovieCard(movie: movie),
        ),
      ],
    ),
  );
  return declare ? PageContentTop(value: contentTop, child: body) : body;
}

/// The rect a render box actually paints at, with every paint transform on the
/// way up applied - the pop's own growth, and the position the fix clamps it to.
/// Same helper as the other two expansion test files; duplicated because all
/// three keep it private.
Rect _paintedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject(finder) as RenderBox;
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

/// The copy's own fill: the one `DecoratedBox` the surface starts with, under the
/// key the copy is located by. Its rect is the whole copy - the card and the
/// panel under it - because the panel hangs below the card inside that surface.
Finder _surface() => find.descendant(
      of: find.byKey(CardFocusExpansion.copyKey),
      matching: find.byType(DecoratedBox),
    );

/// The copy's card half, which is what the panel hangs under.
Finder _copyCard() => find.byKey(CardFocusExpansion.copyCardKey);

/// Mounts [page], puts focus on its card the way the remote does - through the
/// node the card itself built - and lets the pop open.
Future<void> _open(WidgetTester tester, Widget page) async {
  await pumpTelevision(tester, page);
  final card = find.byType(MovieCard);
  expect(card, findsOneWidget, reason: 'precondition: one card on this page');

  final detector = find.descendant(
    of: card,
    matching: find.byType(FocusableActionDetector),
  );
  final node = tester.widget<FocusableActionDetector>(detector).focusNode;
  expect(node, isNotNull, reason: 'precondition: the card is a D-pad target');
  node!.requestFocus();

  // A fixed sequence of frames rather than `pumpAndSettle`: the synopsis
  // placeholder is an endless animation, so "settled" never arrives. Fourteen
  // 50 ms frames is well past the growth and the details' reveal.
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    find.byKey(CardFocusExpansion.copyKey),
    findsOneWidget,
    reason: 'precondition: the pop is up',
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MetadataService.clearCache();
    MetadataService.client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'meta': {
            'id': 'tt0000001',
            'type': 'movie',
            'name': 'Probe',
            'description': _synopsis,
            'genres': ['Action', 'Drama', 'Thriller'],
            'runtime': '1h 40m',
          },
        }),
        200,
      ),
    );
  });

  tearDown(() {
    MetadataService.client = http.Client();
    MetadataService.clearCache();
  });

  testWidgets('the copy never paints above the content top its page declares',
      (tester) async {
    // See All's geometry exactly: the card's cell starts at the declared content
    // top, the way the first grid row does under the toolbar and the pills.
    await _open(
      tester,
      _page(
        contentTop: _seeAllChrome,
        cell: _seeAllCell,
        cardTop: _seeAllChrome,
        movie: _silent(),
      ),
    );

    final copy = _paintedRect(tester, _surface().first);
    final card = _paintedRect(tester, _copyCard());
    debugPrint('[content-top] copy = $copy, card = $card');

    expect(
      copy.top,
      greaterThanOrEqualTo(_seeAllChrome + _margin - 0.5),
      reason: 'the copy must stop below the page\'s chrome - the toolbar, the '
          'genre pills and the gap above the first row are all up there. '
          'Got $copy',
    );
    expect(
      copy.top,
      closeTo(_seeAllChrome + _margin, 0.5),
      reason: 'this cell has no room to grow into, so the copy is pinned to the '
          'bound the declaration sets: $copy',
    );
    expect(
      card.top,
      greaterThanOrEqualTo(_seeAllChrome + _margin - 0.5),
      reason: 'the card half is the top of the copy: $card',
    );

    // The band this page leaves is 540 - 136 - 24 = 380 dp, and this card's own
    // box is 307.58 on top of a panel that cannot be nothing - so the fit has
    // nothing to spend and the floor holds: the card is the resting card.
    expect(
      card.height,
      closeTo(_seeAllCell.height, 0.5),
      reason: 'the card may not grow into a band that has no room for it: '
          '$card',
    );

    // What the declaration buys: the card the user selected is fully on screen
    // and nothing of the page's own chrome is behind the pop. The panel's last
    // lines are the only thing off the bottom edge, and that is this cell's own
    // geometry - 307.58 dp of card plus a panel under 136 dp of chrome do not
    // fit a 540 dp window, and a pop that is cut at the window's edge is what a
    // pop that covers the toolbar would have cost instead.
    expect(
      card.bottom,
      lessThanOrEqualTo(_window.height + 0.5),
      reason: 'the selected card has to be visible: $card',
    );
    expect(
      copy.height,
      greaterThan(card.height),
      reason: 'the details panel is still under the card: $copy',
    );
  });

  testWidgets('the pop opens onto the band the page leaves it, and fits it',
      (tester) async {
    // 96 dp of chrome - the shell's own top bar plus a chip row - over a rail
    // card's box. The band is 540 - 96 - 24 = 420 dp, which is enough for the
    // card and a tight panel, so the fit is unclamped and the arithmetic closes.
    await _open(
      tester,
      _page(
        contentTop: 96,
        cell: _railCell,
        cardTop: 160,
        movie: _silent(),
      ),
    );

    final copy = _paintedRect(tester, _surface().first);
    const double band = 540 - 96 - 2 * _margin;
    debugPrint('[content-top] copy = $copy, band = $band');

    // The fit's own statement, taken at its word: the copy's total height is the
    // band, whatever the panel inside it turns out to measure. That is what
    // "the budget is the content band" means, and it is why this assertion does
    // not name a panel height.
    expect(
      copy.height,
      closeTo(band, 0.5),
      reason: 'card x fit + panel must be the band: $copy against $band',
    );
    expect(
      copy.top,
      closeTo(96 + _margin, 0.5),
      reason: 'the copy opens onto the band\'s top edge, one margin under the '
          'page\'s chrome: $copy',
    );
    expect(
      copy.bottom,
      closeTo(_window.height - _margin, 0.5),
      reason: 'and lands on its bottom edge: $copy',
    );
  });

  testWidgets('a page that declares nothing is the pop it has always been',
      (tester) async {
    // The control: the identical page with no declaration, which is every rail
    // in the app.
    final page = _page(
      contentTop: 96,
      cell: _railCell,
      cardTop: 160,
      movie: _silent(),
      declare: false,
    );
    await _open(tester, page);
    final bare = _paintedRect(tester, _surface().first);
    debugPrint('[content-top] undeclared copy = $bare');

    // Term for term what the fit and the clamp did before the signal existed:
    // the fit spends the whole window (540 - 2 x 12), and the copy is pinned to
    // the window's own margin - which on a page with chrome is the bug.
    expect(
      bare.height,
      closeTo(_window.height - 2 * _margin, 0.5),
      reason: 'the whole window is still the budget: $bare',
    );
    expect(
      bare.top,
      closeTo(_margin, 0.5),
      reason: 'still pinned to the window\'s margin: $bare',
    );
    expect(
      bare.bottom,
      closeTo(_window.height - _margin, 0.5),
      reason: '$bare',
    );
    expect(
      bare.top,
      lessThan(96),
      reason: 'precondition: undeclared, this copy paints over the page\'s '
          'chrome - which is the reported bug, and the reason a page declares '
          'one. Got $bare',
    );

    // And declaring 0 is the same thing as declaring nothing, to the pixel.
    await _open(
      tester,
      PageContentTop(
        value: 0,
        child: _page(
          contentTop: 96,
          cell: _railCell,
          cardTop: 160,
          movie: _silent(),
          declare: false,
        ),
      ),
    );
    final zero = _paintedRect(tester, _surface().first);
    expect(
      zero,
      bare,
      reason: 'a page that declares 0 declares no chrome, and that has to be '
          'the same pop as a page that declares nothing at all',
    );
  });

  testWidgets('focus still moves nothing on a page that declares a content top',
      (tester) async {
    // The pinned slot, on this fixture: the card's own box is frozen where the
    // page put it while the copy is up, because the copy is painted in the
    // Overlay and only paint moves.
    await pumpTelevision(
      tester,
      _page(
        contentTop: _seeAllChrome,
        cell: _seeAllCell,
        cardTop: _seeAllChrome,
        movie: _silent(),
      ),
    );
    final before = tester.getRect(find.byType(MovieCard));

    final detector = find.descendant(
      of: find.byType(MovieCard),
      matching: find.byType(FocusableActionDetector),
    );
    tester.widget<FocusableActionDetector>(detector).focusNode!.requestFocus();
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.byKey(CardFocusExpansion.copyKey),
      findsOneWidget,
      reason: 'precondition: the pop is up',
    );
    expect(
      tester.getRect(find.byType(MovieCard)),
      before,
      reason: 'the box a card occupies stays where it is when the ring arrives, '
          'declared chrome or not',
    );
  });

  testWidgets('a page with chrome gets the panel\'s tight form, others do not',
      (tester) async {
    // The film the mock answers for, so the panel has both a genres line and a
    // synopsis to decide about.
    Future<void> openOn({required bool declare}) async {
      await _open(
        tester,
        _page(
          contentTop: _seeAllChrome,
          cell: _seeAllCell,
          cardTop: _seeAllChrome,
          movie: _withMeta(),
          declare: declare,
        ),
      );
    }

    double synopsisReserve(WidgetTester tester) {
      // The nearest `SizedBox` above the synopsis text is the reserve box the
      // panel puts it in: the box is what stops the popped surface's own bottom
      // edge from moving when the read lands.
      final box = find.ancestor(
        of: find.text(_synopsis),
        matching: find.byType(SizedBox),
      );
      expect(box, findsWidgets, reason: 'the synopsis has to be painted at all');
      return tester.widget<SizedBox>(box.first).height!;
    }

    await openOn(declare: true);
    expect(
      find.textContaining('Action · Drama · Thriller'),
      findsNothing,
      reason: 'the tight form gives the genres line up: it is the one row the '
          'user does not need to identify the card',
    );
    expect(
      find.textContaining('2024 · Movie · 1h 40m'),
      findsOneWidget,
      reason: 'the year, the type and the runtime are not what gets dropped',
    );
    expect(tester.widget<Text>(find.text(_synopsis)).maxLines, 2,
        reason: 'two lines of prose, not four');
    expect(synopsisReserve(tester), 34,
        reason: 'and the reserve is two lines of bodySmall, not four');

    await openOn(declare: false);
    expect(
      find.textContaining('Action · Drama · Thriller'),
      findsOneWidget,
      reason: 'everywhere else the panel is the panel it has always been',
    );
    expect(tester.widget<Text>(find.text(_synopsis)).maxLines, 4,
        reason: 'four lines of prose where there is room for them');
    expect(synopsisReserve(tester), 68, reason: 'and the four-line reserve');
  });
}
