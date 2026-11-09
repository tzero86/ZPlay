import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// Pure-Dart Purstream Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla Purstream provider.
/// Searches and queries api.purstream.club directly for multi-source streams.
class PurstreamScraper extends HttpScraper {
  static const _domain = 'https://purstream.club';
  static const _apiBase = 'https://api.purstream.club/api/v1';
  static const _ua = kZplayUserAgent;

  static const _headers = {
    'User-Agent': _ua,
    'Accept': 'application/json, text/plain, */*',
    'Referer': '$_domain/',
    'Origin': _domain,
    'X-Requested-With': 'XMLHttpRequest',
    'Sec-Fetch-Dest': 'empty',
    'Sec-Fetch-Mode': 'cors',
    'Sec-Fetch-Site': 'same-site',
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
      final client = http.Client();
      try {
        final searchUrl = '$_apiBase/search-bar/search/${Uri.encodeComponent(title)}';
        final searchRes = await client.get(
          Uri.parse(searchUrl),
          headers: _headers,
        ).timeout(const Duration(seconds: 8));

        if (searchRes.statusCode != 200) return;
        final searchData = jsonDecode(searchRes.body);
        if (searchData is! Map) return;

        final items = searchData['data']?['items']?['movies']?['items'];
        if (items is! List || items.isEmpty) return;

        final lowerTitle = title.toLowerCase();
        Map? match;

        for (final item in items) {
          if (item is! Map) continue;
          final itemType = item['type']?.toString();
          final itemTitle = item['title']?.toString().toLowerCase();
          final releaseDate = item['release_date']?.toString();

          if (itemType == mediaType && itemTitle == lowerTitle) {
            if (year == null || (releaseDate != null && releaseDate.startsWith(year.toString()))) {
              match = item;
              break;
            }
          }
        }

        match ??= items.firstWhere(
          (it) => it is Map && it['type']?.toString() == mediaType,
          orElse: () => null,
        );

        if (match == null || match['id'] == null) return;
        final matchId = match['id'].toString();

        final streamUrl = isTv
            ? '$_apiBase/stream/$matchId/episode?season=${season ?? 1}&episode=${episode ?? 1}'
            : '$_apiBase/stream/$matchId';

        final streamRes = await client.get(
          Uri.parse(streamUrl),
          headers: _headers,
        ).timeout(const Duration(seconds: 8));

        if (streamRes.statusCode != 200) return;
        final sJson = jsonDecode(streamRes.body);
        if (sJson is! Map || sJson['type'] != 'success') return;

        final sources = sJson['data']?['items']?['sources'];
        if (sources is! List || sources.isEmpty) return;

        for (final src in sources) {
          if (src is! Map) continue;
          final sUrl = src['stream_url']?.toString();
          if (sUrl == null || sUrl.isEmpty) continue;

          final rawName = src['source_name']?.toString() ?? 'Purstream';
          final cleanName = rawName
              .replaceAll(RegExp(r'^\s*\|\s*'), '')
              .replaceAll(RegExp(r'\s*\|\s*'), ' · ')
              .trim();
          final sQuality = src['quality']?.toString() ?? 'Auto';
          final titleQuality = (sQuality != 'Auto' && !cleanName.contains(sQuality))
              ? ' · $sQuality'
              : '';
          final streamTitle = 'Purstream · $cleanName$titleQuality';

          final reqHeaders = {
            'User-Agent': _ua,
            'Referer': '$_domain/',
          };

          yield StreamSource.zplayHttp(
            title: streamTitle,
            description: 'Purstream Multi-Audio HLS Stream',
            url: sUrl,
            headers: reqHeaders,
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[PurstreamScraper] error: $e');
    }
  }
}
