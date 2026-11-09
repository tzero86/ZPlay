import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart VidUp Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla VidUp provider.
/// Resolves movies and TV shows via vidup.to and enc-dec.app decryption pipeline.
class VidUpScraper extends HttpScraper {
  static const _domain = 'https://vidup.to';
  static const _apiBase = 'https://enc-dec.app/api';
  static const _ua = kZplayUserAgent;

  static const _defaultHeaders = {
    'User-Agent': _ua,
    'Referer': '$_domain/',
    'Origin': _domain,
    'X-Requested-With': 'XMLHttpRequest',
  };

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
        if (kDebugMode) debugPrint('[VidUpScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final client = http.Client();
      try {
        final embedUrl = isTv
            ? '$_domain/tv/$tmdbId/${season ?? 1}/${episode ?? 1}/'
            : '$_domain/movie/$tmdbId/';

        final pageRes = await client.get(
          Uri.parse(embedUrl),
          headers: {'User-Agent': _ua, 'Referer': '$_domain/'},
        ).timeout(const Duration(seconds: 10));

        if (pageRes.statusCode != 200) {
          if (kDebugMode) debugPrint('[VidUpScraper] Embed page returned ${pageRes.statusCode}');
          return;
        }

        final html = pageRes.body;
        final tokenMatch = RegExp(r'\\"(?:en|token)\\":\\"(.*?)\\"').firstMatch(html) ??
            RegExp(r'"(?:en|token)":"(.*?)"').firstMatch(html);

        if (tokenMatch == null || tokenMatch.group(1) == null) {
          if (kDebugMode) debugPrint('[VidUpScraper] No token match found in embed HTML');
          return;
        }

        final rawToken = tokenMatch.group(1)!;

        // Query enc-vidup
        final encRes = await client.get(
          Uri.parse('$_apiBase/enc-vidup?text=${Uri.encodeComponent(rawToken)}'),
          headers: {'User-Agent': _ua, 'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 10));

        if (encRes.statusCode != 200) return;
        final encData = jsonDecode(encRes.body);
        if (encData['status'] != 200 || encData['result'] == null) return;

        final serversUrl = encData['result']['servers']?.toString();
        final streamUrl = encData['result']['stream']?.toString();
        final csrfToken = encData['result']['token']?.toString();

        if (serversUrl == null || streamUrl == null || csrfToken == null) return;

        final reqHeaders = {
          ..._defaultHeaders,
          'X-CSRF-Token': csrfToken,
        };

        // Fetch encrypted servers
        final serversEncRes = await client.post(
          Uri.parse(serversUrl),
          headers: reqHeaders,
        ).timeout(const Duration(seconds: 10));

        if (serversEncRes.statusCode != 200) return;

        // Decrypt servers
        final decServersRes = await client.post(
          Uri.parse('$_apiBase/dec-vidup'),
          headers: {'Content-Type': 'application/json', 'User-Agent': _ua},
          body: jsonEncode({'text': serversEncRes.body}),
        ).timeout(const Duration(seconds: 10));

        if (decServersRes.statusCode != 200) return;
        final decServersData = jsonDecode(decServersRes.body);
        final serversList = decServersData['result'];
        if (serversList is! List || serversList.isEmpty) return;

        // Fan out server resolution in parallel
        final futures = <Future<Map<String, dynamic>?>>[];
        for (final srv in serversList) {
          if (srv is! Map) continue;
          final srvName = srv['name']?.toString() ?? 'Server';
          final srvData = srv['data']?.toString();
          if (srvData == null) continue;

          futures.add(() async {
            try {
              final sEncRes = await client.post(
                Uri.parse('$streamUrl/$srvData'),
                headers: reqHeaders,
              ).timeout(const Duration(seconds: 10));

              if (sEncRes.statusCode != 200) return null;

              final decStreamRes = await client.post(
                Uri.parse('$_apiBase/dec-vidup'),
                headers: {'Content-Type': 'application/json', 'User-Agent': _ua},
                body: jsonEncode({'text': sEncRes.body}),
              ).timeout(const Duration(seconds: 10));

              if (decStreamRes.statusCode != 200) return null;
              final decData = jsonDecode(decStreamRes.body);
              if (decData['status'] != 200 || decData['result'] == null) return null;

              final finalUrl = decData['result']['url']?.toString();
              if (finalUrl == null || finalUrl.isEmpty) return null;

              return {
                'name': srvName,
                'url': finalUrl,
                'captions': decData['result']['captions'],
              };
            } catch (e) {
              return null;
            }
          }());
        }

        final resolved = await Future.wait(futures);

        for (final item in resolved) {
          if (item == null) continue;
          final srvName = item['name'] as String;
          final streamTargetUrl = item['url'] as String;

          final is4K = srvName.toLowerCase().contains('2160') ||
              srvName.toLowerCase().contains('4k') ||
              streamTargetUrl.contains('2160p');
          final qualityLabel = is4K ? '4K' : '1080p';

          final headers = {
            'User-Agent': _ua,
            'Referer': '$_domain/',
            'Origin': _domain,
          };

          yield StreamSource.zplayHttp(
            title: 'VidUp · $srvName · $qualityLabel',
            description: 'VidUp Multi-CDN Stream · $qualityLabel',
            url: streamTargetUrl,
            headers: headers,
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[VidUpScraper] scrapeStream error: $e');
    }
  }
}
