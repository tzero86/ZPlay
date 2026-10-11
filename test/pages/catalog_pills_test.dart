/// The 'See All' grid's genre pill row.
///
/// Two defects on a television, from one row.
///
/// **The pills had no focus indicator.** Selection was an opaque accent fill and
/// focus painted nothing, so the two states were indistinguishable: the sweep
/// pressed Right ten times with nothing moving on screen and the OK that
/// followed applied whichever filter the invisible focus had walked onto. The
/// Browse sort chips answer the same question with the app's own ring, so these
/// pills now do too - and the selected fill had to become the accent *tint* the
/// tokens define for a selected chip, because an accent ring around an accent
/// pill is invisible, which is exactly the state focus is left in after a filter
/// is applied.
///
/// **The row's side margins were inside the scroll view.** A `padding` is
/// content, so the scroll view's edges were the display's edges - 0 and 960. A
/// focus move reveals a pill by railing it against the viewport's trailing edge,
/// so once focus walked far enough the last pill's fill (and its glow) was drawn
/// on the display's final pixel, and the scroll that got it there pushed the
/// first pill past x=0. Measured on the bug: the focused pill's trailing edge
/// lands on 960.0 dp; with the margins outside the scroll view it lands on 944.0.
///
/// The row is driven with the remote's own keys ([pressDpad]) because the
/// geometry above only appears once focus moves - a card that is simply tapped
/// into focus never triggers the reveal scroll at all.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zplay/models/addon/addon.dart';
import 'package:zplay/models/movie/movie_section.dart';
import 'package:zplay/pages/catalog/catalog_page.dart';
import 'package:zplay/services/metadata/metadata_service.dart';
import 'package:zplay/widgets/common/focusable_card.dart';

import '../support/tv_nav_harness.dart';

/// Enough genres that the row is wider than the 960 dp canvas, so the reveal
/// scroll has somewhere to go - which is the state the row was reported in.
const List<String> _genres = [
  'Action',
  'Adventure',
  'Animation',
  'Biography',
  'Comedy',
  'Crime',
  'Documentary',
  'Drama',
  'Family',
  'Fantasy',
  'History',
  'Horror',
];

/// The last pill, and the one that has to be revealed at the end of the row.
const String _lastPill = 'Horror';

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

/// The pill's own widget: the card that carries the label. Scoped through the
/// label so the assertions below can never pick up a grid card or a scroll
/// arrow by accident.
Finder _pill(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(FocusableCard),
    );

Finder _pillRing(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(CardFocusRing));

/// The pill row's scroll view, found through a pill so nothing else on the page
/// can match: there is exactly one, and it is the row's viewport.
Finder _pillScrollView() => find.ancestor(
      of: find.text('Action'),
      matching: find.byType(ListView),
    );

/// The ring [CardFocusRing] paints, and only that: the 3 dp accent border. Every
/// ordinary border on a pill is a 1 dp hairline, so the width separates the
/// focus indicator from the pill's own edge.
Finder _ringBorder(String label) => find.descendant(
      of: _pillRing(label),
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).border is Border &&
            ((w.decoration as BoxDecoration).border as Border).top.width == 3,
      ),
    );

bool _ringDrawn(String label) =>
    _ringBorder(label).evaluate().isNotEmpty;

Color _ringColour(WidgetTester tester, String label) {
  final box = tester.widget<DecoratedBox>(_ringBorder(label).first);
  return (((box.decoration as BoxDecoration).border as Border).top.color);
}

/// The pill's fill, or null when the pill is not in the tree - a list only
/// builds what is near the viewport, so a pill that has been scrolled out is
/// gone rather than merely off screen.
Color? _tryPillFill(WidgetTester tester, String label) {
  final container = find.descendant(
    of: _pill(label),
    matching: find.byType(AnimatedContainer),
  );
  if (container.evaluate().isEmpty) return null;
  final widget = tester.widget<AnimatedContainer>(container.first);
  return (widget.decoration as BoxDecoration).color;
}

Color _pillFill(WidgetTester tester, String label) {
  final fill = _tryPillFill(tester, label);
  expect(fill, isNotNull, reason: 'the pill "$label" has to be on screen here');
  return fill!;
}

/// Puts focus on a pill the way the remote does, without a press: the node is
/// read off the card the pill built, so the assertion is about the pill the user
/// is on rather than about a node this test invented.
Future<void> _focusPill(WidgetTester tester, String label) async {
  final detector = find.descendant(
    of: _pill(label),
    matching: find.byType(FocusableActionDetector),
  );
  final node = tester.widget<FocusableActionDetector>(detector).focusNode;
  expect(node, isNotNull, reason: 'a pill has to be reachable by a remote');
  node!.requestFocus();
  await tester.pump();
}

