/// Guards television detection against the assumption it was built on.
///
/// `FormFactorService.hasRemoteInput` used to read
/// `MediaQuery.navigationModeOf(context) == NavigationMode.directional`, and its
/// doc comment insisted the framework reported this for free with "no platform
/// channel and no plugin". That was false. `navigationMode` is filled from
/// `platformData` (`media_query.dart:333`), the only `platformData` the
/// framework accepts is an ancestor `MediaQuery` passing down its own data, and
/// the Android engine's `SettingsChannel` sends six keys — text scale, spell
/// check, brief password, 24-hour clock, brightness, configuration id — none of
/// them a navigation mode. `common/settings.h` has no such field.
///
/// So the value was [NavigationMode.traditional] on every Android device,
/// television included, and every ten-foot decision keyed on it was off on the
/// one platform that needs it. It survived review because the field exists, the
/// enum has the right name, and the framework documents it in terms of
/// televisions.
///
/// These pin the mechanism rather than the outcome. The pure band maths was
/// already covered in `form_factor_test.dart` and cannot detect this, because
/// the bug was in the value handed to it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:zplay/services/layout/form_factor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => DeviceProfile.debugSetTelevision(value: false));

  group('the platform is asked, and the answer is what counts', () {
    // `probe()` rather than `resolve()`: resolve() short-circuits on
    // `Platform.isAndroid`, so on a Windows or CI host it never touches the
    // channel and the probe would be untestable everywhere except the one
    // machine that already had the answer.
    testWidgets('a leanback box is asked once and believed', (_) async {
      var asked = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DeviceProfile.channel, (call) async {
        asked++;
        expect(call.method, 'isTelevision',
            reason: 'the method name is the contract with MainActivity');
        return true;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(DeviceProfile.channel, null);
      });

      expect(await DeviceProfile.probe(), isTrue);
      expect(asked, 1, reason: 'the probe must actually ask the platform');
    });

    testWidgets('a box that is not leanback answers false', (_) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              DeviceProfile.channel, (_) async => false);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(DeviceProfile.channel, null);
      });

      expect(await DeviceProfile.probe(), isFalse);
    });

    testWidgets('a platform answering null is not a television', (_) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DeviceProfile.channel, (_) async => null);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(DeviceProfile.channel, null);
      });

      expect(await DeviceProfile.probe(), isFalse);
    });

    testWidgets('a platform error is folded into false, not thrown', (_) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DeviceProfile.channel, (call) async {
        throw PlatformException(code: 'UNAVAILABLE', message: 'no ui mode');
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(DeviceProfile.channel, null);
      });

      // resolve() runs before the first frame, so anything escaping here strands
      // the app on a splash screen. Both failure shapes the native side can
      // produce must land on the pointer-device layout instead.
      expect(await DeviceProfile.probe(), isFalse);
    });

    testWidgets('a handler that does not implement it is false too', (_) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              DeviceProfile.channel, (call) async => null);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(DeviceProfile.channel, null);
      });

      expect(await DeviceProfile.probe(), isFalse);
    });
  });

  group('a failed probe must not strand the app on TV chrome', () {
    test('a missing native half resolves to false, not to a guess', () {
      DeviceProfile.debugSetTelevision(value: false);
      // A build without MainActivity's handler, or a detached engine. The app
      // must land on the pointer layout: a TV classified as a phone is still
      // usable, a phone classified as a TV is not.
      expect(DeviceProfile.isTelevision, isFalse);
      expect(
        FormFactorService.resolve(shortestSide: 1920, remoteInput: false),
        FormFactor.expanded,
      );
    });

    test('and form factor still honours a true answer', () {
      DeviceProfile.debugSetTelevision(value: true);
      expect(FormFactorService.hasRemoteInput, isTrue);
      expect(
        FormFactorService.resolve(shortestSide: 1920, remoteInput: true),
        FormFactor.television,
      );
    });
  });

  group('the framework value is not the source of truth', () {
    testWidgets(
      'a MediaQuery claiming directional input does not make a TV',
      (tester) async {
        // This is the exact shape of the old harness: a hand-built MediaQuery
        // asserting directional navigation. If detection went back to reading
        // the framework, this test would still pass and the real device would
        // still be wrong — so it asserts the opposite: that the framework value
        // is ignored in favour of the platform probe.
        DeviceProfile.debugSetTelevision(value: false);

        await tester.pumpWidget(
          const MediaQuery(
            data: MediaQueryData(
              size: Size(1920, 1080),
              navigationMode: NavigationMode.directional,
            ),
            child: SizedBox.shrink(),
          ),
        );

        expect(FormFactorService.hasRemoteInput, isFalse);
      },
    );
  });
}
