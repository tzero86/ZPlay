import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// 111477 Stremio Stream Scraper for ZPlayHTTP.
///
/// Dynamically generates a configured manifest URL from https://st.111477.xyz/
/// using URL-safe Base64 config encoding, optimized with a polite stream limit (3)
/// to avoid overwhelming their server pool and prevent rate-limit "Slow down" issues.
class A111477Scraper extends HttpScraper {
  static const _serviceOrigin = 'https://st.111477.xyz';
  static const _defaultStreamHost = 'https://a.111477.xyz/';

  static const _defaultHeaders = {
    'User-Agent': kZplayUserAgent,
    'Accept': 'application/json, text/plain, */*',
  };

  /// In-memory cache to prevent overloading server token pool on repeat scrapes
  static final Map<String, _CacheEntry> _streamCache = {};

  /// Dynamically generates the URL-safe base64 encoded manifest base URL.
  ///
  /// Parameters:
  /// - [host]: The file server base URL (default: 'https://a.111477.xyz/').
  /// - [sort]: Sort order ('file-desc', 'server-desc', 'none').
  /// - [limit]: Stream limit per request (default: 3 to avoid pool exhaustion).
  /// - [tmdbKey]: Optional TMDb API key to guarantee reliable metadata matching.
  static String generateManifestBaseUrl({
    String host = _defaultStreamHost,
    String sort = 'file-desc',
    int limit = 3,
    String? tmdbKey,
  }) {
    var config = host.trim();
    if (!config.endsWith('/')) config += '/';

    if (sort.isNotEmpty && sort != 'none') {
      config += '::sort=$sort';
    }
    if (limit > 0 && limit != 5) {
      config += '::limit=$limit';
    }
    if (tmdbKey != null && tmdbKey.isNotEmpty) {
      config += '::tmdb=$tmdbKey';
    }

    final bytes = utf8.encode(config);
    final b64 = base64UrlEncode(bytes).replaceAll('=', '');
    return '$_serviceOrigin/config/$b64';
  }

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
    final cacheKey = '$type|$title|$year|$season|$episode|$imdbId';

    () async {
      try {
        // Return cached sources if available and fresh (< 10 min)
        final cached = _streamCache[cacheKey];
        if (cached != null &&
            DateTime.now().difference(cached.timestamp).inMinutes < 10) {
          for (final src in cached.sources) {
            if (!controller.isClosed) controller.add(src);
          }
          controller.close();
          return;
        }
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
          debugPrint('[111477] No valid IMDB or TMDb ID for "$title"');
          controller.close();
          return;
        }

        // Dynamically generate the manifest base URL from st.111477.xyz
        final addonBase = generateManifestBaseUrl(limit: 3);
        final seenUrls = <String>{};
        final collectedSources = <StreamSource>[];

        for (final id in targetIds) {
          final String endpoint;
          if (isTv) {
            final s = season ?? 1;
            final e = episode ?? 1;
            endpoint = '$addonBase/stream/series/$id:$s:$e.json';
          } else {
            endpoint = '$addonBase/stream/movie/$id.json';
          }

          try {
            debugPrint('[111477] Fetching streams from $endpoint');
            final res = await http
                .get(Uri.parse(endpoint), headers: _defaultHeaders)
                .timeout(const Duration(seconds: 12));

            if (res.statusCode == 200) {
              final data = jsonDecode(res.body);
              if (data is Map && data['streams'] is List) {
                final streams = data['streams'] as List;
                debugPrint('[111477] Received ${streams.length} streams for $id');

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
                  final rawName = map['name']?.toString() ?? '111477';

                  final source = StreamSource(
                    name: rawName.isNotEmpty ? rawName : '111477',
                    title: rawTitle.isNotEmpty ? rawTitle : '111477 • Direct Stream',
                    description: rawTitle,
                    url: url,
                    addonName: 'ZPlayHTTP',
                    headers: _defaultHeaders,
                    behaviorHints: map['behaviorHints'] is Map
                        ? Map<String, dynamic>.from(map['behaviorHints'])
                        : null,
                  );

                  collectedSources.add(source);
                  if (!controller.isClosed) {
                    controller.add(source);
                  }
                }

                // If streams found, no need to query redundant IDs
                if (streams.isNotEmpty) {
                  break;
                }
              }
            }
          } catch (e) {
            debugPrint('[111477] Error fetching from $endpoint: $e');
          }
        }

        if (collectedSources.isNotEmpty) {
          _streamCache[cacheKey] = _CacheEntry(
            sources: List.unmodifiable(collectedSources),
            timestamp: DateTime.now(),
          );
        }
      } catch (e) {
        debugPrint('[111477] Global scrape error: $e');
      } finally {
        if (!controller.isClosed) {
          controller.close();
        }
      }
    }();

    return controller.stream;
  }
}

class _CacheEntry {
  final List<StreamSource> sources;
  final DateTime timestamp;

  _CacheEntry({required this.sources, required this.timestamp});
}

