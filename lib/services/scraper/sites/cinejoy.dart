import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import '../../../utils/security/log_redaction.dart';
import 'tmdb_helper.dart';

/// Pure-Dart Cinejoy Stream Scraper for ZPlayHTTP.
///
/// Features:
/// - 100% Pure Dart Cryptography (ECDH on P-256, HKDF-SHA256, AES-256-GCM)
/// - Zero WASM runtimes, zero WebView, zero native assets / C++ / Rust build hooks
/// - 100% cross-platform (Windows, Android, iOS, macOS, Linux)
/// - Queries active Cinejoy servers (Lisbon, Solara, Athens, Castle, Canaias)
class CinejoyScraper extends StreamScraper {
  @override
  String get name => 'ZPlayHTTP';

  static const _apiBase = 'https://api.shegu.st';
  static const _origin = 'https://cinejoy.to';
  static const _referer = 'https://cinejoy.to/';
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static const _defaultHeaders = {
    'User-Agent': _ua,
    'Origin': _origin,
    'Referer': _referer,
    'Accept': 'application/json, text/plain, */*',
  };

  static const List<Map<String, dynamic>> _fallbackServers = [
    {'name': 'Lisbon', '4k': true, 'status': 'ok'},
    {'name': 'Solara', '4k': false, 'status': 'ok'},
    {'name': 'Athens', '4k': false, 'status': 'ok'},
    {'name': 'Castle', '4k': false, 'status': 'ok'},
    {'name': 'Canaias', '4k': false, 'status': 'ok'},
  ];

  static final _domain = ECDomainParameters('secp256r1');

  static const _serverPubKeyHex =
      '0483c7a82132b8516e3eb4061b82e9c881cc585593a4709001131bff7443eabc1701c1f0d50e23ac02b0b9a5979903dbd7e9055aab5e4a5532132d1d200707f5f2';

  static final ECPublicKey _serverPublicKey = () {
    final bytes = Uint8List.fromList([
      for (int i = 0; i < _serverPubKeyHex.length; i += 2)
        int.parse(_serverPubKeyHex.substring(i, i + 2), radix: 16),
    ]);
    final point = _domain.curve.decodePoint(bytes)!;
    return ECPublicKey(point, _domain);
  }();

  static Uint8List _hkdfExtract({
    required Uint8List salt,
    required Uint8List ikm,
  }) {
    final hmac = HMac(SHA256Digest(), 64);
    hmac.init(KeyParameter(salt));
    final prk = Uint8List(32);
    hmac.update(ikm, 0, ikm.length);
    hmac.doFinal(prk, 0);
    return prk;
  }

  static Uint8List _hkdfExpand({
    required Uint8List prk,
    required Uint8List info,
    required int length,
  }) {
    final hmac = HMac(SHA256Digest(), 64);
    hmac.init(KeyParameter(prk));
    final input = Uint8List(info.length + 1);
    input.setRange(0, info.length, info);
    input[info.length] = 1;
    final out = Uint8List(32);
    hmac.update(input, 0, input.length);
    hmac.doFinal(out, 0);
    return out.sublist(0, length);
  }

