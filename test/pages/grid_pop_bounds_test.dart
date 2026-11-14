/// The two grid pages on a television: a focused cell answers with its ring
/// and pops nothing.
///
/// The pop used to grow a details panel under a grid cell too. A cell is
/// narrow and boxed in on every side, so the panel was squeezed to poster
/// width, truncated its own text and ran off the bottom of Browse; the earlier
/// fix only kept it from painting over the chrome above. Netflix's TV grids
/// answer focus with the ring alone, and the cell's caption already carries the
/// title and facts, so the pop is now for rail cards only (see
/// `CardFocusExpansion._inRail`). This file pins that on both pages that grid
/// their cards - See All as the route it is pushed as, Browse inside
/// `AppShellScope` - on the device's own 960x540 canvas.
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
import 'package:zplay/shell/app_shell_scope.dart';
import 'package:zplay/widgets/common/card_focus_expansion.dart';
import 'package:zplay/widgets/movie/movie_card.dart';

import '../support/tv_nav_harness.dart';

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

  // On a television a grid cell does not pop at all: a panel grown under a
  // narrow cell was squeezed to poster width and ran off the page. Focus is the
  // ring, and the cell's own caption carries the title and facts. Both grid
  // pages are checked, since both used to paint the pop over their chrome.
  for (final page in ['See All', 'Browse']) {
    testWidgets('$page: a focused grid cell keeps its place and pops nothing', (
      tester,
    ) async {
      await (page == 'See All' ? mountSeeAll(tester) : mountBrowse(tester));
      final card = _firstCard(tester);
      final cell = tester.getRect(card);
      final detector = find.descendant(
        of: card,
        matching: find.byType(FocusableActionDetector),
      );
      final node = tester.widget<FocusableActionDetector>(detector).focusNode;
      expect(
        node,
        isNotNull,
        reason: 'precondition: the card is a D-pad target',
      );
      node!.requestFocus();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(node.hasFocus, isTrue, reason: 'the cell took focus');
      expect(
        find.byKey(CardFocusExpansion.copyKey),
        findsNothing,
        reason: 'a grid cell must not grow a details panel over its neighbours',
      );
      expect(
        tester.getRect(_firstCard(tester)),
        cell,
        reason: 'focus moves nothing in the grid',
      );
    });
  }
}
