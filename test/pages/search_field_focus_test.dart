/// Guards that the search field does not trap the remote on a television.
///
/// The search page autofocuses its `TextField`, which is right on a pointer
/// device and fatal on a television. A focused field installs
/// `DirectionalFocusAction.forTextField()` (`editable_text.dart:5699`), and that
/// action deliberately ignores directional intents so the arrows move the caret
/// rather than moving focus. A field that takes focus on arrival therefore traps
/// the remote: the user can type, but every arrow press is consumed inside an
/// empty field, and the whole catalogue behind it is unreachable without a mouse.
///
/// Found on a Chromecast with Google TV. After selecting Search, `DPAD_DOWN`,
/// `DPAD_UP`, `DPAD_LEFT` and `DPAD_RIGHT` all did nothing and the page never
/// became reachable. `DPAD_CENTER` worked, which is why the screen looked healthy
/// and the shell's own focus test - which pressed `Tab`, a path that never
/// touches directional focus - passed over it.
///
/// **The way out is the second half of that defect, and it is narrower than it
/// looks.** A field that swallows the arrows must at least answer the two keys
/// it does *not* claim - BACK (which a remote sends as `goBack`) and `escape` -
/// with "close the keyboard, and put the remote back on the page". The handler
/// lives on the field's own `FocusNode` rather than on a widget above the field,
/// because `escape` is bound to `DismissIntent` by `WidgetsApp` and a focused
/// `EditableText` answers that intent from its own `Actions` map: any ancestor
/// handler is simply never called. Key handling walks the focus chain from the
/// primary node upwards, so the field's node is the one place that runs first.
/// `SearchPage._onFieldKeyEvent` owns the argument in full.
///
/// Asserts the production decision rather than a reimplementation of focus
/// lookup: the focus walk itself is a documented trap in the widget test
/// binding, and where focus lands was verified on the device, not here.
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

  /// The platform keyboard, and every method the page asked it for.
  ///
  /// Mocked rather than left unhandled because hiding the keyboard is a platform
  /// call: it is not something a focus move causes on its own, so "the keyboard
  /// went away" has to be read off the channel that was told to hide it.
  List<String> recordKeyboard() {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(SystemChannels.textInput, (call) async {
      calls.add(call.method);
      return null;
    });
    return calls;
  }

  void answerRecognizer(bool available) {
    messenger.setMockMethodCallHandler(VoiceSearch.channel, (call) async {
      if (call.method == 'isAvailable') return available;
      return null;
    });
  }

  setUp(() {
    // Stated rather than inherited from the test before: every test in this file
    // is about which form factor the page is on, and a leaked `true` would make
    // the pointer assertions pass for the wrong reason.
    DeviceProfile.debugSetTelevision(value: false);
    // The ring is what a television user reads focus from, and `CardFocusRing`
    // only paints in a traditional highlight mode - the same setting
    // `tv_dpad_focus_regression_test.dart` and `tv_home_chrome_reachability_test.dart`
    // establish for the same reason.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VoiceSearch.debugReset();
  });

  tearDown(() {
    DeviceProfile.debugSetTelevision(value: false);
    VoiceSearch.debugReset();
    messenger.setMockMethodCallHandler(SystemChannels.textInput, null);
    messenger.setMockMethodCallHandler(VoiceSearch.channel, null);
  });

  /// Presses the remote's BACK key.
  ///
  /// **The physical key has to be supplied by hand.** `LogicalKeyboardKey.goBack`
  /// has no physical mapping in the simulator's US-layout tables, so
  /// `tester.sendKeyEvent(LogicalKeyboardKey.goBack)` asserts inside
  /// `KeyEventSimulator._findPhysicalKey` before any handler is reached - the
  /// event never exists. Android delivers BACK as keycode 4, and this framework's
  /// own Android table maps keycode 4 to `PhysicalKeyboardKey.digit3` (those
  /// tables are keyed by the platform's keycode, not by HID usage), so this is
  /// the event the engine sends for that press: logical `goBack`, which is the
  /// whole of what the page reads, and a physical key the simulator can look up.
  Future<void> pressBack(WidgetTester tester) => tester.sendKeyEvent(
        LogicalKeyboardKey.goBack,
        physicalKey: PhysicalKeyboardKey.digit3,
      );

  /// Mount the page and let the availability answer land, so the microphone -
  /// if this device has one - is on screen before anything is asked of focus.
  Future<void> openSearchPage(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
  }

  testWidgets('a television does not autofocus the search field', (tester) async {
    DeviceProfile.debugSetTelevision(value: true);

    await tester.pumpWidget(
      const MaterialApp(home: SearchPage()),
    );
    await tester.pump();

    // On the device this was the difference between a usable remote and a
    // frozen one, so it is worth a direct look at the field's own autofocus
    // flag rather than inferring it from focus.
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isFalse,
        reason: 'a television must not open with focus trapped in the field, '
            'because a focused field swallows every arrow press');
    // The second half of the same decision, and the reason the microphone is
    // reachable at all: an arrow must not be able to land *in* the field either.
    // What a television lands on is the card `SearchPage._fieldBox` wraps the
    // box in, and the centre button is what opens the field for typing.
    expect(field.focusNode.skipTraversal, isTrue,
        reason: 'on a television the field is entered through its card, never '
            'by walking an arrow into it');
  });

  testWidgets('a television enters the field through the card around its box',
      (tester) async {
    DeviceProfile.debugSetTelevision(value: true);
    answerRecognizer(false);
    await openSearchPage(tester);

    // The band's one landing place on a television, and the reason a remote can
    // leave it: the card is an ordinary focusable, so the arrows that the field
    // itself would swallow still work while the remote is on it.
    final card = find.ancestor(
      of: find.byType(TextField),
      matching: find.byType(FocusableCard),
    );
    expect(card, findsOneWidget,
        reason: 'the field\'s box has to be a control a television can land on');
    expect(
      find.descendant(of: card, matching: find.byType(CardFocusRing)),
      findsOneWidget,
      reason: 'and it wears the app\'s one focus indicator, like every other '
          'control a remote can land on',
    );

    // The nearest `Focus` above the field is the card's, and the centre button on
    // it is what opens the field - and the platform keyboard - for typing.
    final cardNode = Focus.maybeOf(
      tester.element(find.byType(TextField)),
      scopeOk: true,
    )!;
    cardNode.requestFocus();
    await tester.pump();

    expect(
      tester
          .widgetList<CardFocusRing>(
            find.descendant(of: card, matching: find.byType(CardFocusRing)),
          )
          .any((CardFocusRing ring) => ring.focused),
      isTrue,
      reason: 'the box has to say where the remote is: on a television '
          'CardFocusRing is the only thing that paints a focus indicator',
    );

    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isFalse,
        reason: 'standing on the box must not put the caret in the field: that '
            'is the state the arrows cannot leave');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(field.focusNode.hasFocus, isTrue,
        reason: 'the centre button on the card is how a television starts '
            'typing');
  });

  testWidgets('a pointer device still opens with the field focused',
      (tester) async {
    // The other half of the decision above: `autofocus` is what a text field on
    // a phone or a desktop is expected to do, and a change made for the
    // television must not take it away.
    await openSearchPage(tester);

    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue,
        reason: 'a pointer device keeps the field focused on arrival');
    expect(field.focusNode.skipTraversal, isFalse,
        reason: 'and keeps it an ordinary traversal candidate: nothing about a '
            'television decision may change how Tab and the arrows move here');
    expect(
      find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(FocusableCard),
      ),
      findsNothing,
      reason: 'nor does a pointer device get the television\'s card: a mouse '
          'focuses a text field by pointing at it',
    );
  });

  testWidgets(
      'BACK leaves the field on a television, and the microphone takes the ring',
      (tester) async {
    DeviceProfile.debugSetTelevision(value: true);
    answerRecognizer(true);
    final keyboard = recordKeyboard();
    await openSearchPage(tester);

    final field = tester.widget<EditableText>(find.byType(EditableText));
    field.focusNode.requestFocus();
    await tester.pump();
    expect(field.focusNode.hasPrimaryFocus, isTrue,
        reason: 'the field has to be holding focus for this to be the state '
            'under test - it is the trap');

    await pressBack(tester);
    await tester.pump();

    expect(field.focusNode.hasPrimaryFocus, isFalse,
        reason: 'BACK must get the remote out of the field, or the page behind '
            'it can never be reached with a D-pad');
    final mic = Focus.maybeOf(
      tester.element(find.byIcon(Icons.mic_rounded)),
      scopeOk: true,
    );
    expect(mic?.hasPrimaryFocus, isTrue,
        reason: 'the ring has to land somewhere visible, and on a television '
            'the control nearest the field is the microphone');
    expect(keyboard, contains('TextInput.hide'),
        reason: 'the platform keyboard is not closed by moving Flutter focus, '
            'so the page has to ask for it');
  });

  testWidgets('BACK leaves the field with no recognizer either',
      (tester) async {
    // The same primary defect on a device with no recognizer, where the band has
    // no microphone to hand the ring to: the field must still give the remote
    // back. This is the shape the television emulator has.
    DeviceProfile.debugSetTelevision(value: true);
    answerRecognizer(false);
    final keyboard = recordKeyboard();
    await openSearchPage(tester);

    expect(find.byIcon(Icons.mic_rounded), findsNothing,
        reason: 'no recognizer means no microphone at all');

    final field = tester.widget<EditableText>(find.byType(EditableText));
    field.focusNode.requestFocus();
    await tester.pump();
    expect(field.focusNode.hasPrimaryFocus, isTrue);

    await pressBack(tester);
    await tester.pump();

    expect(field.focusNode.hasPrimaryFocus, isFalse);
    expect(keyboard, contains('TextInput.hide'));
  });

  testWidgets('escape leaves the field too, not just the remote\'s BACK key',
      (tester) async {
    // The key a keyboard sends for the same intention. It is the harder of the
    // two: `escape` is bound to `DismissIntent`, and the focused field answers
    // that itself from inside its own subtree.
    DeviceProfile.debugSetTelevision(value: true);
    answerRecognizer(true);
    recordKeyboard();
    await openSearchPage(tester);

    final field = tester.widget<EditableText>(find.byType(EditableText));
    field.focusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(field.focusNode.hasPrimaryFocus, isFalse,
        reason: 'escape is the keyboard half of BACK, and the field must not '
            'keep it');
  });

  testWidgets('a BACK the keyboard swallowed still leaves the field on its key-up',
      (tester) async {
    // What the emulator actually does while the platform keyboard is showing: the
    // IME takes the key-down for itself (and closes), so Flutter's first sight of
    // the press is the key-up. An unhandled up is re-dispatched to Android, where
    // the shell reads it as "leave Search" - so the up has to be consumed too.
    DeviceProfile.debugSetTelevision(value: true);
    answerRecognizer(true);
    final keyboard = recordKeyboard();
    await openSearchPage(tester);

    final field = tester.widget<EditableText>(find.byType(EditableText));
    field.focusNode.requestFocus();
    await tester.pump();
    expect(field.focusNode.hasPrimaryFocus, isTrue);

    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.digit3,
    );
    await tester.pump();

    expect(field.focusNode.hasPrimaryFocus, isFalse,
        reason: 'the press the keyboard half-consumed must still get the remote '
            'out of the field');
    expect(keyboard, contains('TextInput.hide'));
  });

  testWidgets('a pointer device keeps the field on BACK', (tester) async {
    // Nothing about a phone or a desktop changes: there is no remote to lose,
    // and the field keeps the keys it has always had.
    answerRecognizer(false);
    recordKeyboard();
    await openSearchPage(tester);

    final field = tester.widget<EditableText>(find.byType(EditableText));
    field.focusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(field.focusNode.hasPrimaryFocus, isTrue,
        reason: 'the escape handler is a television decision; a pointer device '
            'must not lose its field to it');
  });
}
