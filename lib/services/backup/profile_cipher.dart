import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

/// Raised when an encrypted profile cannot be opened.
class ProfileCipherException implements Exception {
  const ProfileCipherException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Passphrase-based encryption for a full profile export.
///
/// The profile file is a JSON envelope containing a PBKDF2-HMAC-SHA256 salt,
/// an AES-256-GCM nonce, and the authenticated ciphertext. The plaintext is
/// never written anywhere; a wrong passphrase or a modified byte fails the GCM
/// tag instead of returning a partial profile.
abstract final class ProfileCipher {
  static const String format = 'zplay-profile';
  static const int envelopeVersion = 1;
  static const String kdfName = 'PBKDF2-HMAC-SHA256';
  static const String cipherName = 'AES-256-GCM';

  /// Iteration count written into new envelopes. A test may lower it; the
  /// count is read back from the envelope, so old files keep working.
  @visibleForTesting
  static int iterations = 120000;

  static const int _saltBytes = 16;
  static const int _nonceBytes = 12;
  static const int _keyBytes = 32;

  /// Whether [contents] is one of this class's encrypted envelopes.
  static bool isEncrypted(String contents) {
    try {
      final decoded = jsonDecode(contents);
      return decoded is Map<String, dynamic> &&
          decoded['format'] == format &&
          decoded['encrypted'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Encrypts [plaintext] under [passphrase] and returns the envelope JSON.
  static String encrypt(String plaintext, String passphrase) {
    if (passphrase.isEmpty) {
      throw const ProfileCipherException('A passphrase is required.');
    }
    final random = Random.secure();
    final salt = _randomBytes(random, _saltBytes);
    final nonce = _randomBytes(random, _nonceBytes);
    final key = _deriveKey(passphrase, salt, iterations);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final ciphertext = cipher.process(utf8.encode(plaintext));

    return jsonEncode(<String, Object?>{
      'format': format,
      'version': envelopeVersion,
      'encrypted': true,
      'kdf': <String, Object?>{
        'name': kdfName,
        'iterations': iterations,
        'salt': base64Encode(salt),
      },
      'cipher': cipherName,
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(ciphertext),
    });
  }

  /// Decrypts an envelope produced by [encrypt].
  ///
  /// Throws [ProfileCipherException] for a wrong passphrase, a tampered
  /// envelope, or a format this build does not understand.
  static String decrypt(String contents, String passphrase) {
    if (passphrase.isEmpty) {
      throw const ProfileCipherException('A passphrase is required.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } catch (_) {
      throw const ProfileCipherException('The profile is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != format ||
        decoded['encrypted'] != true) {
      throw const ProfileCipherException('The profile is not encrypted.');
    }
    if (decoded['version'] != envelopeVersion) {
      throw const ProfileCipherException(
        'This encrypted profile was written by a newer version.',
      );
    }
    if (decoded['cipher'] != cipherName) {
      throw const ProfileCipherException('Unsupported profile cipher.');
    }

    final kdf = decoded['kdf'];
    if (kdf is! Map || kdf['name'] != kdfName) {
      throw const ProfileCipherException('Unsupported profile key derivation.');
    }
    final iterations = kdf['iterations'];
    final salt = _decodeBase64(kdf['salt']);
    final nonce = _decodeBase64(decoded['nonce']);
    final ciphertext = _decodeBase64(decoded['ciphertext']);
    if (iterations is! int ||
        iterations < 1000 ||
        salt == null ||
        salt.length != _saltBytes ||
        nonce == null ||
        nonce.length != _nonceBytes ||
        ciphertext == null ||
        ciphertext.length < 16) {
      throw const ProfileCipherException('The encrypted profile is damaged.');
    }

    final key = _deriveKey(passphrase, salt, iterations);
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
        );
      return utf8.decode(cipher.process(ciphertext));
    } catch (_) {
      throw const ProfileCipherException(
        'Wrong passphrase or the profile was modified.',
      );
    }
  }

  static Uint8List _deriveKey(
    String passphrase,
    Uint8List salt,
    int iterations,
  ) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, _keyBytes));
    return derivator.process(utf8.encode(passphrase));
  }

  static Uint8List _randomBytes(Random random, int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  static Uint8List? _decodeBase64(Object? value) {
    if (value is! String || value.isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }
}
