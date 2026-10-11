/// Pins the Dart half of the voice-search contract with the native bridge.
///
/// The channel is the whole interface between the app and the platform's
/// recognizer, and every branch on it is a real device state: a television with
/// Google's recognizer, a phone with none, a desktop build with no native half
/// at all, and a refused microphone. None of those can be produced on the
/// machine that runs these tests, so each is faked at the channel boundary and
/// the answers - not the wiring - are asserted.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/platform/voice_search.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answerWith(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(VoiceSearch.channel, handler);
  }

  setUp(VoiceSearch.debugReset);

  tearDown(() {
    messenger.setMockMethodCallHandler(VoiceSearch.channel, null);
    VoiceSearch.debugReset();
  });

  group('availability is asked once and every answer is a boolean', () {
    test('a yes is believed and remembered', () async {
      var asked = 0;
      answerWith((call) async {
        asked++;
        expect(call.method, 'isAvailable',
            reason: 'the method name is the contract with VoiceSearchBridge');
        return true;
      });

      expect(await VoiceSearch.available(), isTrue);
      expect(await VoiceSearch.available(), isTrue);
      expect(asked, 1,
          reason: 'a cached answer, so a rebuild never re-asks the platform');
    });

    test('a no is a no', () async {
      answerWith((_) async => false);
      expect(await VoiceSearch.available(), isFalse);
    });

    test('a null answer is treated as no', () async {
      answerWith((_) async => null);
      expect(await VoiceSearch.available(), isFalse);
    });

    test('a platform error folds into false rather than throwing', () async {
      answerWith((_) async => throw PlatformException(code: 'boom'));
      expect(await VoiceSearch.available(), isFalse);
    });

    test('a channel with no native half folds into false', () async {
      // No handler at all: this is the Windows or web build, where the platform
      // throws MissingPluginException at the call.
      expect(await VoiceSearch.available(), isFalse);
    });
  });

  group('listen passes the platform answer through unchanged', () {
    test('a transcript comes back as spoken', () async {
      answerWith((call) async => call.method == 'listen' ? 'the matrix' : true);
      expect(await VoiceSearch.listen(), 'the matrix');
    });

    test('a cancellation comes back as null', () async {
      answerWith((call) async => call.method == 'listen' ? null : true);
      expect(await VoiceSearch.listen(), isNull);
    });

    test('a refusal keeps its code: denied', () async {
      answerWith((_) async => throw PlatformException(code: 'denied'));
      expect(
        VoiceSearch.listen(),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', 'denied'),
        ),
      );
    });

    test('a refusal keeps its code: unavailable', () async {
      answerWith((_) async => throw PlatformException(code: 'unavailable'));
      expect(
        VoiceSearch.listen(),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', 'unavailable'),
        ),
      );
    });
  });
}
