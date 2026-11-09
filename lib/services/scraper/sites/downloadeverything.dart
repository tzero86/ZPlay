import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// DownloadEverything Stream Scraper & Inside Extractor for ZPlayHTTP.
///
/// Connects to slave.downloadeverythingfromeverywhere.com and resolves
/// streamable direct links from high-speed CDNs (Cloudflare R2, Pixeldrain,
/// Moviebox/HakunaMatata, ClicknUpload, and HubCloud).
class DownloadEverythingScraper extends HttpScraper {
  static const _slaveUrl = 'https://slave.downloadeverythingfromeverywhere.com/';
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36';

  static const _defaultHeaders = {
    'User-Agent': _ua,
    'Origin': 'https://downloadeverythingfromeverywhere.com',
    'Referer': 'https://downloadeverythingfromeverywhere.com/',
    'Content-Type': 'application/json',
  };

  @override
  Stream<StreamSource> scrapeStream({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) {
    final controller = StreamController<StreamSource>();
    final isTv = (type == 'series' || type == 'tv');
    final mediaType = isTv ? 'tv' : 'movie';

    () async {
      try {
        final tmdbId = await TmdbHelper.resolveTmdbId(
          imdbId: imdbId,
          title: title,
          type: mediaType,
          year: year,
        );

        print('[DownloadEverything] Starting scrape for "$title" (tmdb: $tmdbId, imdb: $imdbId, year: $year, S:${season}E:$episode)');

        final payload = <String, dynamic>{
          'mode': isTv ? 'series' : 'movie',
          'title': title,
          if (year != null) 'year': year.toString(),
          if (tmdbId != null) 'tmdb_id': tmdbId,
          if (imdbId != null && imdbId.isNotEmpty) 'imdb_id': imdbId,
          if (isTv && season != null) 'season': season,
          if (isTv && episode != null) 'episode': episode,
        };

        final request = http.Request('POST', Uri.parse(_slaveUrl))
          ..headers.addAll(_defaultHeaders)
          ..body = jsonEncode(payload);

        final client = http.Client();
        final streamedResponse = await client.send(request).timeout(const Duration(seconds: 15));

        const lineSplitter = LineSplitter();
        final stringStream = streamedResponse.stream.transform(utf8.decoder);

        final activeResolutions = <Future<void>>[];
        int totalHitsFound = 0;

        await for (final line in stringStream.transform(lineSplitter)) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          try {
            final parsed = jsonDecode(trimmed);
            if (parsed is Map<String, dynamic> && parsed['t'] == 'hit' && parsed['links'] is List) {
              final site = parsed['site']?.toString() ?? 'DownloadEverything';
              final links = parsed['links'] as List;
              totalHitsFound += links.length;
              print('[DownloadEverything] Hit from site "$site": ${links.length} candidate(s)');

              for (final l in links) {
                if (l is Map<String, dynamic>) {
                  final item = {'site': site, ...l};
                  final fut = _resolveItem(item, title, isTv, season, episode).then((source) {
                    if (source != null && !controller.isClosed) {
                      print('[DownloadEverything] [+] Playable stream extracted: ${source.title}');
                      controller.add(source);
                    }
                  }).catchError((_) {});
                  activeResolutions.add(fut);
                }
              }
            }
          } catch (_) {}
        }

        if (activeResolutions.isNotEmpty) {
          await Future.wait(activeResolutions);
        }

        print('[DownloadEverything] Completed stream for "$title" (total candidates inspected: $totalHitsFound)');
      } catch (e) {
        print('[DownloadEverything] Error: $e');
      } finally {
        if (!controller.isClosed) {
          controller.close();
        }
      }
    }();

    return controller.stream;
  }

