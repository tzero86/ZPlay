/// The search field's microphone: where it is, when it exists, and what it does
/// with an answer.
///
/// Two halves. The widget half mounts the real `SearchPage` with the platform
/// channel mocked and checks where the control is on each form factor - the
/// field's suffix on a pointer device, the band's own row on a television, since
/// a suffix is inside the subtree a remote cannot leave - that it appears only
/// when a recognizer is reported, and that pressing it into a refusal is
/// harmless. The behaviour half calls `applyVoiceTranscript` directly, because a
/// mounted page would run a search against three live network legs, and what a
/// transcript does to the field is a pure step worth proving on its own.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/pages/search/search_page.dart';
import 'package:zplay/services/layout/device_profile.dart';
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
    DeviceProfile.debugSetTelevision(value: false);
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

    // **And here it stays inside the field's suffix.** That is where a pointer
    // device looks for it, and the television's version of this control - a
    // sibling in the band, so a D-pad can land on it at all - must not move the
    // one a mouse can already reach. See the television test below.
    expect(
      find.descendant(of: find.byType(TextField), matching: mic),
      findsOneWidget,
      reason: 'a pointer device keeps the microphone in the field it belongs to',
    );
  });

  testWidgets(
      'a television puts the microphone in the band, where the field cannot hide it',
      (tester) async {
    DeviceProfile.debugSetTelevision(value: true);
    final calls = <String>[];
    messenger.setMockMethodCallHandler(VoiceSearch.channel, (call) async {
      calls.add(call.method);
      if (call.method == 'isAvailable') return true;
      return null;
    });
    await openSearchPage(tester);

    final mic = find.byIcon(Icons.mic_rounded);
    expect(mic, findsOneWidget);

    // **Outside the field's subtree.** A suffix is inside it, and a focused
    // `EditableText` answers every arrow key itself, so a microphone in there is
    // one only a user who is already stuck in the field could press - which is
    // the defect this change exists for.
    expect(
      find.descendant(of: find.byType(TextField), matching: mic),
      findsNothing,
      reason: 'inside the field the microphone is unreachable with a remote',
    );

    // A control of the page's own row, on the house treatment, so the ring a
    // remote looks for is drawn for it like for every other card.
    final card = find.ancestor(of: mic, matching: find.byType(FocusableCard));
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.byType(CardFocusRing)),
        findsOneWidget);

    // The remote's traverse-then-press, done on the microphone's own node
    // because a page pumped on its own has no shell bar to walk DOWN out of
    // (`test/tv_dpad_focus_regression_test.dart` drives the real bar): the field
    // is never focused, and the press is voice search.
    final field = tester.widget<EditableText>(find.byType(EditableText));
    final micNode = Focus.maybeOf(tester.element(mic), scopeOk: true)!;
    micNode.requestFocus();
    await tester.pump();
    expect(field.focusNode.hasFocus, isFalse,
        reason: 'the microphone is a destination of its own, not a stop on the '
            'way through the field');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(calls, contains('listen'),
        reason: 'the centre button on the microphone starts voice search');
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
