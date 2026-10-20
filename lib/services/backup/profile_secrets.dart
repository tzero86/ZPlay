import '../config/service_credentials.dart';
import '../storage/secret_keys.dart';
import '../storage/secure_store.dart';

/// The credential set carried by an encrypted full-profile export.
///
/// A redacted profile deliberately carries none of this. When the user chooses
/// a passphrase, the profile is encrypted and these values travel inside it;
/// they are written back through [SecureStore] on import, never through the
/// plaintext preference map.
abstract final class ProfileSecrets {
  /// Reads every supported credential from its secure store.
  static Future<Map<String, String>> export() async {
    final values = <String, String>{};
    for (final key in SecretKeys.values) {
      final value = await SecureStore.read(key);
      if (value != null && value.isNotEmpty) {
        values[key] = value;
      }
    }
    for (final credential in ServiceCredential.values) {
      final value = ServiceCredentials.notifier(credential).value.trim();
      if (value.isNotEmpty) {
        values[ServiceCredentials.storageKeyFor(credential)] = value;
      }
    }
    return values;
  }

  /// Writes the decrypted credential map back through [SecureStore].
  ///
  /// Only keys this build actually reads are accepted, so a future or
  /// hand-edited profile cannot inject arbitrary names into the keystore.
  static Future<void> import(Map<String, dynamic> raw) async {
    final knownServiceKeys = <String>{
      for (final credential in ServiceCredential.values)
        ServiceCredentials.storageKeyFor(credential),
    };
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is! String || value.isEmpty) continue;
      if (!SecretKeys.values.contains(key) && !knownServiceKeys.contains(key)) {
        continue;
      }
      await SecureStore.write(key, value);
    }
  }
}
