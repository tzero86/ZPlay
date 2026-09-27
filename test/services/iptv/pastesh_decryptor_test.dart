import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:zplay/services/iptv/pastesh_decryptor.dart';

/// A paste.sh blob: the server key on the first line, then the base64 of
/// `Salted__` + 8-byte salt + AES-256-CBC ciphertext, which is what
/// `PasteShDecryptor` expects to be served at `<id>.txt`.
String _pasteBody(String serverKey, Uint8List blob) =>
    '$serverKey\n${base64.encode(blob)}\n';

/// PBKDF2-HMAC-SHA512, 1 iteration, [dkLen] bytes.
///
/// The 128 is the RFC 4231 HMAC block size for SHA-512; SHA-512 pads to 128
/// bytes, not to its 64-byte digest. paste.sh derives with the standard, and
/// the production decoder passes the same 128.
Uint8List _pbkdf2(Uint8List password, Uint8List salt, int dkLen) {
  final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA512Digest(), 128))
    ..init(pc.Pbkdf2Parameters(salt, 1, dkLen));
  return derivator.process(password);
}

/// OpenSSL `EVP_BytesToKey(md5)`, the scheme older paste.sh blobs were written
/// with, in one chaining round: D_i = MD5(D_{i-1} || password || salt).
Uint8List _evpBytesToKey(Uint8List password, Uint8List salt, int total) {
  final out = <int>[];
  var prev = const <int>[];
  while (out.length < total) {
    prev = pc.MD5Digest()
        .process(Uint8List.fromList([...prev, ...password, ...salt]));
    out.addAll(prev);
  }
  return Uint8List.fromList(out);
}

/// Builds the ciphertext half of a paste.sh blob.
///
/// The app ships a decoder and no encoder, so a round-trip test has to produce
/// the ciphertext itself. This is fixture construction only: it touches no
/// [PasteShDecryptor] member, and every assertion is made against what the
/// production decoder returns.
///
/// The key material mirrors what paste.sh documents, and is assembled here in
/// the same order the decoder expects:
///
///   password = id + serverKey + clientKey + 'https://paste.sh'
///   key||iv  = PBKDF2-HMAC-SHA512(utf8(password), salt, 1, 48)  -> 32B key, 16B iv
///   blob     = 'Salted__' || salt || AES-256-CBC-PKCS7(utf8(plaintext))
Uint8List _blob(
  String id,
  String serverKey,
  String clientKey,
  String plaintext, {
  Uint8List? salt,
  bool legacy = false,
}) {
  final usedSalt = salt ?? Uint8List.fromList([1, 3, 3, 7, 2, 0, 6, 5]);
  // Adjacent-literal concatenation, matching the production password verbatim.
  final password = utf8.encode('$id$serverKey$clientKey' 'https://paste.sh');
  final keyIv = legacy
      ? _evpBytesToKey(password, usedSalt, 48)
      : _pbkdf2(password, usedSalt, 48);

  final cipher = pc.PaddedBlockCipher('AES/CBC/PKCS7')
    ..init(
      true,
      pc.PaddedBlockCipherParameters<pc.ParametersWithIV<pc.KeyParameter>, Null>(
        pc.ParametersWithIV(
          pc.KeyParameter(keyIv.sublist(0, 32)),
          keyIv.sublist(32, 48),
        ),
        null,
      ),
    );

  final ciphertext = cipher.process(utf8.encode(plaintext));
  return Uint8List.fromList([...utf8.encode('Salted__'), ...usedSalt, ...ciphertext]);
}

const String _id = 'AbCdEf';
const String _serverKey = 's3rv3r';
const String _clientKey = 'cl13nt';

/// A loopback paste.sh, so [PasteShDecryptor] can run its real request path.
/// Nothing leaves the machine; only the port is dynamic.
class _FakePasteSh {
  _FakePasteSh(this._server);

