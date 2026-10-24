import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import '../../../utils/security/log_redaction.dart';

/// HindMoviez Stream Scraper for ZPlayHTTP.
///
/// Scrapes Bollywood, Hindi Dubbed/Dual-Audio, and Hollywood movies and TV series
/// from hindmovie.icu via mvlink.blog and hshare.ink solver pipelines.
class HindMoviezScraper extends StreamScraper {
  @override
  String get name => 'ZPlayHTTP';

  @override
  String get providerId => 'hindmoviez';

  @override
  String get providerName => 'HindMoviez';

  static const String _baseUrl = 'https://hindmovie.icu';
  static const String _defaultUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static const Map<String, String> _defaultHeaders = {
    'User-Agent': _defaultUa,
    'Accept': 'application/json, text/html, */*',
  };

  // Cached splash cookie for hshare.ink
  static String? _cachedSplashCookie;
  static DateTime? _cachedSplashCookieExpiry;

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

    () async {
      try {
        final cleanTitle = _getCleanTitle(title);
        debugPrint('[HindMoviez] Starting scrape for title="$cleanTitle", type=$type, year=$year, S${season}E$episode, imdb=$imdbId');

        // 1. Search WP-JSON
        List<Map<String, dynamic>> posts = [];
        if (imdbId != null && imdbId.isNotEmpty && imdbId.startsWith('tt')) {
          posts = await _searchWPJson(imdbId);
        }
        if (posts.isEmpty && cleanTitle.isNotEmpty) {
          posts = await _searchWPJson(cleanTitle);
        }

        if (posts.isEmpty) {
          debugPrint('[HindMoviez] No posts found for "$title"');
          controller.close();
          return;
        }

        // 2. Match post
        Map<String, dynamic>? matchedPost;
        if (imdbId != null && imdbId.isNotEmpty) {
          for (final post in posts) {
            final content = post['content']?['rendered']?.toString() ?? '';
            if (content.contains(imdbId)) {
              debugPrint('[HindMoviez] Matched post via IMDB ID: ${post['title']?['rendered']}');
              matchedPost = post;
              break;
            }
          }
        }

        if (matchedPost == null) {
          for (final post in posts) {
            final postTitle = post['title']?['rendered']?.toString() ?? '';
            final postYear = _extractYear(postTitle);
            if (_isStrictMatch(title, year, postTitle, postYear)) {
              debugPrint('[HindMoviez] Matched post via strict title match: $postTitle');
              matchedPost = post;
              break;
            }
          }
        }

        if (matchedPost == null && posts.isNotEmpty) {
          // Relaxed match
          final targetClean = _getCleanTitle(title);
          for (final post in posts) {
            final postTitle = post['title']?['rendered']?.toString() ?? '';
            final pClean = _getCleanTitle(postTitle);
            if (pClean.contains(targetClean) || targetClean.contains(pClean)) {
              debugPrint('[HindMoviez] Matched post via relaxed title match: $postTitle');
              matchedPost = post;
              break;
            }
          }
        }

        if (matchedPost == null) {
          debugPrint('[HindMoviez] No matching post found for "$title"');
          controller.close();
          return;
        }

        var contentHtml = matchedPost['content']?['rendered']?.toString() ?? '';
        final postTitleRendered = matchedPost['title']?['rendered']?.toString() ?? title;

        // 3. Extract Season HTML for TV
        if (isTv && season != null) {
          final seasonHtml = _extractSeasonHtml(contentHtml, season);
          if (seasonHtml.isNotEmpty) {
            contentHtml = seasonHtml;
          }
        }

        // 4. Extract MvLink links
        final mvlinkRegex = RegExp(r'href="(https?:\/\/mvlink\.blog\/(?:web\/)?\d+)"', caseSensitive: false);
        final mvMatches = mvlinkRegex.allMatches(contentHtml).toList();

        if (mvMatches.isEmpty) {
          debugPrint('[HindMoviez] No mvlink.blog links found in matched post');
          controller.close();
          return;
        }

        final mvLinks = <Map<String, String>>[];
        for (final m in mvMatches) {
          final url = m.group(1)!;
          final startIdx = (m.start - 500).clamp(0, m.start);
          final precedingContext = contentHtml.substring(startIdx, m.start);
          final quality = _parseQuality(precedingContext);
          if (quality == '480p') {
            continue; // Skip 480p as in original provider
          }
          mvLinks.add({'url': url, 'quality': quality});
        }

        debugPrint('[HindMoviez] Found ${mvLinks.length} valid MvLink items');

        final seenStreamUrls = <String>{};

        // Concurrently resolve all MvLinks for progressive stream discovery
        await Future.wait(
          mvLinks.map((mv) => _processMvlink(
            mvlinkUrl: mv['url']!,
            referer: '$_baseUrl/',
            quality: mv['quality']!,
            isTv: isTv,
            season: season,
            episode: episode,
            targetTitle: postTitleRendered,
            onSourceFound: (src) {
              if (src.url != null && !seenStreamUrls.contains(src.url)) {
                seenStreamUrls.add(src.url!);
                if (!controller.isClosed) {
                  controller.add(src);
                }
              }
            },
          )),
        );
      } catch (e, stack) {
        debugPrint('[HindMoviez] Global scrape error: $e\n$stack');
      } finally {
        if (!controller.isClosed) {
          controller.close();
        }
      }
    }();

