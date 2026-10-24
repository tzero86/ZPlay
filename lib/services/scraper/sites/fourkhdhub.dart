import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import '../../../utils/security/log_redaction.dart';

/// 1:1 port of webstreamr-0.69.1 src/source/FourKHDHub.ts
/// + src/source/hd-hub-helper.ts (resolveRedirectUrl)
class FourKHDHubScraper extends StreamScraper {
  @override
  String get name => 'ZPlayHTTP';

  final String _baseUrl = 'https://4khdhub.one';

  // Cached resolved base URL (memoized like the TS version, 1 hour)
  String? _resolvedBaseUrl;
  DateTime? _resolvedBaseUrlExpiry;

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  // ── getBaseUrl ──
  // Mirrors: private readonly getBaseUrl = async (ctx: Context): Promise<URL> => {
  //   return await this.fetcher.getFinalRedirectUrl(ctx, new URL(this.baseUrl));
  // };
  Future<String> _getBaseUrl() async {
    if (_resolvedBaseUrl != null &&
        _resolvedBaseUrlExpiry != null &&
        DateTime.now().isBefore(_resolvedBaseUrlExpiry!)) {
      return _resolvedBaseUrl!;
    }

    // getFinalRedirectUrl: HEAD request with maxRedirects: 0, follow Location headers
    var currentUrl = _baseUrl;
    for (int i = 0; i < 10; i++) {
      final request = http.Request('HEAD', Uri.parse(currentUrl));
      request.headers.addAll(_headers);
      request.followRedirects = false;

      final client = http.Client();
      try {
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 10));
        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers['location'];
          if (location != null && location.isNotEmpty) {
            // Resolve relative URLs
            currentUrl = Uri.parse(currentUrl).resolve(location).toString();
            continue;
          }
        }
        break;
      } catch (_) {
        break;
      } finally {
        client.close();
      }
    }

    // Extract origin (scheme + host)
    final uri = Uri.parse(currentUrl);
    _resolvedBaseUrl = '${uri.scheme}://${uri.host}';
    _resolvedBaseUrlExpiry = DateTime.now().add(const Duration(hours: 1));

    return _resolvedBaseUrl!;
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
    final sources = <StreamSource>[];
    print(
      '[4KHDHub] Starting scrape for title="$title", type=$type, year=$year, S${season}E$episode',
    );

    try {
      final pageUrl = await _fetchPageUrl(
        name: title,
        year: year,
        isSeries: type == 'series',
      );
      if (pageUrl == null) {
        print('[4KHDHub] No detail page URL found for "$title"');
        return sources;
      }

      print('[4KHDHub] Fetching detail page: ${redactUrl(pageUrl)}');
      final html = await _fetchText(pageUrl);
      final doc = html_parser.parse(html);

      if (type == 'series' && season != null && episode != null) {
        final seasonStr = season.toString().padLeft(2, '0');
        final episodeStr = episode.toString().padLeft(2, '0');

        for (final episodeItem in doc.querySelectorAll('.episode-item')) {
          final episodeTitleEl = episodeItem.querySelector('.episode-title');
          final episodeTitleText = episodeTitleEl?.text ?? '';
          if (!episodeTitleText.contains('S$seasonStr')) continue;

          dom.Element? downloadItem;
          for (final dl in episodeItem.querySelectorAll(
            '.episode-download-item',
          )) {
            if (dl.text.contains('Episode-$episodeStr')) {
              downloadItem = dl;
              break;
            }
          }
          if (downloadItem == null) continue;

          final srcs = await _extractSourceResults(downloadItem);
          sources.addAll(srcs);
        }
      } else {
        final items = doc.querySelectorAll('.download-item');
        print('[4KHDHub] Found ${items.length} download items on page');
        for (final dl in items) {
          final srcs = await _extractSourceResults(dl);
          sources.addAll(srcs);
        }
      }
    } catch (e, stack) {
      print('[4KHDHub ERROR] Scrape failed: ${redactTextUrls('$e')}\n$stack');
    }

    print(
      '[4KHDHub] Scrape completed. Found ${sources.length} active sources for "$title"',
    );
    return sources;
  }

  // ── fetchPageUrl ──
  Future<String?> _fetchPageUrl({
    required String name,
    int? year,
    required bool isSeries,
  }) async {
    try {
      final baseUrl = await _getBaseUrl();
      final searchUrl = '$baseUrl/?s=${Uri.encodeComponent(name)}';
      print('[4KHDHub] Searching ${redactUrl(searchUrl)}');
      final html = await _fetchText(searchUrl);
      final doc = html_parser.parse(html);

      final formatFilter = isSeries ? 'Series' : 'Movies';

      for (final card in doc.querySelectorAll('.movie-card')) {
        final formatEls = card.querySelectorAll('.movie-card-format');
        final formatTexts = formatEls.map((e) => e.text).toList();
        if (!formatTexts.any((t) => t.contains(formatFilter))) continue;

        if (year != null) {
          final metaEl = card.querySelector('.movie-card-meta');
          final metaText = metaEl?.text.trim() ?? '';
          final cardYear = int.tryParse(metaText);
          if (cardYear != null && (cardYear - year).abs() > 1) continue;
        }

        final titleEl = card.querySelector('.movie-card-title');
        var cardTitle = titleEl?.text ?? '';
        cardTitle = cardTitle.replaceAll(RegExp(r'\[.*?\]'), '').trim();

        final diff = _levenshtein(cardTitle.toLowerCase(), name.toLowerCase());
        final titleMatch =
            diff < 5 ||
            (cardTitle.toLowerCase().contains(name.toLowerCase()) && diff < 16);

        if (!titleMatch) continue;

        final href = card.attributes['href'];
        if (href == null) continue;

        final fullUrl = Uri.parse(baseUrl).resolve(href).toString();
        print(
          '[4KHDHub] Matched page card "$cardTitle" -> ${redactUrl(fullUrl)}',
        );
        return fullUrl;
      }
    } catch (e) {
      print('[4KHDHub ERROR] fetchPageUrl error: ${redactTextUrls('$e')}');
    }
    return null;
  }

  // ── extractSourceResults ──
  Future<List<StreamSource>> _extractSourceResults(dom.Element el) async {
    final sources = <StreamSource>[];
    try {
      final localHtml = el.innerHtml;

      final sizeMatch = RegExp(r'([\d.]+ ?[GM]B)').firstMatch(localHtml);
      final sizeStr = sizeMatch?.group(1);

      final heightMatch = RegExp(r'\d{3,}p').firstMatch(localHtml);
      final heightStr = heightMatch?.group(0);

      final titleEl =
          el.querySelector('.file-title') ??
          el.querySelector('.episode-file-title');
      final fileTitle = titleEl?.text.trim() ?? 'Unknown';

      final displayParts = <String>[fileTitle];
      if (heightStr != null) displayParts.add(heightStr);
      if (sizeStr != null) displayParts.add(sizeStr);

      String? hubCloudUrl;
      String? hubDriveUrl;

      for (final a in el.querySelectorAll('a')) {
        final text = a.text;
        final href = a.attributes['href'];
        if (href == null) continue;

        if (text.contains('HubCloud') && hubCloudUrl == null) {
          hubCloudUrl = href;
        } else if (text.contains('HubDrive') && hubDriveUrl == null) {
          hubDriveUrl = href;
        }
      }

      final redirectUrl = hubCloudUrl ?? hubDriveUrl;
      if (redirectUrl == null) return sources;

      try {
        print('[4KHDHub] Resolving redirect link: ${redactUrl(redirectUrl)}');
        final resolvedUrl = await _resolveRedirectUrl(redirectUrl);
        if (resolvedUrl != null) {
          final safeUrl = _sanitizeStreamUrl(resolvedUrl);
          // Perform quick stream health check to prevent 403 quota / HTML error pages from crashing player
          final isValid = await _validateStreamUrl(safeUrl);
          if (isValid) {
            print(
              '[4KHDHub SUCCESS] Added valid stream source: ${redactUrl(safeUrl)}',
            );
            sources.add(
              StreamSource(
                name: 'ZPlayHTTP',
                addonName: 'ZPlayHTTP',
                title: displayParts.join('\n'),
                url: safeUrl,
              ),
            );
          } else {
            print(
              '[4KHDHub FILTERED] Skipped invalid/quota-exceeded stream URL: ${redactUrl(safeUrl)}',
            );
          }
        }
      } catch (e) {
        print(
          '[4KHDHub ERROR] resolveRedirectUrl error: ${redactTextUrls('$e')}',
        );
      }
    } catch (e) {
      print('[4KHDHub ERROR] extract source error: ${redactTextUrls('$e')}');
    }
    return sources;
  }

  // ── Sanitize stream URL for FFmpeg/MDK compatibility ──
  String _sanitizeStreamUrl(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      final encodedPath = uri.path.replaceAll('::', '%3A%3A');
      return uri.replace(path: encodedPath).toString();
    } catch (_) {
      return rawUrl.replaceAll('::', '%3A%3A');
    }
  }

  // ── Validate stream URL health ──
  Future<bool> _validateStreamUrl(String url) async {
    try {
      final req = http.Request('GET', Uri.parse(url));
      req.headers.addAll(_headers);
      req.headers['Range'] = 'bytes=0-1024';

      final client = http.Client();
      final response = await client
          .send(req)
          .timeout(const Duration(seconds: 4));
      client.close();

      final contentType = (response.headers['content-type'] ?? '')
          .toLowerCase();
      final isSuccess =
          (response.statusCode >= 200 && response.statusCode < 300) ||
          response.statusCode == 206;
      final isHtmlOrJsonError =
          contentType.contains('text/html') ||
          contentType.contains('application/json');

      if (!isSuccess || isHtmlOrJsonError) {
        print(
          '[4KHDHub HEALTH CHECK] Stream URL returned HTTP ${response.statusCode} (content-type: $contentType) -> INVALID',
        );
        return false;
      }
      return true;
    } catch (e) {
      // If validation times out or fails network check, keep URL just in case
      return true;
    }
  }

  // ── resolveRedirectUrl ──
  // Mirrors: src/source/hd-hub-helper.ts
  // export const resolveRedirectUrl = async (ctx: Context, fetcher: Fetcher, redirectUrl: URL): Promise<URL> => {
  //   const redirectHtml = await fetcher.text(ctx, redirectUrl);
  //   const redirectDataMatch = redirectHtml.match(/'o','(.*?)'/) as string[];
  //   const redirectData = JSON.parse(atob(rot13Cipher(atob(atob(redirectDataMatch[1] as string))))) as { o: string };
  //   return new URL(atob(redirectData['o']));
  // };
  Future<String?> _resolveRedirectUrl(String redirectUrl) async {
    try {
      final html = await _fetchText(redirectUrl);

      // Look for the "Generate Direct Download Link" button or script var url
      var nextUrl = '';
      final downloadMatch = RegExp(
        r'<a id="download" href="(.*?)"',
      ).firstMatch(html);
      if (downloadMatch != null) {
        nextUrl = downloadMatch.group(1)!;
      } else {
        // Fallback to checking for the var url = '...'
        final varMatch = RegExp(r"var url = '(.*?)';").firstMatch(html);
        if (varMatch != null) {
          nextUrl = varMatch.group(1)!;
        }
      }

      if (nextUrl.isEmpty) {
        // Fallback to original obfuscated logic just in case older links still use it
        final match = RegExp(r"'o','(.*?)'").firstMatch(html);
        if (match == null) {
          print('4khdhub no redirect link found in html');
          return null;
        }
        final rawData = match.group(1)!;
        final step1 = utf8.decode(base64.decode(rawData));
        final step2 = utf8.decode(base64.decode(step1));
        final step3 = _rot13(step2);
        final step4 = utf8.decode(base64.decode(step3));
        final data = jsonDecode(step4) as Map<String, dynamic>;
        return utf8.decode(base64.decode(data['o'] as String));
      }

      // We found the intermediate gamerxyt.com URL, let's fetch it
      final intermediateHtml = await _fetchText(nextUrl);

      // Look for the final direct download button: class="btn btn-success ... Download File
      final finalLinkMatch = RegExp(
        r'<a href="([^"]+)"[^>]*class="[^"]*btn-success',
      ).firstMatch(intermediateHtml);
      if (finalLinkMatch != null) {
        return finalLinkMatch.group(1)!;
      }

      print('4khdhub final link not found in intermediate page');
      return null;
    } catch (e) {
      print('4khdhub resolveRedirectUrl error: ${redactTextUrls('$e')}');
      return null;
    }
  }

  // ── ROT13 cipher ──
  // Mirrors: rot13-cipher npm package
  String _rot13(String input) {
    return input.split('').map((char) {
      final code = char.codeUnitAt(0);
      if (code >= 65 && code <= 90) {
        // A-Z
        return String.fromCharCode(((code - 65 + 13) % 26) + 65);
      } else if (code >= 97 && code <= 122) {
        // a-z
        return String.fromCharCode(((code - 97 + 13) % 26) + 97);
      }
      return char;
    }).join();
  }

  // ── Levenshtein distance ──
  // Mirrors: fast-levenshtein npm package (with useCollator: true → case-insensitive)
  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final la = a.length;
    final lb = b.length;
    final d = List<List<int>>.generate(
      la + 1,
      (_) => List<int>.filled(lb + 1, 0),
    );

    for (int i = 0; i <= la; i++) {
      d[i][0] = i;
    }
    for (int j = 0; j <= lb; j++) {
      d[0][j] = j;
    }

    for (int i = 1; i <= la; i++) {
      for (int j = 1; j <= lb; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        d[i][j] = [
          d[i - 1][j] + 1, // deletion
          d[i][j - 1] + 1, // insertion
          d[i - 1][j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    return d[la][lb];
  }

  // ── HTTP helper ──
  Future<String> _fetchText(String url) async {
    final response = await http
        .get(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode} for $url');
    }

    return response.body;
  }
}
