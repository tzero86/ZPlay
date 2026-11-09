import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart VidLink Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla VidLink provider.
/// Encrypts TMDB query via enc-dec.app and extracts direct streams from vidlink.pro.
class VidLinkScraper extends HttpScraper {
  static const _base = 'https://vidlink.pro';
  static const _encApi = 'https://enc-dec.app/api/enc-vidlink';
  static const _ua = kZplayUserAgent;

  static const _headers = {
    'User-Agent': _ua,
    'Origin': _base,
    'Referer': '$_base/',
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
        if (kDebugMode) debugPrint('[VidLinkScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final client = http.Client();
      try {
        final encRes = await client.get(
          Uri.parse('$_encApi?text=$tmdbId'),
          headers: {'User-Agent': _ua, 'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 6));

        if (encRes.statusCode != 200) return;
        final encData = jsonDecode(encRes.body);
        if (encData is! Map || encData['status'] != 200 || encData['result'] == null) return;
        final encKey = encData['result'].toString();

        final endpoint = isTv
            ? '$_base/api/b/tv/$encKey/${season ?? 1}/${episode ?? 1}'
            : '$_base/api/b/movie/$encKey';

        final res = await client.get(
          Uri.parse(endpoint),
          headers: _headers,
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode != 200) return;
        final data = jsonDecode(res.body);
        if (data is! Map || data['stream'] is! Map) return;

        final stream = data['stream'] as Map;

        if (stream['playlist'] != null) {
          final playlistUrl = stream['playlist'].toString();
          if (playlistUrl.isNotEmpty) {
            yield StreamSource.zplayHttp(
              title: 'VidLink · Master HLS · 1080p',
              description: 'VidLink HLS Stream',
              url: playlistUrl,
              headers: _headers,
            );
          }
        }

        if (stream['qualities'] is Map) {
          final qualities = stream['qualities'] as Map;
          for (final q in ['1080', '720', '480', '360']) {
            if (qualities[q] is Map && qualities[q]['url'] != null) {
              final qUrl = qualities[q]['url'].toString();
              yield StreamSource.zplayHttp(
                title: 'VidLink · ${q}p',
                description: 'VidLink MP4 Stream',
                url: qUrl,
                headers: _headers,
              );
              break;
            }
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[VidLinkScraper] error: $e');
    }
  }
}
