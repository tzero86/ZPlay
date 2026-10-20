/// Guards the trailer key the catalog names.
///
/// The hover preview asks for a key and gives up quietly when there is none,
/// so a parser that reads nothing looks exactly like a preview that never
/// works. These tests pin the parse against the payload shapes a live addon
/// actually returns.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/models/movie/movie_detail.dart';
import 'package:zplay/models/movie/trailer_key.dart';

void main() {
  group('parseTrailerKey', () {
    test('reads a bare video id', () {
      expect(parseTrailerKey('HzGx48E64Xg'), 'HzGx48E64Xg');
      expect(parseTrailerKey('  HzGx48E64Xg  '), 'HzGx48E64Xg');
    });

    test('reads a video id out of a YouTube URL', () {
      expect(
        parseTrailerKey('https://www.youtube.com/watch?v=HzGx48E64Xg'),
        'HzGx48E64Xg',
      );
      expect(parseTrailerKey('https://youtu.be/HzGx48E64Xg'), 'HzGx48E64Xg');
      expect(
        parseTrailerKey(
          'https://www.youtube-nocookie.com/embed/HzGx48E64Xg?autoplay=1',
        ),
        'HzGx48E64Xg',
      );
    });

    test('refuses a playlist, which has a video id\'s exact shape', () {
      // A playlist id is the same length and the same alphabet as a video
      // id, and one in a hundred catalog entries is exactly that. Embedding
      // it plays a whole playlist instead of the trailer.
      expect(parseTrailerKey('PLl99DlL6b4'), isNull);
      expect(parseTrailerKey('UUl99DlL6b4'), isNull);
      expect(parseTrailerKey('RDl99DlL6b4'), isNull);
      expect(parseTrailerKey('OLl99DlL6b4'), isNull);
    });

    test('refuses a search, a channel, another host and a lookalike', () {
      expect(parseTrailerKey('ytsearch:Dune trailer'), isNull);
      expect(parseTrailerKey('https://vimeo.com/12345'), isNull);
      expect(
        parseTrailerKey('https://youtube.com.evil.test/watch?v=HzGx48E64Xg'),
        isNull,
      );
      expect(parseTrailerKey('short'), isNull);
      expect(parseTrailerKey(''), isNull);
      expect(parseTrailerKey(null), isNull);
      expect(parseTrailerKey(42), isNull);
    });
  });

  group('trailerKeyFromPayload', () {
    test('reads the trailerStreams row', () {
      final key = trailerKeyFromPayload({
        'trailerStreams': [
          {'title': 'Love of Your Life', 'ytId': 'HzGx48E64Xg'},
        ],
      });
      expect(key, 'HzGx48E64Xg');
    });

    test('reads the trailers row', () {
      final key = trailerKeyFromPayload({
        'trailers': [
          {'source': 'HzGx48E64Xg', 'type': 'Trailer'},
        ],
      });
      expect(key, 'HzGx48E64Xg');
    });

    test('prefers a trailer over any other video', () {
      final key = trailerKeyFromPayload({
        'trailers': [
          {'source': 'aaaaaaaaaaa', 'type': 'Teaser'},
          {'source': 'bbbbbbbbbbb', 'type': 'Trailer'},
        ],
      });
      expect(key, 'bbbbbbbbbbb');
    });

    test('skips a playlist and takes the next row', () {
      final key = trailerKeyFromPayload({
        'trailers': [
          {'source': 'PLl99DlL6b4', 'type': 'Trailer'},
          {'source': 'xyXX8LXiNJ4', 'type': 'Trailer'},
        ],
      });
      expect(key, 'xyXX8LXiNJ4');
    });

    test('answers null for a payload with no trailer at all', () {
      expect(trailerKeyFromPayload({'id': 'tt1', 'name': 'A'}), isNull);
      expect(trailerKeyFromPayload({'trailers': 'nonsense'}), isNull);
    });
  });

  group('the models read the payload', () {
    test('a catalog item carries its trailer', () {
      // The shape a live `catalog/movie/top` response has.
      final movie = Movie.fromJson({
        'id': 'tt34384900',
        'name': 'Love of Your Life',
        'type': 'movie',
        'trailers': [
          {'source': 'HzGx48E64Xg', 'type': 'Trailer'},
        ],
        'trailerStreams': [
          {'title': 'Love of Your Life', 'ytId': 'HzGx48E64Xg'},
        ],
      }, 'https://v3-cinemeta.strem.io');

      expect(movie.trailerKey, 'HzGx48E64Xg');
    });

    test('an info response carries its trailer', () {
      final detail = MovieDetail.fromJson({
        'id': 'tt0111161',
        'name': 'The Shawshank Redemption',
        'type': 'movie',
        'trailers': [
          {'source': 'PLl99DlL6b4', 'type': 'Trailer'},
          {'source': 'xyXX8LXiNJ4', 'type': 'Trailer'},
        ],
      });

      expect(detail.trailerKey, 'xyXX8LXiNJ4');
    });

    test('a title with no trailer stays null', () {
      final movie = Movie.fromJson({'id': 'tt1', 'name': 'Nothing'}, '');

      expect(movie.trailerKey, isNull);
    });
  });
}
