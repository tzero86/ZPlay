/// Shared harness for TV (D-pad) navigation verification.
///
/// The known lesson this is built on: screenshots and widget harnesses
/// mislead. The hero auto-rotates, so consecutive frames differ whether or
/// not focus moved; a rect read at focus-notification time is pre-layout and
/// therefore unstable within its own frame; and `Tab` takes the fallback
/// order, never the directional path a remote actually drives. So every
/// helper here follows three rules:
///
/// 1. **Identity first.** The focused card is logged by label/id *plus* rect,
///    never rect-only. Once `ensureVisible(alignment: 1)` pins a followed
///    card to the viewport edge, the rect is identical whether focus advances
///    or is stuck - only the id tells them apart.
/// 2. **Arrow keys only.** Traversal is driven with
///    `LogicalKeyboardKey.arrow{Up,Down,Left,Right}` and activated with
///    `LogicalKeyboardKey.select` (the remote's centre key), never Tab/Enter.
/// 3. **Settled reads.** Geometry is read after [pressDpad]'s settle pumps,
///    not in a focus listener, because the scroll jump and the focus change
///    land in the same frame.
///
/// Canvas discipline: the television is 1920x1080 physical at density 320,
/// i.e. 960x540 dp at DPR 2 ([tvLogicalCanvas] / [tvDpr]). Every pump uses
/// it, and the form factor goes through `DeviceProfile.debugSetTelevision`
/// because nothing on Android populates `MediaQuery.navigationMode`.
///
/// Screenshot/dump discipline: a widget-tree screenshot proves nothing about
/// traversal. Physical screenshots come only from `adb exec-out screencap`
/// at 1920x1080 (see `tool/tv_dpad_sequence.sh`), and every run must pair
/// them with the identity trace this harness prints - a frame without a log
/// line is not evidence.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/widgets/common/focusable_card.dart';

/// The television's logical canvas: 1920x1080 physical at DPR 2.
const Size tvLogicalCanvas = Size(960, 540);

/// A dp is two physical px on this panel.
const double tvDpr = 2.0;

/// Settle delay after a D-pad press: one frame for traversal plus time for
/// the scroll jump it triggers to land, so the read below is post-layout.
const Duration tvSettleStep = Duration(milliseconds: 120);

/// Pumps [child] on the television canvas with the television profile and an
/// always-on focus highlight (a TV has no touch, so `automatic` would paint
/// no ring and the test would pass over an invisible indicator).
Future<void> pumpTelevision(WidgetTester tester, Widget child) async {
  DeviceProfile.debugSetTelevision(value: true);
  tester.view.devicePixelRatio = tvDpr;
  tester.view.physicalSize = tvLogicalCanvas * tvDpr;
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() {
    DeviceProfile.debugSetTelevision(value: false);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic;
  });
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pump();
}

/// The label of the card owning [node], or null when focus is not on a card.
///
/// Reads the enclosing [FocusableActionDetector]'s public `focusNode` from a
/// [Text] descendant upward, so the answer is the node the remote is actually
/// on - not the nearest ancestor above the widget, which is the page's own
/// node and reports one fullscreen rect for every card.
String? labelForNode(WidgetTester tester, FocusNode node) {
  for (final el in find.byType(Text).evaluate()) {
    FocusNode? owner;
    el.visitAncestorElements((ancestor) {
      final w = ancestor.widget;
      if (w is FocusableActionDetector) {
        owner = w.focusNode;
        return false;
      }
      return true;
    });
    if (identical(owner, node)) return (el.widget as Text).data;
  }
  return node.debugLabel;
}

/// One log line for what holds focus: identity *plus* rect, never rect-only.
String describePrimaryFocus(WidgetTester tester, {String step = ''}) {
  final node = FocusManager.instance.primaryFocus;
  if (node == null) return '[$step] focus=null';
  final r = node.rect;
  final rect = r.isEmpty
      ? 'no-rect'
      : '${r.left.toStringAsFixed(0)},${r.top.toStringAsFixed(0)} '
          '${r.width.toStringAsFixed(0)}x${r.height.toStringAsFixed(0)}';
  return '[$step] id=${labelForNode(tester, node) ?? node.runtimeType} '
      'rect=$rect hasFocus=${node.hasFocus}';
}

/// The identity of whatever holds focus right now; 'focus=null' when nothing
/// does. Prefer this over rects in expectations.
String focusedId(WidgetTester tester) {
  final node = FocusManager.instance.primaryFocus;
  if (node == null) return 'focus=null';
  return labelForNode(tester, node) ?? node.runtimeType.toString();
}

/// Sends one D-pad [key], settles, logs the identity line, and returns it.
///
/// The line is both printed (so a failing run shows the whole walk) and
/// returned (so tests can assert the walk visited distinct identities).
Future<String> pressDpad(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  String? step,
}) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(tvSettleStep);
  final label = key.keyLabel.isEmpty ? (key.debugName ?? '?') : key.keyLabel;
  final line = describePrimaryFocus(tester, step: step ?? label);
  debugPrint(line);
  return line;
}

/// Fails unless the remote is somewhere at all. A press that drops focus to
/// null is a trap even when every rect looks fine.
void expectFocusHeld(WidgetTester tester, {required String reason}) {
  expect(FocusManager.instance.primaryFocus, isNotNull, reason: reason);
}

/// The layout box of the card showing [label]. Used by the
/// expansion/misplacement guard: focus may repaint, it must never re-flow.
Rect cardLayoutRect(WidgetTester tester, String label) {
  return tester.getRect(find.ancestor(
    of: find.text(label),
    matching: find.byType(FocusableCard),
  ));
}