/// Mounts the page and lets the catalog load land. No `pumpAndSettle`: the
/// page's loading spinner is an endless animation, so "settled" is never.
Future<void> _mount(WidgetTester tester) async {
  await pumpTelevision(tester, CatalogPage(section: _section()));
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MetadataService.client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'metas': [
            for (var i = 0; i < 24; i++)
              {'id': 'tt$i', 'name': 'Title $i', 'type': 'movie'},
          ],
        }),
        200,
      ),
    );
  });

  tearDown(() {
    MetadataService.client = http.Client();
    MetadataService.clearCache();
  });

  group('the pill row marks where the remote is', () {
    testWidgets('the focused pill draws the ring and the selected pill does not',
        (tester) async {
      await _mount(tester);

      // 'All' is the filter in force on arrival, and it is not focused: the
      // selection fill is not a focus indicator.
      expect(_pillFill(tester, 'All'), isNot(_pillFill(tester, 'Action')),
          reason: 'a selected pill is a fill, and it has to be visible');
      expect(_ringDrawn('All'), isFalse);

      final before = tester.getRect(_pill('Action'));
      await _focusPill(tester, 'Action');

      expect(_ringDrawn('Action'), isTrue,
          reason: 'the pill the remote is on must draw the ring');
      expect(_ringDrawn('All'), isFalse,
          reason: 'selection is not focus');
      expect(tester.getRect(_pill('Action')), before,
          reason: 'the ring is painted over the pill\'s own edge: focus must '
              'never move the box the card occupies');
    });

    testWidgets('the ring stays visible on the pill that is also selected',
        (tester) async {
      await _mount(tester);
      await _focusPill(tester, 'All');

      expect(_ringDrawn('All'), isTrue,
          reason: 'focus is still painted on the selected pill');

      // Drawn is not the same as visible: an accent ring around an accent fill
      // is the state this row shipped in effect, and it reads as no focus at
      // all. The two have to be different colours to be distinguishable.
      expect(_ringColour(tester, 'All'), isNot(_pillFill(tester, 'All')),
          reason: 'the ring has to be visible against the pill it is on');
      expect(_ringColour(tester, 'All'), isNot(_pillFill(tester, 'Action')),
          reason: 'the ring is the same accent on every pill');
    });

    testWidgets('OK applies the pill the ring is on', (tester) async {
      await _mount(tester);
      await _focusPill(tester, 'Action');

      // Walk to 'Drama' the way a remote does, then activate.
      for (var i = 0; i < 12 && focusedId(tester) != 'Drama'; i++) {
        await pressDpad(tester, LogicalKeyboardKey.arrowRight, step: 'pill$i');
      }
      expect(focusedId(tester), 'Drama',
          reason: 'Right has to move the ring, or OK cannot be aimed');

      await pressDpad(tester, LogicalKeyboardKey.select, step: 'ok');

      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      final selected = _pillFill(tester, 'Drama');
      // Every other pill still in the tree is unselected: the row only builds
      // what is near its viewport, so this is the set of pills on screen.
      final others = <Color>{};
      for (final genre in _genres) {
        if (genre == 'Drama') continue;
        final fill = _tryPillFill(tester, genre);
        if (fill != null) others.add(fill);
      }
      expect(others, isNotEmpty,
          reason: 'the rest of the row has to still be there to compare');
      expect(others, isNot(contains(selected)),
          reason: 'exactly one pill carries the applied filter');
      expect(_ringDrawn('Drama'), isTrue,
          reason: 'applying a filter must not cost the user the focus ring: '
              'the remote is still on that pill');

      // The pill that carried the filter before is deselected again. The row has
      // scrolled by now, so 'All' has to be walked back into the tree first -
      // which is also the proof that the remote can leave an applied filter
      // without its ring disappearing on the way.
      for (var i = 0; i < 15 && focusedId(tester) != 'All'; i++) {
        await pressDpad(tester, LogicalKeyboardKey.arrowLeft, step: 'back$i');
      }
      expect(focusedId(tester), 'All');
      expect(_pillFill(tester, 'All'), _pillFill(tester, 'Action'),
          reason: 'the filter that was in force is no longer selected');
    });
  });

  group('the pill row keeps its margins at both ends', () {
    testWidgets('the scroll view is inset by the row margins, not the display',
        (tester) async {
      await _mount(tester);

      final viewport = tester.getRect(_pillScrollView());
      expect(viewport.left, closeTo(16, 0.5),
          reason: 'the 16 dp leading margin is the row\'s, not the scroll view\'s');
      expect(viewport.right, closeTo(944, 0.5),
          reason: 'and the trailing margin has to be inside the view edge');

      expect(tester.getRect(_pill('All')).left, closeTo(16, 0.5),
          reason: 'at rest the first pill sits on the margin');
    });

    testWidgets('the last pill is revealed inside the display, not on its edge',
        (tester) async {
      await _mount(tester);
      await _focusPill(tester, 'Action');

      // Walk the row out. The reveal scroll is what pushes the row once focus
      // passes the pills that were already visible.
      for (var i = 0; i < _genres.length && focusedId(tester) != _lastPill; i++) {
        await pressDpad(tester, LogicalKeyboardKey.arrowRight, step: 'row$i');
      }
      expect(focusedId(tester), _lastPill, reason: 'the row has to reach its end');

      final last = tester.getRect(_pill(_lastPill));
      expect(last.right, lessThanOrEqualTo(944.0),
          reason: 'a pill revealed at the end of the row must stop at the '
              'margin, not run into the display\'s last pixel');
      expect(last.left, greaterThanOrEqualTo(0.0));
    });
  });
}
