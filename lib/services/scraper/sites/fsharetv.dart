import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import '../../metadata/tmdb_service.dart';
import 'tmdb_helper.dart';

/// Pure-Dart FshareTV Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla FshareTV provider.
/// Resolves high-speed MP4 & HLS streams from fsharetv.cc.
class FshareTvScraper extends StreamScraper {
  @override
  String get name => 'ZPlayHTTP';

  static const _baseUrl = 'https://fsharetv.cc';
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static const _headers = {
    'User-Agent': _ua,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': '$_baseUrl/',
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
    if (type == 'tv' || type == 'series' || season != null) return;

    try {
      var resolvedImdbId = imdbId;

      if (resolvedImdbId == null || !resolvedImdbId.startsWith('tt')) {
        final tmdbId = await TmdbHelper.resolveTmdbId(
          imdbId: imdbId,
          title: title,
          type: 'movie',
          year: year,
        );

        // This fetch only bridges a TMDb id to an IMDb one. Without a key the
        // `?api_key=` request is malformed, so skip it rather than swallow the
        // failure and pretend the bridge is coming.
        if (tmdbId != null && TmdbService.hasScraperKey) {
          try {
            final uri = Uri.parse(
              'https://api.themoviedb.org/3/movie/$tmdbId?api_key=${TmdbService.scraperKey}',
            );
            final res = await http.get(uri).timeout(const Duration(seconds: 4));
            if (res.statusCode == 200) {
              final data = jsonDecode(res.body);
              if (data is Map && data['imdb_id'] != null) {
                resolvedImdbId = data['imdb_id'].toString();
              }
            }
          } catch (_) {}
        }
      }

      if (resolvedImdbId == null || !resolvedImdbId.startsWith('tt')) return;

      final client = http.Client();
      try {
        final pageRes = await client.get(
          Uri.parse('$_baseUrl/movie/$resolvedImdbId'),
          headers: _headers,
        ).timeout(const Duration(seconds: 8));

        if (pageRes.statusCode != 200) return;
        final html = pageRes.body;

        final match = RegExp(r'''href="(/w/[^"]+)"''').firstMatch(html);
        if (match == null || match.group(1) == null) return;
        final watchPath = match.group(1)!;

        final watchRes = await client.get(
          Uri.parse('$_baseUrl$watchPath'),
          headers: _headers,
        ).timeout(const Duration(seconds: 8));

        if (watchRes.statusCode != 200) return;
        final watchHtml = watchRes.body;

        final sidMatch = RegExp(r'''(?:source_id|file_id|setSource)[\s=:\('"]+([^'"\)]+)''', caseSensitive: false)
            .firstMatch(watchHtml);
        if (sidMatch == null || sidMatch.group(1) == null) return;
        final sourceId = sidMatch.group(1)!;

        final apiHeaders = {
          ..._headers,
          'Accept': 'application/json, */*; q=0.01',
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '$_baseUrl$watchPath',
        };

        final jsonRes = await client.get(
          Uri.parse('$_baseUrl/api/file/$sourceId/source?trailer=Png81APqcxU&type=watch'),
          headers: apiHeaders,
        ).timeout(const Duration(seconds: 8));

        if (jsonRes.statusCode != 200) return;
        final json = jsonDecode(jsonRes.body);
        if (json is! Map || json['status'] != 'ok') return;

        final groups = <List>[];
        if (json['data']?['file']?['sources'] is List) {
          groups.add(json['data']['file']['sources'] as List);
        }
        if (json['data']?['file']?['alternatives'] is List) {
          for (final g in json['data']['file']['alternatives'] as List) {
            if (g is List) groups.add(g);
          }
        }

        final seen = <String>{};
        for (final group in groups) {
          for (final item in group) {
            if (item is! Map || item['src'] == null) continue;
            final rawSrc = item['src'].toString();
            final srcUrl = rawSrc.startsWith('http') ? rawSrc : '$_baseUrl$rawSrc';
            if (seen.add(srcUrl)) {
              final quality = item['quality']?.toString() ?? '1080';
              final label = item['label']?.toString().trim() ?? '';
              final isHls = srcUrl.contains('.m3u8');

              final titleParts = [
                'FshareTV',
                if (label.isNotEmpty) label,
                '${quality}p',
              ];

              final descParts = [
                'FshareTV Stream',
                if (label.isNotEmpty) label,
                isHls ? 'HLS' : 'MP4',
              ];

              yield StreamSource(
                name: 'ZPlayHTTP',
                addonName: 'ZPlayHTTP',
                title: titleParts.join(' · '),
                description: descParts.join(' · '),
                url: srcUrl,
                headers: _headers,
                behaviorHints: {
                  'notWebReady': false,
                  'proxyHeaders': {
                    'request': _headers,
                  },
                },
              );
            }
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FshareTvScraper] error: $e');
    }
  }
}
