import 'dart:convert';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// VidSrc / VSEmbed VOD Extractor ported 1:1 from Flyx (vidsrc.ts).
class VidSrcScraper extends HttpScraper {
  static const _apiBase = 'https://data.vidsrcme.ru';
  static const _embedBase = 'https://vidsrc.me';
  static const _ua = kZplayUserAgent;

  static const _headers = {
    'User-Agent': _ua,
    'Referer': 'https://cloudorchestranova.com/',
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
    print('[VidSrcScraper] Resolved tmdbId: $tmdbId for "$title" (year: $year, imdbId: $imdbId)');
    if (tmdbId == null) return sources;

    try {
      final isTv = (mediaType == 'tv');
      final params = <String, String>{
        'type': isTv ? 'tv' : 'movie',
        'tmdb': tmdbId.toString(),
        'stream_urls': '',
      };

      if (isTv) {
        if (season != null) params['season'] = season.toString();
        if (episode != null) params['episode'] = episode.toString();
      }

      final uri = Uri.parse('$_apiBase/api.php').replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['status_code']?.toString() == '200' && json['data'] != null) {
          final rawStreamUrls = json['data']['stream_urls'];
          if (rawStreamUrls is List) {
            for (int i = 0; i < rawStreamUrls.length; i++) {
              final url = rawStreamUrls[i].toString().trim();
              if (url.isEmpty || !url.startsWith('http')) continue;
              final isHls = url.contains('.m3u8');

              sources.add(StreamSource(
                name: 'ZPlayHTTP',
                addonName: 'ZPlayHTTP',
                title: rawStreamUrls.length > 1 ? 'VidSrc ${i + 1}' : 'VidSrc',
                description: isHls ? 'VidSrc Direct HLS Stream' : 'VidSrc Direct Stream Source',
                url: url,
                headers: {
                  'User-Agent': _ua,
                  'Referer': 'https://cloudorchestranova.com/',
                },
              ));
            }
          }
        }
      }

      // Fallback: Query VidSrc Embed Page directly
      if (sources.isEmpty) {
        final embedUrl = isTv
            ? '$_embedBase/embed/tv/$tmdbId/${season ?? 1}/${episode ?? 1}'
            : '$_embedBase/embed/movie/$tmdbId';

        final embedRes = await http.get(Uri.parse(embedUrl), headers: {
          'User-Agent': _ua,
          'Referer': 'https://vidsrc.me/',
        }).timeout(const Duration(seconds: 8));

        if (embedRes.statusCode == 200) {
          final html = embedRes.body;
          final m3u8Matches = RegExp(r'https?:\/\/[^"\x27\s]+\.m3u8[^"\x27\s]*').allMatches(html);
          for (final m in m3u8Matches) {
            final url = m.group(0);
            if (url != null && url.startsWith('http')) {
              sources.add(StreamSource(
                name: 'ZPlayHTTP',
                addonName: 'ZPlayHTTP',
                title: 'VidSrc Direct',
                description: 'VidSrc Direct HLS Stream',
                url: url,
                headers: {
                  'User-Agent': _ua,
                  'Referer': 'https://vidsrc.me/',
                },
              ));
            }
          }
        }
      }
    } catch (e) {
      print('VidSrcScraper error: $e');
    }

    print('[VidSrcScraper] Found ${sources.length} active stream(s)');
    return sources;
  }
}
