import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/backup/profile_cipher.dart';

void main() {
  setUp(() => ProfileCipher.iterations = 2000);
  tearDown(() => ProfileCipher.iterations = 120000);

  test('round-trips a profile without leaving the plaintext in the envelope',
      () {
    const plaintext = '{"settings":{"theme":"ember"},"secrets":{"tmdb":"k"}}';
    final envelope = ProfileCipher.encrypt(plaintext, 'correct horse battery');

    expect(envelope, isNot(contains('ember')));
    expect(envelope, isNot(contains('tmdb')));
    expect(ProfileCipher.isEncrypted(envelope), isTrue);
    expect(ProfileCipher.decrypt(envelope, 'correct horse battery'), plaintext);
  });

  test('a wrong passphrase is rejected', () {
    final envelope = ProfileCipher.encrypt('{"a":1}', 'right-passphrase');

    expect(
      () => ProfileCipher.decrypt(envelope, 'wrong-passphrase'),
      throwsA(isA<ProfileCipherException>()),
    );
  });

  test('a modified envelope is rejected', () {
    final decoded =
        jsonDecode(ProfileCipher.encrypt('{"a":1}', 'passphrase'))
            as Map<String, dynamic>;
    final ciphertext = base64Decode(decoded['ciphertext'] as String);
    ciphertext[0] ^= 0x01;
    decoded['ciphertext'] = base64Encode(ciphertext);

    expect(
      () => ProfileCipher.decrypt(jsonEncode(decoded), 'passphrase'),
      throwsA(isA<ProfileCipherException>()),
    );
  });

  test('a newer or malformed envelope is not opened', () {
    expect(
      () => ProfileCipher.decrypt('{"format":"zplay-profile","version":99}',
          'passphrase'),
      throwsA(isA<ProfileCipherException>()),
    );
    expect(ProfileCipher.isEncrypted('{"settings":{}}'), isFalse);
    expect(ProfileCipher.isEncrypted('not json'), isFalse);
  });
}
