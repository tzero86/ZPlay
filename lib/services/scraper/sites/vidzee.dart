import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart VidZee Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla VidZee provider.
/// Resolves cloud streams from core.vidzee.wtf across services (dcloud, ipcloud, tik).
class VidZeeScraper extends HttpScraper {
  static const _baseUrl = 'https://core.vidzee.wtf';
  static const _playerUrl = 'https://player.vidzee.wtf';
  static const _services = ['dcloud', 'ipcloud', 'tik'];
  static const _ua = kZplayUserAgent;

  static const _headers = {
    'User-Agent': _ua,
    'Accept': 'application/json, text/plain, */*',
    'Referer': '$_playerUrl/',
    'Origin': _playerUrl,
  };

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
        if (kDebugMode) debugPrint('[VidZeeScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final client = http.Client();
      try {
        final futures = _services.map((service) async {
          final directEndpoint = isTv
              ? '$_baseUrl/streams/tv/$tmdbId/${season ?? 1}/${episode ?? 1}?s=$service'
              : '$_baseUrl/streams/movie/$tmdbId?s=$service';

          try {
            final res = await client.get(
              Uri.parse(directEndpoint),
              headers: _headers,
            ).timeout(const Duration(seconds: 6));

            if (res.statusCode == 200) {
              final data = jsonDecode(res.body);
              if (data is Map && data['url'] != null) {
                final streamUrl = data['url'].toString();
                if (streamUrl.isNotEmpty) {
                  final rawLang = data['language']?.toString().trim() ?? '';
                  return {
                    'url': streamUrl,
                    'service': service,
                    'language': rawLang,
                    'isHls': streamUrl.contains('.m3u8'),
                  };
                }
              }
            }
          } catch (_) {}
          return null;
        });

        final results = await Future.wait(futures);
        for (final r in results) {
          if (r == null) continue;
          final streamUrl = r['url'] as String;
          final service = r['service'] as String;
          final language = (r['language'] as String?) ?? '';
          final isHls = r['isHls'] as bool;

          final hasValidLang = language.isNotEmpty && language.toLowerCase() != 'auto';
          final titleParts = [
            'VidZee',
            service,
            if (hasValidLang) language,
            '1080p',
          ];

          final reqHeaders = {
            'User-Agent': _ua,
            'Referer': '$_playerUrl/',
            'Origin': _playerUrl,
          };

          yield StreamSource.zplayHttp(
            title: titleParts.join(' · '),
            description: hasValidLang
                ? 'VidZee Stream · $language · ${isHls ? 'HLS' : 'MP4'}'
                : 'VidZee Stream · ${isHls ? 'HLS' : 'MP4'}',
            url: streamUrl,
            headers: reqHeaders,
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[VidZeeScraper] error: $e');
    }
  }
}
