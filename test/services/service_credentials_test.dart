import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/config/legacy_upstream_credentials.dart';
import 'package:zplay/services/config/service_credentials.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ServiceCredentials.buildTimeOverridesForTesting.clear();
    await ServiceCredentials.initialize();
  });

  tearDown(() {
    ServiceCredentials.buildTimeOverridesForTesting.clear();
  });

  group('registry', () {
    test('holds one entry for every credential the enum names', () {
      expect(
        legacyUpstreamCredentialValues.keys.toSet(),
        ServiceCredential.values.toSet(),
      );
    });

    test('every inherited value ships blank', () {
      for (final credential in ServiceCredential.values) {
        final value = legacyUpstreamCredentialValues[credential];
        expect(
          value,
          isNotNull,
          reason: '${credential.name} has no registry entry',
        );
        expect(
          value,
          isEmpty,
          reason: '${credential.name} still ships an upstream credential; ZPlay '
              'sends no upstream keys, so blank it here',
        );
      }
    });

    test('labels, sources and define names are defined for every credential', () {
      for (final credential in ServiceCredential.values) {
        expect(ServiceCredentials.labelFor(credential).isNotEmpty, isTrue);
        expect(ServiceCredentials.sourceHintFor(credential).isNotEmpty, isTrue);
        expect(ServiceCredentials.defineNameFor(credential).isNotEmpty, isTrue);
      }
      expect(
        ServiceCredential.values
            .map(ServiceCredentials.defineNameFor)
            .toSet()
            .length,
        ServiceCredential.values.length,
      );
    });
  });

  group('value ladder', () {
    test('resolves to no source with nothing else set', () {
      const credential = ServiceCredential.wyzie;
      expect(ServiceCredentials.value(credential), isEmpty);
      expect(
        ServiceCredentials.sourceFor(credential),
        CredentialSource.none,
      );
      expect(ServiceCredentials.isUserProvided(credential), isFalse);
      expect(ServiceCredentials.isConfigured(credential), isFalse);
    });

    test('a build-time value wins over the inherited one', () {
      const credential = ServiceCredential.wyzie;
      ServiceCredentials.buildTimeOverridesForTesting[credential] = 'from-build';
      expect(ServiceCredentials.value(credential), 'from-build');
      expect(ServiceCredentials.isUserProvided(credential), isFalse);
    });

    test('a user value wins over the build-time and inherited ones', () async {
      const credential = ServiceCredential.wyzie;
      ServiceCredentials.buildTimeOverridesForTesting[credential] = 'from-build';
      await ServiceCredentials.save(credential, 'from-user');
      expect(ServiceCredentials.value(credential), 'from-user');
      expect(ServiceCredentials.isUserProvided(credential), isTrue);
    });

    test('a blank user value falls through instead of blanking the key', () async {
      const credential = ServiceCredential.wyzie;
      ServiceCredentials.buildTimeOverridesForTesting[credential] = 'from-build';
      await ServiceCredentials.save(credential, '   ');
      expect(ServiceCredentials.value(credential), 'from-build');
      expect(ServiceCredentials.isUserProvided(credential), isFalse);

      ServiceCredentials.buildTimeOverridesForTesting.clear();
      expect(ServiceCredentials.value(credential), isEmpty);
    });

    test('a blank build-time value leaves the credential unconfigured', () {
      const credential = ServiceCredential.xdownloader;
      ServiceCredentials.buildTimeOverridesForTesting[credential] = '';
      expect(ServiceCredentials.value(credential), isEmpty);
      expect(
        ServiceCredentials.sourceFor(credential),
        CredentialSource.none,
      );
      expect(ServiceCredentials.isConfigured(credential), isFalse);
    });
  });

  group('source', () {
    test('reports the rung currently supplying a credential', () async {
      const credential = ServiceCredential.wyzie;
      expect(ServiceCredentials.sourceFor(credential), CredentialSource.none);

      ServiceCredentials.buildTimeOverridesForTesting[credential] = 'from-build';
      expect(
        ServiceCredentials.sourceFor(credential),
        CredentialSource.buildTime,
      );

      await ServiceCredentials.save(credential, 'from-user');
      expect(ServiceCredentials.sourceFor(credential), CredentialSource.user);

      await ServiceCredentials.clear(credential);
      expect(
        ServiceCredentials.sourceFor(credential),
        CredentialSource.buildTime,
      );

      ServiceCredentials.buildTimeOverridesForTesting.clear();
      expect(ServiceCredentials.sourceFor(credential), CredentialSource.none);
    });
  });

  group('persistence', () {
    test('save stores the trimmed value and survives a reload', () async {
      const credential = ServiceCredential.vidgod;
      await ServiceCredentials.save(credential, '  user-token  ');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('service_key_vidgod'), 'user-token');
      expect(ServiceCredentials.notifier(credential).value, 'user-token');

      await ServiceCredentials.initialize();
      expect(ServiceCredentials.value(credential), 'user-token');
      expect(ServiceCredentials.isUserProvided(credential), isTrue);
    });

    test('a stored value is read back on a later launch', () async {
      const credential = ServiceCredential.paper2audio;
      SharedPreferences.setMockInitialValues({
        'service_key_paper2audio': 'stored-token',
      });
      await ServiceCredentials.initialize();

      expect(ServiceCredentials.value(credential), 'stored-token');
      expect(ServiceCredentials.isUserProvided(credential), isTrue);
    });

    test('clear drops the stored value and restores the fallback', () async {
      const credential = ServiceCredential.vidgod;
      await ServiceCredentials.save(credential, 'user-token');
      await ServiceCredentials.clear(credential);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('service_key_vidgod'), isNull);
      expect(ServiceCredentials.isUserProvided(credential), isFalse);
      expect(
        ServiceCredentials.value(credential),
        legacyUpstreamCredentialValues[credential],
      );
    });

    test('the notifier for one credential does not touch another', () async {
      await ServiceCredentials.save(ServiceCredential.wyzie, 'subtitle-key');
      await ServiceCredentials.save(ServiceCredential.vidgod, 'cache-key');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('service_key_wyzie'), 'subtitle-key');
      expect(prefs.getString('service_key_vidgod'), 'cache-key');
      expect(
        ServiceCredentials.notifier(ServiceCredential.wyzie).value,
        'subtitle-key',
      );
      expect(
        ServiceCredentials.notifier(ServiceCredential.paper2audio).value,
        isEmpty,
      );
    });
  });
}