  static Map<String, dynamic> _sealRequest({
    required String path,
    required Map<String, dynamic> payload,
  }) {
    // 1. Generate ephemeral P-256 keypair
    final rnd = Random.secure();
    final privBytes = Uint8List.fromList(
      List.generate(32, (_) => rnd.nextInt(256)),
    );
    var d = BigInt.parse(
      privBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );
    while (d >= _domain.n || d == BigInt.zero) {
      final b = Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
      d = BigInt.parse(
        b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(),
        radix: 16,
      );
    }

    final clientPriv = ECPrivateKey(d, _domain);
    final clientQ = _domain.G * d;
    final clientPubBytes = clientQ!.getEncoded(
      false,
    ); // 65 bytes: 0x04 || X || Y

    // 2. Compute ECDH shared secret
    final agreement = ECDHBasicAgreement();
    agreement.init(clientPriv);
    final BigInt zInt = agreement.calculateAgreement(_serverPublicKey);
    final zHex = zInt.toRadixString(16).padLeft(64, '0');
    final zBytes = Uint8List.fromList([
      for (int i = 0; i < 64; i += 2)
        int.parse(zHex.substring(i, i + 2), radix: 16),
    ]);

    // 3. HKDF key derivation
    final prk = _hkdfExtract(salt: clientPubBytes, ikm: zBytes);
    final reqKey = _hkdfExpand(
      prk: prk,
      info: utf8.encode('lumen-gate-v2|c2s'),
      length: 32,
    );
    final resKey = _hkdfExpand(
      prk: prk,
      info: utf8.encode('lumen-gate-v2|s2c'),
      length: 32,
    );

    // 4. Encrypt JSON payload with AES-256-GCM
    final reqJson = jsonEncode({'path': path, 'payload': payload});
    final reqPlaintext = Uint8List.fromList(utf8.encode(reqJson));
    final iv = Uint8List.fromList(List.generate(12, (_) => rnd.nextInt(256)));

    // Request AAD: "lumen-gate-v2" || 0x00 || 0x01 || 0x01 || clientPubBytes
    final reqAad = Uint8List(13 + 3 + clientPubBytes.length);
    final prefix = utf8.encode('lumen-gate-v2');
    reqAad.setRange(0, prefix.length, prefix);
    reqAad[prefix.length] = 0;
    reqAad[prefix.length + 1] = 1;
    reqAad[prefix.length + 2] = 1; // keyId = 1
    reqAad.setRange(prefix.length + 3, reqAad.length, clientPubBytes);

    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(true, AEADParameters(KeyParameter(reqKey), 128, iv, reqAad));
    final ciphertextAndTag = cipher.process(reqPlaintext);

    // 5. Binary packet: version(0x02) || keyId(0x01) || clientPub(65b) || IV(12b) || ciphertextAndTag
    final body = Uint8List(
      2 + clientPubBytes.length + iv.length + ciphertextAndTag.length,
    );
    body[0] = 2;
    body[1] = 1;
    body.setRange(2, 2 + clientPubBytes.length, clientPubBytes);
    body.setRange(
      2 + clientPubBytes.length,
      2 + clientPubBytes.length + iv.length,
      iv,
    );
    body.setRange(
      2 + clientPubBytes.length + iv.length,
      body.length,
      ciphertextAndTag,
    );

    // Response AAD: "lumen-gate-v2" || 0x00 || 0x02 || 0x01 || clientPubBytes
    final resAad = Uint8List(13 + 3 + clientPubBytes.length);
    resAad.setRange(0, prefix.length, prefix);
    resAad[prefix.length] = 0;
    resAad[prefix.length + 1] = 2;
    resAad[prefix.length + 2] = 1;
    resAad.setRange(prefix.length + 3, resAad.length, clientPubBytes);

    return {'body': body, 'resKey': resKey, 'aad': resAad};
  }

  static Uint8List _decryptResponse({
    required Uint8List resKey,
    required Uint8List aad,
    required Uint8List respBytes,
  }) {
    final iv = respBytes.sublist(0, 12);
    final ciphertext = respBytes.sublist(12);

    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(false, AEADParameters(KeyParameter(resKey), 128, iv, aad));
    return cipher.process(ciphertext);
  }

