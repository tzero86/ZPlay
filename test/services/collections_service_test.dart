import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/collections/collections_service.dart';
import 'package:zplay/services/collections/curated_collection.dart';
import 'package:zplay/services/collections/curated_collections.dart';
import 'package:zplay/services/collections/curated_eras.dart';
import 'package:zplay/services/collections/curated_sagas.dart';
import 'package:zplay/services/collections/tmdb_ranked.dart';
import 'package:zplay/services/metadata/tmdb_service.dart';

final RegExp _imdbId = RegExp(r'^tt\d{7,}$');

const List<String> _sagaIds = [
  'saga_godfather',
  'saga_rocky',
  'saga_back_to_the_future',
  'saga_alien',
  'saga_die_hard',
  'saga_lethal_weapon',
  'saga_terminator',
  'saga_predator',
  'saga_jurassic_park',
  'saga_rambo',
  'saga_indiana_jones',
  'saga_marx_brothers',
];

const Map<String, int> _eraGenres = {
  'era_90s_action': 28,
  'era_90s_comedy': 35,
  'era_90s_horror': 27,
  'era_90s_scifi': 878,
  'era_90s_animation': 16,
  'era_90s_thriller': 53,
};

/// A ranked list that no bundled rail contains, so a swap is unmistakable.
List<CuratedItem> _ranked(String collectionId, {int count = 20}) {
  final slot = _eraGenres.keys.toList().indexOf(collectionId) + 1;
  return [
    for (var i = 0; i < count; i++)
      CuratedItem(
        imdbId: 'tt99${slot.toString().padLeft(2, '0')}'
            '${i.toString().padLeft(3, '0')}',
        title: 'Ranked $collectionId $i',
        year: 1990 + (i % 10),
      ),
  ];
}

/// Curated items carry no equality, so comparisons project to strings.
List<String> _signature(List<CuratedItem> items) => [
      for (final item in items) '${item.imdbId}|${item.title}|${item.year}',
    ];

String _cachePayload(List<CuratedItem> items, {Duration age = Duration.zero}) =>
    jsonEncode({
      'fetchedAt': DateTime.now().subtract(age).millisecondsSinceEpoch,
      'items': [
        for (final item in items)
          {'id': item.imdbId, 'title': item.title, 'year': item.year},
      ],
    });

Map<String, Object> _seededCache({
  List<String> ids = const [],
  Duration age = Duration.zero,
}) =>
    {
      for (final id in ids)
        'tmdb_ranked_$id': _cachePayload(_ranked(id), age: age),
    };

CuratedCollection _collection(String id) =>
    CollectionsService.collections.value.firstWhere((c) => c.id == id);

CuratedCollection _bundled(String id) =>
    curatedCollections.firstWhere((c) => c.id == id);

