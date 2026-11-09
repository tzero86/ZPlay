import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import '../../config/service_credentials.dart';
import 'tmdb_helper.dart';

/// Pure-Dart VidGod Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla VidGod provider.
/// Leverages multi-worker clusters (Pulsar, Orion, Stellar) and cloud cache.
class VidGodScraper extends HttpScraper {
  static const _redisUrl = 'https://vidnest-redis-fell-prism-rest.cloud.layerbase.dev/';
  static String get _redisAuth =>
      'Bearer ${ServiceCredentials.value(ServiceCredential.vidgod)}';
  static const _origin = 'https://vidgod.space';
  static const _ua = kZplayUserAgent;

  static const _servers = [
    {
      'name': 'Pulsar',
      'key': 'pulsar',
      'base': 'https://vidnest-extractor.vividdubbing.workers.dev/api',
      'param': 'prime',
    },
    {
      'name': 'Orion',
      'key': 'orion',
      'base': 'https://404-vidnest.lofiserver.workers.dev/api',
      'param': 'gama',
    },
    {
      'name': 'Stellar',
      'key': 'stellar',
      'base': 'https://404-vidnest.lofiserver.workers.dev/api',
      'param': 'sigma',
    },
  ];

  Future<Map<String, dynamic>?> _getFromCache(
    http.Client client,
    String serverKey,
    String type,
    int tmdbId,
    int? season,
    int? episode,
  ) async {
    try {
      final cacheKey = type == 'tv'
          ? '$serverKey:$type:$tmdbId:${season ?? 1}:${episode ?? 1}'
          : '$serverKey:$type:$tmdbId';

      final res = await client.post(
        Uri.parse(_redisUrl),
        headers: {
          'Authorization': _redisAuth,
          'Content-Type': 'application/json',
          'Accept': '*/*',
          'Origin': _origin,
          'Referer': '$_origin/',
          'User-Agent': _ua,
        },
        body: jsonEncode(['GET', cacheKey]),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data != null && data['result'] != null) {
          final rawResult = data['result'];
          final parsed = rawResult is String ? jsonDecode(rawResult) : rawResult;
          if (parsed is Map && parsed['streams'] is List && (parsed['streams'] as List).isNotEmpty) {
            return Map<String, dynamic>.from(parsed);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _fetchFromWorker(
    http.Client client,
    Map<String, String> srv,
    String type,
    int tmdbId,
    int? season,
    int? episode,
  ) async {
    try {
      final base = srv['base']!;
      final param = srv['param']!;

      final endpoint = type == 'movie'
          ? '$base/movie/$tmdbId?server=$param'
          : '$base/tv/$tmdbId/${season ?? 1}/${episode ?? 1}?server=$param';

      final res = await client.get(
        Uri.parse(endpoint),
        headers: {
          'Accept': 'application/json',
          'Origin': _origin,
          'Referer': '$_origin/',
          'User-Agent': _ua,
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['streams'] is List && (data['streams'] as List).isNotEmpty) {
          return Map<String, dynamic>.from(data);
        }
      }
    } catch (_) {}
    return null;
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
    final mediaType = isTv ? 'tv' : 'movie';

    try {
      final tmdbId = await TmdbHelper.resolveTmdbId(
        imdbId: imdbId,
        title: title,
        type: mediaType,
        year: year,
      );

      if (tmdbId == null) {
        if (kDebugMode) debugPrint('[VidGodScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final client = http.Client();
      try {
        final futures = _servers.map((srv) async {
          final serverKey = srv['key']!;
          final serverName = srv['name']!;

          // Check cache first
          var data = await _getFromCache(client, serverKey, mediaType, tmdbId, season, episode);

          // Fallback to live worker
          data ??= await _fetchFromWorker(client, srv, mediaType, tmdbId, season, episode);

          if (data != null) {
            return {
              'serverName': serverName,
              'streams': data['streams'],
            };
          }
          return null;
        });

        final results = await Future.wait(futures);

        for (final r in results) {
          if (r == null) continue;
          final serverName = r['serverName'] as String;
          final streamsList = r['streams'] as List;

          for (final item in streamsList) {
            if (item is! Map) continue;
            final streamUrl = item['url']?.toString();
            if (streamUrl == null || streamUrl.isEmpty) continue;

            final quality = item['quality']?.toString() ?? '1080p';

            final headers = {
              'User-Agent': _ua,
              'Referer': '$_origin/',
              'Origin': _origin,
            };

            yield StreamSource.zplayHttp(
              title: 'VidGod · $serverName · $quality',
              description: 'VidGod Cloud Stream · $quality',
              url: streamUrl,
              headers: headers,
            );
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[VidGodScraper] scrapeStream error: $e');
    }
  }
}
