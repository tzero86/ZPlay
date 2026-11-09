import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// FlyStream VOD Extractor ported to pure Dart.
///
/// Extracts high-speed multi-quality HLS streams (1080p, 4K HEVC) directly
/// from flystream.net API.
class FlyStreamScraper extends HttpScraper {
  static const _apiBase = 'https://flystream.net';
  static const _ua = kZplayUserAgent;

  static const _headers = {
    'User-Agent': _ua,
    'Referer': 'https://flystream.net/',
    'Accept': 'application/json',
  };

  @override
  Future<List<StreamSource>> scrape({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async {
    final sources = <StreamSource>[];
    final mediaType = (type == 'series' || type == 'tv') ? 'tv' : 'movie';

    final tmdbId = await TmdbHelper.resolveTmdbId(imdbId: imdbId, title: title, type: mediaType, year: year);
    print('[FlyStreamScraper] Resolved tmdbId: $tmdbId for "$title" (year: $year, imdbId: $imdbId)');

    try {
      final isTv = (mediaType == 'tv');
      final randomViewer = List.generate(32, (_) => math.Random().nextInt(16).toRadixString(16)).join();

      final params = <String, String>{
        'type': isTv ? 'tv' : 'movie',
        'viewerId': randomViewer,
        'title': title,
        if (tmdbId != null) 'tmdbId': tmdbId.toString(),
        if (imdbId != null && imdbId.isNotEmpty) 'imdb': imdbId,
        if (year != null) 'year': year.toString(),
        if (isTv && season != null) 'season': season.toString(),
        if (isTv && episode != null) 'episode': episode.toString(),
      };

      final uri = Uri.parse('$_apiBase/api/streams').replace(queryParameters: params);
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final streams = data['streams'] as List?;

        if (streams != null && streams.isNotEmpty) {
          for (final s in streams) {
            if (s is! Map) continue;
            final rawUrl = s['url']?.toString();
            if (rawUrl == null || rawUrl.isEmpty) continue;
            final url = rawUrl.startsWith('/') ? '$_apiBase$rawUrl' : rawUrl;
            if (!url.startsWith('http')) continue;

            final quality = s['quality']?.toString() ?? 'Auto';
            final codec = s['videoCodec']?.toString() ?? '';
            final size = s['size']?.toString();
            final name = s['name']?.toString() ?? s['title']?.toString() ?? title;

            final descDetails = [
              if (quality.isNotEmpty) quality,
              if (codec.isNotEmpty) codec.toUpperCase(),
              if (size != null && size.isNotEmpty) size,
            ].join(' · ');

            sources.add(StreamSource(
              name: 'ZPlayHTTP',
              addonName: 'ZPlayHTTP',
              title: 'FlyStream $name',
              description: descDetails.isNotEmpty ? 'FlyStream $descDetails' : 'FlyStream Direct HLS Stream',
              url: url,
              headers: {
                'User-Agent': _ua,
                'Referer': 'https://flystream.net/',
              },
            ));
          }
        }
      }
    } catch (e) {
      print('FlyStreamScraper error: $e');
    }

    print('[FlyStreamScraper] Found ${sources.length} active stream(s)');
    return sources;
  }
}
