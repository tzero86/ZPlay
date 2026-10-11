/// The two grid pages' chrome, and the band the focus pop gets because of it.
///
/// `test/widgets/card_pop_content_top_test.dart` pins the signal itself: what a
/// page's declaration does to the copy's fit and to the bound it may not paint
/// above. This file pins that the two pages that had the defect declare a number
/// that is *their own* chrome, measured against the layout they build:
///
/// - On See All the copy used to be pinned to the window's 12 dp margin - 124 dp
///   above the first row - so it painted over the 56 dp toolbar and the genre
///   pill row, with the pills left half-visible beside it. The page's own
///   `gridTopPadding` is 56 + 60 + 20 = 136 dp, and the first row's cells start
///   exactly there.
/// - On Browse the same thing happened over the catalog chip row, one `s16` below
///   a header the page stacks itself (`padding.top` + the chip row, plus the
///   extras row on the form factors that do not merge it in).
///
/// Both pages are mounted the way they run - `CatalogPage` as the route it is
/// pushed as, `DiscoverPage` inside `AppShellScope` - on the device's own
/// 960x540 canvas. The assertions are written against the *layout the page
/// built* (the first cell's top, which is where its content starts) rather than
/// against a hard-coded header height, so they hold in this harness and in the
/// app: what is pinned is the relation the fix creates, not a mount's numbers.
///
/// The pop is measured through the copy's own keys, as the expansion tests do,
/// and the card is focused through the node it built rather than through a key
/// press - the geometry under test does not depend on how focus arrived, and a
/// press would drag the page's own scroll into the measurement.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zplay/models/addon/addon.dart';
import 'package:zplay/models/movie/movie_section.dart';
import 'package:zplay/pages/catalog/catalog_page.dart';
import 'package:zplay/pages/discover/discover_page.dart';
import 'package:zplay/services/addon/addon_manager.dart';
import 'package:zplay/services/layout/form_factor.dart';
import 'package:zplay/services/metadata/metadata_service.dart';
import 'package:zplay/services/theme/design_tokens.dart';
import 'package:zplay/shell/app_shell_scope.dart';
import 'package:zplay/widgets/common/card_focus_expansion.dart';
import 'package:zplay/widgets/common/focusable_card.dart';
import 'package:zplay/widgets/movie/movie_card.dart';

import '../support/tv_nav_harness.dart';

/// The edge margin the pop keeps - `_edgeMargin` in
/// `lib/widgets/common/card_focus_expansion.dart`, which is private. Spelled out
/// here because every assertion below is about the copy's distance from an edge,
/// and a test that read the constant out of the code it is checking would not be
/// checking it.
const double _margin = 12;

/// The gap both grids put between the bottom of their chrome and their first
/// row: `_buildDiscoverContent`'s `topOffset + ZplaySpacing.s16`, and the 20 dp
/// term of `catalog_page.dart`'s `gridTopPadding`.
const double _seeAllContentTop = 136;

/// One installed addon advertising a single movie catalog - what Browse needs to
/// have something to lay out, and the same shape `catalog_pills_test.dart` uses
/// for See All.
const String _installedAddon = '''
[
  {
    "id": "com.cinemeta.stremio",
    "baseUrl": "https://v3-cinemeta.strem.io",
    "enabled": true,
    "enableCatalogs": true,
    "name": "Cinemeta",
    "manifest": {
      "id": "com.cinemeta.stremio",
      "name": "Cinemeta",
      "version": "v3.0.14",
      "description": "The official addon for movie and series catalogs",
      "catalogs": [
        {"type": "movie", "id": "top", "name": "Top"}
      ]
    }
  }
]
''';

/// Enough genres that See All's pill row is wider than the canvas, which is the
/// state the row was reported in.
const List<String> _genres = [
  'Action',
  'Adventure',
  'Animation',
  'Comedy',
  'Crime',
  'Drama',
  'Family',
  'Fantasy',
  'Horror',
];

