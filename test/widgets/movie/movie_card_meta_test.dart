/// The card's caption: one title line, then one facts line.
///
/// The facts line is a single string - `8.0 · 2024 · Movie` - so the terms the
/// catalog did not supply simply are not there. The separators used to be
/// laid-out dot Containers between loose Texts, which is the shape that spends
/// caption width on decoration and cannot ellipsise; these tests pin the
/// joined form, its degraded shapes, and that it survives a 320 dp surface.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/widgets/movie/movie_card.dart';

void main() {
  Widget host(Widget child, {double width = 200, double height = 400}) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, height: height, child: child),
          ),
        ),
      );

  Movie movie({
    String? year = '2024',
    String? rating = '8.0',
    String type = 'movie',
  }) => Movie(
    id: 'tt0000001',
    name: 'The Odyssey',
    year: year,
    type: type,
    addonBaseUrl: 'https://example.test',
    imdbRating: rating,
  );

  testWidgets('the caption reads the title, then rating · year · type', (
    tester,
  ) async {
    await tester.pumpWidget(host(MovieCard(movie: movie())));

    expect(find.text('The Odyssey'), findsOneWidget);
    expect(find.text('8.0 · 2024 · Movie'), findsOneWidget);
  });

  testWidgets('a card with no rating and no year drops both terms', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(MovieCard(movie: movie(year: null, rating: null))),
    );

    expect(find.text('Movie'), findsOneWidget);
    expect(
      find.textContaining('·'),
      findsNothing,
      reason: 'nothing to separate, so no separator',
    );
  });

  testWidgets('a series without a rating keeps its year and its word', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(MovieCard(movie: movie(rating: null, type: 'series'))),
    );

    expect(find.text('2024 · Series'), findsOneWidget);
    expect(
      find.textContaining('·'),
      findsOneWidget,
      reason: 'one facts line, one separator',
    );
  });

  testWidgets('the caption survives a 320 dp surface without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MovieCard(movie: movie())),
      ),
    );

    expect(
      find.text('8.0 · 2024 · Movie'),
      findsOneWidget,
      reason: 'the facts line is drawn, not clipped away',
    );
    expect(tester.takeException(), isNull);
  });
}
