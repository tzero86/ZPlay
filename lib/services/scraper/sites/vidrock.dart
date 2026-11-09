import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart VidRock Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla VidRock provider.
/// Resolves AES-GCM encrypted streams from vidrock.ru.
class VidRockScraper extends HttpScraper {
  static const _gcmHexKey = '7f3e9c2a8b5d1f4e6a9c3b7d2e5f8a1c4b6d9e2f5a8c1b4d7e9f2a5c8b1d4e7f';
  static const _baseUrl = 'https://vidrock.ru/';
  static const _ua = kZplayUserAgent;

  static Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  static Uint8List _base64UrlToBytes(String value) {
    var b64 = value.replaceAll('-', '+').replaceAll('_', '/');
    final pad = b64.length % 4;
    if (pad == 2) {
      b64 += '==';
    } else if (pad == 3) {
      b64 += '=';
    }
    return base64Decode(b64);
  }

  static String? _decryptStreamUrl(String value) {
    try {
      final data = _base64UrlToBytes(value);
      if (data.length < 28) return null;

      final iv = data.sublist(0, 12);
      final ciphertext = data.sublist(12);

      final keyBytes = _hexToBytes(_gcmHexKey);
      final cipher = GCMBlockCipher(AESEngine());
      cipher.init(false, AEADParameters(KeyParameter(keyBytes), 128, iv, Uint8List(0)));

      final decrypted = cipher.process(ciphertext);
      return utf8.decode(decrypted);
    } catch (_) {
      return null;
    }
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
        if (kDebugMode) debugPrint('[VidRockScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final client = http.Client();
      try {
        final path = isTv
            ? 'tv/$tmdbId/${season ?? 1}/${episode ?? 1}'
            : 'movie/$tmdbId';

        final res = await client.get(
          Uri.parse('${_baseUrl}api/$path'),
          headers: {
            'User-Agent': _ua,
            'Referer': _baseUrl,
            'Origin': _baseUrl,
          },
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode != 200) return;
        final data = jsonDecode(res.body);
        if (data is! Map) return;

        for (final entry in data.entries) {
          final provider = entry.key.toString();
          final info = entry.value;

          String? streamUrl;
          if (info is String) {
            streamUrl = info.startsWith('http') ? info : await compute(_decryptStreamUrl, info);
          } else if (info is Map) {
            final raw = info['url']?.toString() ?? info['stream']?.toString() ?? info['file']?.toString();
            if (raw != null) {
              streamUrl = raw.startsWith('http') ? raw : await compute(_decryptStreamUrl, raw);
            }
          }

          if (streamUrl != null && streamUrl.isNotEmpty) {
            if (streamUrl.contains('/playlist/')) {
              try {
                final pRes = await client.get(
                  Uri.parse(streamUrl),
                  headers: {
                    'User-Agent': _ua,
                    'Referer': _baseUrl,
                  },
                ).timeout(const Duration(seconds: 6));

                if (pRes.statusCode == 200 && pRes.body.trim().startsWith('[')) {
                  final pList = jsonDecode(pRes.body);
                  if (pList is List && pList.isNotEmpty) {
                    for (final item in pList) {
                      if (item is Map) {
                        final rawItemUrl = item['url']?.toString();
                        if (rawItemUrl != null && rawItemUrl.startsWith('http')) {
                          final resVal = item['resolution']?.toString() ?? '1080';
                          final isHls = rawItemUrl.contains('.m3u8');
                          final reqHeaders = {
                            'User-Agent': _ua,
                            'Referer': _baseUrl,
                          };

                          yield StreamSource.zplayHttp(
                            title: 'VidRock · $provider · ${resVal}p',
                            description: 'VidRock Stream · ${isHls ? 'HLS' : 'MP4'}',
                            url: rawItemUrl,
                            headers: reqHeaders,
                          );
                        }
                      }
                    }
                    continue;
                  }
                }
              } catch (_) {}
            }

            final isHls = streamUrl.contains('.m3u8');
            final reqHeaders = {
              'User-Agent': _ua,
              'Referer': _baseUrl,
            };

            yield StreamSource.zplayHttp(
              title: 'VidRock · $provider · 1080p',
              description: 'VidRock Stream · ${isHls ? 'HLS' : 'MP4'}',
              url: streamUrl,
              headers: reqHeaders,
            );
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[VidRockScraper] error: $e');
    }
  }
}
