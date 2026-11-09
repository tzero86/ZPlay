import 'dart:convert';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// MultiEmbed / 2embed VOD Extractor ported 1:1 from Flyx (multiembed.ts).
class MultiEmbedScraper extends HttpScraper {
  static const _embedBase = 'https://www.2embed.cc';
  static const _ua = kZplayUserAgent;

  static const _headers = {
    'User-Agent': _ua,
    'Referer': 'https://www.2embed.cc/',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
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
    print('[MultiEmbedScraper] Resolved tmdbId: $tmdbId for "$title" (year: $year, imdbId: $imdbId)');
    if (tmdbId == null) return sources;

    try {
      final isTv = (mediaType == 'tv');
      final s = season ?? 1;
      final e = episode ?? 1;

      final embedPath = isTv
          ? '/embedtv/$tmdbId&s=$s&e=$e'
          : ((imdbId != null && imdbId.startsWith('tt')) ? '/embed/$imdbId' : '/embed/$tmdbId');

      final embedRes = await http.get(Uri.parse('$_embedBase$embedPath'), headers: _headers).timeout(const Duration(seconds: 10));
      if (embedRes.statusCode != 200) return sources;

      final html = embedRes.body;

      // Extract server URLs from dropdown
      final onclickRegex = RegExp(r"onclick=\x22go\('([^']+)'\)\x22");
      final matches = onclickRegex.allMatches(html);

      final serverUrls = <String>[];
      for (final m in matches) {
        final url = m.group(1);
        if (url != null && url.startsWith('http')) {
          serverUrls.add(url);
        }
      }

      // Check data-src default server
      final datasrcMatch = RegExp(r'data-src="([^"]+)"').firstMatch(html);
      if (datasrcMatch != null) {
        final dUrl = datasrcMatch.group(1);
        if (dUrl != null && dUrl.startsWith('http') && !serverUrls.contains(dUrl)) {
          serverUrls.insert(0, dUrl);
        }
      }

      for (final sUrl in serverUrls) {
        if (sources.length >= 6) break;
        if (sUrl.contains('/xps')) {
          // XPS Chain: play.xpass.top -> playlist.json -> m3u8
          final uri = Uri.parse(sUrl);
          final pImdb = uri.queryParameters['imdb'] ?? imdbId ?? '';
          final pTmdb = uri.queryParameters['tmdb'] ?? tmdbId.toString();

          final xpsPageUrl = isTv
              ? 'https://play.xpass.top/e/tv/$pTmdb/$s/$e?autostart=true'
              : 'https://play.xpass.top/e/movie/$pImdb?autostart=true';

          try {
            final xpsRes = await http.get(Uri.parse(xpsPageUrl), headers: {
              'User-Agent': _ua,
              'Referer': 'https://streamsrcs.2embed.cc/',
            }).timeout(const Duration(seconds: 8));

            if (xpsRes.statusCode == 200) {
              final xpsHtml = xpsRes.body;
              final dataMatch = RegExp(r'var data\s*=\s*(\{.*?\});').firstMatch(xpsHtml);
              String? playlistPath;

              if (dataMatch != null) {
                try {
                  final dataObj = jsonDecode(dataMatch.group(1)!);
                  playlistPath = dataObj['playlist']?.toString();
                } catch (_) {}
              }

              playlistPath ??= RegExp(r'"playlist"\s*:\s*"([^"]+)"').firstMatch(xpsHtml)?.group(1);

              if (playlistPath != null && playlistPath.isNotEmpty) {
                final playlistUrl = playlistPath.startsWith('http')
                    ? playlistPath
                    : 'https://play.xpass.top${playlistPath.startsWith('/') ? '' : '/'}$playlistPath';

                final plRes = await http.get(Uri.parse(playlistUrl), headers: {
                  'User-Agent': _ua,
                  'Referer': xpsPageUrl,
                  'Origin': 'https://play.xpass.top',
                  'Accept': 'application/json,*/*',
                }).timeout(const Duration(seconds: 8));

                if (plRes.statusCode == 200) {
                  final plJson = jsonDecode(plRes.body);
                  final playlists = plJson['playlist'] as List?;
                  if (playlists != null) {
                    for (final plItem in playlists) {
                      final srcList = plItem['sources'] as List?;
                      if (srcList != null) {
                        for (final src in srcList) {
                          final file = src['file']?.toString();
                          if (file != null &&
                              file.startsWith('http') &&
                              !file.contains('/error') &&
                              !file.contains('.txt') &&
                              (file.contains('.m3u8') || file.contains('.mp4') || file.contains('/playlist/'))) {
                            final label = src['label']?.toString() ?? 'Auto';
                            sources.add(StreamSource(
                              name: 'ZPlayHTTP',
                              addonName: 'ZPlayHTTP',
                              title: '2embed XPS · $label',
                              description: '2embed Multi-CDN Stream',
                              url: file,
                              headers: {
                                'User-Agent': _ua,
                                'Referer': 'https://play.xpass.top/',
                              },
                            ));
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      print('MultiEmbedScraper error: $e');
    }

    print('[MultiEmbedScraper] Found ${sources.length} active stream(s)');
    return sources;
  }
}
