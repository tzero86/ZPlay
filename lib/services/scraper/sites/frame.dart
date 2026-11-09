import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart Frame Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla Frame provider.
/// Resolves multi-provider streams (Zephyr, Atlas, Luna, Volt, Echo, Rift, Quill) via api.peestream.in.
class FrameScraper extends HttpScraper {
  static const _baseUrl = 'https://api.peestream.in';
  static const _ua = kZplayUserAgent;

  static const _providers = [
    {'id': 'vaplayer', 'name': 'Zephyr'},
    {'id': 'castle', 'name': 'Atlas'},
    {'id': 'hera', 'name': 'Luna'},
    {'id': 'multivid', 'name': 'Volt'},
    {'id': 'netmirror', 'name': 'Echo'},
    {'id': 'vidsuper-castle', 'name': 'Rift'},
    {'id': 'vidsuper-vixsrc', 'name': 'Quill'},
  ];

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
        if (kDebugMode) debugPrint('[FrameScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final client = http.Client();
      try {
        final futures = _providers.map((p) async {
          final pId = p['id']!;
          final pName = p['name']!;

          final queryParams = {
            'q': tmdbId.toString(),
            'type': mediaType,
            'provider': pId,
            if (isTv) 'season': (season ?? 1).toString(),
            if (isTv) 'episode': (episode ?? 1).toString(),
          };

          try {
            final uri = Uri.parse('$_baseUrl/api/search').replace(queryParameters: queryParams);
            final res = await client.get(
              uri,
              headers: {
                'User-Agent': _ua,
                'Accept': 'application/json',
                'Referer': 'https://peestream.in/',
              },
            ).timeout(const Duration(seconds: 8));

            if (res.statusCode == 200) {
              final data = jsonDecode(res.body);
              if (data is Map && data['results'] is List) {
                final list = <Map<String, dynamic>>[];
                for (final result in data['results']) {
                  if (result is! Map || result['streams'] is! List) continue;
                  for (final stream in result['streams']) {
                    if (stream is! Map) continue;
                    final sUrl = stream['url']?.toString();
                    if (sUrl == null || sUrl.isEmpty) continue;

                    list.add({
                      'url': sUrl,
                      'server': 'FRAME $pName',
                      'quality': stream['quality']?.toString() ?? '1080p',
                      'isHls': (stream['type']?.toString() == 'm3u8' || sUrl.contains('.m3u8')),
                    });
                  }
                }
                return list;
              }
            }
          } catch (_) {}
          return <Map<String, dynamic>>[];
        });

        final nested = await Future.wait(futures);
        for (final list in nested) {
          for (final item in list) {
            final sUrl = item['url'] as String;
            final server = item['server'] as String;
            final quality = item['quality'] as String;
            final isHls = item['isHls'] as bool;

            final reqHeaders = {
              'User-Agent': _ua,
            };

            yield StreamSource.zplayHttp(
              title: '$server · $quality',
              description: 'FRAME Stream · ${isHls ? 'HLS' : 'MP4'}',
              url: sUrl,
              headers: reqHeaders,
            );
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FrameScraper] error: $e');
    }
  }
}
