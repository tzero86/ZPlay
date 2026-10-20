import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/storage/secret_keys.dart';
import 'package:zplay/services/storage/secure_store.dart';

/// A keystore that is never there, which is what a Linux box without libsecret
/// and a unit test without the plugin both look like.
class _MissingKeystore implements SecureKeyValueStore {
  @override
  Future<String?> read(String key) async => throw StateError('no keystore');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('no keystore');

  @override
  Future<void> delete(String key) async => throw StateError('no keystore');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemorySecureKeyValueStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = InMemorySecureKeyValueStore();
    SecureStore.storeOverride = store;
  });

  tearDown(SecureStore.resetForTesting);

  test('a value written to the keystore is not left in preferences', () async {
    await SecureStore.write(SecretKeys.tmdbApiKey, 'secret-key');

    expect(store.values[SecretKeys.tmdbApiKey], 'secret-key');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(SecretKeys.tmdbApiKey), isFalse);

    expect(await SecureStore.read(SecretKeys.tmdbApiKey), 'secret-key');
  });

  test('a legacy plaintext value migrates on first read', () async {
    SharedPreferences.setMockInitialValues({
      SecretKeys.realDebridToken: 'legacy-token',
    });

    expect(await SecureStore.read(SecretKeys.realDebridToken), 'legacy-token');
    expect(store.values[SecretKeys.realDebridToken], 'legacy-token');

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.containsKey(SecretKeys.realDebridToken),
      isFalse,
      reason: 'the plaintext copy must not outlive the migrated one',
    );

    // A second read comes from the keystore alone.
    expect(await SecureStore.read(SecretKeys.realDebridToken), 'legacy-token');
  });

  test('delete removes the value from both stores', () async {
    await SecureStore.write(SecretKeys.simklAccessToken, 'token');
    await SecureStore.delete(SecretKeys.simklAccessToken);

    expect(store.values.containsKey(SecretKeys.simklAccessToken), isFalse);
    expect(await SecureStore.read(SecretKeys.simklAccessToken), isNull);
  });

  group('without a keystore', () {
    setUp(() {
      SecureStore.storeOverride = _MissingKeystore();
    });

    test('a write and read fall back to preferences under the same key',
        () async {
      await SecureStore.write(SecretKeys.torboxApiKey, 'fallback-key');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SecretKeys.torboxApiKey), 'fallback-key');
      expect(await SecureStore.read(SecretKeys.torboxApiKey), 'fallback-key');
    });

    test('a legacy value stays readable and in place', () async {
      SharedPreferences.setMockInitialValues({
        SecretKeys.allDebridApiKey: 'legacy-key',
      });

      expect(await SecureStore.read(SecretKeys.allDebridApiKey), 'legacy-key');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(SecretKeys.allDebridApiKey),
        'legacy-key',
        reason: 'nothing could be written to the keystore, so the only '
            'readable copy must be left where it is',
      );
    });

    test('delete still clears the preference', () async {
      SharedPreferences.setMockInitialValues({
        SecretKeys.premiumizeApiKey: 'old-key',
      });

      await SecureStore.delete(SecretKeys.premiumizeApiKey);
      expect(await SecureStore.read(SecretKeys.premiumizeApiKey), isNull);
    });
  });

  test('the secret registry covers tokens, keys and the service prefix', () {
    expect(SecretKeys.isSecret(SecretKeys.traktAccessToken), isTrue);
    expect(SecretKeys.isSecret(SecretKeys.traktRefreshToken), isTrue);
    expect(SecretKeys.isSecret(SecretKeys.simklAccessToken), isTrue);
    expect(SecretKeys.isSecret(SecretKeys.tmdbApiKey), isTrue);
    expect(SecretKeys.isSecret(SecretKeys.realDebridToken), isTrue);
    expect(SecretKeys.isSecret(SecretKeys.allDebridApiKey), isTrue);
    expect(SecretKeys.isSecret(SecretKeys.premiumizeApiKey), isTrue);
    expect(SecretKeys.isSecret(SecretKeys.debridLinkApiKey), isTrue);
    expect(SecretKeys.isSecret(SecretKeys.torboxApiKey), isTrue);
    expect(SecretKeys.isSecret(SecretKeys.qobuzEclipseToken), isTrue);
    expect(SecretKeys.isSecret(SecretKeys.qobuzEclipseEndpoint), isTrue);
    expect(SecretKeys.isSecret(SecretKeys.qobuzEclipseManifestUrl), isTrue);
    expect(SecretKeys.isSecret('service_key_wyzie'), isTrue);
    expect(SecretKeys.isSecret('service_key_trakt_secret'), isTrue);
    expect(SecretKeys.isSecret('debrid_service'), isFalse);
    expect(SecretKeys.isSecret('trakt_username'), isFalse);
  });
}
