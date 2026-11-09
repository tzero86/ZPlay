import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart PeeStream Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla PeeStream provider.
/// Connects to providers.peestream.in via SSE scrape pipeline and fallback search.
class PeeStreamScraper extends HttpScraper {
  static const _baseUrl = 'https://providers.peestream.in';
  static const _ua = kZplayUserAgent;

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
        if (kDebugMode) debugPrint('[PeeStreamScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final client = http.Client();
      try {
        var foundStreams = false;

        // 1. Try SSE scrape route
        final queryParams = {
          'type': mediaType,
          'tmdbId': tmdbId.toString(),
          'title': title,
        };
        if (year != null) queryParams['releaseYear'] = year.toString();
        if (imdbId != null && imdbId.isNotEmpty) queryParams['imdbId'] = imdbId;
        if (isTv) {
          queryParams['season'] = (season ?? 1).toString();
          queryParams['episode'] = (episode ?? 1).toString();
        }

        final scrapeUri = Uri.parse('$_baseUrl/scrape').replace(queryParameters: queryParams);

        try {
          final res = await client.get(
            scrapeUri,
            headers: {
              'User-Agent': _ua,
              'Accept': 'text/event-stream',
              'Referer': '$_baseUrl/',
            },
          ).timeout(const Duration(seconds: 12));

          if (res.statusCode == 200) {
            final events = res.body.split('\n\n');
            for (final ev in events) {
              if (ev.contains('event: completed')) {
                final match = RegExp(r'data:\s*(.+)').firstMatch(ev);
                if (match != null && match.group(1) != null) {
                  try {
                    final parsed = jsonDecode(match.group(1)!.trim());
                    if (parsed is Map && parsed['stream'] is Map) {
                      final stream = parsed['stream'] as Map;
                      final streamUrl = stream['playlist']?.toString() ??
                          stream['url']?.toString() ??
                          stream['file']?.toString();

                      if (streamUrl != null && streamUrl.isNotEmpty) {
                        final sourceId = parsed['sourceId']?.toString() ?? 'Poseidon';
                        final quality = stream['quality']?.toString() ?? '1080p';

                        Map<String, String>? reqHeaders;
                        if (stream['headers'] is Map) {
                          reqHeaders = (stream['headers'] as Map)
                              .map((k, v) => MapEntry(k.toString(), v.toString()));
                        } else {
                          reqHeaders = {'User-Agent': _ua};
                        }

                        yield StreamSource.zplayHttp(
                          title: 'PeeStream · $sourceId · $quality',
                          description: 'PeeStream Multi-Server Stream · $quality',
                          url: streamUrl,
                          headers: reqHeaders,
                        );
                        foundStreams = true;
                      }
                    }
                  } catch (_) {}
                }
              }
            }
          }
        } catch (_) {}

        // 2. Fallback search route if SSE didn't return streams
        if (!foundStreams) {
          try {
            final searchParams = {
              'q': title,
              'type': mediaType,
              'tmdbId': tmdbId.toString(),
            };
            if (isTv) {
              searchParams['season'] = (season ?? 1).toString();
              searchParams['episode'] = (episode ?? 1).toString();
            }

            final searchUri = Uri.parse('$_baseUrl/api/search').replace(queryParameters: searchParams);
            final sRes = await client.get(
              searchUri,
              headers: {
                'User-Agent': _ua,
                'Accept': 'application/json',
                'Referer': '$_baseUrl/',
              },
            ).timeout(const Duration(seconds: 10));

            if (sRes.statusCode == 200) {
              final data = jsonDecode(sRes.body);
              if (data is Map && data['results'] is List) {
                for (final result in data['results']) {
                  if (result is! Map) continue;
                  final pName = result['providerName']?.toString() ??
                      result['provider']?.toString() ??
                      'PeeStream';

                  if (result['streams'] is List) {
                    for (final st in result['streams']) {
                      if (st is! Map) continue;
                      final streamUrl = st['url']?.toString();
                      if (streamUrl == null || streamUrl.isEmpty) continue;

                      final stName = st['name']?.toString() ?? pName;
                      final quality = st['quality']?.toString() ?? '1080p';

                      final streamHeaders = {'User-Agent': _ua};

                      yield StreamSource.zplayHttp(
                        title: 'PeeStream · $stName · $quality',
                        description: 'PeeStream Stream · $quality',
                        url: streamUrl,
                        headers: streamHeaders,
                      );
                    }
                  }
                }
              }
            }
          } catch (_) {}
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[PeeStreamScraper] scrapeStream error: $e');
    }
  }
}