  static Future<Map<String, dynamic>?> _executeEncryptedQuery({
    required String path,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final sealed = _sealRequest(path: path, payload: payload);
      final client = http.Client();
      final postRes = await client
          .post(
            Uri.parse('$_apiBase/g'),
            headers: {
              'User-Agent': _ua,
              'Origin': _origin,
              'Referer': '$_origin/watch',
              'Content-Type': 'application/octet-stream',
            },
            body: sealed['body'] as Uint8List,
          )
          .timeout(const Duration(seconds: 7));
      client.close();

      if (postRes.statusCode != 200 || postRes.bodyBytes.length <= 28) {
        debugPrint(
          '[CinejoyScraper] POST /g status: ${postRes.statusCode}, bodyLen: ${postRes.bodyBytes.length}',
        );
        return null;
      }

      final decryptedBytes = _decryptResponse(
        resKey: sealed['resKey'] as Uint8List,
        aad: sealed['aad'] as Uint8List,
        respBytes: postRes.bodyBytes,
      );

      final decryptedJson = utf8.decode(decryptedBytes);
      final decoded = jsonDecode(decryptedJson);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (e, stack) {
      debugPrint('[CinejoyScraper] _executeEncryptedQuery error: $e\n$stack');
    }
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
  }) {
    final controller = StreamController<StreamSource>();
    final isTv = (type == 'series' || type == 'tv');
    final mediaType = isTv ? 'tv' : 'movie';

    () async {
      try {
        final tmdbId = await TmdbHelper.resolveTmdbId(
          imdbId: imdbId,
          title: title,
          type: mediaType,
          year: year,
        );

        if (tmdbId == null || tmdbId <= 0) {
          debugPrint('[CinejoyScraper] Could not resolve TMDb ID for "$title"');
          controller.close();
          return;
        }

        debugPrint(
          '[CinejoyScraper] Starting scrape for "$title" (tmdb: $tmdbId, S:${season}E:$episode)',
        );

        // 1. Fetch available servers dynamically
        List<Map<String, dynamic>> servers = _fallbackServers;
        try {
          final srvRes = await http
              .get(Uri.parse('$_apiBase/servers'), headers: _defaultHeaders)
              .timeout(const Duration(seconds: 4));
          if (srvRes.statusCode == 200) {
            final data = jsonDecode(srvRes.body);
            if (data is Map && data['servers'] is List) {
              servers = (data['servers'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
            }
          }
        } catch (_) {
          // Use fallback servers
        }

        final seenUrls = <String>{};

        // 2. Query all active servers concurrently
        final serverTasks = servers.map((srv) async {
          final srvName = srv['name']?.toString() ?? '';
          if (srvName.isEmpty || srv['status'] == 'disabled') return;
          if (srvName.toLowerCase() == 'sakura' && !isTv) return;

          try {
            final payload = <String, String>{'tmdb': tmdbId.toString()};
            final String targetPath;
            if (isTv) {
              payload['season'] = (season ?? 1).toString();
              payload['episode'] = (episode ?? 1).toString();
              targetPath = '/$srvName/series';
            } else {
              targetPath = '/$srvName/movie';
            }

            debugPrint(
              '[CinejoyScraper] Querying $targetPath with payload $payload',
            );
            final result = await _executeEncryptedQuery(
              path: targetPath,
              payload: payload,
            );

            final dynamic streamData = result != null
                ? (result['data'] is Map
                      ? result['data']['stream']
                      : result['stream'])
                : null;
            final streams = (streamData is List) ? streamData : const [];

            debugPrint(
              '[CinejoyScraper] [$srvName] Result: Got ${streams.length} stream(s)',
            );

            if (streams.isEmpty) return;

            final is4k = srv['4k'] == true;

            for (final st in streams) {
              if (st is! Map) continue;
              final stType = st['type']?.toString();

              if (stType == 'hls') {
                final playlistUrl = (st['playlist'] ?? '').toString().trim();
                if (playlistUrl.isEmpty || seenUrls.contains(playlistUrl)) {
                  continue;
                }
                seenUrls.add(playlistUrl);

                final quality = is4k ? '4K / 1080p' : 'Auto';
                final streamTitle = '[Cinejoy - $srvName] $quality';
                final desc = '$srvName • $quality • HLS';

                debugPrint(
                  '[CinejoyScraper SUCCESS] Added stream source from $srvName: ${redactUrl(playlistUrl)}',
                );

                if (!controller.isClosed) {
                  controller.add(
                    _buildSource(
                      url: playlistUrl,
                      title: streamTitle,
                      quality: quality,
                      description: desc,
                    ),
                  );
                }
              } else if (stType == 'file' && st['qualities'] is Map) {
                final quals = st['qualities'] as Map;
                final subId = st['id']?.toString();

                for (final entry in quals.entries) {
                  final qKey = entry.key.toString();
                  final qVal = entry.value;
                  if (qVal is! Map) continue;

                  final fileUrl = (qVal['url'] ?? '').toString().trim();
                  if (fileUrl.isEmpty ||
                      !fileUrl.startsWith('http') ||
                      seenUrls.contains(fileUrl)) {
                    continue;
                  }
                  seenUrls.add(fileUrl);

                  final quality =
                      qKey.endsWith('p') || qKey.toLowerCase() == '4k'
                      ? qKey
                      : '${qKey}p';
                  final label = subId != null && subId.isNotEmpty
                      ? '$srvName ($subId)'
                      : srvName;
                  final streamTitle = '[Cinejoy - $label] $quality';
                  final format = (qVal['type'] ?? 'mp4')
                      .toString()
                      .toUpperCase();
                  final desc = '$label • $quality • $format';

                  debugPrint(
                    '[CinejoyScraper SUCCESS] Added MP4 source from $label: ${redactUrl(fileUrl)}',
                  );

                  if (!controller.isClosed) {
                    controller.add(
                      _buildSource(
                        url: fileUrl,
                        title: streamTitle,
                        quality: quality,
                        description: desc,
                      ),
                    );
                  }
                }
              }
            }
          } catch (e, stack) {
            debugPrint(
              '[CinejoyScraper] Error querying server $srvName: $e\n$stack',
            );
          }
        });

        await Future.wait(serverTasks);
      } catch (e, stack) {
        debugPrint('[CinejoyScraper] Top-level error: $e\n$stack');
      } finally {
        if (!controller.isClosed) {
          controller.close();
        }
      }
    }();

    return controller.stream;
  }

  StreamSource _buildSource({
    required String url,
    required String title,
    required String quality,
    required String description,
  }) {
    return StreamSource(
      name: title,
      title: title,
      description: description,
      url: url,
      addonName: 'ZPlayHTTP',
      headers: {'User-Agent': _ua, 'Referer': _referer, 'Origin': _origin},
      behaviorHints: {
        'notWebReady': false,
        'proxyHeaders': {
          'request': {
            'User-Agent': _ua,
            'Referer': _referer,
            'Origin': _origin,
          },
        },
      },
    );
  }
}
