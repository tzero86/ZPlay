import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// Pure-Dart LookMovie Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla LookMovie provider.
/// Resolves multi-quality HLS streams from lookmovie2.to / lookmovie.foundation.
class LookMovieScraper extends StreamScraper {
  @override
  String get name => 'ZPlayHTTP';

  static const _domains = [
    'https://www.lookmovie2.to',
    'https://lookmovie2.to',
    'https://lookmovie.foundation',
  ];

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static const _headersBase = {
    'User-Agent': _ua,
    'Accept-Language': 'en-US,en;q=0.9',
  };

  Future<Map<String, dynamic>?> _searchLookMovie(
    http.Client client,
    String type,
    String title,
    int? year,
  ) async {
    for (final base in _domains) {
      try {
        final headers = {
          ..._headersBase,
          'Accept': 'application/json',
          'Referer': '$base/',
          'X-Requested-With': 'XMLHttpRequest',
        };

        final res = await client.get(
          Uri.parse('$base/api/v1/$type/do-search/?q=${Uri.encodeComponent(title)}'),
          headers: headers,
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map && data['result'] is List && (data['result'] as List).isNotEmpty) {
            final results = data['result'] as List;
            Map? match;
            if (year != null) {
              match = results.firstWhere(
                (r) => r is Map && r['year']?.toString() == year.toString(),
                orElse: () => null,
              );
            }
            match ??= results.firstWhere(
              (r) => r is Map && r['title']?.toString().toLowerCase() == title.toLowerCase(),
              orElse: () => null,
            );

            if (match != null) {
              return {'match': match, 'base': base};
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  String? _getEpisodeId(String html, int s, int e) {
    final storageMatch = RegExp(r'''window\[['"](?:movie|show)_storage['"]\]\s*=\s*\{([^}]+)\}''')
        .firstMatch(html);
    if (storageMatch != null) {
      final block = storageMatch.group(1)!;
      final sm = RegExp(r'''seasons\s*:\s*(\[[\s\S]+?\])\s*[,}]''').firstMatch(block);
      if (sm != null && sm.group(1) != null) {
        try {
          final seasons = jsonDecode(sm.group(1)!);
          if (seasons is List) {
            final season = seasons.firstWhere(
              (x) => x is Map && (x['season'] ?? x['meta']?['season'])?.toString() == s.toString(),
              orElse: () => null,
            );
            if (season != null && season['episodes'] != null) {
              final eps = season['episodes'];
              if (eps is List) {
                final ep = eps.firstWhere(
                  (x) => x is Map && x['episode']?.toString() == e.toString(),
                  orElse: () => null,
                );
                if (ep != null) return (ep['id_episode'] ?? ep['id'])?.toString();
              } else if (eps is Map) {
                final ep = eps[e.toString()] ?? eps.values.firstWhere(
                  (x) => x is Map && x['episode']?.toString() == e.toString(),
                  orElse: () => null,
                );
                if (ep != null) return (ep['id_episode'] ?? ep['id'])?.toString();
              }
            }
          }
        } catch (_) {}
      }
    }

    final am = RegExp('''data-season=["']$s["'][^>]*?data-episode=["']$e["'][^>]*?data-id=["'](\\d+)["']''')
            .firstMatch(html) ??
        RegExp('''data-episode=["']$e["'][^>]*?data-season=["']$s["'][^>]*?data-id=["'](\\d+)["']''')
            .firstMatch(html);
    return am?.group(1);
  }

  @override
  Stream<StreamSource> scrapeStream({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async* {
    final isTv = (type == 'tv' || type == 'series');
    final typeStr = isTv ? 'shows' : 'movies';

    try {
      final client = http.Client();
      try {
        final searchRes = await _searchLookMovie(client, typeStr, title, year);
        if (searchRes == null || searchRes['match'] == null) return;

        final match = searchRes['match'] as Map;
        final base = searchRes['base'] as String;
        final slug = match['slug']?.toString();
        if (slug == null || slug.isEmpty) return;

        final headers = {
          ..._headersBase,
          'Accept': 'text/html',
          'Referer': '$base/',
        };

        final pageRes = await client.get(
          Uri.parse('$base/$typeStr/play/$slug'),
          headers: headers,
        ).timeout(const Duration(seconds: 8));

        if (pageRes.statusCode != 200) return;
        final html = pageRes.body;

        final storageMatch = RegExp(r'''window\[['"](?:movie|show)_storage['"]\]\s*=\s*\{([^}]+)\}''')
            .firstMatch(html);
        if (storageMatch == null || storageMatch.group(1) == null) return;

        final block = storageMatch.group(1)!;
        final hashMatch = RegExp(r'''hash\s*:\s*['"]([^'"]+)['"]''').firstMatch(block);
        final expiresMatch = RegExp(r'''expires\s*:\s*(\d+)''').firstMatch(block);

        if (hashMatch == null || expiresMatch == null) return;
        final hash = hashMatch.group(1)!;
        final expires = expiresMatch.group(1)!;

        final streamId = isTv
            ? _getEpisodeId(html, season ?? 1, episode ?? 1)
            : (match['id_movie'] ?? match['id'] ?? RegExp(r'''['"]?(?:id_movie|movieId)['"]?\s*[:=]\s*['"]?(\d+)['"]?''').firstMatch(html)?.group(1))?.toString();

        if (streamId == null || streamId.isEmpty) return;

        final accessParam = isTv ? 'episode' : 'movie';
        final accessUrl = '$base/api/v1/security/$accessParam-access?id_$accessParam=$streamId&hash=$hash&expires=$expires';

        final accessHeaders = {
          ..._headersBase,
          'Accept': 'application/json',
          'Referer': '$base/',
          'X-Requested-With': 'XMLHttpRequest',
        };

        final accessRes = await client.get(
          Uri.parse(accessUrl),
          headers: accessHeaders,
        ).timeout(const Duration(seconds: 8));

        if (accessRes.statusCode != 200) return;
        final data = jsonDecode(accessRes.body);

        final streams = data is Map
            ? (data['streams'] ?? data['result']?['streams'] ?? data['data']?['streams'] ?? data)
            : null;

        if (streams is Map) {
          for (final entry in streams.entries) {
            final q = entry.key.toString();
            final url = entry.value?.toString();
            if (url == null || !url.contains('.m3u8')) continue;

            final qualityLabel = q.contains('1080') ? '1080p' : q.contains('720') ? '720p' : '$q p';

            final streamHeaders = {
              'User-Agent': _ua,
              'Referer': '$base/',
            };

            yield StreamSource(
              name: 'ZPlayHTTP',
              addonName: 'ZPlayHTTP',
              title: 'LookMovie · $qualityLabel',
              description: 'LookMovie HLS Stream · $qualityLabel',
              url: url,
              headers: streamHeaders,
              behaviorHints: {
                'notWebReady': false,
                'proxyHeaders': {
                  'request': streamHeaders,
                },
              },
            );
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[LookMovieScraper] scrapeStream error: $e');
    }
  }
}