/// Twenty-four titles: enough for both grids to fill their visible rows.
const int _titleCount = 24;

/// The rect a render box actually paints at, with every paint transform on the
/// way up applied - the pop's own growth, and the position the fix clamps it to.
/// Same helper as the three expansion test files; duplicated because all of them
/// keep it private.
Rect _paintedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject(finder) as RenderBox;
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

/// The copy's own fill: the one `DecoratedBox` the surface starts with, under
/// the key the copy is located by. Its rect is the whole copy - the card and the
/// panel under it.
Finder _surface() => find.descendant(
      of: find.byKey(CardFocusExpansion.copyKey),
      matching: find.byType(DecoratedBox),
    );

/// The grid card nearest the page's top-left corner: the first cell of the first
/// row, which is the cell the defect is about.
Finder _firstCard(WidgetTester tester) {
  final cards = find.byType(MovieCard);
  expect(cards, findsWidgets, reason: 'precondition: the grid drew cards');

  var best = 0;
  var bestRect = tester.getRect(cards.at(0));
  for (var i = 1; i < cards.evaluate().length; i++) {
    final rect = tester.getRect(cards.at(i));
    final higher = rect.top < bestRect.top - 0.5;
    final sameRowToTheLeft =
        (rect.top - bestRect.top).abs() < 0.5 && rect.left < bestRect.left;
    if (higher || sameRowToTheLeft) {
      best = i;
      bestRect = rect;
    }
  }
  return cards.at(best);
}

/// Puts focus on [card] the way the remote does - through the node the card
/// built, so the pop is driven by the same focus change a D-pad press makes -
/// and lets it open. Settling is explicit pumps: the synopsis placeholder pulses
/// forever, and a page that is loading shows a spinner that does the same, so
/// `pumpAndSettle` never returns.
Future<void> _focusAndOpen(WidgetTester tester, Finder card) async {
  final detector = find.descendant(
    of: card,
    matching: find.byType(FocusableActionDetector),
  );
  final node = tester.widget<FocusableActionDetector>(detector).focusNode;
  expect(node, isNotNull, reason: 'precondition: the card is a D-pad target');
  node!.requestFocus();
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    find.byKey(CardFocusExpansion.copyKey),
    findsOneWidget,
    reason: 'precondition: the pop is up on the card that took focus',
  );
}

