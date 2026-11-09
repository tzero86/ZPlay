import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart MeowTV Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla MeowTV provider.
/// Resolves streams via api.meowtv.ru and enc-dec.app decryption.
class MeowTvScraper extends HttpScraper {
  static const _apiBase = 'https://api.meowtv.ru';
  static const _referer = 'https://meowtv.ru/';
  static const _encDecApi = 'https://enc-dec.app/api/dec-meowtv';
  static const _ua = kZplayUserAgent;

  static const _headers = {
    'User-Agent': _ua,
    'Accept': 'application/json',
    'Referer': _referer,
    'Origin': 'https://meowtv.ru',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  Future<dynamic> _decryptPayload(http.Client client, dynamic payload) async {
    try {
      final res = await client.post(
        Uri.parse(_encDecApi),
        headers: {'Content-Type': 'application/json', 'User-Agent': _ua},
        body: jsonEncode({'data': payload}),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['status'] == 200 && data['result'] != null) {
          final r = data['result'];
          return r is String ? jsonDecode(r) : r;
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
        if (kDebugMode) debugPrint('[MeowTvScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final client = http.Client();
      try {
        final path = isTv
            ? '/streams/tv/$tmdbId/${season ?? 1}/${episode ?? 1}?s=hindiv3'
            : '/streams/movie/$tmdbId?s=hindiv3';

        final res = await client.get(
          Uri.parse('$_apiBase$path'),
          headers: _headers,
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode != 200) return;
        final payload = jsonDecode(res.body);

        final data = await _decryptPayload(client, payload);
        if (data is! Map) return;

        final urls = <String>[];
        if (data['url'] != null && data['url'].toString().startsWith('http')) {
          urls.add(data['url'].toString());
        }

        if (data['streams'] is List) {
          for (final st in data['streams']) {
            if (st is Map && st['url'] != null && st['url'].toString().startsWith('http')) {
              urls.add(st['url'].toString());
            }
          }
        }

        for (final u in urls) {
          final isHls = u.contains('.m3u8');
          final reqHeaders = {
            'User-Agent': _ua,
            'Referer': _referer,
            'Origin': 'https://meowtv.ru',
          };

          yield StreamSource.zplayHttp(
            title: 'MeowTV · Hindiv3 · 1080p',
            description: 'MeowTV Stream · ${isHls ? 'HLS' : 'MP4'}',
            url: u,
            headers: reqHeaders,
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[MeowTvScraper] error: $e');
    }
  }
}
