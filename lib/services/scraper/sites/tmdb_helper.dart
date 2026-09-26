import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/env_service.dart';
import '../../metadata/tmdb_service.dart';

class TmdbHelper {
  static const _tmdbDirect = 'https://api.themoviedb.org/3';

  /// Optional keyless TMDb fallback host. There is no default: the upstream
  /// developer's proxy stays off unless `TMDB_PROXY_BASE` names a host, so a
  /// keyless install resolves metadata through a TMDb key or not at all.
  static String? get _tmdbProxy {
    final value = EnvService.tmdbProxyBase;
    return value.isEmpty ? null : value;
  }

  /// Whether a keyed TMDb call is available. Without one the only routes left
  /// are the keyless proxy and a local guess, so we resolve to a negative id
  /// rather than sending `?api_key=` with nothing after it.
  static bool get _hasKey => TmdbService.hasScraperKey;

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Accept': 'application/json',
  };

  static final Map<String, int> _cache = {};

  static String _cleanString(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static Future<int?> resolveTmdbId({
    String? imdbId,
    required String title,
    required String type,
    int? year,
  }) async {
    final cacheKey = '${imdbId ?? ""}|$title|$type|${year ?? ""}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    String cleanId = (imdbId ?? '').trim();
    cleanId = cleanId.replaceAll(RegExp(r'^(tmdb|movie|tv|imdb):', caseSensitive: false), '');
    if (cleanId.contains(':')) {
      cleanId = cleanId.split(':')[0];
    }

    final isTv = (type == 'tv' || type == 'series');
    final endpoint = isTv ? 'tv' : 'movie';

    if (cleanId.isNotEmpty) {
      // 1. Direct numeric ID
      if (RegExp(r'^\d+$').hasMatch(cleanId)) {
        final id = int.parse(cleanId);
        _cache[cacheKey] = id;
        return id;
      }

      // 2. Query TMDB Find API for tt IMDB IDs
      if (cleanId.startsWith('tt') && _hasKey) {
        try {
          final uri = Uri.parse('$_tmdbDirect/find/$cleanId?api_key=${TmdbService.scraperKey}&external_source=imdb_id');
          final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 7));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final results = isTv ? (data['tv_results'] as List?) : (data['movie_results'] as List?);
            if (results != null && results.isNotEmpty) {
              final id = results.first['id'] as int?;
              if (id != null) {
                _cache[cacheKey] = id;
                return id;
              }
            }
          }
        } catch (_) {}

        // Backup find query via the keyless proxy, when one is configured
        final proxy = _tmdbProxy;
        if (proxy != null) {
          try {
            final uri = Uri.parse('$proxy/find/$cleanId?external_source=imdb_id');
            final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
            if (res.statusCode == 200) {
              final data = jsonDecode(res.body);
              final results = isTv ? (data['tv_results'] as List?) : (data['movie_results'] as List?);
              if (results != null && results.isNotEmpty) {
                final id = results.first['id'] as int?;
                if (id != null) {
                  _cache[cacheKey] = id;
                  return id;
                }
              }
            }
          } catch (_) {}
        }
      }
    }

    // 3. Search by title, type, and year matching
    if (title.isNotEmpty) {
      final targetCleanTitle = _cleanString(title);

      // Search via official TMDB API with the user's key. Without a key the
      // proxy below is the only remaining route, so the keyed call is skipped
      // rather than sent with an empty `api_key`.
      if (_hasKey) {
        try {
          final uri = Uri.parse('$_tmdbDirect/search/$endpoint?api_key=${TmdbService.scraperKey}&query=${Uri.encodeComponent(title)}');
          final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 7));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final results = data['results'] as List?;
            if (results != null && results.isNotEmpty) {
              int? bestMatchId;

              for (final item in results) {
                final itemTitle = (item['title'] ?? item['name'] ?? item['original_title'] ?? item['original_name'] ?? '').toString();
                final itemCleanTitle = _cleanString(itemTitle);
                final dateStr = (item['release_date'] ?? item['first_air_date'] ?? '').toString();
                final itemYear = dateStr.length >= 4 ? int.tryParse(dateStr.substring(0, 4)) : null;

                final titleMatch = itemCleanTitle == targetCleanTitle ||
                    itemCleanTitle.contains(targetCleanTitle) ||
                    targetCleanTitle.contains(itemCleanTitle);

                if (titleMatch) {
                  if (year != null && itemYear != null) {
                    if (itemYear == year || (itemYear - year).abs() <= 1) {
                      final id = item['id'] as int?;
                      if (id != null) {
                        _cache[cacheKey] = id;
                        return id;
                      }
                    }
                  } else {
                    bestMatchId ??= item['id'] as int?;
                  }
                }
              }

              if (bestMatchId != null) {
                _cache[cacheKey] = bestMatchId;
                return bestMatchId;
              }

              // Fallback to first result if available
              final fallbackId = results.first['id'] as int?;
              if (fallbackId != null) {
                _cache[cacheKey] = fallbackId;
                return fallbackId;
              }
            }
          }
        } catch (_) {}
      }

      // Backup search via the keyless proxy, when one is configured
      final proxy = _tmdbProxy;
      if (proxy != null) {
        try {
          final uri = Uri.parse('$proxy/search/$endpoint?query=${Uri.encodeComponent(title)}');
          final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final results = data['results'] as List?;
            if (results != null && results.isNotEmpty) {
              for (final item in results) {
                final itemTitle = (item['title'] ?? item['name'] ?? item['original_title'] ?? item['original_name'] ?? '').toString();
                final itemCleanTitle = _cleanString(itemTitle);
                final dateStr = (item['release_date'] ?? item['first_air_date'] ?? '').toString();
                final itemYear = dateStr.length >= 4 ? int.tryParse(dateStr.substring(0, 4)) : null;

                if (itemCleanTitle == targetCleanTitle || itemCleanTitle.contains(targetCleanTitle)) {
                  if (year == null || itemYear == null || itemYear == year || (itemYear - year).abs() <= 1) {
                    final id = item['id'] as int?;
                    if (id != null) {
                      _cache[cacheKey] = id;
                      return id;
                    }
                  }
                }
              }

              final fallbackId = results.first['id'] as int?;
              if (fallbackId != null) {
                _cache[cacheKey] = fallbackId;
                return fallbackId;
              }
            }
          }
        } catch (_) {}
      }
    }

    return null;
  }
}
