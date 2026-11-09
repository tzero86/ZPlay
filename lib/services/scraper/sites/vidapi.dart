import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart VidAPI Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla VidAPI provider.
/// Resolves HLS and MP4 streams from streamdata.vaplayer.ru.
class VidApiScraper extends HttpScraper {
  static const _apiBase = 'https://streamdata.vaplayer.ru/api.php';
  static const _embedOrigin = 'https://nextgencloudfabric.com';
  static const _ua = kZplayUserAgent;

  static const _verifyHeaders = {
    'User-Agent': _ua,
    'Referer': '$_embedOrigin/',
    'Origin': _embedOrigin,
  };

  void _extractStreamUrls(dynamic obj, Set<String> urls) {
    if (obj == null) return;
    if (obj is String) {
      if (obj.startsWith('http') && (obj.contains('.m3u8') || obj.contains('.mp4') || obj.contains('.mpd'))) {
        urls.add(obj);
      }
    } else if (obj is List) {
      for (final item in obj) {
        _extractStreamUrls(item, urls);
      }
    } else if (obj is Map) {
      for (final val in obj.values) {
        _extractStreamUrls(val, urls);
      }
    }
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
        if (kDebugMode) debugPrint('[VidApiScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final client = http.Client();
      try {
        final queryParams = {
          'tmdb': tmdbId.toString(),
          'type': mediaType,
          if (isTv) 'season': (season ?? 1).toString(),
          if (isTv) 'episode': (episode ?? 1).toString(),
        };

        final uri = Uri.parse(_apiBase).replace(queryParameters: queryParams);

        final res = await client.get(
          uri,
          headers: {
            'Accept': '*/*',
            'Origin': _embedOrigin,
            'Referer': '$_embedOrigin/',
            'User-Agent': _ua,
          },
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode != 200) return;
        final data = jsonDecode(res.body);

        final streamUrls = <String>{};
        _extractStreamUrls(data, streamUrls);

        for (final sUrl in streamUrls) {
          final isHls = sUrl.contains('.m3u8');
          final isDash = sUrl.contains('.mpd');
          final format = isHls ? 'HLS' : isDash ? 'DASH' : 'MP4';

          yield StreamSource.zplayHttp(
            title: 'VidAPI · $format · 1080p',
            description: 'VidAPI Stream · $format',
            url: sUrl,
            headers: _verifyHeaders,
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[VidApiScraper] error: $e');
    }
  }
}
