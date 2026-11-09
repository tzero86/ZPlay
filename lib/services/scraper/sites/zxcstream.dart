import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart ZxcStream Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla ZxcStream provider.
/// Resolves multi-server streams (berkas, orion, aquarius, resshin) from player.zxcstream.xyz.
class ZxcStreamScraper extends HttpScraper {
  static const _baseUrl = 'https://player.zxcstream.xyz';
  static const _aesKey = '7f4c9e2a81d63b05c4f7a9e8126d3b50e1a8c7f23d9465ab0c6e9f1d4a7b832c';
  static const _servers = ['berkas', 'orion', 'aquarius', 'resshin'];
  static const _ua = kZplayUserAgent;

  static const _headers = {
    'User-Agent': _ua,
    'Referer': '$_baseUrl/',
    'Origin': _baseUrl,
    'Accept': 'application/json, text/plain, */*',
  };

  static String? _decryptCryptoJS(String ciphertextB64, String passphrase) {
    try {
      final buf = base64Decode(ciphertextB64);
      final prefix = utf8.decode(buf.sublist(0, 8), allowMalformed: true);

      if (prefix != 'Salted__') {
        final key = md5.convert(utf8.encode(passphrase)).bytes;
        final iv = Uint8List(16);
        final cipher = CBCBlockCipher(AESEngine());
        cipher.init(false, ParametersWithIV(KeyParameter(Uint8List.fromList(key)), iv));
        final decrypted = Uint8List(buf.length);
        var offset = 0;
        for (var i = 0; i < buf.length; i += 16) {
          offset += cipher.processBlock(buf, i, decrypted, offset);
        }
        return utf8.decode(decrypted);
      }

      final salt = buf.sublist(8, 16);
      final cipherBytes = buf.sublist(16);

      var hash = <int>[];
      var keyAndIv = <int>[];
      while (keyAndIv.length < 48) {
        final passBytes = utf8.encode(passphrase);
        final combined = Uint8List(hash.length + passBytes.length + salt.length);
        combined.setRange(0, hash.length, hash);
        combined.setRange(hash.length, hash.length + passBytes.length, passBytes);
        combined.setRange(hash.length + passBytes.length, combined.length, salt);

        hash = md5.convert(combined).bytes;
        keyAndIv.addAll(hash);
      }

      final key = Uint8List.fromList(keyAndIv.sublist(0, 32));
      final iv = Uint8List.fromList(keyAndIv.sublist(32, 48));

      final cipher = CBCBlockCipher(AESEngine());
      cipher.init(false, ParametersWithIV(KeyParameter(key), iv));

      final decrypted = Uint8List(cipherBytes.length);
      var offset = 0;
      for (var i = 0; i < cipherBytes.length; i += 16) {
        offset += cipher.processBlock(cipherBytes, i, decrypted, offset);
      }

      // Strip PKCS7 padding
      if (offset > 0) {
        final pad = decrypted[offset - 1];
        if (pad > 0 && pad <= 16) {
          return utf8.decode(decrypted.sublist(0, offset - pad));
        }
      }
      return utf8.decode(decrypted);
    } catch (_) {
      return null;
    }
  }

  static String? _decryptCryptoJSRunner(List<String> args) {
    return _decryptCryptoJS(args[0], args[1]);
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
        if (kDebugMode) debugPrint('[ZxcStreamScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final client = http.Client();
      try {
        final futures = _servers.map((server) async {
          try {
            final tokenRes = await client.post(
              Uri.parse('$_baseUrl/backend/you-are-gay'),
              headers: {
                ..._headers,
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'id': tmdbId,
                'media_type': mediaType,
                'path': server,
                if (isTv) 'season': season ?? 1,
                if (isTv) 'episode': episode ?? 1,
              }),
            ).timeout(const Duration(seconds: 8));

            if (tokenRes.statusCode != 200) return <Map<String, dynamic>>[];
            final tokenData = jsonDecode(tokenRes.body);
            if (tokenData is! Map || tokenData['token'] == null) return <Map<String, dynamic>>[];

            final queryParams = {
              'id': tmdbId.toString(),
              'b': mediaType,
              'ts': tokenData['ts']?.toString() ?? '',
              'token': tokenData['token'].toString(),
              'title': title,
              'year': (year ?? 2024).toString(),
              'date': (year ?? 2024).toString(),
              if (isTv) 'season': (season ?? 1).toString(),
              if (isTv) 'episode': (episode ?? 1).toString(),
            };

            final sourcesUri = Uri.parse('$_baseUrl/backend_/sources/$server').replace(queryParameters: queryParams);
            final sourcesRes = await client.get(sourcesUri, headers: _headers).timeout(const Duration(seconds: 8));

            if (sourcesRes.statusCode != 200) return <Map<String, dynamic>>[];
            dynamic sourcesData = jsonDecode(sourcesRes.body);

            if (sourcesData is String) {
              final dec = await compute(_decryptCryptoJSRunner, [sourcesData, _aesKey]);
              if (dec != null) {
                try {
                  sourcesData = jsonDecode(dec);
                } catch (_) {}
              }
            }

            final list = <Map<String, dynamic>>[];
            if (sourcesData is List) {
              for (final it in sourcesData) {
                if (it is Map && it['url'] != null) {
                  list.add({
                    'url': it['url'].toString(),
                    'server': server,
                  });
                }
              }
            } else if (sourcesData is Map) {
              if (sourcesData['url'] != null) {
                list.add({
                  'url': sourcesData['url'].toString(),
                  'server': server,
                });
              }
              if (sourcesData['sources'] is List) {
                for (final it in sourcesData['sources']) {
                  if (it is Map && it['url'] != null) {
                    list.add({
                      'url': it['url'].toString(),
                      'server': server,
                    });
                  }
                }
              }
            }
            return list;
          } catch (_) {
            return <Map<String, dynamic>>[];
          }
        });

        final nested = await Future.wait(futures);
        for (final list in nested) {
          for (final item in list) {
            final sUrl = item['url'] as String;
            final sName = item['server'] as String;
            final isHls = sUrl.contains('.m3u8');

            yield StreamSource.zplayHttp(
              title: 'ZxcStream · $sName · 1080p',
              description: 'ZxcStream Stream · ${isHls ? 'HLS' : 'MP4'}',
              url: sUrl,
              headers: _headers,
            );
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ZxcStreamScraper] error: $e');
    }
  }
}
