import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart Bcine Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla Bcine provider.
/// Resolves direct cryptographic master playlists and multi-server streams.
class BcineScraper extends HttpScraper {
  static const _ua = kZplayUserAgent;

  static const _vParam = '_v=34403446';
  static const _nD = '4860ac8bfddb';
  static const _aD = '224eff10e662e9635c9f671cf46351dcd69af42b1edd56f5e5fa21751f44b9c8';
  static const _ls = [17, 91, 203, 44, 8, 177, 62, 239, 119, 3, 154, 81, 28, 210, 101, 7];
  static const _wa = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

  static const _servers = [
    {'id': 'NIGHT', 'endpoint': '/server/night', 'name': 'Night'},
    {'id': 'EMP', 'endpoint': '/server/emp', 'name': 'Empire'},
    {'id': 'MAIN', 'endpoint': '/server/vidsrc', 'name': 'VidSrc'},
  ];

  static int _ab(int e) {
    var t = e & 0xFFFFFFFF;
    t ^= (t >> 16);
    t = (t * 2146121005) & 0xFFFFFFFF;
    t ^= (t >> 15);
    t = (t * 2221713035) & 0xFFFFFFFF;
    return (t ^ (t >> 16)) & 0xFFFFFFFF;
  }

  static Uint8List _sD(int e) {
    final t = utf8.encode(_aD);
    final r = (e + 17).clamp(32, 128);
    final n = Uint8List(r);
    var a = 2166136261;
    for (var s = 0; s < r; s++) {
      a ^= t[s % t.length];
      a = _ab((a + _ls[s % _ls.length] + ((2654435761 * s) & 0xFFFFFFFF)) & 0xFFFFFFFF);
      n[s] = a & 255;
    }
    return n;
  }

  static String _iD(Uint8List e) {
    var t = '';
    for (var r = 0; r < e.length; r += 3) {
      final n = e[r];
      final a = (r + 1 < e.length) ? e[r + 1] : null;
      final s = (r + 2 < e.length) ? e[r + 2] : null;
      t += _wa[n >> 2];
      t += _wa[((3 & n) << 4) | ((a ?? 0) >> 4)];
      if (a == null) break;
      t += _wa[((15 & a) << 2) | ((s ?? 0) >> 6)];
      if (s == null) break;
      t += _wa[63 & s];
    }
    return t;
  }

  static String _generateDirectHlsUrl(int tmdbId, int? s, int? e) {
    final isTv = s != null && e != null;
    final season = isTv ? s : 0;
    final episode = isTv ? e : 0;

    final str = '$_nD:${isTv ? 's' : 'm'}:$tmdbId:$season:$episode';
    final a = utf8.encode(str);
    final sArr = _sD(a.length);
    final i = Uint8List(a.length + 2);
    i[0] = a.length & 255;
    i[1] = (a.length >> 8) & 255;
    var o = (2654435769 ^ a.length) & 0xFFFFFFFF;
    for (var l = 0; l < a.length; l++) {
      o = _ab((o + sArr[l % sArr.length] + _ls[l % _ls.length] + l) & 0xFFFFFFFF);
      i[l + 2] = (a[l] ^ (255 & o)) ^ sArr[(7 * l + 3) % sArr.length];
    }

    return 'https://glendale-plumbing.com/c/v1/${_iD(i)}/master.m3u8';
  }

  Future<String?> _fetchInternalToken(http.Client client) async {
    try {
      final res = await client.get(
        Uri.parse('https://1embed.cc/api/token'),
        headers: {
          'User-Agent': _ua,
          'Referer': 'https://1embed.cc/',
          'Accept': 'application/json, text/plain, */*',
        },
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['token'] != null) {
          return data['token'].toString();
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
        if (kDebugMode) debugPrint('[BcineScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      // 1. Direct Cryptographic HLS Master Stream
      final directHls = '${_generateDirectHlsUrl(tmdbId, season, episode)}?$_vParam';
      final directHeaders = {
        'User-Agent': _ua,
        'Referer': 'https://bcine.ru/',
        'Origin': 'https://bcine.ru',
      };

      yield StreamSource.zplayHttp(
        title: 'Bcine · Direct Master · 1080p',
        description: 'Bcine Direct Master HLS Stream',
        url: directHls,
        headers: directHeaders,
      );

      // 2. Multi-server streams
      final client = http.Client();
      try {
        final token = await _fetchInternalToken(client);
        if (token != null && token.isNotEmpty) {
          final query = isTv
              ? 'id=$tmdbId?type=tv&s=${season ?? 1}&e=${episode ?? 1}'
              : 'id=$tmdbId?type=movie';

          for (final srv in _servers) {
            try {
              final endpoint = srv['endpoint']!;
              final srvName = srv['name']!;

              final res = await client.get(
                Uri.parse('https://1embed.cc$endpoint?$query'),
                headers: {
                  'User-Agent': _ua,
                  'Referer': 'https://1embed.cc/',
                  'Authorization': 'Bearer $token',
                  'Accept': 'application/json, text/plain, */*',
                },
              ).timeout(const Duration(seconds: 6));

              if (res.statusCode == 200) {
                final data = jsonDecode(res.body);
                if (data is Map && data['url'] != null) {
                  final sUrl = data['url'].toString();
                  if (sUrl.contains('.m3u8')) {
                    final reqHeaders = {
                      'User-Agent': _ua,
                      'Referer': 'https://1embed.cc/',
                    };

                    yield StreamSource.zplayHttp(
                      title: 'Bcine · $srvName · 1080p',
                      description: 'Bcine $srvName HLS Stream',
                      url: sUrl,
                      headers: reqHeaders,
                    );
                  }
                }
              }
            } catch (_) {}
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BcineScraper] scrapeStream error: $e');
    }
  }
}
