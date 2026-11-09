import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart Mapple Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla Mapple provider.
/// Solves SHA-256 Proof-of-Work and resolves multi-server HLS streams from mapple.club.
class MappleScraper extends HttpScraper {
  static const _baseUrl = 'https://mapple.club';
  static const _ua = kZplayUserAgent;

  static const _servers = [
    {'id': 'mapple', 'name': 'Mapple'},
    {'id': 's1', 'name': 'Nexus'},
    {'id': 's2', 'name': 'Cipher'},
    {'id': 's3', 'name': 'Pulse'},
    {'id': 's4', 'name': 'Vertex'},
    {'id': 's10', 'name': 'Chimp'},
  ];

  static String? _solvePoW(String challenge, int difficulty) {
    final maskBytes = difficulty ~/ 8;
    final maskBits = difficulty % 8;
    final finalMask = maskBits > 0 ? ((0xFF << (8 - maskBits)) & 0xFF) : 0;

    final challengeBytes = utf8.encode(challenge);

    for (var nonce = 0; nonce < 1000000; nonce++) {
      final nonceStr = nonce.toString();
      final nonceBytes = utf8.encode(nonceStr);

      final combined = Uint8List(challengeBytes.length + nonceBytes.length);
      combined.setRange(0, challengeBytes.length, challengeBytes);
      combined.setRange(challengeBytes.length, combined.length, nonceBytes);

      final digest = sha256.convert(combined).bytes;

      var ok = true;
      for (var i = 0; i < maskBytes; i++) {
        if (digest[i] != 0) {
          ok = false;
          break;
        }
      }

      if (ok && (finalMask == 0 || (digest[maskBytes] & finalMask) == 0)) {
        return nonceStr;
      }
    }
    return null;
  }

  static String? _solvePoWRunner(List<dynamic> args) {
    return _solvePoW(args[0] as String, args[1] as int);
  }
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
    final mediaType = isTv ? 'tv' : 'movie';

