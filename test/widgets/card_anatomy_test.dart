/// The card anatomy from the brief's §6.
///
/// Resting is poster, title and metadata. Focus adds a crisp accent ring
/// and - for a series only - a type badge, and must move nothing. A film never
/// carries the type badge.
///
/// The geometry assertions measure the card's **layout** rect (the `MovieCard`
/// element resolves to the `Focus` marker, which sits above the card's own
/// paint transforms), which is exactly the geometry the shipped bug broke: a
/// border that dropped on focus re-laid-out the row by 4 dp.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/models/anime/anime_media.dart';
import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/services/iptv/hardcoded_channels.dart';
import 'package:zplay/services/theme/design_tokens.dart';
import 'package:zplay/widgets/anime/anime_card.dart';
import 'package:zplay/widgets/common/card_badges.dart';
import 'package:zplay/widgets/common/focusable_card.dart';
import 'package:zplay/widgets/iptv/iptv_channel_card.dart';
import 'package:zplay/widgets/movie/movie_card.dart';

/// Every painted border inside [scope]. For a movie card the rule is that a
/// focused card paints exactly one - the ring - so this finder must return
/// exactly one. (A live-TV card carries a pill outline on its LIVE badge, so
/// that family is checked through [_ringBorders] instead.)
Finder _bordersIn(Finder scope) => find.descendant(
      of: scope,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).border != null,
        description: 'a painted border',
      ),
    );

/// The card's focus ring: a border of the ring's own accent width. Scoped this
/// way rather than to `CardFocusRing`, because the ring's subtree also holds
/// the card's badges - and a badge outline (the live pill) is not a card edge.
Finder _ringBorders(Finder scope) => find.descendant(
      of: scope,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).border != null &&
            (widget.decoration as BoxDecoration).border!.top.width > 1.0,
        description: 'the ring, wider than a hairline',
      ),
    );

