import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// Pure-Dart FSOnline Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla FSOnline provider.
/// Resolves FileSuN streams from www3.fsonline.app.
class FSOnlineScraper extends HttpScraper {
  static const _origin = 'https://www3.fsonline.app';
  static const _ajaxUrl = '$_origin/wp-admin/admin-ajax.php';
  static const _ua = kZplayUserAgent;

  static const _headers = {
    'User-Agent': _ua,
    'Origin': _origin,
    'Referer': '$_origin/',
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

    try {
      final client = http.Client();
      try {
        final query = year != null ? '$title $year' : title;
        final searchRes = await client.get(
          Uri.parse('$_origin/?s=${Uri.encodeComponent(query)}'),
          headers: _headers,
        ).timeout(const Duration(seconds: 8));

        if (searchRes.statusCode != 200) return;
        final searchHtml = searchRes.body;

        final typeFolder = isTv ? 'seriale' : 'film';
        final linkMatch = RegExp('''href=["'](https?://www3\\.fsonline\\.app/$typeFolder/([^"'/]+)/)["']''', caseSensitive: false)
            .firstMatch(searchHtml);
        if (linkMatch == null || linkMatch.group(1) == null) return;

        final targetPageUrl = isTv
            ? '$_origin/episoade/${linkMatch.group(2)!.replaceAll(RegExp(r'-\d{4}$'), '')}-sezonul-${season ?? 1}-episodul-${episode ?? 1}/'
            : linkMatch.group(1)!;

        final pageRes = await client.get(
          Uri.parse(targetPageUrl),
          headers: _headers,
        ).timeout(const Duration(seconds: 8));

        if (pageRes.statusCode != 200) return;
        final pageHtml = pageRes.body;

        final movieId = (RegExp(r'''movie-id=['"]([^'"]+)['"]''').firstMatch(pageHtml) ??
                RegExp(r'''movie-id=([^ >]+)''').firstMatch(pageHtml))
            ?.group(1);
        if (movieId == null) return;

        final ajaxRes = await client.post(
          Uri.parse(_ajaxUrl),
          headers: {
            ..._headers,
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': targetPageUrl,
          },
          body: 'action=lazy_player&movieID=$movieId',
        ).timeout(const Duration(seconds: 8));

        if (ajaxRes.statusCode != 200) return;
        final ajaxHtml = ajaxRes.body;

        var idx = 0;
        while ((idx = ajaxHtml.indexOf('data-vs="', idx)) != -1) {
          final embedStart = idx + 9;
          final embedEnd = ajaxHtml.indexOf('"', embedStart);
          if (embedEnd == -1) break;
          final embedUrl = ajaxHtml.substring(embedStart, embedEnd);

          final spanStart = ajaxHtml.indexOf('<span>', embedEnd);
          final spanEnd = ajaxHtml.indexOf('</span>', spanStart);
          final serverLabel = spanStart != -1 && spanEnd != -1
              ? ajaxHtml.substring(spanStart + 6, spanEnd).trim().toLowerCase()
              : '';

          if (serverLabel.contains('filesun')) {
            try {
              final rRes = await client.get(
                Uri.parse(embedUrl),
                headers: {'Referer': _origin, 'User-Agent': _ua},
              ).timeout(const Duration(seconds: 6));

              if (rRes.statusCode == 200) {
                final m3u8Match = RegExp(r'''file:\s*["'](https?://[^"']+\.m3u8[^"']*)["']''').firstMatch(rRes.body) ??
                    RegExp(r'''["']?file["']?:\s*["'](https?://[^"']+)["']''').firstMatch(rRes.body);

                if (m3u8Match != null && m3u8Match.group(1) != null) {
                  final streamUrl = m3u8Match.group(1)!.replaceAll(r'\/', '/');
                  final reqHeaders = {
                    'Referer': embedUrl,
                    'Origin': 'https://player.fsonline.app',
                    'User-Agent': _ua,
                  };

                  yield StreamSource.zplayHttp(
                    title: 'FSOnline · FileSuN · 1080p',
                    description: 'FSOnline HLS Stream',
                    url: streamUrl,
                    headers: reqHeaders,
                  );
                }
              }
            } catch (_) {}
          }
          idx = spanEnd != -1 ? spanEnd : embedEnd;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FSOnlineScraper] error: $e');
    }
  }
}
