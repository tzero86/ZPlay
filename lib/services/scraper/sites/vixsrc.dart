import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart VixSrc Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla VixSrc provider.
/// Resolves tokenized HLS playlists from vixsrc.to.
class VixSrcScraper extends HttpScraper {
  static const _baseUrl = 'https://vixsrc.to';
  static const _ua = kZplayUserAgent;

  static const _headers = {
    'User-Agent': _ua,
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': '$_baseUrl/',
    'Origin': _baseUrl,
  };

  String? _extract(RegExp reg, String text) {
    final m = reg.firstMatch(text);
    if (m == null || m.group(1) == null) return null;
    var val = m.group(1)!;
    val = val.replaceAll(r'\u0026', '&').replaceAll(r'\/', '/').replaceAll(r'\', '');
    return val;
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
        if (kDebugMode) debugPrint('[VixSrcScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final client = http.Client();
      try {
        final apiUrl = isTv
            ? '$_baseUrl/api/tv/$tmdbId/${season ?? 1}/${episode ?? 1}'
            : '$_baseUrl/api/movie/$tmdbId';

        final apiRes = await client.get(
          Uri.parse(apiUrl),
          headers: _headers,
        ).timeout(const Duration(seconds: 8));

        if (apiRes.statusCode != 200) return;
        final apiData = jsonDecode(apiRes.body);
        if (apiData is! Map || apiData['src'] == null) return;

        final rawEmbed = apiData['src'].toString();
        final embedUrl = rawEmbed.startsWith('http') ? rawEmbed : '$_baseUrl$rawEmbed';

        final embedRes = await client.get(
          Uri.parse(embedUrl),
          headers: _headers,
        ).timeout(const Duration(seconds: 8));

        if (embedRes.statusCode != 200) return;
        final html = embedRes.body;

        final token = _extract(RegExp(r'''token["']\s*:\s*["']([^"']+)'''), html);
        final expires = _extract(RegExp(r'''expires["']\s*:\s*["']([^"']+)'''), html);
        var playlist = _extract(RegExp(r'''url["']\s*:\s*["']([^"']+)'''), html);

        if (token == null || expires == null || playlist == null) return;

        if (playlist.startsWith('/')) {
          playlist = '$_baseUrl$playlist';
        }

        final lang = _extract(RegExp(r'''lang(?:uage)?["']\s*:\s*["']([a-z]{2,5})''', caseSensitive: false), html) ?? 'en';
        final delim = playlist.contains('?') ? '&' : '?';
        final rawMasterUrl = '$playlist${delim}token=$token&expires=$expires&h=1&lang=$lang';

        final isForeign = lang.isNotEmpty && lang.toLowerCase() != 'en';
        const langMap = {
          'es': 'Spanish',
          'fr': 'French',
          'de': 'German',
          'it': 'Italian',
          'ru': 'Russian',
          'ja': 'Japanese',
          'hi': 'Hindi',
        };
        final langName = langMap[lang.toLowerCase()] ?? lang.toUpperCase();
        final title = isForeign
            ? 'VixSrc · Master HLS · $langName · 1080p'
            : 'VixSrc · Master HLS · 1080p';
        final desc = isForeign
            ? 'VixSrc Master Stream · $langName'
            : 'VixSrc Master Stream';

        final reqHeaders = {
          ..._headers,
          'Referer': embedUrl,
        };

        yield StreamSource.zplayHttp(
          title: title,
          description: desc,
          url: rawMasterUrl,
          headers: reqHeaders,
        );
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[VixSrcScraper] error: $e');
    }
  }
}
