import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// MovieNight (movienig.ht) Scraper
///
/// Fetches high-definition streams (4K 2160p, 1080p, 720p HLS) from MovieNight's
/// server infrastructure (Dallas, Seattle, Austin, Helena, etc.)
class MovieNightScraper extends HttpScraper {
  static const _base = 'https://movienig.ht';
  static const _ua = kZplayUserAgent;

  static const _headers = {
    'User-Agent': _ua,
    'Referer': 'https://movienig.ht/',
    'Origin': 'https://movienig.ht',
    'Accept': 'text/event-stream',
  };

  /// Primary high-performing servers to query directly
  static const _priorityServers = [
    {'id': 'dallas', 'label': 'Dallas 4K'},
    {'id': 'austin', 'label': 'Austin'},
    {'id': 'helena', 'label': 'Helena'},
    {'id': 'seattle', 'label': 'Seattle 4K'},
    {'id': 'vixsrc-1', 'label': 'Newport Beach'},
    {'id': 'tucson', 'label': 'Tucson'},
    {'id': 'salem', 'label': 'Salem'},
  ];

  @override
  Future<List<StreamSource>> scrape({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async {
    final sources = <StreamSource>[];
    final mediaType = (type == 'series' || type == 'tv') ? 'tv' : 'movie';

    final tmdbId = await TmdbHelper.resolveTmdbId(
      imdbId: imdbId,
      title: title,
      type: mediaType,
      year: year,
    );

    if (tmdbId == null && (imdbId == null || imdbId.isEmpty)) {
      debugPrint('[MovieNightScraper] Could not resolve TMDb or IMDb ID for "$title"');
      return sources;
    }

    final idToUse = tmdbId ?? imdbId;
    debugPrint('[MovieNightScraper] Scraping MovieNight for "$title" (id: $idToUse, type: $mediaType)');

    final encTitle = Uri.encodeComponent(title);
    final yearQuery = year != null ? '&year=$year' : '';
    final imdbQuery = (imdbId != null && imdbId.isNotEmpty) ? '&imdbId=$imdbId' : '';

    final serverTasks = _priorityServers.map((server) async {
      final serverId = server['id']!;
      final serverLabel = server['label']!;

      try {
        final Uri uri;
        if (mediaType == 'tv') {
          final s = season ?? 1;
          final e = episode ?? 1;
          uri = Uri.parse(
            '$_base/api/stream/v1/tv/$idToUse/$s/$e?title=$encTitle$yearQuery$imdbQuery&server=$serverId&only=1',
          );
        } else {
          uri = Uri.parse(
            '$_base/api/stream/v1/movie/$idToUse?title=$encTitle$yearQuery$imdbQuery&server=$serverId&only=1',
          );
        }

        final client = http.Client();
        final request = http.Request('GET', uri);
        request.headers.addAll(_headers);

        final response = await client.send(request).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final bodyBytes = await response.stream.toBytes();
          final bodyStr = utf8.decode(bodyBytes, allowMalformed: true);

          if (bodyStr.contains('event: done')) {
            final doneIdx = bodyStr.indexOf('event: done');
            final dataIdx = bodyStr.indexOf('data: ', doneIdx);

            if (dataIdx != -1) {
              final jsonStart = dataIdx + 6;
              final jsonEnd = bodyStr.indexOf('\n', jsonStart);
              final jsonText = (jsonEnd != -1 ? bodyStr.substring(jsonStart, jsonEnd) : bodyStr.substring(jsonStart)).trim();

              try {
                final data = jsonDecode(jsonText) as Map<String, dynamic>;
                final streamSources = data['sources'] as List?;

                if (streamSources != null && streamSources.isNotEmpty) {
                  for (final src in streamSources) {
                    if (src is! Map) continue;
                    final rawUrl = src['url']?.toString();
                    if (rawUrl == null || rawUrl.isEmpty) continue;

                    final quality = src['quality']?.toString() ?? 'Auto';
                    final titleQuality = quality != 'Auto' ? ' ($quality)' : '';

                    sources.add(StreamSource(
                      name: 'ZPlayHTTP',
                      addonName: 'ZPlayHTTP',
                      title: 'MovieNight $serverLabel$titleQuality',
                      description: 'MovieNight · $serverLabel · Quality: $quality HLS',
                      url: rawUrl,
                      headers: {
                        'User-Agent': _ua,
                        'Referer': 'https://movienig.ht/',
                      },
                    ));
                  }
                }
              } catch (e) {
                debugPrint('[MovieNightScraper] JSON parse error for $serverId: $e');
              }
            }
          }
        }
        client.close();
      } catch (_) {
        // Timeout or connection error
      }
    });

    await Future.wait(serverTasks);

    debugPrint('[MovieNightScraper] Total sources found: ${sources.length}');
    return sources;
  }
}
