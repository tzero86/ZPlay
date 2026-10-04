/// Blank-artwork regression: a catalog item with no poster of its own must
/// still draw one from metahub's keyless image host, keyed on the IMDb id.
///
/// Both edges are load-bearing and both are asserted here: the movie's own
/// poster always wins over the fallback, and an id metahub cannot serve must
/// land on [MissingPoster] without a request the app already knows will 404.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/services/metadata/metahub_art.dart';
import 'package:zplay/widgets/common/poster_skeleton.dart';
import 'package:zplay/widgets/movie/movie_card.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 176, height: 340, child: child),
          ),
        ),
      );

  Movie movie({required String id, String? poster, String? backdrop}) => Movie(
        id: id,
        name: 'Probe Title',
        poster: poster,
        backdrop: backdrop,
        year: '2024',
        type: 'movie',
        addonBaseUrl: 'test',
      );

  group('MetahubArt', () {
    test('builds the measured keyless URLs', () {
      expect(MetahubArt.backdropUrl('tt0468569'),
          'https://images.metahub.space/background/large/tt0468569/img');
      expect(MetahubArt.logoUrl('tt0468569'),
          'https://images.metahub.space/logo/large/tt0468569/img');
      expect(MetahubArt.posterUrl('tt0468569'),
          'https://images.metahub.space/poster/medium/tt0468569/img');
    });

    test('size is caller-chosen and every input yields a URL', () {
      expect(MetahubArt.posterUrl('tt0468569', size: 'large'),
          'https://images.metahub.space/poster/large/tt0468569/img');
      expect(MetahubArt.backdropUrl('whatever'), contains('whatever'));
    });

    test('isUsableId is exactly tt + digits', () {
      expect(MetahubArt.isUsableId('tt0468569'), isTrue);
      for (final id in [
        '',
        'tt',
        'tt046856a',
        'tt 0468569',
        'tt-468569',
        'probe',
        'TT0468569',
        '0468569',
      ]) {
        expect(MetahubArt.isUsableId(id), isFalse, reason: 'id "$id"');
      }
    });
  });

  group('MovieCard poster fallback', () {
    testWidgets('a movie with no poster gets the metahub poster',
        (tester) async {
      await tester.pumpWidget(
        host(MovieCard(movie: movie(id: 'tt0468569'), onTap: () {})),
      );
      await tester.pump();

      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.imageUrl,
          'https://images.metahub.space/poster/medium/tt0468569/img');
    });

    testWidgets('an empty poster string counts as no poster', (tester) async {
      await tester.pumpWidget(
        host(MovieCard(movie: movie(id: 'tt0468569', poster: ''), onTap: () {})),
      );
      await tester.pump();

      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.imageUrl,
          'https://images.metahub.space/poster/medium/tt0468569/img');
    });

    testWidgets('the movie\'s own poster always wins over the fallback',
        (tester) async {
      await tester.pumpWidget(
        host(MovieCard(
          movie: movie(id: 'tt0468569', poster: 'https://cdn.example/own.jpg'),
          onTap: () {},
        )),
      );
      await tester.pump();

      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.imageUrl, 'https://cdn.example/own.jpg');
    });

    testWidgets('an unusable id lands on MissingPoster, no request at all',
        (tester) async {
      await tester.pumpWidget(
        host(MovieCard(movie: movie(id: 'probe'), onTap: () {})),
      );
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byType(MissingPoster), findsOneWidget);
    });
  });

  group('MovieCard landscape art', () {
    // A 2:3 poster cropped into a 16:9 tile keeps only a third of its height,
    // which is what every rail of landscape thumbnails looked like when the
    // only fallback was the poster. A landscape tile wants a real wide still.
    testWidgets('a landscape tile with no backdrop gets the metahub wide still',
        (tester) async {
      await tester.pumpWidget(
        host(MovieCard(
          movie: movie(id: 'tt0468569', poster: 'https://cdn.example/p.jpg'),
          artwork: CardArtwork.landscape,
          onTap: () {},
        )),
      );
      await tester.pump();

      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(
        image.imageUrl,
        'https://images.metahub.space/background/large/tt0468569/img',
        reason: 'the wide still, not the poster squeezed into 16:9',
      );
    });

    testWidgets('the catalog backdrop still wins over the fallback',
        (tester) async {
      await tester.pumpWidget(
        host(MovieCard(
          movie: movie(
            id: 'tt0468569',
            poster: 'https://cdn.example/p.jpg',
            backdrop: 'https://cdn.example/wide.jpg',
          ),
          artwork: CardArtwork.landscape,
          onTap: () {},
        )),
      );
      await tester.pump();

      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.imageUrl, 'https://cdn.example/wide.jpg');
    });

    testWidgets('an unusable id falls back to the poster, never metahub',
        (tester) async {
      await tester.pumpWidget(
        host(MovieCard(
          movie: movie(id: 'probe', poster: 'https://cdn.example/p.jpg'),
          artwork: CardArtwork.landscape,
          onTap: () {},
        )),
      );
      await tester.pump();

      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.imageUrl, 'https://cdn.example/p.jpg');
    });

    testWidgets('a poster card is untouched by the wide-still fallback',
        (tester) async {
      // The 2:3 path is what every non-Home caller already renders, so the new
      // fallback must not reach it.
      await tester.pumpWidget(
        host(MovieCard(
          movie: movie(id: 'tt0468569', poster: 'https://cdn.example/p.jpg'),
          onTap: () {},
        )),
      );
      await tester.pump();

      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.imageUrl, 'https://cdn.example/p.jpg');
    });
  });
}
