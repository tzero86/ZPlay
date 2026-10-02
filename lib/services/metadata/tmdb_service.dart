import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env_service.dart';

enum TmdbKeyResult { ok, rejected, unreachable }

class TmdbMovie {
  const TmdbMovie({
    required this.imdbId,
    required this.title,
    required this.year,
    required this.voteAverage,
    required this.voteCount,
  });

  final String imdbId;
  final String title;
  final int year;
  final double voteAverage;
  final int voteCount;
}

abstract final class TmdbService {
  static const String _keyApiKey = 'tmdb_api_key';
  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const Duration _timeout = Duration(seconds: 10);

  static SharedPreferences? _prefs;
  static bool _hydrating = false;

  static final Map<int, String?> _imdbIdCache = {};

  @visibleForTesting
  static http.Client client = http.Client();

  /// The credential exactly as pasted, empty when unconfigured. Assigning persists it.
  static final ValueNotifier<String> apiKey = _PersistedApiKey('');

  static bool get isConfigured => apiKey.value.trim().isNotEmpty;

  /// Credential the legacy scraper lookups may use: the user's key when set,
  /// otherwise a build-time key. Empty when neither exists.
  ///
  /// The upstream fork's inherited key is gone, so this resolves empty on a
  /// fresh install. A caller must check [hasScraperKey] before putting the
  /// value in a URL: `?api_key=` with nothing after it is a malformed request
  /// to TMDb, not a graceful degrade.
  static String get scraperKey {
    final user = apiKey.value.trim();
    if (user.isNotEmpty) return user;
    return buildTimeApiKeyOverrideForTesting ?? EnvService.tmdbApiKey;
  }

  /// Stands in for the compile-time define in tests, which cannot set one.
  @visibleForTesting
  static String? buildTimeApiKeyOverrideForTesting;

  /// Whether [scraperKey] can be sent. False means the caller resolves nothing
  /// rather than issuing a keyed request with an empty credential.
  static bool get hasScraperKey => scraperKey.isNotEmpty;

  /// The read currently in flight, so a caller that arrives while one is
  /// running waits on it instead of starting a second one. Two interleaved
  /// reads would fight over [_hydrating], and the one that finished first
  /// would leave the other's assignment persisting the key back to storage.
  static Future<void>? _reading;

  static Future<void> initialize() =>
      _reading ??= _read().whenComplete(() => _reading = null);