void main() {
  // `onShowFocusHighlight` is only reported in the traditional highlight mode,
  // which is what a D-pad television is. Force it so focus reads the same in a
  // widget test as it does on the device.
  setUp(() {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });
  tearDown(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  Widget host(Widget child, {double width = 176, double height = 340}) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, height: height, child: child),
          ),
        ),
      );

  Movie movie({String type = 'movie', String? rating}) => Movie(
        id: 'probe',
        name: 'Probe Title',
        year: '2024',
        type: type,
        addonBaseUrl: 'test',
        imdbRating: rating,
      );

  AnimeMedia anime(String format) => AnimeMedia(id: 1, format: format);

  HardcodedChannel channel() => const HardcodedChannel(
        id: 'probe',
        name: 'Probe Channel',
        short: 'PRB',
        category: 'Combat',
        keywords: ['probe'],
        gradient: [Color(0xFFD20A0A), Color(0xFF1A1A1A)],
      );

  Future<void> focusFirstCard(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  group('the focus ring', () {
    testWidgets('a focused card paints exactly one accent ring, no glow',
        (tester) async {
      await tester.pumpWidget(
        host(MovieCard(movie: movie(), onTap: () {})),
      );
      await tester.pump();

      // Scoped to the ring's own subtree rather than to the whole card: that
      // subtree also holds the poster's own fill and shadow and, on the live-TV
      // card, the badge's pill outline - neither of which is the card's edge.
      // What this pins is that the card's own edge is one accent line and
      // nothing else, which is the duplicate-ring bug it was written for.
      final cardBorders = _bordersIn(find.byType(CardFocusRing));
      expect(cardBorders, findsNothing,
          reason: 'a resting card paints no ring');

      await focusFirstCard(tester);

      expect(cardBorders, findsOneWidget,
          reason: 'one ring, never a ring plus a separate border');
      expect(
        tester.widget<CardFocusRing>(find.byType(CardFocusRing)).focused,
        isTrue,
        reason: 'the border is the card focus ring, not a decorative one',
      );
      final decoration =
          tester.widget<DecoratedBox>(cardBorders).decoration
              as BoxDecoration;
      expect(decoration.border!.top.width, greaterThan(1.0),
          reason: 'the ring is a crisp accent line, wider than a hairline');
      expect(decoration.border!.top.color,
          ZplayTokens.of(tester.element(cardBorders)).accent,
          reason: 'the ring is the palette accent');
      expect(decoration.boxShadow, isNull,
          reason: 'no outer glow, no inner glow');
    });
  });

  group('focus and selection move nothing', () {
    testWidgets('focusing changes no geometry', (tester) async {
      await tester.pumpWidget(
        host(MovieCard(movie: movie(type: 'series', rating: '8.6'), onTap: () {})),
      );
      await tester.pump();

      final card = find.byType(MovieCard);
      final before = tester.getRect(card);
      final beforeSize = tester.getSize(card);

      await focusFirstCard(tester);

      expect(tester.getRect(card), before,
          reason: 'focus must not move the card');
      expect(tester.getSize(card), beforeSize,
          reason: 'focus must not resize the card');
    });

    testWidgets('pressing changes no geometry', (tester) async {
      await tester.pumpWidget(
        host(MovieCard(movie: movie(type: 'series'), onTap: () {})),
      );
      await tester.pump();

      final card = find.byType(MovieCard);
      final before = tester.getRect(card);

      final gesture = await tester.startGesture(tester.getCenter(card));
      await tester.pump(const Duration(milliseconds: 250));

      expect(tester.getRect(card), before,
          reason: 'a selected card must not move or resize either');

      await gesture.up();
    });
  });

  group('the type badge', () {
    testWidgets('appears for a series, only once focused', (tester) async {
      await tester.pumpWidget(
        host(MovieCard(movie: movie(type: 'series'), onTap: () {})),
      );
      await tester.pump();

      expect(find.text('SERIES'), findsNothing,
          reason: 'the type badge is revealed on focus only');

      await focusFirstCard(tester);

      expect(find.text('SERIES'), findsOneWidget);
    });

    testWidgets('never appears for a film', (tester) async {
      await tester.pumpWidget(
        host(MovieCard(movie: movie(type: 'movie'), onTap: () {})),
      );
      await tester.pump();

      await focusFirstCard(tester);

      expect(find.text('SERIES'), findsNothing);
      expect(find.text('MOVIE'), findsNothing);
      expect(find.byType(CardTypeBadge), findsNothing);
    });

    testWidgets('an anime series is a series', (tester) async {
      await tester.pumpWidget(
        host(MovieCard(movie: movie(type: 'anime'), onTap: () {})),
      );
      await tester.pump();
      await focusFirstCard(tester);

      expect(find.text('ANIME'), findsOneWidget);
    });
  });

  group('the rating badge', () {
    testWidgets('shows the score in every state', (tester) async {
      await tester.pumpWidget(
        host(MovieCard(movie: movie(rating: '8.6'), onTap: () {})),
      );
      await tester.pump();

      expect(find.byType(CardRatingBadge), findsOneWidget);
      expect(find.text('8.6'), findsOneWidget,
          reason: 'the score is the rating the catalog gave');
    });

    testWidgets('is absent when the item has no rating', (tester) async {
      await tester.pumpWidget(
        host(MovieCard(movie: movie(), onTap: () {})),
      );
      await tester.pump();

      expect(find.byType(CardRatingBadge), findsNothing);
    });
  });

  group('the anime card follows the same anatomy', () {
    testWidgets('an episodic title carries the badge on focus', (tester) async {
      await tester.pumpWidget(
        host(AnimeCard(anime: anime('TV'), onTap: () {})),
      );
      await tester.pump();

      expect(find.text('SERIES'), findsNothing);
      await focusFirstCard(tester);
      expect(find.text('SERIES'), findsOneWidget);
    });

    testWidgets('an anime film carries no type badge', (tester) async {
      await tester.pumpWidget(
        host(AnimeCard(anime: anime('MOVIE'), onTap: () {})),
      );
      await tester.pump();
      await focusFirstCard(tester);

      expect(find.byType(CardTypeBadge), findsNothing);
    });
  });

  group('the live-TV card follows the same anatomy', () {
    testWidgets('a focused channel paints exactly one accent ring',
        (tester) async {
      await tester.pumpWidget(
        host(IptvChannelCard(channel: channel(), onTap: () {})),
      );
      await tester.pump();

      final ring = _ringBorders(find.byType(IptvChannelCard));
      expect(ring, findsNothing, reason: 'a resting channel paints no ring');

      await focusFirstCard(tester);

      expect(ring, findsOneWidget);
      final decoration =
          tester.widget<DecoratedBox>(ring).decoration as BoxDecoration;
      expect(decoration.border!.top.width, greaterThan(1.0));
      expect(decoration.border!.top.color,
          ZplayTokens.of(tester.element(ring)).accent);
      expect(decoration.boxShadow, isNull, reason: 'no glow');
    });

    testWidgets('focus moves nothing and reveals the category badge',
        (tester) async {
      await tester.pumpWidget(
        host(IptvChannelCard(channel: channel(), onTap: () {})),
      );
      await tester.pump();

      final card = find.byType(IptvChannelCard);
      final before = tester.getRect(card);
      expect(find.byType(CardTypeBadge), findsNothing,
          reason: 'the type badge is revealed on focus only');

      await focusFirstCard(tester);

      expect(tester.getRect(card), before,
          reason: 'focus must not move or resize the card');
      expect(find.text('COMBAT'), findsOneWidget);
    });
  });

  group('sizing still describes the cell', () {
    test('the badges add no height to the measured text block', () {
      // Badges are `Positioned` overlays on the poster. If one ever claimed
      // vertical space the text block would grow and this would move.
      expect(MovieCardSizing.textBlockHeight, 47.1);
      final sizing = MovieCardSizing.fromWidth(1920);
      expect(
        sizing.totalHeight,
        closeTo(sizing.posterHeight + 47.1, 0.01),
      );
    });

    testWidgets('a box the sizing budgets fits the card without overflow',
        (tester) async {
      final sizing = MovieCardSizing.fromWidth(1920);
      await tester.pumpWidget(
        host(
          MovieCard(movie: movie(type: 'series', rating: '8.6'), onTap: () {}),
          width: sizing.cardWidth,
          height: sizing.totalHeight,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: 'a cell exactly the budgeted height must not overflow');
    });

    testWidgets('the badges are overlays and take no space from the poster',
        (tester) async {
      final sizing = MovieCardSizing.fromWidth(1920);

      Future<double> posterHeight(Movie item) async {
        await tester.pumpWidget(
          host(
            MovieCard(movie: item, onTap: () {}),
            width: sizing.cardWidth,
            height: sizing.totalHeight,
          ),
        );
        await tester.pump();
        return tester
            .getSize(
              find.descendant(
                of: find.byType(MovieCard),
                matching: find.byType(AspectRatio),
              ),
            )
            .height;
      }

      final bare = await posterHeight(movie());
      final badged = await posterHeight(movie(type: 'series', rating: '8.6'));

      expect(badged, closeTo(bare, 0.001),
          reason: 'a type badge and a rating badge must not push the title '
              'down: they are Positioned over the poster, never in the column');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a grid cell sized by the sizing does not overflow',
        (tester) async {
      final sizing = MovieCardSizing.fromWidth(960);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GridView.builder(
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisExtent: sizing.totalHeight,
                mainAxisSpacing: sizing.spacing,
                crossAxisSpacing: sizing.spacing,
              ),
              itemCount: 8,
              itemBuilder: (context, index) => MovieCard(
                movie: movie(
                  type: index.isEven ? 'series' : 'movie',
                  rating: '8.6',
                ),
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: 'a cell the sizing budgets must fit the card it holds');
      expect(find.byType(MovieCard), findsNWidgets(8),
          reason: 'the column count is unchanged');
    });
  });
}
