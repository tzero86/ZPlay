import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/backup/profile_secrets.dart';
import 'package:zplay/services/config/service_credentials.dart';
import 'package:zplay/services/storage/secret_keys.dart';
import 'package:zplay/services/storage/secure_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemorySecureKeyValueStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = InMemorySecureKeyValueStore();
    SecureStore.storeOverride = store;
    await ServiceCredentials.initialize();
  });

  tearDown(SecureStore.resetForTesting);

  test('exports and imports the full credential set through the keystore',
      () async {
    await SecureStore.write(SecretKeys.traktAccessToken, 'trakt-token');
    await SecureStore.write(SecretKeys.torboxApiKey, 'torbox-key');
    await ServiceCredentials.save(ServiceCredential.wyzie, 'wyzie-key');

    final exported = await ProfileSecrets.export();
    expect(exported[SecretKeys.traktAccessToken], 'trakt-token');
    expect(exported[SecretKeys.torboxApiKey], 'torbox-key');
    expect(
      exported[ServiceCredentials.storageKeyFor(ServiceCredential.wyzie)],
      'wyzie-key',
    );

    final fresh = InMemorySecureKeyValueStore();
    SecureStore.storeOverride = fresh;
    await ProfileSecrets.import(exported);

    expect(fresh.values[SecretKeys.traktAccessToken], 'trakt-token');
    expect(fresh.values[SecretKeys.torboxApiKey], 'torbox-key');
    expect(
      fresh.values[ServiceCredentials.storageKeyFor(ServiceCredential.wyzie)],
      'wyzie-key',
    );
  });

  test('ignores unknown keys and non-secret names', () async {
    await ProfileSecrets.import(<String, dynamic>{
      'not_a_secret': 'value',
      SecretKeys.tmdbApiKey: 'tmdb-key',
      'service_key_unknown': 'ignored',
    });

    expect(store.values['not_a_secret'], isNull);
    expect(store.values[SecretKeys.tmdbApiKey], 'tmdb-key');
    expect(store.values['service_key_unknown'], isNull);
  });
}