  static Future<void> _read() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final stored = _prefs?.getString(_keyApiKey) ?? '';
      _hydrating = true;
      apiKey.value = stored;
      _hydrating = false;
    } catch (e) {
      debugPrint('[TmdbService] Error initializing: $e');
    }
  }

  /// Re-reads the stored key into [apiKey].
  ///
  /// [initialize] reads it once, at startup. A profile import writes the store
  /// underneath a running app, and without this the notifier keeps serving the
  /// pre-import value: Settings reports the key the export carried as "Not
  /// set", and the ranked rails stay on the offline picks until a restart.
  static Future<void> reload() async {
    // Let the startup read land first, so the value the import just wrote is
    // the last one applied.
    await _reading;
    await initialize();
  }

  /// Does a credential work? Never writes it anywhere.
  static Future<TmdbKeyResult> validate(String raw) async {
    final key = raw.trim();
    if (key.isEmpty) return TmdbKeyResult.rejected;
    final outcome = await _request(key, '/configuration', const {});
    return outcome.status;
  }

  static Future<void> save(String raw) async {
    final key = raw.trim();
    try {
      await _prefs?.setString(_keyApiKey, key);
    } catch (e) {
      debugPrint('[TmdbService] Error saving TMDb key: $e');
    }
    _hydrating = true;
    apiKey.value = key;
    _hydrating = false;
  }

  static Future<void> clear() async {
    try {
      await _prefs?.remove(_keyApiKey);
    } catch (e) {
      debugPrint('[TmdbService] Error clearing TMDb key: $e');
    }
    _hydrating = true;
    apiKey.value = '';
    _hydrating = false;
  }

  /// A keyed GET against the v3 API, with [path] relative to the base URL.
  ///
  /// Null when no credential is set, when TMDb rejects it, or when the read
  /// fails, so a caller never has to branch on the credential itself.
  static Future<Map<String, dynamic>?> getJson(
    String path, [
    Map<String, String> params = const {},
  ]) async {
    final key = apiKey.value.trim();
    if (key.isEmpty) return null;
    final outcome = await _request(key, path, params);
    return outcome.status == TmdbKeyResult.ok ? outcome.body : null;
  }

  /// Top `limit` films of one genre in one decade, most voted first, imdb ids
  /// resolved. Uses the user's credential only: with no key set it returns an
  /// empty list and makes no request, so the rails never spend the built-in
  /// key's quota.
  static Future<List<TmdbMovie>> discover({
    required int fromYear,
    required int toYear,
    required int genreId,
    int limit = 20,
    double minVotes = 500,
    bool includeAdult = false,
  }) async {
    final key = apiKey.value.trim();
    if (key.isEmpty) return const [];

    final outcome = await _request(key, '/discover/movie', {
      'with_genres': '$genreId',
      'primary_release_date.gte': '$fromYear-01-01',
      'primary_release_date.lte': '$toYear-12-31',
      'sort_by': 'vote_count.desc',
      'vote_count.gte': '${minVotes.round()}',
      'include_adult': '$includeAdult',
      'language': 'en-US',
      'page': '1',
    });
    final body = outcome.body;
    if (outcome.status != TmdbKeyResult.ok || body == null) return const [];

    final results = body['results'];
    if (results is! List) return const [];

    final candidates = <_Candidate>[];
    for (final entry in results) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is! int) continue;
      candidates.add(
        _Candidate(
          tmdbId: id,
          title: entry['title']?.toString() ?? '',
          year: _yearOf(entry['release_date']?.toString()),
          voteAverage: (entry['vote_average'] as num?)?.toDouble() ?? 0,
          voteCount: (entry['vote_count'] as num?)?.toInt() ?? 0,
        ),
      );
    }

    final imdbIds = await Future.wait([
      for (final candidate in candidates) _imdbIdFor(key, candidate.tmdbId),
    ]);

    final movies = <TmdbMovie>[];
    for (var i = 0; i < candidates.length && movies.length < limit; i++) {
      final imdbId = imdbIds[i];
      if (imdbId == null || imdbId.isEmpty) continue;
      final candidate = candidates[i];
      movies.add(
        TmdbMovie(
          imdbId: imdbId,
          title: candidate.title,
          year: candidate.year,
          voteAverage: candidate.voteAverage,
          voteCount: candidate.voteCount,
        ),
      );
    }
    return movies;
  }

  static Future<String?> _imdbIdFor(String key, int tmdbId) {
    if (_imdbIdCache.containsKey(tmdbId)) {
      return Future.value(_imdbIdCache[tmdbId]);
    }
    return _resolveImdbId(key, tmdbId);
  }

  static Future<String?> _resolveImdbId(String key, int tmdbId) async {
    final outcome = await _request(key, '/movie/$tmdbId', const {});
    if (outcome.status != TmdbKeyResult.ok || outcome.body == null) return null;
    final raw = outcome.body!['imdb_id'];
    final imdbId = (raw is String && raw.isNotEmpty) ? raw : null;
    _imdbIdCache[tmdbId] = imdbId;
    return imdbId;
  }

  static Future<_HttpOutcome> _request(
    String key,
    String path,
    Map<String, String> params,
  ) async {
    final base = Uri.parse('$_baseUrl$path');

    var response = await _get(
      base.replace(queryParameters: {...params, 'api_key': key}),
    );
    if (response == null) return const _HttpOutcome.unreachable();

    if (response.statusCode == 401) {
      // A v4 read token is rejected when sent as `api_key`, so retry it as a
      // bearer header before calling the credential bad.
      response = await _get(base.replace(queryParameters: params), bearer: key);
      if (response == null) return const _HttpOutcome.unreachable();
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      return const _HttpOutcome.rejected();
    }
    if (response.statusCode != 200) return const _HttpOutcome.unreachable();

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return _HttpOutcome.ok(decoded);
    } catch (_) {}
    return const _HttpOutcome.unreachable();
  }

  static Future<http.Response?> _get(Uri uri, {String? bearer}) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (bearer != null) headers['Authorization'] = 'Bearer $bearer';
    try {
      return await client.get(uri, headers: headers).timeout(_timeout);
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static int _yearOf(String? date) {
    if (date == null || date.isEmpty) return 0;
    return int.tryParse(date.split('-').first) ?? 0;
  }
}

class _PersistedApiKey extends ValueNotifier<String> {
  _PersistedApiKey(super.initialValue);

  @override
  set value(String next) {
    super.value = next;
    if (!TmdbService._hydrating) unawaited(_persist(next));
  }

  Future<void> _persist(String next) async {
    try {
      await TmdbService._prefs?.setString(TmdbService._keyApiKey, next);
    } catch (e) {
      debugPrint('[TmdbService] Error saving TMDb key: $e');
    }
  }
}

class _Candidate {
  const _Candidate({
    required this.tmdbId,
    required this.title,
    required this.year,
    required this.voteAverage,
    required this.voteCount,
  });

  final int tmdbId;
  final String title;
  final int year;
  final double voteAverage;
  final int voteCount;
}

class _HttpOutcome {
  const _HttpOutcome.ok(this.body) : status = TmdbKeyResult.ok;
  const _HttpOutcome.rejected()
      : body = null,
        status = TmdbKeyResult.rejected;
  const _HttpOutcome.unreachable()
      : body = null,
        status = TmdbKeyResult.unreachable;

  final TmdbKeyResult status;
  final Map<String, dynamic>? body;
}
