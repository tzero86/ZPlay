import 'dart:convert';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// VidCore VOD Extractor ported 1:1 from Flyx (vidcore.ts).
///
/// Fetches multi-server m3u8 streams via www.vidcore.org / vidcore.org API.
class VidCoreScraper extends HttpScraper {
  static const List<String> _apiBases = [
    'https://www.vidcore.org',
    'https://vidcore.org',
  ];

  static const _ua = kZplayUserAgent;

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

    try {
      final mediaType = (type == 'series' || type == 'tv') ? 'tv' : 'movie';
      final tmdbId = await TmdbHelper.resolveTmdbId(imdbId: imdbId, title: title, type: mediaType, year: year);
      print('[VidCoreScraper] Resolved tmdbId: $tmdbId for "$title" (year: $year, imdbId: $imdbId)');
      if (tmdbId == null) return sources;

      final seenUrls = <String>{};
      final skipped = <String>{};

      for (final base in _apiBases) {
        final params = <String, String>{
          'id': tmdbId.toString(),
          'type': mediaType,
          if (mediaType == 'tv' && season != null) 'season': season.toString(),
          if (mediaType == 'tv' && episode != null) 'episode': episode.toString(),
        };

        final initialData = await _fetchSourcesRound(base, params);
        if (initialData == null || initialData['sources'] == null) continue;

        final initialSources = initialData['sources'] as List;
        _extractAndAdd(initialSources, base, sources, seenUrls, skipped);

        // Perform skip rounds to collect additional servers (up to 4 rounds)
        for (int round = 1; round < 4 && skipped.length < 12; round++) {
          final p2 = Map<String, String>.from(params);
          if (skipped.isNotEmpty) {
            p2['skip'] = skipped.join(',');
          }

          final roundData = await _fetchSourcesRound(base, p2);
          if (roundData == null || roundData['sources'] == null) break;
          final roundSources = roundData['sources'] as List;
          if (roundSources.isEmpty) break;

          _extractAndAdd(roundSources, base, sources, seenUrls, skipped);
        }

        if (sources.isNotEmpty) break;
      }
    } catch (e) {
      print('VidCoreScraper error: $e');
    }

    print('[VidCoreScraper] Found ${sources.length} active stream(s)');
    return sources;
  }

  Future<Map<String, dynamic>?> _fetchSourcesRound(String base, Map<String, String> params) async {
    try {
      final uri = Uri.parse('$base/api/sources').replace(queryParameters: params);
      final res = await http.get(uri, headers: {
        'User-Agent': _ua,
        'Referer': '$base/embed/movie/${params['id'] ?? ''}',
        'Origin': base,
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  void _extractAndAdd(
    List outerSources,
    String apiBase,
    List<StreamSource> sources,
    Set<String> seenUrls,
    Set<String> skipped,
  ) {
    for (final o in outerSources) {
      if (o is! Map) continue;
      final label = o['label']?.toString() ?? o['provider']?.toString() ?? o['server']?.toString() ?? 'VidCore';
      if (o['label'] != null) skipped.add(o['label'].toString());

      List inners = [];
      if (o['data'] is Map && o['data']['sources'] is List) {
        inners = o['data']['sources'];
      } else if (o['sources'] is List) {
        inners = o['sources'];
      } else if (o['url'] != null) {
        inners = [o];
      }

      for (final s in inners) {
        if (s is! Map) continue;
        final url = s['url']?.toString();
        if (url == null || url.isEmpty || seenUrls.contains(url)) continue;
        if (!url.startsWith('http')) continue;

        seenUrls.add(url);
        final quality = s['quality']?.toString() ?? o['quality']?.toString() ?? 'Auto';
        final isHls = url.contains('.m3u8');
        final isDash = url.contains('.mpd');

        sources.add(StreamSource(
          name: 'ZPlayHTTP',
          addonName: 'ZPlayHTTP',
          title: 'VidCore $label · $quality',
          description: isHls ? 'VidCore Direct HLS Stream' : (isDash ? 'VidCore Direct DASH Stream' : 'VidCore Direct VOD Stream'),
          url: url,
          headers: {
            'User-Agent': _ua,
            'Referer': '$apiBase/',
          },
        ));
      }
    }
  }
}
