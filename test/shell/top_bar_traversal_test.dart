/// Guards that a remote can cross between the top bar and the page.
///
/// The shell deliberately installs no `FocusTraversalGroup` (see
/// `_AppShellState._layout`): a boundary there once stopped focus leaving the
/// rail entirely, so traversal between the chrome and the content is the
/// platform's own Cartesian search. That is only correct if the geometry is: the
/// bar is a horizontal row across the top, so RIGHT walks along it, DOWN drops
/// into the page, and UP comes back. This drives the real shell through real key
/// events, because the failure it guards is behavioural - a bar that draws
/// correctly and cannot be navigated away from.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/shell/app_shell.dart';
import 'package:zplay/shell/shell_rail.dart';

/// The focused control's global rectangle.
///
/// The focus tree, not the widget tree: what matters is which node the remote is
/// on, and the only way to read that is [FocusManager.primaryFocus].
Rect _focusRect() {
  final context = FocusManager.instance.primaryFocus!.context!;
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

void main() {
  tearDown(() => DeviceProfile.debugSetTelevision(value: false));

  testWidgets('up reaches the bar, left/right walk it, down returns to the page',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    DeviceProfile.debugSetTelevision(value: true);
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(960, 540) * 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: AppShell()));
    // The cold-start splash holds a 1.8 s timer; let it fire rather than leave
    // the harness with a pending timer when the tree comes down.
    await tester.pump(const Duration(seconds: 2));

    final bar = tester.getRect(find.byType(ShellRail));
    expect(bar.height, 48.0);
    // The shell autofocuses the selected row on a television, so a cold launch
    // starts on the bar rather than nowhere.
    final start = _focusRect();
    expect(start.top, lessThan(bar.bottom),
        reason: 'a television starts focused on the bar');

    // RIGHT walks along the bar: the next destination is further right, on the
    // same line.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    final right = _focusRect();
    expect(right.top, lessThan(bar.bottom),
        reason: 'right stays on the bar');
    expect(right.left, greaterThan(start.left),
        reason: 'right moves to the next destination along the bar');

    // DOWN leaves the bar for the page under it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final down = _focusRect();
    expect(down.top, greaterThanOrEqualTo(bar.bottom),
        reason: 'down leaves the bar and lands in the content below it');

    // UP returns to the bar, which is the half that a bottom-anchored chrome
    // would get wrong.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(_focusRect().top, lessThan(bar.bottom),
        reason: 'up comes back to the bar');
  });
}
