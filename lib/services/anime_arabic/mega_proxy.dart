import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../../utils/security/log_redaction.dart';

class MegaResolved {
  final String url;
  final int size;

  const MegaResolved({required this.url, required this.size});
}

class _MegaFile {
  final String dlUrl;
  final int size;
  final Uint8List aesKey;
  final Uint8List nonce;

  const _MegaFile({
    required this.dlUrl,
    required this.size,
    required this.aesKey,
    required this.nonce,
  });
}

class MegaProxy {
  MegaProxy._();
  static final MegaProxy instance = MegaProxy._();

  HttpServer? _server;
  final Map<String, _MegaFile> _files = {};
  int _seq = 0;

  Future<int> _ensureServer() async {
    if (_server != null) return _server!.port;
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.listen(_handle, onError: (e, st) {
      debugPrint('[MegaProxy] listen error: $e');
    });
    _server = s;
    debugPrint('[MegaProxy] bound on 127.0.0.1:${s.port}');
    return s.port;
  }

  /// Resolves a `mega.nz/embed/<id>!<key>` URL to a local proxy URL
  Future<MegaResolved?> resolve(String embedUrl) async {
    try {
      final parsed = _parseEmbed(embedUrl);
      if (parsed == null) {
        debugPrint('[MegaProxy] could not parse embed: ${redactUrl(embedUrl)}');
        return null;
      }
      final (fileId, keyBytes) = parsed;

      // Mega file key is 256 bits split into 8x 32-bit words [k0..k7].
      // AES-128 key = first 4 words XOR last 4 words.
      // CTR nonce  = bytes [16..24].
      final aesKey = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        aesKey[i] = keyBytes[i] ^ keyBytes[i + 16];
      }
      final nonce = Uint8List(8);
      for (var i = 0; i < 8; i++) {
        nonce[i] = keyBytes[i + 16];
      }

      final api = await _megaApi(fileId);
      if (api == null) return null;
      final size = (api['s'] as num?)?.toInt() ?? 0;
      final dlUrl = api['g']?.toString() ?? '';
      if (size <= 0 || dlUrl.isEmpty) {
        debugPrint('[MegaProxy] api missing g/s: $api');
        return null;
      }

      final port = await _ensureServer();
      final token = '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
      _files[token] = _MegaFile(
        dlUrl: dlUrl,
        size: size,
        aesKey: aesKey,
        nonce: nonce,
      );
      final url = 'http://127.0.0.1:$port/v/$token.mp4';
      return MegaResolved(url: url, size: size);
    } catch (e, st) {
      debugPrint('[MegaProxy] resolve failed: $e\n$st');
      return null;
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // Mega API
  // ────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> _megaApi(String fileId) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(
        Uri.parse('https://g.api.mega.co.nz/cs?id=${_seq++}'),
      );
      req.headers.set('Content-Type', 'application/json');
      req.write(jsonEncode([
        {'a': 'g', 'g': 1, 'ssl': 1, 'n': fileId}
      ]));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final list = jsonDecode(body);
      if (list is List && list.isNotEmpty && list[0] is Map) {
        return list[0] as Map<String, dynamic>;
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // Loopback HTTP server handler
  // ────────────────────────────────────────────────────────────────────
  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    if (!path.startsWith('/v/')) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final token = path.substring(3).replaceAll('.mp4', '');
    final file = _files[token];
    if (file == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }

    // CORS & range support
    req.response.headers.set('Access-Control-Allow-Origin', '*');
    req.response.headers.set('Accept-Ranges', 'bytes');
    req.response.headers.set('Content-Type', 'video/mp4');

    int start = 0;
    int end = file.size - 1;
    final rangeHeader = req.headers.value('range');
    var isPartial = false;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final spec = rangeHeader.substring(6).split('-').first;
      final requestedStart = int.tryParse(spec);
      if (requestedStart != null && requestedStart >= 0 && requestedStart < file.size) {
        start = requestedStart;
        isPartial = true;
      }
    }

    final contentLength = end - start + 1;
    req.response.statusCode = isPartial ? HttpStatus.partialContent : HttpStatus.ok;
    if (isPartial) {
      req.response.headers.set('Content-Range', 'bytes $start-$end/${file.size}');
    }
    req.response.headers.set('Content-Length', contentLength.toString());

    if (req.method == 'HEAD') {
      await req.response.close();
      return;
    }

    // Fetch upstream chunk and decrypt AES-CTR on the fly
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final upReq = await client.getUrl(Uri.parse(file.dlUrl));
      upReq.headers.set('Range', 'bytes=$start-$end');
      final upRes = await upReq.close();

      // Initialize AES-CTR cipher with nonce adjusted to byte offset
      final cipher = _initCtrCipher(file.aesKey, file.nonce, start);
      await for (final chunk in upRes) {
        final out = Uint8List(chunk.length);
        cipher.processBytes(
          Uint8List.fromList(chunk),
          0,
          chunk.length,
          out,
          0,
        );
        req.response.add(out);
      }
      await req.response.close();
    } catch (e) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    } finally {
      client.close(force: true);
    }
  }

  CTRStreamCipher _initCtrCipher(
    Uint8List aesKey,
    Uint8List nonce,
    int byteOffset,
  ) {
    // 16-byte CTR counter = 8 bytes nonce + 8 bytes counter (big-endian)
    final blockOffset = byteOffset ~/ 16;
    final iv = Uint8List(16);
    iv.setRange(0, 8, nonce);
    final bd = ByteData.sublistView(iv);
    bd.setUint64(8, blockOffset, Endian.big);

    final cipher = CTRStreamCipher(AESEngine())
      ..init(
        false,
        ParametersWithIV(KeyParameter(aesKey), iv),
      );

    // If byteOffset isn't 16-byte aligned, burn initial intra-block keystream bytes
    final intraBlockSkip = byteOffset % 16;
    if (intraBlockSkip > 0) {
      final dummy = Uint8List(intraBlockSkip);
      cipher.processBytes(dummy, 0, intraBlockSkip, dummy, 0);
    }
    return cipher;
  }

  // ────────────────────────────────────────────────────────────────────
  // URL parsing
  // ────────────────────────────────────────────────────────────────────
  (String, Uint8List)? _parseEmbed(String embedUrl) {
    // mega.nz/embed/<fileId>!<keyB64> or mega.nz/embed/!<fileId>!<keyB64>
    final m = RegExp(r'mega\.(?:nz|co\.nz)/embed/(?:#|!)?([A-Za-z0-9_-]+)!([A-Za-z0-9_-]+)')
        .firstMatch(embedUrl);
    if (m == null) return null;
    final fileId = m.group(1)!;
    final keyB64 = m.group(2)!;
    try {
      final normalized = base64Url.normalize(keyB64);
      final keyBytes = base64Url.decode(normalized);
      if (keyBytes.length != 32) return null;
      return (fileId, keyBytes);
    } catch (_) {
      return null;
    }
  }
}
