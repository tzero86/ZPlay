import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart FlaxMovies Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla FlaxMovies provider.
/// Resolves multi-CDN streams (Airflix, Cinevaro, Vaplayer, Vidnest Alfa).
class FlaxMoviesScraper extends HttpScraper {
  static const _baseUrl = 'https://flaxmovies.xyz';
  static const _ua = kZplayUserAgent;

  static const _defaultWorkers = [
    'https://freakyniki.elaxo.lol',
    'https://vidlove.nabilekson.workers.dev',
  ];

  static const _headers = {
    'User-Agent': _ua,
    'Referer': '$_baseUrl/',
    'Origin': _baseUrl,
    'Accept': 'application/json, text/plain, */*',
  };

  Future<List<String>> _getWorkerUrls(http.Client client, String embedUrl) async {
    final foundUrls = <String>[];

    try {
      final res = await client.get(
        Uri.parse(embedUrl),
        headers: {
          'User-Agent': _ua,
          'Referer': '$_baseUrl/',
          'Origin': _baseUrl,
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final html = res.body;

        final directMatch = RegExp(r'''WORKER_URL\s*[:=]\s*["'](https?://[^"']+)["']''', caseSensitive: false)
            .firstMatch(html);
        if (directMatch != null && directMatch.group(1) != null) {
          final wUrl = directMatch.group(1)!.replaceAll(RegExp(r'/+$'), '');
          if (!foundUrls.contains(wUrl)) foundUrls.add(wUrl);
        }

        final scriptMatches = RegExp(r'''<script[^>]+src=["']([^"']+)["']''', caseSensitive: false)
            .allMatches(html);

        for (final sm in scriptMatches) {
          var scriptUrl = sm.group(1);
          if (scriptUrl == null) continue;

          if (scriptUrl.startsWith('//')) {
            scriptUrl = 'https:$scriptUrl';
          } else if (scriptUrl.startsWith('/')) {
            scriptUrl = '$_baseUrl$scriptUrl';
          } else if (!scriptUrl.startsWith('http')) {
            scriptUrl = '$_baseUrl/$scriptUrl';
          }

          if (scriptUrl.contains('jsdelivr') ||
              scriptUrl.contains('google') ||
              scriptUrl.contains('cloudflare')) {
            continue;
          }

          try {
            final sRes = await client.get(
              Uri.parse(scriptUrl),
              headers: {'User-Agent': _ua, 'Referer': embedUrl},
            ).timeout(const Duration(seconds: 5));

            if (sRes.statusCode == 200) {
              final m = RegExp(r'''WORKER_URL\s*[:=]\s*["'](https?://[^"']+)["']''', caseSensitive: false)
                  .firstMatch(sRes.body);
              if (m != null && m.group(1) != null) {
                final wUrl = m.group(1)!.replaceAll(RegExp(r'/+$'), '');
                if (!foundUrls.contains(wUrl)) foundUrls.add(wUrl);
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    for (final d in _defaultWorkers) {
      if (!foundUrls.contains(d)) foundUrls.add(d);
    }
    return foundUrls;
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

    try {
      final tmdbId = await TmdbHelper.resolveTmdbId(
        imdbId: imdbId,
        title: title,
        type: isTv ? 'tv' : 'movie',
        year: year,
      );

      if (tmdbId == null) {
        if (kDebugMode) debugPrint('[FlaxMoviesScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final client = http.Client();
      try {
        final embedUrl = isTv
            ? '$_baseUrl/embed/tv/$tmdbId/${season ?? 1}/${episode ?? 1}'
            : '$_baseUrl/embed/movie/$tmdbId';

        final workerUrls = await _getWorkerUrls(client, embedUrl);

        final query = isTv
            ? 'tmdb_id=$tmdbId&tmdbId=$tmdbId&season=${season ?? 1}&episode=${episode ?? 1}'
            : 'tmdb_id=$tmdbId&tmdbId=$tmdbId';

        var foundStreams = false;

        for (final worker in workerUrls) {
          try {
            final url = '$worker/?$query';
            final res = await client.get(
              Uri.parse(url),
              headers: _headers,
            ).timeout(const Duration(seconds: 10));

            if (res.statusCode != 200) continue;

            final data = jsonDecode(res.body);
            if (data is! Map || data['streams'] is! List) continue;

            final streams = data['streams'] as List;
            if (streams.isEmpty) continue;

            for (final st in streams) {
              if (st is! Map) continue;
              final streamUrl = st['url']?.toString();
              if (streamUrl == null || streamUrl.isEmpty) continue;

              final provider = st['provider']?.toString() ?? 'CDN';
              final resolution = st['resolution']?.toString() ?? '1080p';

              final streamHeaders = {
                'User-Agent': _ua,
                'Referer': '$_baseUrl/',
                'Origin': _baseUrl,
              };

              yield StreamSource.zplayHttp(
                title: 'FlaxMovies · $provider · $resolution',
                description: 'FlaxMovies Multi-CDN Stream · $resolution',
                url: streamUrl,
                headers: streamHeaders,
              );
              foundStreams = true;
            }

            if (foundStreams) break;
          } catch (_) {}
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FlaxMoviesScraper] scrapeStream error: $e');
    }
  }
}
