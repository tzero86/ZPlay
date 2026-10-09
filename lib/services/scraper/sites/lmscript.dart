import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart LMScript Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla LMScript provider.
/// Resolves movies from lmscript.xyz.
class LMScriptScraper extends StreamScraper {
  @override
  String get name => 'ZPlayHTTP';

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

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
      final tmdbId = await TmdbHelper.resolveTmdbId(
        imdbId: imdbId,
        title: title,
        type: 'movie',
        year: year,
      );

      final client = http.Client();
      try {
        final url = 'https://lmscript.xyz/v1/movies?filters[q]=${Uri.encodeComponent(title)}&expand=streams';
        final res = await client.get(
          Uri.parse(url),
          headers: {'User-Agent': _ua, 'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode != 200) return;
        final data = jsonDecode(res.body);
        if (data is! Map || data['items'] is! List) return;

        final items = data['items'] as List;
        Map? movie;

        if (tmdbId != null) {
          movie = items.firstWhere(
            (it) => it is Map && ('${it['tmdb_prefix']}' == '$tmdbId' || '${it['tmdb_id']}' == '$tmdbId'),
            orElse: () => null,
          );
        }

        movie ??= items.firstWhere(
          (it) => it is Map && it['title']?.toString().toLowerCase() == title.toLowerCase(),
          orElse: () => null,
        );

        if (movie == null || movie['streams'] is! Map) return;
        final streams = movie['streams'] as Map;

        for (final entry in streams.entries) {
          final quality = entry.key.toString();
          final streamUrl = entry.value?.toString();
          if (streamUrl == null || streamUrl.isEmpty) continue;

          final isHls = streamUrl.contains('.m3u8');
          final headers = {'User-Agent': _ua};

          yield StreamSource(
            name: 'ZPlayHTTP',
            addonName: 'ZPlayHTTP',
            title: 'LMScript · $quality',
            description: 'LMScript Stream · ${isHls ? 'HLS' : 'MP4'}',
            url: streamUrl,
            headers: headers,
            behaviorHints: {
              'notWebReady': false,
              'proxyHeaders': {
                'request': headers,
              },
            },
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[LMScriptScraper] error: $e');
    }
  }
}
