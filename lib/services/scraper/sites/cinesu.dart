import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart CineSu Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla CineSu provider.
/// Resolves direct master HLS from cine.su.
class CineSuScraper extends HttpScraper {
  static const _baseDomain = 'https://glendale-plumbing.com';
  static const _referer = 'https://cine.su/';
  static const _ua = kZplayUserAgent;

  static const _nD = '4860ac8bfddb';
  static const _aD = '224eff10e662e9635c9f671cf46351dcd69af42b1edd56f5e5fa21751f44b9c8';
  static const _ls = [17, 91, 203, 44, 8, 177, 62, 239, 119, 3, 154, 81, 28, 210, 101, 7];
  static const _wa = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

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

  static String _generateMasterUrl(int tmdbId, int? s, int? e) {
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

    return '$_baseDomain/c/v1/${_iD(i)}/master.m3u8';
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
        if (kDebugMode) debugPrint('[CineSuScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final streamUrl = _generateMasterUrl(tmdbId, season, episode);

      final headers = {
        'User-Agent': _ua,
        'Referer': _referer,
        'Origin': 'https://cine.su',
      };

      yield StreamSource.zplayHttp(
        title: 'CineSu · Direct Master · 1080p',
        description: 'CineSu Master HLS Stream',
        url: streamUrl,
        headers: headers,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[CineSuScraper] error: $e');
    }
  }
}
