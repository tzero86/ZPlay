import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart Hexa Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla Hexa provider.
/// Resolves HLS and MP4 sources from hexa.su / flixer.su via enc-dec.app.
class HexaScraper extends HttpScraper {
  static const _apiBase = 'https://enc-dec.app/api';
  static const _domains = ['hexa.su', 'flixer.su'];
  static const _ua = kZplayUserAgent;

  String _randomApiKey() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<String?> _getChallengeToken(http.Client client) async {
    try {
      final res = await client.get(
        Uri.parse('$_apiBase/enc-hexa'),
        headers: {'User-Agent': _ua, 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['status'] == 200 && data['result'] is Map) {
          return data['result']['token']?.toString();
        }
      }
    } catch (_) {}
    return null;
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
        if (kDebugMode) debugPrint('[HexaScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final client = http.Client();
      try {
        final capToken = await _getChallengeToken(client);
        if (capToken == null || capToken.isEmpty) return;

        final apiKey = _randomApiKey();

        Map<String, dynamic>? decrypted;

        for (final domain in _domains) {
          try {
            final url = isTv
                ? 'https://theemoviedb.$domain/api/tmdb/tv/$tmdbId/season/${season ?? 1}/episode/${episode ?? 1}/images'
                : 'https://theemoviedb.$domain/api/tmdb/movie/$tmdbId/images';

            final encRes = await client.get(
              Uri.parse(url),
              headers: {
                'User-Agent': _ua,
                'Referer': 'https://$domain/',
                'Accept': 'text/plain',
                'X-Fingerprint-Lite': 'e9136c41504646444',
                'X-Api-Key': apiKey,
                'X-Cap-Token': capToken,
              },
            ).timeout(const Duration(seconds: 10));

            if (encRes.statusCode != 200 || encRes.body.isEmpty) continue;

            final decRes = await client.post(
              Uri.parse('$_apiBase/dec-hexa'),
              headers: {'Content-Type': 'application/json', 'User-Agent': _ua},
              body: jsonEncode({'text': encRes.body, 'key': apiKey}),
            ).timeout(const Duration(seconds: 8));

            if (decRes.statusCode == 200) {
              final decData = jsonDecode(decRes.body);
              if (decData is Map &&
                  decData['status'] == 200 &&
                  decData['result'] is Map &&
                  decData['result']['sources'] is List &&
                  (decData['result']['sources'] as List).isNotEmpty) {
                decrypted = Map<String, dynamic>.from(decData['result']);
                break;
              }
            }
          } catch (_) {}
        }

        if (decrypted == null || decrypted['sources'] is! List) return;

        final sources = decrypted['sources'] as List;
        for (final src in sources) {
          if (src is! Map) continue;
          final streamUrl = src['url']?.toString();
          if (streamUrl == null || streamUrl.isEmpty) continue;

          final sName = src['name']?.toString() ?? src['server']?.toString() ?? 'Server';
          final quality = src['quality']?.toString() ?? '1080p';

          final headers = {
            'User-Agent': _ua,
            'Referer': 'https://${_domains.first}/',
          };

          yield StreamSource.zplayHttp(
            title: 'Hexa · $sName · $quality',
            description: 'Hexa Stream · $quality',
            url: streamUrl,
            headers: headers,
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[HexaScraper] scrapeStream error: $e');
    }
  }
}