  @override
  Future<List<StreamSource>> scrape({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async {
    return scrapeStream(
      type: type,
      title: title,
      year: year,
      season: season,
      episode: episode,
      imdbId: imdbId,
    ).toList();
  }

  Future<StreamSource?> _resolveItem(
    Map<String, dynamic> item,
    String fallbackTitle,
    bool isTv,
    int? season,
    int? episode,
  ) async {
    final rawUrl = item['url']?.toString() ?? '';
    if (rawUrl.isEmpty) return null;

    // Skip known unstreamable / blocked / challenge domains
    if (rawUrl.contains('111477.xyz') ||
        rawUrl.contains('vadapav.mov') ||
        rawUrl.contains('driveseed.org') ||
        rawUrl.contains('new3.gdflix.io') ||
        rawUrl.contains('rapidrar.cr') ||
        rawUrl.contains('megaup.net') ||
        rawUrl.contains('telegram.dog') ||
        rawUrl.contains('t.me')) {
      return null;
    }

    String? directStreamUrl;
    String provider = item['site']?.toString() ?? 'DownloadEverything';
    Map<String, String>? streamHeaders;

    try {
      // 1. Moviebox / HakunaMatata direct streams
      if (rawUrl.contains('hakunaymatata.com')) {
        directStreamUrl = rawUrl;
        provider = 'Moviebox';
        streamHeaders = {'User-Agent': 'Lavf/60.16.100'};
      }
      // 2. Pixeldrain Direct API
      else if (rawUrl.contains('pixeldrain.dev') || rawUrl.contains('pixeldrain.com')) {
        final m = RegExp(r'pixeldrain\.(?:dev|com)\/(?:u|l)\/([a-zA-Z0-9_-]+)').firstMatch(rawUrl);
        if (m != null) {
          directStreamUrl = 'https://pixeldrain.com/api/file/${m.group(1)}';
          provider = 'Pixeldrain';
          streamHeaders = {'User-Agent': _ua};
        }
      }
      // 3. HubCloud Inside Resolver (Cloudflare R2 Direct S3 Signed Stream)
      else if (rawUrl.contains('hubcloud.') || rawUrl.contains('vcloud.zip')) {
        directStreamUrl = await _resolveHubCloud(rawUrl);
        if (directStreamUrl != null) {
          provider = 'HubCloud';
          streamHeaders = {'User-Agent': _ua};
        }
      }
      // 4. ClicknUpload Inside Form Resolver
      else if (rawUrl.contains('clicknupload.')) {
        directStreamUrl = await _resolveClicknUpload(rawUrl);
        if (directStreamUrl != null) {
          provider = 'ClicknUpload';
          streamHeaders = {'User-Agent': _ua};
        }
      }
      // 5. Direct MP4 / MKV Streams (Tattooin, Vikingfile, etc.)
      else if (RegExp(r'\.(?:mp4|mkv)(?:\?|$)', caseSensitive: false).hasMatch(rawUrl) &&
          !rawUrl.contains('111477.xyz') &&
          !rawUrl.contains('vadapav.mov') &&
          !rawUrl.contains('.cyou/res/')) {
        // Quick verification to ensure stream is online and not 404
        try {
          final check = await http.head(
            Uri.parse(rawUrl),
            headers: {'User-Agent': _ua},
          ).timeout(const Duration(milliseconds: 1500));
          if (check.statusCode == 200 || check.statusCode == 206 || check.statusCode == 302) {
            directStreamUrl = rawUrl;
            provider = item['site']?.toString() ?? 'DirectStream';
            streamHeaders = {'User-Agent': _ua};
          }
        } catch (_) {}
      }
    } catch (_) {}

    if (directStreamUrl == null || directStreamUrl.isEmpty) return null;

    final tags = (item['tags'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final qualityMatch = tags.firstWhere(
      (t) => RegExp(r'2160p|4k|1080p|720p|480p', caseSensitive: false).hasMatch(t),
      orElse: () => '1080p',
    );

    final rawTitle = item['name']?.toString() ?? item['release']?.toString() ?? fallbackTitle;
    final tagsStr = tags.isNotEmpty ? tags.join(' · ') : qualityMatch;

    return StreamSource(
      name: 'ZPlayHTTP',
      addonName: 'ZPlayHTTP',
      title: '[$provider] $rawTitle ($qualityMatch)',
      description: '$qualityMatch · $tagsStr · $provider',
      url: directStreamUrl,
      headers: streamHeaders ?? {'User-Agent': _ua},
    );
  }

  /// Extracts direct Cloudflare R2 / S3 signed stream link from HubCloud.
  Future<String?> _resolveHubCloud(String hubUrl) async {
    try {
      final res1 = await http.get(
        Uri.parse(hubUrl),
        headers: {'User-Agent': _ua, 'Referer': 'https://downloadeverythingfromeverywhere.com/'},
      ).timeout(const Duration(seconds: 8));

      String html = res1.body;
      if (res1.isRedirect || res1.statusCode == 301 || res1.statusCode == 302) {
        final loc = res1.headers['location'];
        if (loc != null) {
          final resRedirect = await http.get(Uri.parse(loc), headers: {'User-Agent': _ua});
          html = resRedirect.body;
        }
      }

      final hubPhpMatch = RegExp(r'https?://[^\s"<>]*/hubcloud\.php\?[^\s"<>]*').firstMatch(html);
      if (hubPhpMatch != null) {
        final phpUrl = hubPhpMatch.group(0)!;
        final phpRes = await http.get(
          Uri.parse(phpUrl),
          headers: {'User-Agent': _ua, 'Referer': hubUrl},
        ).timeout(const Duration(seconds: 8));

        final phpBody = phpRes.body;

        // Check for Cloudflare R2 signed link
        final r2Match = RegExp(r'https?://[a-zA-Z0-9.\-_]+\.r2\.cloudflarestorage\.com/[^\s"<>]+').firstMatch(phpBody);
        if (r2Match != null) {
          return r2Match.group(0)!.replaceAll('&amp;', '&');
        }

        // Check for Pixel mirror link
        final pixelMatch = RegExp(r'https?://pixel\.hubcloud\.[a-z]+/\?id=[^\s"<>]+').firstMatch(phpBody);
        if (pixelMatch != null) {
          return pixelMatch.group(0)!;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Resolves direct stream link from ClicknUpload through automated form submit.
  Future<String?> _resolveClicknUpload(String clicknUrl) async {
    try {
      final res1 = await http.get(
        Uri.parse(clicknUrl),
        headers: {'User-Agent': _ua, 'Referer': 'https://downloadeverythingfromeverywhere.com/'},
      ).timeout(const Duration(seconds: 8));

      final formMatch = RegExp(r'<form[^>]+method=["\x27]POST["\x27][^>]*>([\s\S]*?)</form>', caseSensitive: false)
          .firstMatch(res1.body);
      if (formMatch == null) return null;

      final formBody = formMatch.group(1)!;
      final inputMatches = RegExp(r'<input[^>]+name=["\x27]([^"\x27]+)["\x27][^>]+value=["\x27]([^"\x27]*)["\x27]', caseSensitive: false)
          .allMatches(formBody);

      final params1 = <String, String>{};
      for (final m in inputMatches) {
        params1[m.group(1)!] = m.group(2)!;
      }
      params1['method_free'] = 'Slow Download';

      final cookies = res1.headers['set-cookie'] ?? '';

      final res2 = await http.post(
        Uri.parse(clicknUrl),
        headers: {
          'User-Agent': _ua,
          'Referer': clicknUrl,
          'Content-Type': 'application/x-www-form-urlencoded',
          if (cookies.isNotEmpty) 'Cookie': cookies,
        },
        body: params1,
      ).timeout(const Duration(seconds: 8));

      final formMatch2 = RegExp(r'<form[^>]+method=["\x27]POST["\x27][^>]*>([\s\S]*?)</form>', caseSensitive: false)
          .firstMatch(res2.body);
      if (formMatch2 == null) return null;

      final inputMatches2 = RegExp(r'<input[^>]+name=["\x27]([^"\x27]+)["\x27][^>]+value=["\x27]([^"\x27]*)["\x27]', caseSensitive: false)
          .allMatches(formMatch2.group(1)!);

      final params2 = <String, String>{};
      for (final m in inputMatches2) {
        params2[m.group(1)!] = m.group(2)!;
      }
      params2['down_script'] = '1';

      await Future.delayed(const Duration(milliseconds: 4500));

      final res3 = await http.post(
        Uri.parse(clicknUrl),
        headers: {
          'User-Agent': _ua,
          'Referer': clicknUrl,
          'Content-Type': 'application/x-www-form-urlencoded',
          if (cookies.isNotEmpty) 'Cookie': cookies,
        },
        body: params2,
      ).timeout(const Duration(seconds: 8));

      final directMatch = RegExp(r'https?://[a-zA-Z0-9.\-_:]+/d/[a-zA-Z0-9_\-/]+').firstMatch(res3.body) ??
          RegExp(r'window\.open\(["\x27](https?://[^"\x27]+)["\x27]\)').firstMatch(res3.body);

      if (directMatch != null) {
        final found = directMatch.group(1) ?? directMatch.group(0)!;
        if (found.contains('clicknupload.') && !found.contains('/d/')) {
          return null;
        }
        return found;
      }
    } catch (_) {}
    return null;
  }
}
