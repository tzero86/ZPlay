import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Vadapav Stream Scraper for ZPlayHTTP.
///
/// Fetches direct HTTP streams from vadapav.mov Stremio addon:
/// https://stremio.vadapav.mov/manifest.json
class VadapavScraper extends HttpScraper {
  static const _addonBase = 'https://stremio.vadapav.mov';

  static const _defaultHeaders = {
    'User-Agent': kZplayUserAgent,
    'Accept': 'application/json, text/plain, */*',
  };

  @override
  Stream<StreamSource> scrapeStream({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) {
    final controller = StreamController<StreamSource>();
    final isTv = (type == 'series' || type == 'tv');
    final mediaType = isTv ? 'tv' : 'movie';

    () async {
      try {
        final List<String> targetIds = [];

        // 1. If IMDB ID provided, add as primary query
        if (imdbId != null && imdbId.isNotEmpty && imdbId.startsWith('tt')) {
          targetIds.add(imdbId);
        }

        // 2. Resolve TMDb ID for TMDb query fallback
        final tmdbId = await TmdbHelper.resolveTmdbId(
          imdbId: imdbId,
          title: title,
          type: mediaType,
          year: year,
        );

        if (tmdbId != null && tmdbId > 0) {
          targetIds.add('tmdb:$tmdbId');
        }

        if (targetIds.isEmpty) {
          debugPrint('[Vadapav] No valid IMDB or TMDb ID for "$title"');
          controller.close();
          return;
        }

        final seenUrls = <String>{};

        for (final id in targetIds) {
          final String endpoint;
          if (isTv) {
            final s = season ?? 1;
            final e = episode ?? 1;
            endpoint = '$_addonBase/stream/series/$id:$s:$e.json';
          } else {
            endpoint = '$_addonBase/stream/movie/$id.json';
          }

          try {
            debugPrint('[Vadapav] Fetching streams from $endpoint');
            final res = await http
                .get(Uri.parse(endpoint), headers: _defaultHeaders)
                .timeout(const Duration(seconds: 12));

            if (res.statusCode == 200) {
              final data = jsonDecode(res.body);
              if (data is Map && data['streams'] is List) {
                final streams = data['streams'] as List;
                debugPrint('[Vadapav] Received ${streams.length} streams for $id');

                for (final item in streams) {
                  if (item is! Map) continue;
                  final map = Map<String, dynamic>.from(item);

                  final url = map['url']?.toString();
                  if (url == null || url.isEmpty || !url.startsWith('http')) {
                    continue;
                  }

                  if (seenUrls.contains(url)) continue;
                  seenUrls.add(url);

                  // Extract release title or name
                  final rawTitle = map['title']?.toString() ?? '';
                  final rawName = map['name']?.toString() ?? 'vadapav.mov';

                  final source = StreamSource(
                    name: rawName.isNotEmpty ? rawName : 'vadapav.mov',
                    title: rawTitle.isNotEmpty ? rawTitle : 'vadapav.mov • Direct Stream',
                    description: rawTitle,
                    url: url,
                    addonName: 'ZPlayHTTP',
                    headers: _defaultHeaders,
                    behaviorHints: map['behaviorHints'] is Map
                        ? Map<String, dynamic>.from(map['behaviorHints'])
                        : null,
                  );

                  if (!controller.isClosed) {
                    controller.add(source);
                  }
                }

                if (streams.isNotEmpty) {
                  break;
                }
              }
            }
          } catch (e) {
            debugPrint('[Vadapav] Error fetching from $endpoint: $e');
          }
        }
      } catch (e) {
        debugPrint('[Vadapav] Global scrape error: $e');
      } finally {
        if (!controller.isClosed) {
          controller.close();
        }
      }
    }();

    return controller.stream;
  }
}
