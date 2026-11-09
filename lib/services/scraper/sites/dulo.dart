import 'dart:async';
import 'package:flutter/foundation.dart';
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';
import 'dulo_client.dart';

/// Pure-Dart Dulo Stream Scraper for ZPlayHTTP.
/// Extracts direct HLS (m3u8) streams for Movies and TV shows.
class DuloScraper extends HttpScraper {
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
        if (kDebugMode) debugPrint('[DuloScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final stream = isTv
          ? DuloClient.instance.getTvStreams(tmdbId, season ?? 1, episode ?? 1)
          : DuloClient.instance.getMovieStreams(tmdbId);

      await for (final s in stream) {
        final headers = DuloClient.instance.playbackHeaders;
        final qualityLabel = s.quality.isNotEmpty && s.quality != 'Auto' ? s.quality : '1080p';
        final titleLabel = s.title.isNotEmpty ? s.title : 'Stream';

        yield StreamSource.zplayHttp(
          title: 'Dulo · $titleLabel · $qualityLabel',
          description: 'Dulo Multi-CDN HLS Stream · $qualityLabel',
          url: s.url,
          headers: headers,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[DuloScraper] scrapeStream error: $e');
    }
  }
}
