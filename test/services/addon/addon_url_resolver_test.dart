import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/addon/addon_url_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AddonUrlResolver.clearCache();
  });

  tearDown(() {
    AddonUrlResolver.clearCache();
  });

  group('hasPlaceholder', () {
    test('is true for a supported alias', () {
      expect(AddonUrlResolver.hasPlaceholder('https://torrentio.strem.fun/realdebrid={realdebrid}'), isTrue);
      expect(AddonUrlResolver.hasPlaceholder('{debrid}'), isTrue);
    });

    test('is case insensitive', () {
      expect(AddonUrlResolver.hasPlaceholder('{RealDebrid}'), isTrue);
    });

    test('is false for a URL without a supported alias', () {
      expect(AddonUrlResolver.hasPlaceholder('https://v3-cinemeta.strem.io/manifest.json'), isFalse);
      expect(AddonUrlResolver.hasPlaceholder('{unknown}'), isFalse);
    });
  });

  group('resolve', () {
    test('leaves a URL without placeholders untouched', () async {
      const url = 'https://v3-cinemeta.strem.io/manifest.json';
      expect(await AddonUrlResolver.resolve(url), url);
    });

    test('substitutes a saved Real-Debrid token', () async {
      SharedPreferences.setMockInitialValues({'rd_access_token': 'RDKEY123'});
      expect(
        await AddonUrlResolver.resolve('https://torrentio.strem.fun/realdebrid={realdebrid}/manifest.json'),
        'https://torrentio.strem.fun/realdebrid=RDKEY123/manifest.json',
      );
    });

    test('substitutes a saved TorBox key', () async {
      SharedPreferences.setMockInitialValues({'torbox_api_key': 'TBKEY456'});
      expect(await AddonUrlResolver.resolve('{torbox}'), 'TBKEY456');
    });

    test('leaves a placeholder whose key is not configured in place', () async {
      const url = 'https://torrentio.strem.fun/realdebrid={realdebrid}/manifest.json';
      expect(await AddonUrlResolver.resolve(url), url);
    });

    test('leaves a blank key placeholder in place', () async {
      SharedPreferences.setMockInitialValues({'rd_access_token': '   '});
      const url = '{realdebrid}';
      expect(await AddonUrlResolver.resolve(url), url);
    });

    test('follows the selected service for {debrid}', () async {
      SharedPreferences.setMockInitialValues({
        'debrid_service': 'TorBox',
        'torbox_api_key': 'TBKEY456',
        'rd_access_token': 'RDKEY123',
      });
      expect(await AddonUrlResolver.resolve('{debrid}'), 'TBKEY456');
    });

    test('leaves {debrid} in place when no service is selected', () async {
      SharedPreferences.setMockInitialValues({'rd_access_token': 'RDKEY123'});
      expect(await AddonUrlResolver.resolve('{debrid}'), '{debrid}');
    });

    test('handles mixed case placeholders', () async {
      SharedPreferences.setMockInitialValues({'rd_access_token': 'RDKEY123'});
      expect(await AddonUrlResolver.resolve('{RealDebrid}'), 'RDKEY123');
    });

    test('substitutes several placeholders in one URL', () async {
      SharedPreferences.setMockInitialValues({
        'debrid_service': 'Real-Debrid',
        'rd_access_token': 'RDKEY123',
        'torbox_api_key': 'TBKEY456',
      });
      expect(
        await AddonUrlResolver.resolve('https://x.test/{realdebrid}|{torbox}/{debrid}'),
        'https://x.test/RDKEY123|TBKEY456/RDKEY123',
      );
    });

    test('trims whitespace around a saved key', () async {
      SharedPreferences.setMockInitialValues({'rd_access_token': '  RDKEY123  '});
      expect(await AddonUrlResolver.resolve('{realdebrid}'), 'RDKEY123');
    });

    test('resolves the real Torrentio shape to a key bearing URL', () async {
      SharedPreferences.setMockInitialValues({'rd_access_token': 'RDKEY123'});
      expect(
        await AddonUrlResolver.resolve('https://torrentio.strem.fun/realdebrid={realdebrid}'),
        'https://torrentio.strem.fun/realdebrid=RDKEY123',
      );
    });
  });

  group('clearCache', () {
    test('drops cached keys so a rotated key is picked up', () async {
      SharedPreferences.setMockInitialValues({'rd_access_token': 'OLDKEY'});
      expect(await AddonUrlResolver.resolve('{realdebrid}'), 'OLDKEY');

      SharedPreferences.setMockInitialValues({'rd_access_token': 'NEWKEY'});
      expect(await AddonUrlResolver.resolve('{realdebrid}'), 'OLDKEY');

      AddonUrlResolver.clearCache();
      expect(await AddonUrlResolver.resolve('{realdebrid}'), 'NEWKEY');
    });
  });
}