/// Curated data is bundled, so every rule below is a static invariant.
void main() {
  group('curatedCollections', () {
    test('ids are unique', () {
      final ids = curatedCollections.map((c) => c.id).toSet();
      expect(ids.length, curatedCollections.length);
    });

    test('sagas ship the verified packs', () {
      expect(curatedSagas.map((c) => c.id).toList(), _sagaIds);
      for (final collection in curatedSagas) {
        expect(collection.kind, CuratedKind.saga);
      }
    });

    test('every collection has at least two items', () {
      for (final collection in curatedCollections) {
        expect(
          collection.count,
          greaterThanOrEqualTo(2),
          reason: collection.id,
        );
      }
    });

    test('every item has an imdb id, a title and a plausible year', () {
      for (final collection in curatedCollections) {
        for (final item in collection.items) {
          expect(_imdbId.hasMatch(item.imdbId), isTrue, reason: item.imdbId);
          expect(item.title.trim(), isNotEmpty, reason: item.imdbId);
          expect(item.year, inInclusiveRange(1900, 2026), reason: item.imdbId);
        }
      }
    });

    test('item ids are unique within a collection', () {
      for (final collection in curatedCollections) {
        final ids = collection.items.map((i) => i.imdbId).toSet();
        expect(ids.length, collection.count, reason: collection.id);
      }
    });

    test('saga items run in release order', () {
      for (final collection in curatedSagas) {
        for (var i = 1; i < collection.items.length; i++) {
          expect(
            collection.items[i].year,
            greaterThanOrEqualTo(collection.items[i - 1].year),
            reason: collection.id,
          );
        }
      }
    });

    test('1990s rails hold only 1990s films', () {
      final nineties =
          curatedCollections.where((c) => c.id.startsWith('era_90s_'));
      expect(nineties, isNotEmpty);
      for (final collection in nineties) {
        for (final item in collection.items) {
          expect(item.year, inInclusiveRange(1990, 1999), reason: item.imdbId);
        }
      }
    });

    // The decade lanes are the one set whose whole point is a year range, so the
    // films have to agree with it. These assertions are what caught two picks
    // that came back from Cinemeta with a year outside their own lane.
    //
    // The century comes from the films, not the id: `era_00s` is the 2000s and
    // `era_70s` the 1970s, so reading 1900 off the id would be wrong for one of
    // them.
    test('every decade rail holds films from a single decade', () {
      final decades =
          curatedCollections.where((c) => RegExp(r'^era_\d0s$').hasMatch(c.id));
      expect(decades, isNotEmpty);
      for (final collection in decades) {
        final seen = collection.items
            .map((item) => item.year - (item.year % 10))
            .toSet();
        expect(
          seen.length,
          1,
          reason: '${collection.id} spans $seen: '
              '${collection.items.map((i) => '${i.title} ${i.year}').join(', ')}',
        );
      }
    });

    test('the decade subtitle states the range the items actually span', () {
      for (final collection
          in curatedCollections.where((c) => RegExp(r'^era_\d0s$').hasMatch(c.id))) {
        final start = collection.items.first.year;
        final decadeStart = start - (start % 10);
        expect(collection.subtitle, contains('$decadeStart'));
        expect(collection.subtitle, contains('${decadeStart + 9}'));
      }
    });

    // A decade rail and a 1990s genre rail can legitimately share a film, but
    // two decade lanes must not, since that is an authoring slip rather than a
    // deliberate cross-reference.
    test('no film appears in two decade lanes', () {
      final seen = <String, String>{};
      for (final collection
          in curatedCollections.where((c) => RegExp(r'^era_\d0s$').hasMatch(c.id))) {
        for (final item in collection.items) {
          expect(
            seen.containsKey(item.imdbId),
            isFalse,
            reason: '${item.title} is in both ${seen[item.imdbId]} and ${collection.id}',
          );
          seen[item.imdbId] = collection.id;
        }
      }
    });
  });

  group('CollectionsService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await CollectionsService.initialize();
    });

    test('shows curated rails on Home by default', () {
      expect(CollectionsService.showOnHome.value, isTrue);
    });

    test('persists the Home visibility toggle', () async {
      CollectionsService.showOnHome.value = false;
      await pumpEventQueue();
      expect(CollectionsService.showOnHome.value, isFalse);

      await CollectionsService.initialize();
      expect(CollectionsService.showOnHome.value, isFalse);
    });

    test('movieFor builds an offline cinemeta movie', () {
      final item = curatedCollections.first.items.first;
      final movie = CollectionsService.movieFor(item);

      expect(movie.id, item.imdbId);
      expect(movie.name, item.title);
      expect(movie.year, item.year.toString());
      expect(movie.type, 'movie');
      expect(movie.addonBaseUrl, 'https://v3-cinemeta.strem.io');
      expect(
        movie.poster,
        'https://images.metahub.space/poster/medium/${item.imdbId}/img',
      );
    });

    test('sectionFor builds a movie catalog section', () {
      final collection = curatedCollections.first;
      final section = CollectionsService.sectionFor(collection);

      expect(section.title, collection.title);
      expect(section.subtitle, collection.subtitle);
      expect(section.contentType, 'movie');
      expect(section.addonBaseUrl, 'https://v3-cinemeta.strem.io');
      expect(section.catalog.type, 'movie');
      expect(section.catalog.id, 'curated_${collection.id}');
      expect(section.catalog.name, collection.title);
      expect(section.movies.length, collection.count);
    });

    test('homeSections has one section per collection', () {
      final sections = CollectionsService.homeSections();

      expect(sections.length, curatedCollections.length);
      expect(
        sections.map((s) => s.title).toList(),
        curatedCollections.map((c) => c.title).toList(),
      );
    });
  });

  /// The ranked view is offline everywhere below: every rail carries a fresh
  /// cache, so [TmdbRanked.refreshAll] finds nothing to fetch.
  group('TMDb ranked rails', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(
        _seededCache(ids: _eraGenres.keys.toList()),
      );
      TmdbService.apiKey.value = '';
      await CollectionsService.initialize();
      await CollectionsService.applyRanked();
    });

    tearDown(() {
      TmdbService.apiKey.value = '';
      CollectionsService.collections.value =
          List<CuratedCollection>.unmodifiable(curatedCollections);
    });

    test('maps every 1990s rail to its TMDb genre', () {
      expect(TmdbRanked.genreByCollection, _eraGenres);
      expect(TmdbRanked.ids, curatedEras.map((c) => c.id));
      expect(
        TmdbRanked.genreByCollection.containsKey('saga_godfather'),
        isFalse,
      );
    });

    test('with no key the bundled picks stay, cache or not', () async {
      expect(TmdbService.isConfigured, isFalse);

      for (final id in _eraGenres.keys) {
        expect(_signature(_collection(id).items), _signature(_bundled(id).items),
            reason: id);
        expect(_collection(id).subtitle, _bundled(id).subtitle, reason: id);
      }
    });

    test('a configured key swaps the cached ranked lists in place', () async {
      TmdbService.apiKey.value = 'a-user-key';
      await CollectionsService.applyRanked();

      final ids = CollectionsService.collections.value.map((c) => c.id).toList();
      expect(ids, curatedCollections.map((c) => c.id).toList());

      for (final id in _eraGenres.keys) {
        final collection = _collection(id);
        expect(_signature(collection.items), _signature(_ranked(id)),
            reason: id);
        expect(collection.subtitle, '20 films, ranked by TMDb', reason: id);
        expect(collection.title, _bundled(id).title, reason: id);
        expect(collection.kind, CuratedKind.era, reason: id);
      }

      for (final saga in curatedSagas) {
        expect(_signature(_collection(saga.id).items), _signature(saga.items),
            reason: saga.id);
        expect(_collection(saga.id).subtitle, saga.subtitle, reason: saga.id);
      }

      final rankedAction = _ranked('era_90s_action');
      final section = CollectionsService.homeSections()
          .firstWhere((s) => s.title == 'The 90s: Action');
      expect(section.subtitle, '20 films, ranked by TMDb');
      expect(section.catalog.id, 'curated_era_90s_action');
      expect(section.movies.length, 20);
      expect(
        section.movies.map((m) => m.id).toList(),
        [for (final item in rankedAction) item.imdbId],
      );
      expect(
        section.movies.first.poster,
        'https://images.metahub.space/poster/medium/'
        '${rankedAction.first.imdbId}/img',
      );
    });

    test('clearing the key restores the bundled picks at once', () async {
      TmdbService.apiKey.value = 'a-user-key';
      await CollectionsService.applyRanked();
      expect(
        _signature(_collection('era_90s_action').items),
        _signature(_ranked('era_90s_action')),
      );

      TmdbService.apiKey.value = '';

      for (final id in _eraGenres.keys) {
        expect(_signature(_collection(id).items), _signature(_bundled(id).items),
            reason: id);
        expect(_collection(id).subtitle, _bundled(id).subtitle, reason: id);
      }
    });

    test('an unreadable cache entry reads as absent', () async {
      SharedPreferences.setMockInitialValues({
        'tmdb_ranked_era_90s_action': 'not json at all',
        'tmdb_ranked_era_90s_comedy': '{"fetchedAt": 1, "items": 3}',
        'tmdb_ranked_era_90s_horror': '[]',
        'tmdb_ranked_era_90s_scifi': '{"fetchedAt": "soon", "items": []}',
      });
      await CollectionsService.initialize();
      await CollectionsService.applyRanked();

      for (final id in _eraGenres.keys) {
        expect(await TmdbRanked.cachedItems(id), isNull, reason: id);
        expect(_signature(_collection(id).items), _signature(_bundled(id).items),
            reason: id);
      }
    });

    test('a cache older than a day is not used', () async {
      SharedPreferences.setMockInitialValues(
        _seededCache(ids: ['era_90s_scifi'], age: const Duration(hours: 25)),
      );
      await CollectionsService.initialize();
      await CollectionsService.applyRanked();

      expect(await TmdbRanked.cachedItems('era_90s_scifi'), isNull);
      expect(
        _signature(_collection('era_90s_scifi').items),
        _signature(_bundled('era_90s_scifi').items),
      );
    });

    test('a fresh cache is read back with its films', () async {
      final items = await TmdbRanked.cachedItems('era_90s_action');

      expect(items, isNotNull);
      expect(_signature(items!), _signature(_ranked('era_90s_action')));
    });
  });
}
