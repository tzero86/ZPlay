import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// RiveStream Stream Scraper for ZPlayHTTP.
///
/// Scrapes multi-provider video streams (HLS/MP4) from RiveStream's backend
/// microservice (https://scrapper.rivestream.app/api/provider).
/// Excludes torrents, captions, and drive downloads.
class RiveStreamScraper extends HttpScraper {
  static const _apiBase = 'https://scrapper.rivestream.app';
  static const _referer = 'https://www.rivestream.app/';
  static const _origin = 'https://www.rivestream.app';
  static const _ua = kZplayUserAgent;

  static const _defaultHeaders = {
    'User-Agent': _ua,
    'Referer': _referer,
    'Origin': _origin,
    'Accept': 'application/json, text/plain, */*',
  };

  static const _fallbackProviders = [
    'apex',
    'pulse',
    'solstice',
    'quasar',
    'primevids',
    'flowcast',
    'citadel',
    'guru',
    'asiacloud',
    'horizon',
    'hindicast',
  ];

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
        final tmdbId = await TmdbHelper.resolveTmdbId(
          imdbId: imdbId,
          title: title,
          type: mediaType,
          year: year,
        );

        if (tmdbId == null || tmdbId <= 0) {
          debugPrint('[RiveStreamScraper] Could not resolve TMDb ID for "$title"');
          controller.close();
          return;
        }

        debugPrint(
            '[RiveStreamScraper] Starting concurrent scrape for "$title" (tmdb: $tmdbId, S:${season}E:$episode)');

        // Discover active providers dynamically, fallback if timeout
        List<String> providers = _fallbackProviders;
        try {
          final pRes = await http
              .get(Uri.parse('$_apiBase/api/providers'), headers: _defaultHeaders)
              .timeout(const Duration(seconds: 3));
          if (pRes.statusCode == 200) {
            final pData = jsonDecode(pRes.body);
            if (pData is Map && pData['data'] is List) {
              providers = (pData['data'] as List).map((e) => e.toString()).toList();
            } else if (pData is List) {
              providers = pData.map((e) => e.toString()).toList();
            }
          }
        } catch (_) {
          // Use fallback providers
        }

        final seenUrls = <String>{};
        final cbValue = DateTime.now().millisecondsSinceEpoch ~/ 3000000;

        final providerTasks = providers.map((provider) async {
          try {
            final cbParam = (provider == 'primevids' || provider == 'citadel')
                ? '&cb=$cbValue'
                : '';

            final String endpoint;
            if (isTv) {
              final s = season ?? 1;
              final e = episode ?? 1;
              endpoint =
                  '$_apiBase/api/provider?provider=$provider&id=$tmdbId&season=$s&episode=$e$cbParam';
            } else {
              endpoint =
                  '$_apiBase/api/provider?provider=$provider&id=$tmdbId$cbParam';
            }

            final client = http.Client();
            final res = await client
                .get(Uri.parse(endpoint), headers: _defaultHeaders)
                .timeout(const Duration(seconds: 6));

            if (res.statusCode != 200) {
              client.close();
              return;
            }

            final data = jsonDecode(res.body);
            client.close();

            if (data is! Map || data['data'] is! Map) {
              return;
            }

            final sources = data['data']['sources'] as List?;
            if (sources == null || sources.isEmpty) {
              return;
            }

            for (final src in sources) {
              if (src is! Map) continue;

              final rawUrl = (src['url'] ?? '').toString().trim();
              if (rawUrl.isEmpty || !rawUrl.startsWith('http') || seenUrls.contains(rawUrl)) {
                continue;
              }
              seenUrls.add(rawUrl);

              final srcName = (src['source'] ?? provider).toString();
              final quality = (src['quality'] ?? 'Auto').toString();
              final format = (src['format'] ?? 'hls').toString().toUpperCase();
              final size = src['size']?.toString();

              final streamTitle = '[Rive - $srcName] $quality';
              final desc = size != null
                  ? '$srcName • $quality • $format • ${_formatSize(size)}'
                  : '$srcName • $quality • $format';

              if (!controller.isClosed) {
                controller.add(
                  _buildSource(
                    url: rawUrl,
                    title: streamTitle,
                    quality: quality,
                    description: desc,
                  ),
                );
              }
            }
          } catch (_) {
            // Skip individual provider error
          }
        });

        await Future.wait(providerTasks);
      } catch (e) {
        debugPrint('[RiveStreamScraper] Error scraping "$title": $e');
      } finally {
        if (!controller.isClosed) {
          controller.close();
        }
      }
    }();

    return controller.stream;
  }

  String _formatSize(String sizeStr) {
    final bytes = int.tryParse(sizeStr);
    if (bytes == null || bytes <= 0) return sizeStr;
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '$bytes B';
  }

  StreamSource _buildSource({
    required String url,
    required String title,
    required String quality,
    required String description,
  }) {
    return StreamSource.zplayHttp(
      name: title,
      title: title,
      description: description,
      url: url,
      headers: {
        'User-Agent': _ua,
        'Referer': _referer,
        'Origin': _origin,
      },
    );
  }
}
