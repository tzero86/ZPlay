/// Guards that the shell never disables a slot page's own controls.
///
/// `SkipPageShellFocus` exists to defuse a focus node that covers a whole page:
/// such a node takes focus, covers everything beneath it, and no arrow press can
/// reach a control the user can plainly see. It finds that node by walking the
/// focus tree and marking the page's root.
///
/// The walk was wrong. It carried a "we are inside the page now" flag down the
/// tree, which only holds while the focus tree nests the way the element tree
/// does - and it does not. The shell's own `ExcludeFocus` node sits between a
/// page's contents and the page, so the flag was never raised, every control
/// below was classified on its own, and all of them were marked. On the Search
/// page that left the field's own node with `canRequestFocus = false`, so a tap
/// put no cursor in the box and no text reached the controller: the search bar
/// rendered, was hit-testable, and could not be typed into.
///
/// The covering half of the rule is why this is a page-level property and not a
/// control-level one. In the Flutter pinned here `Scaffold` installs no focus
/// node at all, so on most pages the only node inside the page is a leaf
/// control; marking a leaf gains nothing and costs the control its focusability.
///
/// Driven through the real `AppShell`, because the defect needs the shell's own
/// slot wrapper and its `IndexedStack` of five mounted pages: a page mounted
/// under the wrapper alone does not reproduce it. The canvas is a 480 dp phone
/// rather than a narrower one because Home overflows by 28 px at 412 dp, which
/// would fail this test for a reason that has nothing to do with focus.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/shell/app_shell.dart';
import 'package:zplay/shell/shell_rail.dart';

void main() {
  tearDown(() => DeviceProfile.debugSetTelevision(value: false));

  testWidgets('tapping the search field in the shell focuses it and types',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1440, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: AppShell()));
    // The cold-start splash holds a timer; let it fire rather than leave the
    // harness with one pending when the tree comes down.
    await tester.pump(const Duration(seconds: 2));

    // The phone rail is icon-only, so the row is reached by its glyph.
    await tester.tap(find.descendant(
      of: find.byType(ShellRail),
      matching: find.byIcon(Icons.search_rounded),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final field = find.byType(TextField).hitTestable();
    expect(field, findsOneWidget, reason: 'the search slot shows one field');

    final node = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    ).focusNode;

    expect(
      node.canRequestFocus,
      isTrue,
      reason: 'the shell must not disable a page control it mistook for the '
          'page root: a field that cannot request focus renders, accepts taps, '
          'and never takes a cursor',
    );

    // Take focus away first, so this is about the tap and not about autofocus
    // having put the cursor there on arrival.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    await tester.tap(field);
    await tester.pump();
    expect(node.hasFocus, isTrue, reason: 'a tap on the field must focus it');

    await tester.enterText(field, 'breaking bad');
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .controller
          .text,
      'breaking bad',
      reason: 'typed text must reach the controller, which is the half a user '
          'actually notices',
    );
  });
}