    return controller.stream;
  }

  // ── WP-JSON Search ──
  Future<List<Map<String, dynamic>>> _searchWPJson(String query) async {
    try {
      final url = '$_baseUrl/wp-json/wp/v2/posts?search=${Uri.encodeComponent(query)}&per_page=100';
      final res = await http.get(Uri.parse(url), headers: _defaultHeaders).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
    } catch (e) {
      debugPrint('[HindMoviez] searchWPJson error: $e');
    }
    return [];
  }

  // ── Title Cleaning & Matching ──
  static String _getCleanTitle(String raw) {
    var s = raw.toLowerCase();
    s = s.replaceAll('download', '');
    s = s.replaceAll(RegExp(r'\b(dual audio|multi audio|hindi|english|tamil|telugu|malayalam|korean|japanese|chinese|spanish|french|italian|german)\b'), '');
    s = s.replaceAll(RegExp(r'\b(480p|720p|1080p|2160p|4k|2k|hd|fhd|uhd)\b'), '');
    s = s.replaceAll(RegExp(r'\b(web-?dl|web-?dlrip|web-?rip|brrip|bdrip|bluray|blu-?ray|hdtv|tvrip|dvdrip|camrip|hdrip)\b'), '');
    s = s.replaceAll(RegExp(r'\b(x264|x265|hevc|10bit|12bit|aac|ac3|dd5\.1|ddp5\.1|atmos|dts)\b'), '');
    s = s.replaceAll(RegExp(r'\b(season|saison|staffel)\s*\d+(?:\s*(?:-|to)\s*\d+)?\b'), '');
    s = s.replaceAll(RegExp(r'\bs\d+(?:\s*(?:-|to)\s*\d+)?\b'), '');
    s = s.replaceAll(RegExp(r'\b(episode|episodes|ep)\s*\d+(?:\s*(?:-|to)\s*\d+)?\s*(added|update|updated)?\b'), '');
    s = s.replaceAll(RegExp(r'\b(complete|all episodes|pack|batch)\b'), '');
    s = s.replaceAll(RegExp(r'\b(movie|film|part\s*\d+|vol\s*\d+|volume\s*\d+)\b'), '');
    s = s.replaceAll(RegExp(r'\b(unrated|extended|directors cut|uncut|18)\b'), '');
    s = s.replaceAll(RegExp(r'\b(19\d{2}|20\d{2})\b'), '');
    s = s.replaceAll(RegExp(r'[^a-z0-9]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'^(the|a|an)\s+'), '');
    return s;
  }

  static int? _extractYear(String s) {
    final m = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(s);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  static bool _isStrictMatch(String targetTitle, int? targetYear, String postTitle, int? postYear) {
    final c1 = _getCleanTitle(targetTitle);
    final c2 = _getCleanTitle(postTitle);
    if (c1.isEmpty || c2.isEmpty) return false;
    if (c1 == c2) return true;
    if (targetYear != null && postYear != null) {
      if ((targetYear - postYear).abs() > 1) return false;
    }
    return c1.startsWith(c2) || c2.startsWith(c1);
  }

  static String _extractSeasonHtml(String html, int season) {
    final seasonRegex = RegExp(r'(?:Season|Saison|Staffel)\s+0*(\d+)\b', caseSensitive: false);
    final matches = seasonRegex.allMatches(html).toList();
    if (matches.isEmpty) return html;

    final seasonsFound = <Map<String, dynamic>>[];
    for (final m in matches) {
      var startIdx = html.lastIndexOf('<', m.start);
      if (startIdx < 0 || m.start - startIdx > 500) {
        startIdx = m.start;
      }
      final tagPrefix = html.substring(startIdx, (m.start + 50).clamp(0, html.length)).toLowerCase();
      if (tagPrefix.contains('download') || tagPrefix.contains('episode')) continue;

      final sNum = int.tryParse(m.group(1)!);
      if (sNum != null) {
        seasonsFound.add({'season': sNum, 'index': startIdx});
      }
    }

    final matched = seasonsFound.where((e) => e['season'] == season).toList();
    if (matched.isEmpty) return html;

    final startIndex = matched.first['index'] as int;
    int endIndex = html.length;
    for (final s in seasonsFound) {
      final sIdx = s['index'] as int;
      if (sIdx > startIndex && s['season'] != season) {
        endIndex = sIdx;
        break;
      }
    }

    return html.substring(startIndex, endIndex);
  }

  static String _parseQuality(String context) {
    final c = context.toLowerCase();
    if (c.contains('2160p') || c.contains('4k') || c.contains('uhd')) return '2160p';
    if (c.contains('1440p') || c.contains('2k')) return '1440p';
    if (c.contains('1080p') || c.contains('fhd')) return '1080p';
    if (c.contains('720p') || c.contains('hd')) return '720p';
    if (c.contains('480p') || c.contains('sd')) return '480p';
    return '1080p';
  }

  // ── Process MvLink page ──
  Future<List<StreamSource>> _processMvlink({
    required String mvlinkUrl,
    required String referer,
    required String quality,
    required bool isTv,
    int? season,
    int? episode,
    required String targetTitle,
    void Function(StreamSource)? onSourceFound,
  }) async {
    final sources = <StreamSource>[];
    try {
      debugPrint('[HindMoviez] Fetching MvLink: $mvlinkUrl');
      final res = await http.get(
        Uri.parse(mvlinkUrl),
        headers: {'User-Agent': _defaultUa, 'Referer': referer},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        debugPrint('[HindMoviez] MvLink status ${res.statusCode} for $mvlinkUrl');
        return sources;
      }
      final mvHtml = res.body;

      final hshareRegex = RegExp(r'href="(?:https:\/\/hshare\.ink\/\?id=([^"]+)|https:\/\/hshare\.ink\/dl\/([^"]+))"', caseSensitive: false);
      final matches = hshareRegex.allMatches(mvHtml);

      final hshareIds = <String>[];
      for (final m in matches) {
        final id = m.group(1) ?? m.group(2);
        if (id != null && id.isNotEmpty) {
          hshareIds.add(Uri.decodeComponent(id));
        }
      }

      debugPrint('[HindMoviez] Found ${hshareIds.length} HShare IDs in $mvlinkUrl');
      if (hshareIds.isEmpty) return sources;

      if (isTv && episode != null) {
        // Fast path for TV shows
        final epIdx = episode - 1;
        if (epIdx >= 0 && epIdx < hshareIds.length) {
          debugPrint('[HindMoviez] Fast-path episode $episode at index $epIdx');
          final stream = await _resolveHShare(
            hshareId: hshareIds[epIdx],
            mvlinkUrl: mvlinkUrl,
            quality: quality,
            isTv: isTv,
            season: season,
            episode: episode,
            targetTitle: targetTitle,
            onSourceFound: onSourceFound,
          );
          if (stream.isNotEmpty) {
            sources.addAll(stream);
            return sources;
          }
        }
      }

      // Process IDs
      for (final id in hshareIds) {
        debugPrint('[HindMoviez] Resolving HShare ID: $id');
        final stream = await _resolveHShare(
          hshareId: id,
          mvlinkUrl: mvlinkUrl,
          quality: quality,
          isTv: isTv,
          season: season,
          episode: episode,
          targetTitle: targetTitle,
          onSourceFound: onSourceFound,
        );
        sources.addAll(stream);
        if (sources.isNotEmpty && !isTv) {
          break; // Stop after first successful quality stream for movie
        }
      }
    } catch (e) {
      debugPrint('[HindMoviez] processMvlink error: $e');
    }
    return sources;
  }

  // ── Resolve HShare ID -> Stream Sources ──
  Future<List<StreamSource>> _resolveHShare({
    required String hshareId,
    required String mvlinkUrl,
    required String quality,
    required bool isTv,
    int? season,
    int? episode,
    required String targetTitle,
    void Function(StreamSource)? onSourceFound,
  }) async {
    final sources = <StreamSource>[];
    try {
      // 1. Bypass via admin-ajax.php
      final rUrl = await _bypassHShareAPI(hshareId, mvlinkUrl);
      debugPrint('[HindMoviez] Bypassed HShare API -> rUrl: $rUrl');
      if (rUrl == null || rUrl.isEmpty) return sources;

      // 2. Fetch r.php and solve challenge if needed
      final downloadHtml = await _fetchRPageWithBypass(rUrl, mvlinkUrl);
      debugPrint('[HindMoviez] Download HTML length: ${downloadHtml?.length}');
      if (downloadHtml == null || downloadHtml.isEmpty) return sources;

      // 3. Extract direct file name
      final nameMatch = RegExp(r'Name:\s*([^<]+)', caseSensitive: false).firstMatch(downloadHtml);
      final rawFileName = nameMatch?.group(1)?.trim();

      // 4. Extract hcloud.ink links
      final hcloudRegex = RegExp(r'href="([^"]+hcloud\.ink[^"]+)"', caseSensitive: false);
      final hcloudMatches = hcloudRegex.allMatches(downloadHtml).toList();
      debugPrint('[HindMoviez] Found ${hcloudMatches.length} hcloud links');

      int serverNum = 1;
      for (final hm in hcloudMatches) {
        final hcloudUrl = hm.group(1)!;
        debugPrint('[HindMoviez] Resolving hcloud URL: $hcloudUrl');
        final directUrl = await _resolveHCloudUrl(hcloudUrl, rUrl);
        debugPrint('[HindMoviez] Resolved direct stream: $directUrl');
        if (directUrl != null && directUrl.isNotEmpty) {
          final serverLabel = 'Server $serverNum';
          final source = _buildStreamSource(
            url: directUrl,
            quality: quality,
            rawFileName: rawFileName,
            targetTitle: targetTitle,
            isTv: isTv,
            season: season,
            episode: episode,
            serverLabel: serverLabel,
          );
          sources.add(source);
          onSourceFound?.call(source);
          serverNum++;
        }
      }
    } catch (e) {
      debugPrint('[HindMoviez] resolveHShare error: $e');
    }
    return sources;
  }

  // ── Bypass HShare API via admin-ajax.php ──
  Future<String?> _bypassHShareAPI(String hshareId, String mvlinkUrl) async {
    try {
      final b64 = base64Url.encode(utf8.encode(hshareId)).replaceAll('=', '');
      final res = await http.post(
        Uri.parse('https://mvlink.blog/wp-admin/admin-ajax.php'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer': mvlinkUrl,
          'X-Requested-With': 'XMLHttpRequest',
          'User-Agent': _defaultUa,
        },
        body: 'action=hindshare_sign&d=${Uri.encodeQueryComponent(b64)}',
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json is Map && json['success'] == true && json['data'] is Map) {
          return json['data']['url']?.toString();
        }
      }
    } catch (e) {
      debugPrint('[HindMoviez] bypassHShareAPI error: $e');
    }
    return null;
  }

  // ── Fetch r.php with Cookie / Anti-Bot Solver ──
  Future<String?> _fetchRPageWithBypass(String rUrl, String referer) async {
    try {
      // 1. Try with cached cookie if available
      if (_cachedSplashCookie != null &&
          _cachedSplashCookieExpiry != null &&
          DateTime.now().isBefore(_cachedSplashCookieExpiry!)) {
        final cachedRes = await _getWithCookieAndRedirects(
          url: rUrl,
          referer: referer,
          cookie: _cachedSplashCookie,
        );

        if (cachedRes != null && cachedRes.statusCode == 200 && !cachedRes.body.contains('wsidchk')) {
          return cachedRes.body;
        }
      }

      // 2. Initial request (follow redirects false, without cookie)
      debugPrint('[HindMoviez] Fetching rUrl: $rUrl');
      final initialRes = await _getWithCookieAndRedirects(
        url: rUrl,
        referer: referer,
      );

      if (initialRes != null && initialRes.statusCode == 200) {
        if (!initialRes.body.contains('wsidchk')) {
          return initialRes.body;
        }
        // Needs challenge solution!
        debugPrint('[HindMoviez] Solving Wallarm splash challenge...');
        return await _solveHShareChallenge(rUrl, initialRes.body, referer);
      }
    } catch (e) {
      debugPrint('[HindMoviez] fetchRPage error: $e');
    }
    return null;
  }

  // ── Solve Wallarm Anti-Bot Splash Challenge ──
  Future<String?> _solveHShareChallenge(String rUrl, String html, String referer) async {
    try {
      // 1. Extract U array
      final uMatch = RegExp(r'var\s+U\s*=\s*\[(.*?)\];', dotAll: true).firstMatch(html);
      if (uMatch == null) return null;
      final rawU = uMatch.group(1)!;
      final u = RegExp(r"'([^']*)'").allMatches(rawU).map((m) => m.group(1)!).toList();

      // 2. Extract rotation target 'r' from IIFE: }(a0w, 0x2fe00));
      final rotMatch = RegExp(r'\}\(a0w\s*,\s*(0x[0-9a-fA-F]+|\d+)\)\);').firstMatch(html);
      if (rotMatch == null) return null;
      final targetR = int.parse(rotMatch.group(1)!);

      // 3. Extract offset base: e = e - 0x15f;
      final baseMatch = RegExp(r'e\s*=\s*e\s*-\s*(0x[0-9a-fA-F]+|\d+);').firstMatch(html);
      if (baseMatch == null) return null;
      final baseOffset = int.parse(baseMatch.group(1)!);

      // 4. Extract mapping object: var a0q={D:0x186,r:0x180,w:0x192,e:0x187}
      final mapMatch = RegExp(r'var\s+([a-zA-Z0-9_]+)\s*=\s*\{([^}]+)\}\s*,\s*a\s*=\s*a0e').firstMatch(html);
      final a0qMap = <String, int>{};
      if (mapMatch != null) {
        for (final pair in mapMatch.group(2)!.split(',')) {
          final parts = pair.split(':');
          if (parts.length == 2) {
            a0qMap[parts[0].trim()] = int.parse(parts[1].trim());
          }
        }
      }

      // 5. Extract while loop expression
      final exprMatch = RegExp(r'var\s+e\s*=\s*([^;]+);\s*if\s*\(\s*e\s*===\s*r\s*\)').firstMatch(html);
      if (exprMatch == null) return null;
      final exprStr = exprMatch.group(1)!;

      int parseIntLeading(String s) {
        final m = RegExp(r'^-?\d+').firstMatch(s);
        return m != null ? int.parse(m.group(0)!) : 0;
      }

      String a(int code) {
        final idx = code - baseOffset;
        if (idx < 0 || idx >= u.length) return '';
        return u[idx];
      }

      num evalTerm(String term) {
        final mults = term.split('*');
        num termVal = 1.0;
        for (final mult in mults) {
          final mTrim = mult.trim();
          final isNeg = mTrim.startsWith('(-') || mTrim.startsWith('-');
          final callMatch = RegExp(r'a\((0x[0-9a-fA-F]+|[a-zA-Z0-9_]+\.[a-zA-Z0-9_]+)\)').firstMatch(mTrim);
          int code = 0;
          if (callMatch != null) {
            final arg = callMatch.group(1)!;
            if (arg.contains('.')) {
              final prop = arg.split('.')[1];
              code = a0qMap[prop] ?? 0;
            } else {
              code = int.parse(arg);
            }
          }
          final strVal = a(code);
          final intVal = parseIntLeading(strVal);

          final divMatch = RegExp(r'/\s*(0x[0-9a-fA-F]+|\d+)').firstMatch(mTrim);
          final divisor = divMatch != null ? int.parse(divMatch.group(1)!) : 1;

          num partVal = intVal / divisor;
          if (isNeg) partVal = -partVal;
          termVal *= partVal;
        }
        return termVal;
      }

      // Rotate U until while condition holds
      final terms = exprStr.replaceAll('+-', '-').split('+');
      int iterations = 0;
      while (iterations < 200) {
        num sum = 0;
        for (final t in terms) {
          if (t.contains('-') && !t.contains('(-')) {
            final sub = t.split('-');
            sum += evalTerm(sub[0]);
            for (var i = 1; i < sub.length; i++) {
              if (sub[i].isNotEmpty) sum -= evalTerm(sub[i]);
            }
          } else {
            sum += evalTerm(t);
          }
        }
        if (sum.round() == targetR) break;
        u.add(u.removeAt(0));
        iterations++;
      }

      // Extract a0G mapping
      final a0gMatch = RegExp(r'var\s+([a-zA-Z0-9_]+)\s*=\s*\{([^}]+)\}\s*;\s*setTimeout\s*\(\s*function\s*\(\)\s*\{').firstMatch(html);
      final a0gMap = <String, int>{};
      if (a0gMatch != null) {
        for (final pair in a0gMatch.group(2)!.split(',')) {
          final parts = pair.split(':');
          if (parts.length == 2) {
            a0gMap[parts[0].trim()] = int.parse(parts[1].trim());
          }
        }
      }

      // 6. Calculate r and x digits
      int parseDigits(String expr) {
        final parts = expr.split(RegExp(r'\)\s*\+\s*\('));
        var s = '';
        for (final p in parts) {
          final count = RegExp(r'!\+\[\]|!!\[\]').allMatches(p).length;
          s += count.toString();
        }
        return int.tryParse(s) ?? 0;
      }

      final rDigitsMatch = RegExp(r'r=\+\(([\s\S]*?)\),\s*w=').firstMatch(html);
      final xDigitsMatch = RegExp(r'x=\+\(([\s\S]*?)\),\s*s=').firstMatch(html);
      if (rDigitsMatch == null || xDigitsMatch == null) return null;

      final rVal = parseDigits(rDigitsMatch.group(1)!);
      final xVal = parseDigits(xDigitsMatch.group(1)!);
      final wsidchk = (rVal + xVal).toString();

      // 7. Extract W (action)
      final wActionMatch = RegExp(r"W\s*=\s*'(\/[a-zA-Z0-9]+)'").firstMatch(html);
      if (wActionMatch == null) return null;
      final actionPath = wActionMatch.group(1)!;

      // 8. Extract P (pdata)
      final pDataMatch = RegExp(r"P\s*=\s*'([^']+)'").firstMatch(html);
      if (pDataMatch == null) return null;
      final pdata = pDataMatch.group(1)!;

      // 9. Extract ts
      final tsMatch = RegExp(r"'ts'\s*,\s*'(\d+)'").firstMatch(html) ??
          RegExp(r"'ts'\s*,\s*[^=]+(?:'value'|L\([^)]+\))\s*=\s*'(\d+)'").firstMatch(html) ??
          RegExp(r"E\[L\([^)]+\)\]\s*=\s*'(\d+)'").firstMatch(html);
      final ts = tsMatch?.group(1) ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

      // 10. Extract id
      final idStmtMatch = RegExp(r"o\['value'\]\s*=\s*([^;,]+)[;,]").firstMatch(html);
      String idVal = '';
      if (idStmtMatch != null) {
        final pieces = idStmtMatch.group(1)!.split('+');
        for (final piece in pieces) {
          final pTrim = piece.trim();
          if (pTrim.startsWith("'") && pTrim.endsWith("'")) {
            idVal += pTrim.substring(1, pTrim.length - 1);
          } else {
            final lMatch = RegExp(r'L\((0x[0-9a-fA-F]+|[a-zA-Z0-9_]+\.[a-zA-Z0-9_]+)\)').firstMatch(pTrim);
            if (lMatch != null) {
              final arg = lMatch.group(1)!;
              int code = 0;
              if (arg.contains('.')) {
                code = a0gMap[arg.split('.')[1]] ?? 0;
              } else {
                code = int.parse(arg);
              }
              idVal += a(code);
            }
          }
        }
      }

      // 11. Send Challenge GET Request
      final challengeUrl = 'https://hshare.ink$actionPath?wsidchk=$wsidchk&pdata=$pdata&id=$idVal&ts=$ts&cttl=0';
      debugPrint('[HindMoviez] Submitting challenge GET: $challengeUrl');

      final client = http.Client();
      try {
        final chalReq = http.Request('GET', Uri.parse(challengeUrl))
          ..followRedirects = false
          ..headers.addAll({
            'User-Agent': _defaultUa,
            'Referer': rUrl,
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          });
        final chalStreamed = await client.send(chalReq).timeout(const Duration(seconds: 10));
        final chalRes = await http.Response.fromStream(chalStreamed);

        final cookieHeader = chalRes.headers['set-cookie'];
        final locationHeader = chalRes.headers['location'];
        debugPrint('[HindMoviez] Challenge response: status=${chalRes.statusCode}, location=${redactUrl(locationHeader)}, set-cookie=${cookieHeader != null}');

        String? cookie;
        if (cookieHeader != null) {
          cookie = cookieHeader.split(';').first;
          _cachedSplashCookie = cookie;
          _cachedSplashCookieExpiry = DateTime.now().add(const Duration(minutes: 50));
        }

        final finalTarget = locationHeader != null
            ? (locationHeader.startsWith('http') ? locationHeader : 'https://hshare.ink$locationHeader')
            : rUrl;

        debugPrint('[HindMoviez] Fetching unlocked target with redirects: ${redactUrl(finalTarget)} (cookie present: ${cookie != null})');
        final finalRes = await _getWithCookieAndRedirects(
          url: finalTarget,
          referer: rUrl,
          cookie: cookie,
        );

        if (finalRes != null && finalRes.statusCode == 200) {
          debugPrint('[HindMoviez] Unlocked page response: status=${finalRes.statusCode}, length=${finalRes.body.length}, has hcloud=${finalRes.body.contains('hcloud')}');
          return finalRes.body;
        }
      } finally {
        client.close();
      }
    } catch (e, stack) {
      debugPrint('[HindMoviez] solveHShareChallenge error: $e\n$stack');
      return null;
    }
    return null;
  }

  // ── Manual redirect follower preserving Cookie header ──
  Future<http.Response?> _getWithCookieAndRedirects({
    required String url,
    required String referer,
    String? cookie,
    int maxHops = 5,
  }) async {
    final client = http.Client();
    try {
      var currentUrl = url;
      for (int hop = 0; hop < maxHops; hop++) {
        final req = http.Request('GET', Uri.parse(currentUrl))
          ..followRedirects = false
          ..headers.addAll({
            'User-Agent': _defaultUa,
            'Referer': referer,
            if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
          });
        final streamed = await client.send(req).timeout(const Duration(seconds: 10));
        final res = await http.Response.fromStream(streamed);
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers['location'] != null) {
          currentUrl = Uri.parse(currentUrl).resolve(res.headers['location']!).toString();
          continue;
        }
        return res;
      }
    } catch (e) {
      debugPrint('[HindMoviez] _getWithCookieAndRedirects error: $e');
    } finally {
      client.close();
    }
    return null;
  }

  // ── Resolve HCloud.ink URL ──
  Future<String?> _resolveHCloudUrl(String hcloudUrl, String referer) async {
    try {
      final uri = Uri.parse(hcloudUrl);
      final rawParam = uri.queryParameters['url'];
      if (rawParam == null) return null;

      final decoded = utf8.decode(base64.decode(base64.normalize(rawParam)));
      if (decoded.startsWith('http')) {
        if (decoded.contains('.workers.dev') || decoded.contains('.powerly.dev')) {
          return _appendTimestamp(decoded);
        }

        // Check for nested url= parameter first
        final nestedMatch = RegExp(r'url=([^&]+)', caseSensitive: false).firstMatch(decoded);
        if (nestedMatch != null) {
          try {
            final nestedDecoded = utf8.decode(base64.decode(base64.normalize(nestedMatch.group(1)!)));
            if (nestedDecoded.contains('.workers.dev') || nestedDecoded.contains('.powerly.dev')) {
              return _appendTimestamp(nestedDecoded);
            }
          } catch (_) {}
        }

        // Fetch redirect/embed page
        final res = await http.get(
          Uri.parse(decoded),
          headers: {'User-Agent': _defaultUa, 'Referer': referer},
        ).timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          final workerRegex = RegExp(r'href="([^"]+\.(?:workers\.dev|powerly\.dev)[^"]+)"', caseSensitive: false);
          final match = workerRegex.firstMatch(res.body);
          if (match != null) {
            return _appendTimestamp(match.group(1)!);
          }
        }
      }
    } catch (e) {
      debugPrint('[HindMoviez] resolveHCloudUrl error: $e');
    }
    return null;
  }

  static String _appendTimestamp(String url) {
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}s=${DateTime.now().millisecondsSinceEpoch}';
  }

  // ── Build StreamSource ──
  StreamSource _buildStreamSource({
    required String url,
    required String quality,
    String? rawFileName,
    required String targetTitle,
    required bool isTv,
    int? season,
    int? episode,
    required String serverLabel,
  }) {
    final nameLower = (rawFileName ?? url).toLowerCase();

    // Audio classification
    String audioBadge = 'Single-Audio';
    String audioLang = 'Hindi';

    if (nameLower.contains('dual') || (nameLower.contains('hindi') && nameLower.contains('english'))) {
      audioBadge = 'Dual-Audio';
      audioLang = 'Hindi + English';
    } else if (nameLower.contains('multi')) {
      audioBadge = 'Multi-Audio';
      audioLang = 'Multilingual';
    } else if (nameLower.contains('hindi')) {
      audioBadge = 'Hindi';
      audioLang = 'Hindi';
    } else if (nameLower.contains('tamil')) {
      audioBadge = 'Tamil';
      audioLang = 'Tamil';
    } else if (nameLower.contains('telugu')) {
      audioBadge = 'Telugu';
      audioLang = 'Telugu';
    } else if (nameLower.contains('english')) {
      audioBadge = 'English';
      audioLang = 'English';
    }

    // Codec / format
    String format = 'MKV';
    if (nameLower.contains('.mp4')) format = 'MP4';
    if (nameLower.contains('.m3u8')) format = 'HLS';

    final tags = <String>[];
    if (nameLower.contains('10bit')) tags.add('10bit');
    if (nameLower.contains('x265') || nameLower.contains('hevc')) {
      tags.add('x265');
    } else if (nameLower.contains('x264') || nameLower.contains('h264')) {
      tags.add('x264');
    }
    tags.add('WEB-DL');

    final qIcon = (quality.contains('4k') || quality.contains('2160')) ? '🌟' : '💎';

    final titleHeader = isTv
        ? '📺 $targetTitle S${season?.toString().padLeft(2, '0')}E${episode?.toString().padLeft(2, '0')}'
        : '🎬 $targetTitle';

    final displayQuality = '$qIcon $quality | 🌐 $audioLang | 🗃️ $serverLabel';
    final displayDetails = '🎞️ $format | 📌 ${tags.join(' • ')}';
    final fullTitle = '$titleHeader\n$displayQuality\n$displayDetails';

    return StreamSource(
      name: 'HindMoviez • $quality • $audioBadge',
      title: fullTitle,
      description: rawFileName ?? fullTitle,
      url: url,
      addonName: 'ZPlayHTTP',
      providerId: 'hindmoviez',
      providerName: 'HindMoviez',
      headers: _defaultHeaders,
      behaviorHints: const {'notWebReady': true},
    );
  }
}