  static Future<_FakePasteSh> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakePasteSh(server);
    unawaited(fake._pump());
    return fake;
  }

  final HttpServer _server;
  final seenPaths = <String>[];
  final seenAgents = <String>[];

  /// Body served for `<id>.txt`.
  String body = '';

  /// Status answered with, for the non-2xx case.
  int status = HttpStatus.ok;

  String get origin => 'http://127.0.0.1:${_server.port}';

  /// The url the app is expected to hand to `decrypt`, hash included.
  String urlWith({String id = _id, String clientKey = _clientKey}) =>
      '$origin/$id#$clientKey';

  Future<void> _pump() async {
    await for (final request in _server) {
      seenPaths.add(request.uri.path);
      seenAgents.add(request.headers.value(HttpHeaders.userAgentHeader) ?? '');
      request.response
        ..statusCode = status
        ..write(body);
      await request.response.close();
    }
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late _FakePasteSh paste;

  setUp(() async {
    paste = await _FakePasteSh.start();
  });

  tearDown(() async {
    await paste.stop();
  });

  group('modern PBKDF2 blobs', () {
    test('decrypts a stream url back to exactly what was stored', () async {
      // The headline round trip. A decoder that mangles this returns garbage
      // bytes, which the portal scraper cannot parse, and the channel presents
      // to the user as "does not play" with no error anywhere.
      const stored = 'http://line1.tv:8080/get.php?username=abc&password=xyz';
      paste.body = _pasteBody(_serverKey, _blob(_id, _serverKey, _clientKey, stored));

      expect(await PasteShDecryptor.decrypt(paste.urlWith()), stored);
    });

    test('decrypts a payload that is exactly one aes block', () async {
      // 16 bytes encrypt to one data block plus a full padding block, the case
      // where a dropped or duplicated padding block is least visible.
      const stored = 'xxxxxxxxxxxxxxxx';
      expect(stored.length, 16);
      paste.body = _pasteBody(_serverKey, _blob(_id, _serverKey, _clientKey, stored));

      expect(await PasteShDecryptor.decrypt(paste.urlWith()), stored);
    });

    test('decrypts a payload spanning many blocks', () async {
      // Pastes carry whole portal catalogs, not one line.
      final stored =
          List.generate(200, (i) => 'line$i http://host$i.tv:8080/get.php').join('\n');
      expect(stored.length, greaterThan(2000));
      paste.body = _pasteBody(_serverKey, _blob(_id, _serverKey, _clientKey, stored));

      final out = await PasteShDecryptor.decrypt(paste.urlWith());
      expect(out, stored);
      expect(out.length, stored.length);
    });

    test('decrypts non-ascii channel names and emoji', () async {
      // Channel names carry the source's own encoding, and emoji show up in
      // pasted headers; a decoder that assumes one byte per character loses
      // everything after the first non-ascii rune.
      const stored = 'Спорт 1: Бокс 🥊 — 直接連線';
      paste.body = _pasteBody('ключ', _blob(_id, 'ключ', 'клиент', stored));

      expect(
        await PasteShDecryptor.decrypt(paste.urlWith(clientKey: 'клиент')),
        stored,
      );
    });

    test('decrypts a single character payload', () async {
      paste.body = _pasteBody(_serverKey, _blob(_id, _serverKey, _clientKey, 'a'));

      expect(await PasteShDecryptor.decrypt(paste.urlWith()), 'a');
    });

    test('decrypts when the password is longer than the hmac block', () async {
      // The password is id + serverKey + clientKey + the paste.sh suffix, so a
      // long client key pushes it past SHA-512's 128-byte HMAC block and the
      // derivator has to hash the key down first.
      final longKey = 'k' * 200;
      expect(longKey.length, greaterThan(128));
      const stored = 'http://long.tv/get.php';
      paste.body = _pasteBody(_serverKey, _blob(_id, _serverKey, longKey, stored));

      expect(await PasteShDecryptor.decrypt(paste.urlWith(clientKey: longKey)), stored);
    });

    test('accepts a server key line with surrounding whitespace', () async {
      // Scraped catalogs paste the key with trailing spaces or a carriage
      // return; an untrimmed key would derive the wrong key material.
      const stored = 'http://trim.tv/get.php';
      final blob = _blob(_id, _serverKey, _clientKey, stored);
      paste.body = '  $_serverKey  \r\n${base64.encode(blob)}\r\n';

      expect(await PasteShDecryptor.decrypt(paste.urlWith()), stored);
    });

    test('decodes a base64 blob wrapped across several lines', () async {
      const stored = 'http://wrapped.tv/get.php';
      final b64 = base64.encode(_blob(_id, _serverKey, _clientKey, stored));
      final wrapped = b64.replaceAllMapped(RegExp('.{16}'), (m) => '${m[0]}\n');
      paste.body = '$_serverKey\n$wrapped';

      expect(await PasteShDecryptor.decrypt(paste.urlWith()), stored);
    });
  });

  group('wrong key material', () {
    // A wrong key does not throw and does not return the plaintext. What
    // actually happens is that the PKCS7 padding check inside
    // `PaddedBlockCipher` rejects the random bytes with "Invalid or corrupted
    // pad block", both derivation paths throw, and the decoder swallows that
    // into ''. So a wrong key is loud only because it collapses to empty, and
    // `IptvScraper._fetchPaste` treats empty as "skip this link" -- a silently
    // dropped portal, never a visible error. These lock that down so a change
    // to the swallow-everything behaviour is deliberate.
    test('a wrong client key returns empty', () async {
      const stored = 'http://line1.tv/get.php';
      paste.body = _pasteBody(_serverKey, _blob(_id, _serverKey, _clientKey, stored));

      expect(await PasteShDecryptor.decrypt(paste.urlWith(clientKey: 'wrong')), '');
    });

    test('a wrong client key is deterministic, so the failure is reproducible', () async {
      const stored = 'http://line1.tv/get.php';
      paste.body = _pasteBody(_serverKey, _blob(_id, _serverKey, _clientKey, stored));

      final first = await PasteShDecryptor.decrypt(paste.urlWith(clientKey: 'wrong'));
      final second = await PasteShDecryptor.decrypt(paste.urlWith(clientKey: 'wrong'));

      expect(first, '');
      expect(first, second);
    });

    test('a served server key that differs from the encryption key returns empty', () async {
      // The password mixes in the server key, so a paste whose first line was
      // edited or truncated derives different key material and never unpads.
      const stored = 'http://line1.tv/get.php';
      final blob = _blob(_id, 'encrypted', _clientKey, stored);
      paste.body = _pasteBody('served', blob);

      expect(await PasteShDecryptor.decrypt(paste.urlWith()), '');
    });

    test('a wrong paste id returns empty', () async {
      // The id is the tail of the url path and part of the password, so
      // fetching a blob under a different id must not produce the plaintext.
      const stored = 'http://line1.tv/get.php';
      paste.body = _pasteBody(_serverKey, _blob(_id, _serverKey, _clientKey, stored));

      expect(await PasteShDecryptor.decrypt(paste.urlWith(id: 'Zzzzzz')), '');
    });

    test('a wrong salt returns empty', () async {
      // The salt is read from the blob itself, not from the paste body, so a
      // blob re-hosted with a different salt is a different key.
      const stored = 'http://line1.tv/get.php';
      final blob = _blob(_id, _serverKey, _clientKey, stored);
      final tampered = Uint8List.fromList(blob)..[8] = blob[8] ^ 0xFF;
      paste.body = _pasteBody(_serverKey, tampered);

      expect(await PasteShDecryptor.decrypt(paste.urlWith()), '');
    });

    test('a rare wrong key can slip through as malformed text', () async {
      // The padding check is a 1-in-255-ish filter, not a guarantee. This key
      // is pinned because it is one that slips past: the decoder returns a
      // non-empty string of replacement characters, which
      // `IptvScraper._fetchPaste` hands on as if it were a real portal list.
      // That is the one case where a wrong key produces a non-empty, visibly
      // wrong result rather than a silent skip.
      const stored = 'http://line1.tv/get.php';
      paste.body = _pasteBody(_serverKey, _blob(_id, _serverKey, _clientKey, stored));

      final out = await PasteShDecryptor.decrypt(paste.urlWith(clientKey: 'wrong187'));

      expect(out, isNotEmpty);
      expect(out, isNot(stored));
      expect(out, contains('�'));
    });
  });

  group('legacy EVP_BytesToKey blobs', () {
    test('decrypts a blob written with the md5 fallback scheme', () async {
      // The second derivation path exists for older pastes. The PBKDF2 attempt
      // fails the padding check, `decrypt` then falls through to
      // EVP_BytesToKey(md5) and recovers the plaintext, so the fallback is
      // reachable and must stay reachable.
      const stored = 'http://legacy.tv/get.php';
      paste.body = _pasteBody(
        _serverKey,
        _blob(_id, _serverKey, _clientKey, stored, legacy: true),
      );

      expect(await PasteShDecryptor.decrypt(paste.urlWith()), stored);
    });

    test('decrypts a non-ascii legacy payload', () async {
      const stored = 'Legacy 🥊 西';
      paste.body = _pasteBody(
        _serverKey,
        _blob(_id, _serverKey, _clientKey, stored, legacy: true),
      );

      expect(await PasteShDecryptor.decrypt(paste.urlWith()), stored);
    });
  });

  group('rejected input', () {
    test('an empty url returns empty', () async {
      expect(await PasteShDecryptor.decrypt(''), '');
    });

    test('a url with no client key fragment returns empty without a request', () async {
      expect(await PasteShDecryptor.decrypt('http://127.0.0.1/AbCdEf'), '');
      expect(paste.seenPaths, isEmpty);
    });

    test('a url whose fragment is the whole string returns empty', () async {
      // `#` at index 0 leaves no base url to derive the paste id from.
      expect(await PasteShDecryptor.decrypt('#cl13nt'), '');
      expect(paste.seenPaths, isEmpty);
    });

    test('a non-2xx response returns empty', () async {
      paste.status = HttpStatus.notFound;
      paste.body = _pasteBody(_serverKey, _blob(_id, _serverKey, _clientKey, 'http://x.tv/'));

      expect(await PasteShDecryptor.decrypt(paste.urlWith()), '');
    });

    test('an empty paste body returns empty', () async {
      paste.body = '';

      expect(await PasteShDecryptor.decrypt(paste.urlWith()), '');
    });

    test('a body with only a server key returns empty', () async {
      paste.body = '$_serverKey\n';

      expect(await PasteShDecryptor.decrypt(paste.urlWith()), '');
    });

    test('a body that is not base64 returns empty', () async {
      paste.body = '$_serverKey\nnot base64 !!!\n';

      expect(await PasteShDecryptor.decrypt(paste.urlWith()), '');
    });

    test('a blob too short to hold a salt and ciphertext returns empty', () async {
      paste.body = _pasteBody(_serverKey, Uint8List.fromList([1, 2, 3]));

      expect(await PasteShDecryptor.decrypt(paste.urlWith()), '');
    });

    test('a blob that is just the header returns empty', () async {
      // Exactly 16 bytes: no ciphertext at all. The length guard is `< 17`, so
      // this is the boundary the guard was written for.
      paste.body = _pasteBody(_serverKey, utf8.encode('Salted__12345678'));

      expect(await PasteShDecryptor.decrypt(paste.urlWith()), '');
    });

    test('a blob with a partial ciphertext block returns empty', () async {
      // 17 bytes leaves one byte of ciphertext, which is not a whole AES block.
      // Both derivation paths throw here and the decoder swallows it.
      paste.body = _pasteBody(
        _serverKey,
        Uint8List.fromList([...utf8.encode('Salted__'), 1, 2, 3, 4, 5, 6, 7, 8, 0x41]),
      );

      expect(await PasteShDecryptor.decrypt(paste.urlWith()), '');
    });
  });

  group('request shape', () {
    test('requests the txt form of the paste with a browser user agent', () async {
      // paste.sh answers non-browser clients with an html page, which the
      // decoder would base64-decode into noise and report as an empty paste.
      const stored = 'http://shape.tv/get.php';
      paste.body = _pasteBody(_serverKey, _blob(_id, _serverKey, _clientKey, stored));

      await PasteShDecryptor.decrypt(paste.urlWith());

      expect(paste.seenPaths, ['/$_id.txt']);
      expect(paste.seenAgents, [
        'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 (KHTML, like Gecko)',
      ]);
    });
  });
}
