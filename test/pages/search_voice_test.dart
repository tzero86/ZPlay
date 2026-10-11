/// The search field's microphone: when it exists, and what it does with an
/// answer.
///
/// Two halves. The widget half mounts the real `SearchPage` with the platform
/// channel mocked and checks that the control appears only when a recognizer is
/// reported and that pressing it into a refusal is harmless. The behaviour half
/// calls `applyVoiceTranscript` directly, because a mounted page would run a
/// search against three live network legs, and what a transcript does to the
/// field is a pure step worth proving on its own.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/pages/search/search_page.dart';
import 'package:zplay/services/platform/voice_search.dart';
import 'package:zplay/widgets/common/focusable_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answerAvailability(bool available) {
    messenger.setMockMethodCallHandler(VoiceSearch.channel, (call) async {
      if (call.method == 'isAvailable') return available;
      return null;
    });
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VoiceSearch.debugReset();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(VoiceSearch.channel, null);
    VoiceSearch.debugReset();
  });

  /// Mount the page and let the availability answer arrive.
  ///
  /// The field paints before the channel is asked, so the answer lands a few
  /// frames in - which is the point of asking after the first frame.
  Future<void> openSearchPage(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
  }

  testWidgets('no recognizer means no microphone at all', (tester) async {
    answerAvailability(false);
    await openSearchPage(tester);

    expect(find.byIcon(Icons.mic_rounded), findsNothing,
        reason: 'a control that exists and fails is worse than no control');
  });

  testWidgets('a recognizer puts a focusable, ringed microphone beside the field',
      (tester) async {
    answerAvailability(true);
    await openSearchPage(tester);

    final mic = find.byIcon(Icons.mic_rounded);
    expect(mic, findsOneWidget);

    // The house treatment for anything a remote can land on, so it is neither
    // pointer-only nor the one focusable in the app without a ring.
    final card = find.ancestor(of: mic, matching: find.byType(FocusableCard));
    expect(card, findsOneWidget,
        reason: 'the microphone must be a control a remote can land on');
    expect(tester.widget<FocusableCard>(card).onTap, isNotNull);
    expect(find.descendant(of: card, matching: find.byType(CardFocusRing)),
        findsOneWidget);
    expect(
        find.descendant(of: card, matching: find.byType(FocusableActionDetector)),
        findsOneWidget);
  });

  testWidgets('a refused microphone reports without touching the query',
      (tester) async {
    messenger.setMockMethodCallHandler(VoiceSearch.channel, (call) async {
      if (call.method == 'isAvailable') return true;
      throw PlatformException(code: 'denied');
    });
    await openSearchPage(tester);

    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Microphone access'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
      reason: 'a refusal must not fill or clear the field',
    );
  });

  group('a transcript is exactly what the field runs', () {
    test('fills the field and searches the spoken text', () {
      final controller = TextEditingController(text: 'old query');
      String? changedTo;
      String? searchedFor;

      applyVoiceTranscript(
        '  The Matrix  ',
        controller: controller,
        onChanged: (text) => changedTo = text,
        onSearch: (text) => searchedFor = text,
      );

      expect(controller.text, 'The Matrix',
          reason: 'the field shows the trimmed transcript');
      expect(changedTo, 'The Matrix');
      expect(searchedFor, 'The Matrix',
          reason: 'the search runs on exactly the transcript, just like a chip');
      controller.dispose();
    });

    test('a cancellation leaves the query untouched', () {
      final controller = TextEditingController(text: 'the matrix');
      var touched = 0;

      applyVoiceTranscript(
        null,
        controller: controller,
        onChanged: (_) => touched++,
        onSearch: (_) => touched++,
      );

      expect(controller.text, 'the matrix');
      expect(touched, 0);
      controller.dispose();
    });

    test('an empty transcript is not a search', () {
      final controller = TextEditingController(text: 'the matrix');
      var touched = 0;

      applyVoiceTranscript(
        '   ',
        controller: controller,
        onChanged: (_) => touched++,
        onSearch: (_) => touched++,
      );

      expect(controller.text, 'the matrix');
      expect(touched, 0);
      controller.dispose();
    });
  });
}
