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

  test('a hero backdrop asks for the largest size the CDN has', () {
    expect(
      ArtQuality.upgrade(
        'https://image.tmdb.org/t/p/w780/backdrop.jpg',
        kind: ArtKind.heroBackdrop,
      ),
      'https://image.tmdb.org/t/p/original/backdrop.jpg',
    );
    expect(
      ArtQuality.upgrade(
        'https://images.metahub.space/background/medium/tt1/img',
        kind: ArtKind.heroBackdrop,
      ),
      'https://images.metahub.space/background/large/tt1/img',
    );
  });

  test('a card thumbnail asks for a thumbnail-sized still, up or down', () {
    expect(
      ArtQuality.upgrade(
        'https://images.metahub.space/background/large/tt1/img',
        kind: ArtKind.thumbnail,
      ),
      'https://images.metahub.space/background/medium/tt1/img',
      reason: 'the 3840 px still is ten times what a thumbnail can show',
    );
    expect(
      ArtQuality.upgrade(
        'https://image.tmdb.org/t/p/w300/backdrop.jpg',
        kind: ArtKind.thumbnail,
      ),
      'https://image.tmdb.org/t/p/w780/backdrop.jpg',
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
