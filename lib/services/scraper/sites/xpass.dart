import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart XPass Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla XPass provider.
/// Resolves multi-server streams from play.xpass.top.
class XPassScraper extends HttpScraper {
  static const _base = 'https://play.xpass.top';
  static const _ua = kZplayUserAgent;

  static const _headers = {
    'Accept': '*/*',
    'User-Agent': _ua,
    'Origin': _base,
    'Referer': '$_base/',
    'Cookie': 'auth_token=de21073d24bca9b50f189b402ac870734cf945f2085cb7e1a4fc453fcfe4f57e',
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
        if (kDebugMode) debugPrint('[XPassScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final client = http.Client();
      try {
        final refererUrl = '$_base/e/${isTv ? 'tv' : 'movie'}/$tmdbId?autostart=true';
        final reqHeaders = {
          ..._headers,
          'Referer': refererUrl,
        };

        dynamic sources;

        if (!isTv) {
          final res = await client.get(
            Uri.parse(refererUrl),
            headers: reqHeaders,
          ).timeout(const Duration(seconds: 8));

          if (res.statusCode == 200) {
            final match = RegExp(r'''var backups=(\[[\s\S]*?\])''').firstMatch(res.body);
            if (match != null && match.group(1) != null) {
              try {
                sources = jsonDecode(match.group(1)!);
              } catch (_) {}
            }
          }
        } else {
          final res = await client.get(
            Uri.parse('$_base/data/tv/$tmdbId/${season ?? 1}/${episode ?? 1}?autostart=true&force=true'),
            headers: reqHeaders,
          ).timeout(const Duration(seconds: 8));

          if (res.statusCode == 200) {
            try {
              sources = jsonDecode(res.body);
            } catch (_) {}
          }
        }

        if (sources is! List || sources.isEmpty) return;

        for (final src in sources) {
          if (src is! Map || src['url'] == null) continue;
          final sUrl = src['url'].toString();
          final sName = src['name']?.toString() ?? 'Server';

          try {
            final mRes = await client.get(
              Uri.parse('$_base$sUrl'),
              headers: reqHeaders,
            ).timeout(const Duration(seconds: 6));

            if (mRes.statusCode == 200) {
              final mdata = jsonDecode(mRes.body);
              if (mdata is Map && mdata['playlist'] is List && (mdata['playlist'] as List).isNotEmpty) {
                final pl0 = mdata['playlist'][0];
                if (pl0 is Map && pl0['sources'] is List) {
                  final list = pl0['sources'] as List;
                  Map? target;
                  for (final item in list) {
                    if (item is Map && item['type'] == 'hls') {
                      target = item;
                      break;
                    }
                  }
                  target ??= list.firstWhere((item) => item is Map, orElse: () => null);

                  if (target != null && target['file'] != null) {
                    final streamUrl = target['file'].toString();
                    final isHls = (target['type'] == 'hls' || streamUrl.contains('.m3u8'));

                    yield StreamSource.zplayHttp(
                      title: 'XPass · $sName · 1080p',
                      description: 'XPass Stream · ${isHls ? 'HLS' : 'MP4'}',
                      url: streamUrl,
                      headers: {
                        'Origin': _base,
                        'Referer': _base,
                        'User-Agent': _ua,
                      },
                    );
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
      if (kDebugMode) debugPrint('[XPassScraper] error: $e');
    }
  }
}
