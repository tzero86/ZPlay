import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/models/movie/movie.dart';

/// The status tags on cards ("New season", "New episode", "New release") are
/// read from the catalog's own dates. They have to stay sparse - a tag on
/// every card is noise - so the windows are pinned here.
void main() {
  final now = DateTime.utc(2026, 11, 14, 12);

  Movie series(List<Map<String, Object?>> videos) => Movie.fromJson({
    'id': 'tt1',
    'name': 'A Show',
    'type': 'series',
    'videos': videos,
  }, 'https://addon.example.com');

  Map<String, Object?> ep(int season, int episode, DateTime at) => {
    'season': season,
    'episode': episode,
    'released': at.toIso8601String(),
  };

  test('a season premiere in the last three weeks is a new season', () {
    final show = series([
      ep(1, 8, now.subtract(const Duration(days: 300))),
      ep(2, 1, now.subtract(const Duration(days: 10))),
    ]);
    expect(CardFreshness.of(show, now: now), CardFreshness.newSeason);
  });

  test('an ordinary episode counts only within three days', () {
    final fresh = series([ep(2, 4, now.subtract(const Duration(days: 2)))]);
    final stale = series([ep(2, 4, now.subtract(const Duration(days: 6)))]);
    expect(CardFreshness.of(fresh, now: now), CardFreshness.newEpisode);
    expect(CardFreshness.of(stale, now: now), isNull);
  });

  test('unaired episodes and specials are ignored', () {
    final show = series([
      ep(2, 3, now.subtract(const Duration(days: 40))),
      ep(0, 1, now.subtract(const Duration(days: 1))),
      ep(3, 1, DateTime.now().add(const Duration(days: 30))),
    ]);
    expect(CardFreshness.of(show, now: now), isNull);
  });

  test('a film released in the last month is a new release', () {
    Movie film(DateTime released) => Movie.fromJson({
      'id': 'tt2',
      'name': 'A Film',
      'type': 'movie',
      'released': released.toIso8601String(),
    }, 'https://addon.example.com');

    expect(
      CardFreshness.of(film(now.subtract(const Duration(days: 12))), now: now),
      CardFreshness.newRelease,
    );
    expect(
      CardFreshness.of(film(now.subtract(const Duration(days: 60))), now: now),
      isNull,
    );
    expect(
      CardFreshness.of(film(now.add(const Duration(days: 5))), now: now),
      isNull,
      reason: 'a film that is not out yet is not new',
    );
  });

  test('a title without dates carries no tag', () {
    final bare = Movie(id: 'x', name: 'X', type: 'movie', addonBaseUrl: '');
    expect(CardFreshness.of(bare, now: now), isNull);
  });
}
