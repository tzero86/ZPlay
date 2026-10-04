/// [ArtQuality.upgrade] rewrites a metahub still's size segment, and only that.
///
/// The measurements behind the rule are in the class's own doc comment; what is
/// pinned here is the rewrite's exact shape, because the two ways to get it
/// wrong both produce a *plausible* URL: a regex that is not anchored also
/// rewrites the domain when it appears in someone else's query string, and one
/// that matches too little leaves every poster at 500 px - which is the bug
/// this exists to fix, so a no-op would look like success.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/metadata/art_quality.dart';
import 'package:zplay/services/metadata/metahub_art.dart';

void main() {
  group('ArtQuality.upgrade', () {
    test('raises every metahub kind from small or medium to large', () {
      const base = 'https://images.metahub.space';
      expect(ArtQuality.upgrade('$base/poster/medium/tt0468569/img'),
          '$base/poster/large/tt0468569/img');
      expect(ArtQuality.upgrade('$base/poster/small/tt0468569/img'),
          '$base/poster/large/tt0468569/img');
      expect(ArtQuality.upgrade('$base/background/medium/tt0468569/img'),
          '$base/background/large/tt0468569/img');
      expect(ArtQuality.upgrade('$base/logo/small/tt0468569/img'),
          '$base/logo/large/tt0468569/img');
    });

    test('leaves a still that is already large alone', () {
      const url = 'https://images.metahub.space/poster/large/tt0468569/img';
      expect(ArtQuality.upgrade(url), url);
    });

    test('leaves another host alone', () {
      const tmdb = 'https://image.tmdb.org/t/p/w500/probe.jpg';
      const own = 'https://cdn.example/own.jpg';
      const simkl = 'https://simkl.in/posters/12345_m.jpg';
      expect(ArtQuality.upgrade(tmdb), tmdb);
      expect(ArtQuality.upgrade(own), own);
      expect(ArtQuality.upgrade(simkl), simkl);
    });

    test('the match is anchored, so the domain in a query string is not a hit',
        () {
      // An unanchored pattern would rewrite this into a URL on the metahub
      // host, which is a request for someone else's picture - or a 404.
      const trapped =
          'https://cdn.example/redirect?next=https://images.metahub.space/poster/medium/tt0468569/img';
      expect(ArtQuality.upgrade(trapped), trapped);
    });

    test('null and empty pass through, so a nullable poster needs no guard',
        () {
      expect(ArtQuality.upgrade(null), isNull);
      expect(ArtQuality.upgrade(''), '');
    });
  });

  group('MetahubArt sizes', () {
    test('posterUrl defaults to the large still a drawn card needs', () {
      expect(MetahubArt.posterUrl('tt0468569'),
          'https://images.metahub.space/poster/large/tt0468569/img');
    });

    test('posterUrl stays caller-sized, so a thumbnail can still ask small', () {
      expect(MetahubArt.posterUrl('tt0468569', size: 'medium'),
          'https://images.metahub.space/poster/medium/tt0468569/img');
    });
  });
}
