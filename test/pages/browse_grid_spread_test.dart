/// The Browse grid's columns.
///
/// At 960x540 dp the grid's cards are height-bound, not width-bound: the budget
/// for two rows squeezes the artwork to 112.8 x 166.9 dp while
/// `MovieCardSizing.cardWidth` stays at its nominal 176. Counting columns of 176
/// left one 112 dp card alone in a 220 dp cell - about 120 dp of empty canvas
/// between neighbours, and a 120 dp dead band at the right edge against the
/// grid's own 16 dp left padding, so four sparse columns used barely half the
/// canvas.
///
/// These tests pin the properties the fix is made of rather than the column
/// count itself: every column is the width of the card that is drawn, the gaps
/// between columns are uniform, and both outer margins are the grid's own
/// padding. The card's own size is pinned unchanged, because 114x169 dp is
/// deliberate.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zplay/pages/discover/discover_page.dart';
import 'package:zplay/services/addon/addon_manager.dart';
import 'package:zplay/services/layout/form_factor.dart';
import 'package:zplay/services/metadata/metadata_service.dart';
import 'package:zplay/shell/app_shell_scope.dart';
import 'package:zplay/widgets/common/focusable_card.dart';
import 'package:zplay/widgets/movie/movie_card.dart';

import '../support/tv_nav_harness.dart';

/// One installed addon advertising a single movie catalog, which is all Browse
/// needs to have something to lay out. The catalog itself is served by the
/// stubbed client below, so nothing here touches the network.
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

/// Enough titles to fill the television's two visible rows at any column count.
const int _titleCount = 28;

/// The grid's own side padding: `MovieCardSizing.sidePadding`, which is
/// [ZplaySpacing.s16].
const double _margin = 16;

/// The house gap between two cells, `MovieCardSizing.spacing`.
const double _gap = 16;

/// The television canvas these numbers were reported on.
const double _canvasWidth = 960;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    MetadataService.clearCache();
    MetadataService.client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'metas': [
            for (var i = 0; i < _titleCount; i++)
              {'id': 'tt$i', 'name': 'Title $i', 'type': 'movie'},
          ],
        }),
        200,
      ),
    );
    AddonManager.readStoredForTesting = () async => _installedAddon;
    await AddonManager.instance.reload();
  });

  tearDown(() {
    MetadataService.client = http.Client();
    MetadataService.clearCache();
    AddonManager.readStoredForTesting = null;
  });

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
    // The catalog load is a future; the spinner it shows in the meantime is an
    // endless animation, so this pumps a fixed few frames rather than settling.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// The cards laid out in the top row, left to right.
  List<Rect> topRow(WidgetTester tester) {
    final cards = find.byType(MovieCard);
    final rects = <Rect>[
      for (var i = 0; i < tester.widgetList(cards).length; i++)
        tester.getRect(cards.at(i)),
    ]..sort((a, b) => a.left.compareTo(b.left));
    if (rects.isEmpty) return const [];
    final top = rects.first.top;
    return rects.where((r) => (r.top - top).abs() < 0.5).toList();
  }

  /// The artwork inside a card: the ring wraps the poster, so its rect is the
  /// size the user actually sees.
  Rect artwork(WidgetTester tester, Rect cell) {
    final card = find.byWidgetPredicate(
      (w) => w is MovieCard,
      description: 'the card in this cell',
    );
    for (var i = 0; i < card.evaluate().length; i++) {
      if (tester.getRect(card.at(i)) == cell) {
        return tester.getRect(
          find.descendant(of: card.at(i), matching: find.byType(CardFocusRing)),
        );
      }
    }
    throw StateError('no card at $cell');
  }

  testWidgets('the columns are the width of the card that is drawn',
      (tester) async {
    await mountBrowse(tester);

    final row = topRow(tester);
    expect(row, isNotEmpty, reason: 'the grid has to have drawn something');

    for (final cell in row) {
      final art = artwork(tester, cell);
      expect(
        cell.width - art.width,
        lessThanOrEqualTo(8),
        reason: 'a column the width band asked for leaves the 112 dp card '
            'drowning in empty canvas: $cell against $art',
      );
    }
  });

  testWidgets('the card keeps the size it is documented at', (tester) async {
    await mountBrowse(tester);

    final art = artwork(tester, topRow(tester).first);
    expect(art.width, closeTo(112.8, 1));
    expect(art.height, closeTo(166.9, 1));
  });

  testWidgets('the columns are spread evenly, with even outer margins',
      (tester) async {
    await mountBrowse(tester);

    final row = topRow(tester);
    expect(row.length, greaterThanOrEqualTo(6),
        reason: 'four sparse columns use barely half the canvas');

    expect(row.first.left, closeTo(_margin, 0.5));
    expect(row.last.right, closeTo(_canvasWidth - _margin, 0.5));

    for (var i = 1; i < row.length; i++) {
      expect(
        row[i].left - row[i - 1].right,
        closeTo(_gap, 0.5),
        reason: 'the gap between columns is uniform, not a dead band at the end',
      );
    }
  });
}
