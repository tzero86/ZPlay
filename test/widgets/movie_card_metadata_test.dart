import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/services/theme/design_tokens.dart';
import 'package:zplay/widgets/movie/movie_card.dart';

void main() {
  testWidgets('a poster card carries year, type and rating on its caption', (
    tester,
  ) async {
    final movie = Movie(
      id: 'tt0133093',
      name: 'The Matrix',
      year: '1999',
      type: 'movie',
      addonBaseUrl: 'https://example.test',
      imdbRating: '8.7',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 200, child: MovieCard(movie: movie)),
          ),
        ),
      ),
    );

    expect(find.text('1999'), findsOneWidget);
    expect(find.text('Movie'), findsOneWidget);
    expect(find.text('★ 8.7'), findsOneWidget);

    final clip = tester.widget<ClipRRect>(
      find
          .descendant(
            of: find.byType(MovieCard),
            matching: find.byType(ClipRRect),
          )
          .first,
    );
    expect(clip.borderRadius, ZplayRadius.cardAll);
  });
}
