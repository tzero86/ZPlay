import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/updater/app_updater_service.dart';

void main() {
  const hash =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  group('AppUpdaterService.checksumForAsset', () {
    test('reads sha256sum output', () {
      expect(
        AppUpdaterService.checksumForAsset(
          '$hash  app-arm64-v8a-release.apk\n',
          'app-arm64-v8a-release.apk',
        ),
        hash,
      );
    });

    test('accepts the binary-mode marker and a path prefix', () {
      expect(
        AppUpdaterService.checksumForAsset(
          '$hash *./ZPlay-Windows-Setup.exe',
          'ZPlay-Windows-Setup.exe',
        ),
        hash,
      );
    });

    test('does not match another asset', () {
      expect(
        AppUpdaterService.checksumForAsset('$hash  other.apk', 'app.apk'),
        isNull,
      );
    });

    test('ignores malformed lines', () {
      expect(
        AppUpdaterService.checksumForAsset('not-a-hash  app.apk', 'app.apk'),
        isNull,
      );
    });

    test('returns null for an empty asset name', () {
      expect(AppUpdaterService.checksumForAsset('$hash  app.apk', ''), isNull);
    });
  });
}