    try {
      final tmdbId = await TmdbHelper.resolveTmdbId(
        imdbId: imdbId,
        title: title,
        type: mediaType,
        year: year,
      );

      if (tmdbId == null) {
        if (kDebugMode) debugPrint('[MappleScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final client = http.Client();
      try {
        final pageUrl = isTv
            ? '$_baseUrl/watch/tv/$tmdbId/${season ?? 1}/${episode ?? 1}'
            : '$_baseUrl/watch/movie/$tmdbId';

        final pageRes = await client.get(
          Uri.parse(pageUrl),
          headers: {
            'User-Agent': _ua,
            'Referer': '$_baseUrl/',
            'Origin': _baseUrl,
          },
        ).timeout(const Duration(seconds: 8));

        if (pageRes.statusCode != 200) return;
        final html = pageRes.body;

        final reqMatch = RegExp(r'''window\.__REQUEST_TOKEN__\s*=\s*"([^"]+)"''').firstMatch(html);
        if (reqMatch == null || reqMatch.group(1) == null) return;
        final requestToken = reqMatch.group(1)!;

        final rawCookie = pageRes.headers['set-cookie'];
        final cookieParts = <String>[];
        if (rawCookie != null) {
          final reg = RegExp(r'(_mapple_site(?:_partitioned)?=[^;]+)');
          for (final m in reg.allMatches(rawCookie)) {
            cookieParts.add(m.group(1)!);
          }
        }
        final cookieHeader = cookieParts.join('; ');

        final initHeaders = {
          'Content-Type': 'application/json',
          'User-Agent': _ua,
          'Referer': pageUrl,
          'Origin': _baseUrl,
          if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
        };

        final initRes = await client.post(
          Uri.parse('$_baseUrl/api/playback-init'),
          headers: initHeaders,
          body: jsonEncode({
            'mediaId': tmdbId,
            'mediaType': mediaType,
            'requestToken': requestToken,
          }),
        ).timeout(const Duration(seconds: 8));

        if (initRes.statusCode != 200) return;
        final initData = jsonDecode(initRes.body);
        if (initData is! Map) return;

        var streamToken = initData['token']?.toString();

        if (initData['requiresPow'] == true && initData['pow'] is Map) {
          final powInfo = initData['pow'] as Map;
          final challenge = powInfo['challenge']?.toString() ?? '';
          final difficulty = (powInfo['difficulty'] as num?)?.toInt() ?? 10;
          final challengeId = powInfo['challengeId'];

          final nonce = await compute(_solvePoWRunner, [challenge, difficulty]);
          if (nonce != null) {
            final solveRes = await client.post(
              Uri.parse('$_baseUrl/api/playback-init'),
              headers: initHeaders,
              body: jsonEncode({
                'mediaId': tmdbId,
                'mediaType': mediaType,
                'requestToken': requestToken,
                'pow': {
                  'challengeId': challengeId,
                  'nonce': nonce,
                },
              }),
            ).timeout(const Duration(seconds: 8));

            if (solveRes.statusCode == 200) {
              final solveData = jsonDecode(solveRes.body);
              if (solveData is Map && solveData['token'] != null) {
                streamToken = solveData['token']?.toString();
              }
            }
          }
        }

        if (streamToken == null || streamToken.isEmpty) return;

        final tvSlug = isTv ? '${season ?? 1}-${episode ?? 1}' : '';

        // Query all servers in parallel for minimum latency
        final futures = _servers.map((srv) async {
          try {
            final sId = srv['id']!;
            final sName = srv['name']!;

            final encryptRes = await client.post(
              Uri.parse('$_baseUrl/api/encrypt'),
              headers: initHeaders,
              body: jsonEncode({
                'data': {
                  'mediaId': tmdbId,
                  'mediaType': mediaType,
                  'tv_slug': tvSlug,
                  'source': sId,
                  'apikey': 'mptv_sk_a8f29c4e7b3d1f',
                },
              }),
            ).timeout(const Duration(seconds: 6));

            if (encryptRes.statusCode != 200) return null;
            final encryptData = jsonDecode(encryptRes.body);
            final encrypted = encryptData['encrypted']?.toString();
            if (encrypted == null) return null;

            final streamEncryptedUrl = Uri.parse('$_baseUrl/api/stream-encrypted').replace(
              queryParameters: {
                'data': encrypted,
                'requestToken': requestToken,
                'token': streamToken!,
              },
            );

            final streamRes = await client.get(
              streamEncryptedUrl,
              headers: {
                'User-Agent': _ua,
                'Referer': pageUrl,
                'Origin': _baseUrl,
                if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
              },
            ).timeout(const Duration(seconds: 8));

            if (streamRes.statusCode != 200) return null;
            final streamData = jsonDecode(streamRes.body);
            if (streamData is Map && streamData['success'] == true && streamData['data'] is Map) {
              var fileUrl = streamData['data']['stream_url']?.toString();
              if (fileUrl != null && fileUrl.isNotEmpty) {
                if (fileUrl.contains('omena-puu') || fileUrl.contains('nocach')) {
                  fileUrl += fileUrl.contains('?') ? '&format=.m3u8' : '?format=.m3u8';
                }

                final reqHeaders = {
                  'User-Agent': _ua,
                  'Referer': '$_baseUrl/',
                  'Origin': _baseUrl,
                };

                return StreamSource.zplayHttp(
                  title: 'Mapple · $sName · 1080p',
                  description: 'Mapple $sName HLS Stream',
                  url: fileUrl,
                  headers: reqHeaders,
                );
              }
            }
          } catch (_) {}
          return null;
        });

        final results = await Future.wait(futures);
        for (final source in results) {
          if (source != null) {
            yield source;
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[MappleScraper] scrapeStream error: $e');
    }
  }
}
