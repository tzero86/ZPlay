import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/metadata/art_quality.dart';

void main() {
  test('upgrades a metahub poster to the large still', () {
    expect(
      ArtQuality.upgrade(
        'https://images.metahub.space/poster/medium/tt0133093/img',
      ),
      'https://images.metahub.space/poster/large/tt0133093/img',
    );
  });

  test('upgrades a TMDb poster to w780', () {
    expect(
      ArtQuality.upgrade('https://image.tmdb.org/t/p/w500/abc.jpg'),
      'https://image.tmdb.org/t/p/w780/abc.jpg',
    );
  });

  test('upgrades a TMDb backdrop to w1280', () {
    expect(
      ArtQuality.upgrade(
        'https://image.tmdb.org/t/p/w780/backdrop.jpg',
        kind: ArtKind.backdrop,
      ),
      'https://image.tmdb.org/t/p/w1280/backdrop.jpg',
    );
  });

  test('leaves original, already-large and foreign URLs alone', () {
    for (final url in <String>[
      'https://image.tmdb.org/t/p/original/abc.jpg',
      'https://image.tmdb.org/t/p/w1280/abc.jpg',
      'https://images.metahub.space/poster/large/tt1/img',
      'https://example.test/poster/w500/abc.jpg',
    ]) {
      expect(ArtQuality.upgrade(url), url);
    }
    expect(ArtQuality.upgrade(null), isNull);
  });
}
