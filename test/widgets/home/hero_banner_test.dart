/// The hero's metadata line and its interaction with the slide's layout.
///
/// The line used to be a private `_HeroMetaLine` inside `hero_banner.dart`;
/// it is now the shared `HeroMetaLine` from `common/hero_meta_line.dart`, with
/// the genre cap moved to the call site. These tests pin the two things that
/// move could silently break: the terms and their interpuncts stay one `Text`
/// (so the band's height arithmetic holds), and the score stays the badge in
/// front of that line rather than a term inside it.
///
/// Every movie here carries no artwork at all - no backdrop, no poster, and an
/// id metahub cannot address - so no image request leaves the test.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/models/movie/movie_detail.dart';
import 'package:zplay/services/home/home_page_settings.dart';
import 'package:zplay/widgets/home/hero_banner.dart';

/// A catalog row the slide can paint nothing from: `film-1` is not `tt` plus
/// digits, so the metahub still is skipped rather than requested.
Movie _movie({String name = 'The Odyssey', String? year = '2024'}) => Movie(
  id: 'film-1',
  name: name,
  year: year,
  type: 'movie',
  addonBaseUrl: 'https://catalog.example',
);

MovieDetail _detail({
  List<String> genres = const ['Action', 'Adventure', 'Thriller', 'Drama'],
  String? year = '2024',
  String? runtime = '1h 47m',
  String? imdbRating = '8.0',
}) => MovieDetail(
  id: 'film-1',
  type: 'movie',
  name: 'The Odyssey',
  year: year,
  runtime: runtime,
  imdbRating: imdbRating,
  genres: genres,
);

/// Pumps one slide on a bounded surface.
///
/// Reduced motion is forced on: the slide's Ken Burns drift then never starts
/// (see `_HeroSlideState._onShellSlotChanged`), so there is no ticking
/// animation between the test's frames and no state left over at teardown.
Future<void> _pumpSlide(
  WidgetTester tester, {
  required Movie movie,
  MovieDetail? detail,
  double width = 800,
  double height = 400,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: height,
                child: HeroSlide(
                  movie: movie,
                  detail: detail,
                  screenWidth: width,
                  bandHeight: height,
                  actionsYielded: false,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() => HomePageSettings.heroStyle.value = HeroStyle.immersive);

  testWidgets('the metadata renders as one line', (tester) async {
    await _pumpSlide(tester, movie: _movie(), detail: _detail());

    final meta = tester.widget<Text>(find.textContaining('Action'));
    expect(
      meta.data,
      'Action · Adventure · Thriller · 2024 · 1h 47m',
      reason:
          'the four genres are capped at three at the call site, then the '
          'year and the runtime join the same string',
    );
    expect(
      tester.widget<Text>(find.textContaining('2024')),
      same(meta),
      reason:
          'the year is a term inside the genre Text, not a widget beside it',
    );
    expect(
      find.text('2024'),
      findsNothing,
      reason:
          'a bare year Text would be a second line, which the band cannot '
          'afford',
    );
  });

  testWidgets('the rating is drawn as the leading badge', (tester) async {
    await _pumpSlide(tester, movie: _movie(), detail: _detail());

    expect(find.text('8.0'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('8.0')).dx,
      lessThan(tester.getTopLeft(find.textContaining('Action')).dx),
      reason: 'the score leads the line; inside it, `8.0` would read as a year',
    );
  });

  testWidgets('without a rating the line carries no badge', (tester) async {
    await _pumpSlide(
      tester,
      movie: _movie(),
      detail: _detail(imdbRating: null),
    );

    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(find.text('8.0'), findsNothing);
    expect(find.textContaining('Action'), findsOneWidget);
  });

  testWidgets('blank terms are dropped rather than doubling interpuncts', (
    tester,
  ) async {
    await _pumpSlide(
      tester,
      movie: _movie(year: '   '),
      detail: _detail(
        genres: const ['', 'Action', '   ', 'Adventure'],
        year: '   ',
        runtime: null,
        imdbRating: null,
      ),
    );

    expect(find.text('Action · Adventure'), findsOneWidget);
    expect(find.textContaining(' ·  · '), findsNothing);
  });

  testWidgets('a title with no metadata at all draws no blank line', (
    tester,
  ) async {
    await _pumpSlide(
      tester,
      movie: _movie(year: null),
      detail: _detail(
        genres: const [],
        year: null,
        runtime: null,
        imdbRating: null,
      ),
    );

    expect(find.textContaining(' · '), findsNothing);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });

  testWidgets('a long title does not overflow a narrow band', (tester) async {
    const title =
        'The Extraordinarily Long and Winding Title of a Film Nobody Can Fit';
    await _pumpSlide(
      tester,
      movie: _movie(name: title),
      detail: _detail(),
      width: 320,
      height: 236,
    );

    expect(tester.takeException(), isNull);
    expect(find.text(title), findsOneWidget);
  });

  testWidgets('a movie with no wide artwork and no poster still builds', (
    tester,
  ) async {
    await _pumpSlide(tester, movie: _movie());

    expect(tester.takeException(), isNull);
    expect(
      find.byType(Image),
      findsNothing,
      reason: 'there is no image to build, and none is invented',
    );
    expect(find.text('The Odyssey'), findsOneWidget);
    expect(find.text('Film'), findsOneWidget);
  });
}
