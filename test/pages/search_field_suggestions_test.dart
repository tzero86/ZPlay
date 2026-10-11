/// Guards that the television search field does not ask the platform keyboard
/// for a suggestion strip.
///
/// The keyboard on a television is the platform's own IME - the app renders no
/// keyboard and ships no keyboard package - and its suggestion strip is a row
/// that appears above the key grid only once the field has text. Its arrival
/// re-flows every key below it. Verified on a Chromecast with Google TV: with
/// an empty field the keyboard came up without the strip, the first keystroke
/// brought it in, and the key grid moved down under the D-pad. A user is not
/// typing blind, they are pressing the key they can see, so the second press
/// lands on a different letter than the first.
///
/// The lever is `enableSuggestions: false`, which Flutter forwards as
/// `TYPE_TEXT_FLAG_NO_SUGGESTIONS` plus the visible-password variation
/// (`TextInputPlugin.inputTypeFromTextInputType`, which sets both because some
/// devices ignore the first flag alone). The app cannot restyle that keyboard,
/// so the input-type contract is the whole of its influence over it - which is
/// why this is asserted directly rather than through any rendering.
///
/// The flag is television-only on purpose: suggestions are what a text field is
/// expected to offer on a pointer device, and nothing there moves under the
/// user's hand when the strip appears.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/pages/search/search_page.dart';
import 'package:zplay/services/layout/device_profile.dart';

void main() {
  tearDown(() => DeviceProfile.debugSetTelevision(value: false));

  testWidgets('a television asks the IME for no suggestion strip', (
    tester,
  ) async {
    DeviceProfile.debugSetTelevision(value: true);

    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));

    // `TextField.enableSuggestions` defaults to true, so this assertion is the
    // whole difference the television branch makes: before it, the platform was
    // free to add the strip, and the strip is the re-flow.
    expect(
      field.enableSuggestions,
      isFalse,
      reason: 'the platform keyboard re-flows its keys under the D-pad when '
          'this field lets it offer the suggestion strip',
    );
    expect(
      field.autocorrect,
      isFalse,
      reason: 'the field takes a film title; a keyboard that silently rewrites '
          'it is guessing at the one thing the user is sure of',
    );
  });

  testWidgets('a pointer device keeps the suggestions a field is expected to '
      'have', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));

    expect(field.enableSuggestions, isTrue);
    expect(field.autocorrect, isTrue);
  });
}
