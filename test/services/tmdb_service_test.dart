import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/metadata/tmdb_service.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TmdbService.client = MockClient((_) async => http.Response('', 500));
    TmdbService.buildTimeApiKeyOverrideForTesting = null;
    await TmdbService.initialize();
  });

  group('initialize', () {
    test('loads a stored credential', () async {
      SharedPreferences.setMockInitialValues({'tmdb_api_key': 'stored-key'});
      await TmdbService.initialize();
      expect(TmdbService.apiKey.value, 'stored-key');
      expect(TmdbService.isConfigured, isTrue);
    });

    test('starts unconfigured on a fresh install', () {
      expect(TmdbService.apiKey.value, '');
      expect(TmdbService.isConfigured, isFalse);
    });
  });

  group('validate', () {
    test('accepts a working key via the api_key parameter', () async {
      late Uri seen;
      TmdbService.client = MockClient((request) async {
        seen = request.url;
        return _json(const {});
      });

      expect(await TmdbService.validate('  good-key  '), TmdbKeyResult.ok);
      expect(seen.path, '/3/configuration');
      expect(seen.queryParameters['api_key'], 'good-key');
      expect(TmdbService.isConfigured, isFalse);
    });

    test('retries a rejected v4 token as a bearer header', () async {
      final requests = <http.Request>[];
      TmdbService.client = MockClient((request) async {
        requests.add(request);
        if (request.headers['Authorization'] == 'Bearer v4-token') {
          return _json(const {});
        }
        return _json(const {'status_code': 7}, 401);
      });

      expect(await TmdbService.validate('v4-token'), TmdbKeyResult.ok);
      expect(requests.length, 2);
      expect(requests.first.url.queryParameters['api_key'], 'v4-token');
      expect(requests.last.url.queryParameters.containsKey('api_key'), isFalse);
    });

    test('reports a credential rejected twice', () async {
      TmdbService.client = MockClient((_) async => http.Response('', 401));
      expect(await TmdbService.validate('nope'), TmdbKeyResult.rejected);
    });

    test('treats a 5xx as unreachable', () async {
      TmdbService.client = MockClient((_) async => http.Response('', 503));
      expect(await TmdbService.validate('anything'), TmdbKeyResult.unreachable);
    });

    test('treats a socket failure as unreachable', () async {
      TmdbService.client =
          MockClient((_) async => throw const SocketException('down'));
      expect(await TmdbService.validate('anything'), TmdbKeyResult.unreachable);
    });

    test('treats a timeout as unreachable', () async {
      TmdbService.client =
          MockClient((_) async => throw TimeoutException('slow'));
      expect(await TmdbService.validate('anything'), TmdbKeyResult.unreachable);
    });

    test('rejects an empty key without a request', () async {
      var called = false;
      TmdbService.client = MockClient((_) async {
        called = true;
        return _json(const {});
      });

      expect(await TmdbService.validate('   '), TmdbKeyResult.rejected);
      expect(called, isFalse);
    });
  });

  group('persistence', () {
    test('save trims and persists, clear wipes', () async {
      await TmdbService.save('  my-key  ');
      expect(TmdbService.apiKey.value, 'my-key');
      expect(TmdbService.isConfigured, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tmdb_api_key'), 'my-key');

      await TmdbService.clear();
      expect(TmdbService.apiKey.value, '');
      expect(TmdbService.isConfigured, isFalse);
      expect(prefs.getString('tmdb_api_key'), isNull);
    });

    test('assigning apiKey persists it', () async {
      TmdbService.apiKey.value = 'assigned-key';
      await pumpEventQueue();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tmdb_api_key'), 'assigned-key');
    });
  });

  group('discover', () {
    test('returns empty with no request when unconfigured', () async {
      var called = false;
      TmdbService.client = MockClient((_) async {
        called = true;
        return _json(const {});
      });

      final movies = await TmdbService.discover(
        fromYear: 1990,
        toYear: 1999,
        genreId: 28,
      );
      expect(movies, isEmpty);
      expect(called, isFalse);
    });

    test('ranks by votes, resolves imdb ids, skips missing, caches', () async {
      TmdbService.apiKey.value = 'user-key';
      late Uri discoverUri;
      final detailHits = <int>[];

      TmdbService.client = MockClient((request) async {
        final path = request.url.path;
        if (path == '/3/discover/movie') {
          discoverUri = request.url;
          return _json({
            'results': [
              {
                'id': 900001,
                'title': 'A',
                'release_date': '1994-05-01',
                'vote_average': 8.1,
                'vote_count': 9000,
              },
              {
                'id': 900002,
                'title': 'B',
                'release_date': '1995-06-01',
                'vote_average': 7.2,
                'vote_count': 8000,
              },
              {
                'id': 900003,
                'title': 'C',
                'release_date': null,
                'vote_average': 6.5,
                'vote_count': 7000,
              },
            ],
          });
        }
        final id = int.parse(path.split('/').last);
        detailHits.add(id);
        if (id == 900002) return _json(const {'imdb_id': null});
        return _json({'imdb_id': 'tt0000$id'});
      });

      final movies = await TmdbService.discover(
        fromYear: 1990,
        toYear: 1999,
        genreId: 28,
        minVotes: 1000,
      );

      expect(discoverUri.path, '/3/discover/movie');
      expect(discoverUri.queryParameters['api_key'], 'user-key');
      expect(discoverUri.queryParameters['with_genres'], '28');
      expect(discoverUri.queryParameters['sort_by'], 'vote_count.desc');
      expect(discoverUri.queryParameters['vote_count.gte'], '1000');
      expect(discoverUri.queryParameters['include_adult'], 'false');
      expect(discoverUri.queryParameters['language'], 'en-US');
      expect(discoverUri.queryParameters['page'], '1');
      expect(discoverUri.queryParameters['primary_release_date.gte'], '1990-01-01');
      expect(discoverUri.queryParameters['primary_release_date.lte'], '1999-12-31');

      expect(movies.map((m) => m.imdbId).toList(), ['tt0000900001', 'tt0000900003']);
      expect(movies.first.title, 'A');
      expect(movies.first.year, 1994);
      expect(movies.first.voteAverage, 8.1);
      expect(movies.first.voteCount, 9000);
      expect(movies.last.year, 0);
      expect(detailHits, unorderedEquals([900001, 900002, 900003]));

      detailHits.clear();
      final again = await TmdbService.discover(
        fromYear: 1990,
        toYear: 1999,
        genreId: 28,
      );
      expect(again.map((m) => m.imdbId).toList(), ['tt0000900001', 'tt0000900003']);
      expect(detailHits, isEmpty);
    });

    test('honours limit after skipping unresolved films', () async {
      TmdbService.apiKey.value = 'user-key';
      TmdbService.client = MockClient((request) async {
        if (request.url.path == '/3/discover/movie') {
          return _json({
            'results': [
              for (var i = 0; i < 4; i++)
                {
                  'id': 910000 + i,
                  'title': 'T$i',
                  'release_date': '1992-01-01',
                  'vote_average': 5.0,
                  'vote_count': 100 - i,
                },
            ],
          });
        }
        final id = int.parse(request.url.path.split('/').last);
        return _json({'imdb_id': 'tt0000$id'});
      });

      final movies = await TmdbService.discover(
        fromYear: 1990,
        toYear: 1999,
        genreId: 35,
        limit: 2,
      );
      expect(movies.map((m) => m.imdbId).toList(),
          ['tt0000910000', 'tt0000910001']);
    });

    test('fails soft when the API rejects the credential', () async {
      TmdbService.apiKey.value = 'bad-key';
      TmdbService.client = MockClient((_) async => http.Response('', 401));
      final movies = await TmdbService.discover(
        fromYear: 1990,
        toYear: 1999,
        genreId: 27,
      );
      expect(movies, isEmpty);
    });
  });

  group('scraperKey', () {
    test('resolves empty and reports no key with nothing configured', () {
      expect(TmdbService.apiKey.value, '');
      expect(TmdbService.scraperKey, isEmpty);
      expect(TmdbService.hasScraperKey, isFalse);
    });

    test('a build-time key makes a keyed request possible', () {
      TmdbService.buildTimeApiKeyOverrideForTesting = 'from-build';
      expect(TmdbService.scraperKey, 'from-build');
      expect(TmdbService.hasScraperKey, isTrue);
    });

    test('prefers the user credential over the build-time one', () {
      TmdbService.buildTimeApiKeyOverrideForTesting = 'from-build';

      TmdbService.apiKey.value = 'mine';
      expect(TmdbService.scraperKey, 'mine');
      expect(TmdbService.hasScraperKey, isTrue);
    });

    test('a blank user value falls through instead of blanking the key', () async {
      TmdbService.buildTimeApiKeyOverrideForTesting = 'from-build';

      await TmdbService.save('   ');
      expect(TmdbService.scraperKey, 'from-build');
      expect(TmdbService.hasScraperKey, isTrue);
    });
  });
}
