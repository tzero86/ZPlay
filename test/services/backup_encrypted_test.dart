import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/backup/backup_restore_service.dart';
import 'package:zplay/services/backup/profile_cipher.dart';
import 'package:zplay/services/config/service_credentials.dart';
import 'package:zplay/services/storage/secret_keys.dart';
import 'package:zplay/services/storage/secure_store.dart';

const String _addonUrl =
    'https://torrentio.example.test/realdebrid=addon-secret/manifest.json';
const String _portal = 'http://portal.example/?user=me&pass=portal-password';

String _addonDoc(String baseUrl) => jsonEncode(<Map<String, dynamic>>[
  <String, dynamic>{
    'baseUrl': baseUrl,
    'enabled': true,
    'enableCatalogs': false,
    'enableSearch': true,
    'enableStreams': true,
    'enableSubtitles': false,
    'manifest': <String, dynamic>{
      'id': 'com.example.addon',
      'name': 'Example Addon',
      'version': '1.0.0',
      'resources': <String>['stream'],
      'types': <String>['movie'],
      'catalogs': <Object>[],
    },
  },
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemorySecureKeyValueStore secure;

  setUp(() async {
    ProfileCipher.iterations = 2000;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    secure = InMemorySecureKeyValueStore();
    SecureStore.storeOverride = secure;
    await ServiceCredentials.initialize();
  });

  tearDown(() {
    ProfileCipher.iterations = 120000;
    SecureStore.resetForTesting();
  });

  test('a passphrase exports a full encrypted profile', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'installed_addons_v5': _addonDoc(_addonUrl),
      'iptv_custom_portals': <String>[_portal],
      'debrid_service': 'Real-Debrid',
    });
    await SecureStore.write(SecretKeys.traktAccessToken, 'trakt-secret');
    await ServiceCredentials.save(ServiceCredential.wyzie, 'wyzie-secret');

    final exported = await BackupRestoreService.exportSettingsJson(
      passphrase: 'correct horse battery',
    );

    expect(ProfileCipher.isEncrypted(exported), isTrue);
    expect(exported, isNot(contains('trakt-secret')));
    expect(exported, isNot(contains('portal-password')));
    expect(exported, isNot(contains('addon-secret')));

    // Destination device: fresh preferences and a fresh keystore.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final fresh = InMemorySecureKeyValueStore();
    SecureStore.storeOverride = fresh;
    await ServiceCredentials.initialize();

    final message = await BackupRestoreService.importSettingsJson(
      exported,
      passphrase: 'correct horse battery',
    );

    expect(message, contains('full profile'));
    expect(fresh.values[SecretKeys.traktAccessToken], 'trakt-secret');
    expect(
      fresh.values[ServiceCredentials.storageKeyFor(ServiceCredential.wyzie)],
      'wyzie-secret',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('iptv_custom_portals'), <String>[_portal]);
    expect(prefs.getString('installed_addons_v5'), contains(_addonUrl));
  });

  test('a wrong passphrase changes nothing', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'debrid_service': 'Real-Debrid',
    });
    final exported = await BackupRestoreService.exportSettingsJson(
      passphrase: 'right-passphrase',
    );

    SharedPreferences.setMockInitialValues(<String, Object>{
      'debrid_service': 'TorBox',
    });
    await expectLater(
      BackupRestoreService.importSettingsJson(
        exported,
        passphrase: 'wrong-passphrase',
      ),
      throwsA(isA<ProfileCipherException>()),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('debrid_service'), 'TorBox');
  });

  test('an encrypted profile without a passphrase is refused', () async {
    final exported = await BackupRestoreService.exportSettingsJson(
      passphrase: 'some-passphrase',
    );

    await expectLater(
      BackupRestoreService.importSettingsJson(exported),
      throwsA(isA<ProfileCipherException>()),
    );
  });
}
