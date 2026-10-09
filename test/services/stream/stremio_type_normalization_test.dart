/// The catalog and details layers hand the player `tv` for episodic content,
/// but the Stremio stream route only knows `movie` and `series`.
///
/// Before the normalization, a `tv`-typed title failed every addon's `types`
/// manifest check — so the addon was dropped in silence, with no request and no
/// error — and the ones that survived the check would have been asked for
/// `/stream/tv/...`, an endpoint that does not exist.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/stream/stream_service.dart';

void main() {
  group('StreamService addon type normalization', () {
    test('maps the internal tv alias onto the Stremio series route', () {
      expect(StreamService.stremioTypeForTesting('tv'), 'series');
      expect(StreamService.stremioTypeForTesting('show'), 'series');
    });

    test('leaves every real Stremio type untouched', () {
      expect(StreamService.stremioTypeForTesting('series'), 'series');
      expect(StreamService.stremioTypeForTesting('movie'), 'movie');
    });

    test('an addon declaring only series is queryable for a tv-typed title', () {
      // The manifest check is what used to discard the addon outright: the
      // addon says `series`, the title arrived as `tv`, and the two never met.
      final declared = <String>['series'];
      final type = StreamService.stremioTypeForTesting('tv');

      expect(declared.contains(type), isTrue,
          reason: 'a tv-typed title must still reach a series-only addon');
    });
  });
}
