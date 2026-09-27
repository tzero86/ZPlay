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
/// Asserts the production decision rather than a reimplementation of focus
/// lookup: the focus walk itself is a documented trap in the widget test
/// binding, and where focus lands was verified on the device, not here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/pages/search/search_page.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/services/layout/form_factor.dart';

void main() {
  tearDown(() => DeviceProfile.debugSetTelevision(value: false));

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
  });
}
