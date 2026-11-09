import 'package:flutter/foundation.dart';

import '../../storage/secure_store.dart';
import '../models/debrid_file.dart';

/// The stored-credential half of a Debrid provider.
///
/// The five providers read their key from the keystore under a different
/// [secretKey] and are otherwise the same: trim it, delete it when blank, and
/// answer whether one is configured.
mixin DebridKeyStorage {
  /// The `SecretKeys` constant this provider's credential lives under.
  @protected
  String get secretKey;

  Future<String?> getKey() => SecureStore.read(secretKey);

  /// Stores [key] trimmed, or deletes the credential when it is blank.
  Future<void> saveKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await SecureStore.delete(secretKey);
    } else {
      await SecureStore.write(secretKey, trimmed);
    }
  }

  Future<bool> hasKey() async {
    final key = await getKey();
    return key != null && key.isNotEmpty;
  }
}

/// What the app needs from any provider it can route streams through.
///
/// The APIs answer in different shapes, so the raw map [verifyKey] returns
/// stays provider specific and only [accountLabel] interprets it. Failure
/// classification, error strings and any provider-only fields stay inside the
/// provider.
abstract class DebridProvider with DebridKeyStorage {
  /// Display name, also the value persisted as the selected service.
  String get name;

  /// Checks [key] against the provider's account endpoint.
  ///
  /// Returns the account payload, or null when the key is blank, rejected or
  /// the endpoint could not be reached.
  Future<Map<String, dynamic>?> verifyKey(String key);

  /// The account label for a [verifyKey] payload, or null when it did not
  /// verify.
  ///
  /// Most providers name the account in a `username` field; TorBox falls back to
  /// `email` and Premiumize's payload carries no name at all.
  String? accountLabel(Map<String, dynamic>? payload) =>
      payload?['username'] as String?;

  Future<List<DebridFile>> resolveMagnet(
    String magnet, {
    int? fileIndex,
    String? filename,
    int? season,
    int? episode,
    String? episodeTitle,
  });
}