MovieSection _section() => MovieSection(
      title: 'Popular',
      subtitle: '',
      contentType: 'movie',
      addonBaseUrl: 'https://addon.example.com',
      catalog: AddonCatalog(
        type: 'movie',
        id: 'top',
        extra: const [CatalogExtra(name: 'genre', options: _genres)],
      ),
      movies: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    MetadataService.clearCache();
    // URL-aware, because the two pages read two different resources: the grids
    // need a catalog, and the details panel asks for one title's info. Both are
    // stubbed, so nothing here touches the network - and the panel's read is
    // what makes the tight form's dropped genres line observable.
    MetadataService.client = MockClient((request) async {
      if (request.url.path.contains('/meta/')) {
        return http.Response(
          jsonEncode({
            'meta': {
              'id': 'tt0',
              'type': 'movie',
              'name': 'Title 0',
              'description':
                  'A synopsis long enough that only the panel\'s own line limit '
                      'is what ends it, which is what the reserve is for.',
              'genres': ['Action', 'Drama', 'Thriller'],
              'runtime': '1h 40m',
            },
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'metas': [
            for (var i = 0; i < _titleCount; i++)
              {'id': 'tt$i', 'name': 'Title $i', 'type': 'movie'},
          ],
        }),
        200,
      );
    });
    AddonManager.readStoredForTesting = () async => _installedAddon;
    await AddonManager.instance.reload();
  });

  tearDown(() {
    MetadataService.client = http.Client();
    MetadataService.clearCache();
    AddonManager.readStoredForTesting = null;
  });

  /// Mounts See All and lets its catalog load land. No `pumpAndSettle`: the
  /// page's loading spinner is an endless animation, so "settled" is never.
  Future<void> mountSeeAll(WidgetTester tester) async {
    await pumpTelevision(tester, CatalogPage(section: _section()));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Mounts Browse the way the shell does, on the television canvas.
  Future<void> mountBrowse(WidgetTester tester) async {
    final slot = ValueNotifier(ShellSlot.browse);
    await pumpTelevision(
      tester,
      AppShellScope(
        controller: AppShellController(
          current: slot,
          onSelect: (next) {
            slot.value = next;
            return true;
          },
          formFactor: () => FormFactor.television,
        ),
        child: const DiscoverPage(),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('See All: the pop stops under the toolbar and the pill row',
      (tester) async {
    await mountSeeAll(tester);
    final card = _firstCard(tester);
    final cell = tester.getRect(card);

    // The page's chrome is its own `gridTopPadding`, and this is the assertion
    // that ties the number the page declares to the layout it builds: the first
    // row's cells start at it.
    expect(
      cell.top,
      closeTo(_seeAllContentTop, 0.5),
      reason: 'precondition: See All stacks 56 dp of toolbar, a 60 dp pill row '
          'and a 20 dp gap above its first row, so the cells start at '
          '$_seeAllContentTop. Got $cell',
    );

    await _focusAndOpen(tester, card);
    final copy = _paintedRect(tester, _surface().first);
    debugPrint('[grid-pop] See All copy = $copy');

    expect(
      copy.top,
      greaterThanOrEqualTo(_seeAllContentTop + _margin - 0.5),
      reason: 'the copy may not paint above the page\'s own content: the '
          'toolbar and the genre pills are up there. Got $copy',
    );
    expect(
      copy.top,
      closeTo(_seeAllContentTop + _margin, 0.5),
      reason: 'with the cell at $_seeAllContentTop and nothing to grow into, '
          'the copy is pinned to the bound the page sets: $copy',
    );

    // The pills themselves, so the claim is about the widgets the user saw
    // half-covered rather than about a number: the row sits under the toolbar
    // and the copy clears it entirely.
    final pill = tester.getRect(
      find.ancestor(of: find.text('Action'), matching: find.byType(FocusableCard)),
    );
    expect(
      copy.top,
      greaterThan(pill.bottom),
      reason: 'the genre pill row has to stay visible beside the pop. Pill '
          '$pill, copy $copy',
    );

    // And the tight panel, on the page it exists for: the mock answers with
    // genres, and the panel still drops the line.
    expect(
      find.textContaining('Action · Drama · Thriller'),
      findsNothing,
      reason: 'a page with chrome above the surface gets the panel\'s tight form',
    );
  });

  testWidgets('Browse: the pop stops under the chip row', (tester) async {
    await mountBrowse(tester);
    final card = _firstCard(tester);
    final cell = tester.getRect(card);

    await _focusAndOpen(tester, card);
    final copy = _paintedRect(tester, _surface().first);
    debugPrint('[grid-pop] Browse cell = $cell, copy = $copy');

    // Browse's declaration is `headerHeight + s16`, so the first row's cells
    // start at the page's content top here too - whatever header height this
    // mount produced (the shell's own bar is not mounted in a widget test, so it
    // is the chip row alone).
    expect(
      copy.top,
      greaterThanOrEqualTo(cell.top + _margin - 0.5),
      reason: 'the copy may not paint above the page\'s content, and on Browse '
          'the catalog chip row is directly above it. Cell $cell, copy $copy',
    );
    expect(
      copy.top,
      greaterThan(cell.top - ZplaySpacing.s16 + _margin - 0.5),
      reason: 'one margin below the bottom of the page\'s chrome, which is the '
          'gap above this row: $copy',
    );
    expect(
      tester.getRect(_firstCard(tester)).top,
      closeTo(cell.top, 0.5),
      reason: 'precondition: the page did not scroll the row out from under the '
          'measurement',
    );
  });
}
