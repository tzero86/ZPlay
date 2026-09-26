import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import '../../metadata/tmdb_service.dart';
import 'tmdb_helper.dart';

/// Pure-Dart Nova Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla Nova provider.
/// Connects to nova-streamz.vercel.app Stremio manifest endpoints.
class NovaScraper extends StreamScraper {
  @override
  String get name => 'ZPlayHTTP';

  static const _baseUrl = 'https://nova-streamz.vercel.app';
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
    final isTv = (type == 'tv' || type == 'series');

    try {
      var resolvedImdbId = imdbId;

      if (resolvedImdbId == null || !resolvedImdbId.startsWith('tt')) {
        final tmdbId = await TmdbHelper.resolveTmdbId(
          imdbId: imdbId,
          title: title,
          type: isTv ? 'tv' : 'movie',
          year: year,
        );

        // This fetch only bridges a TMDb id to an IMDb one. Without a key the
        // `?api_key=` request is malformed, so skip it rather than swallow the
        // failure and pretend the bridge is coming.
        if (tmdbId != null && TmdbService.hasScraperKey) {
          try {
            final uri = Uri.parse(
              isTv
                  ? 'https://api.themoviedb.org/3/tv/$tmdbId/external_ids?api_key=${TmdbService.scraperKey}'
                  : 'https://api.themoviedb.org/3/movie/$tmdbId?api_key=${TmdbService.scraperKey}',
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
        final path = isTv
            ? '/stream/series/$resolvedImdbId:${season ?? 1}:${episode ?? 1}.json'
            : '/stream/movie/$resolvedImdbId.json';

        final res = await client.get(
          Uri.parse('$_baseUrl$path'),
          headers: {'User-Agent': _ua, 'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode != 200) return;
        final data = jsonDecode(res.body);
        if (data is! Map || data['streams'] is! List) return;

        final streams = data['streams'] as List;
        for (final st in streams) {
          if (st is! Map) continue;
          final streamUrl = st['url']?.toString();
          if (streamUrl == null || streamUrl.isEmpty) continue;

          final stName = (st['name']?.toString() ?? 'Nova').replaceAll('Nova ', '');
          final rawTitle = st['title']?.toString();
          final stTitle = rawTitle != null && rawTitle.contains(' | ')
              ? rawTitle.replaceAll(' | ', ' · ')
              : (rawTitle ?? '');
          final titleLabel = stTitle.isNotEmpty ? '$stName · $stTitle' : stName;

          Map<String, String>? reqHeaders;
          if (st['behaviorHints'] is Map &&
              st['behaviorHints']['proxyHeaders'] is Map &&
              st['behaviorHints']['proxyHeaders']['request'] is Map) {
            reqHeaders = (st['behaviorHints']['proxyHeaders']['request'] as Map)
                .map((k, v) => MapEntry(k.toString(), v.toString()));
          }

          yield StreamSource(
            name: 'ZPlayHTTP',
            addonName: 'ZPlayHTTP',
            title: 'Nova · $titleLabel',
            description: 'Nova Multi-Source Stream',
            url: streamUrl,
            headers: reqHeaders,
            behaviorHints: {
              'notWebReady': false,
              if (reqHeaders != null)
                'proxyHeaders': {
                  'request': reqHeaders,
                },
            },
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[NovaScraper] scrapeStream error: $e');
    }
  }
}
