/// Guards that a Settings toggle row says where focus is and what it is set to.
///
/// Settings rows were converted to `FocusableCard` + `CardFocusRing` after a
/// television could open the page and not enter anything (the rows were bare
/// `InkWell`s). The conversion covered the navigating rows and missed the
/// toggles: `_SettingsSwitchRow` had no card around it, so the only focus node
/// in the row was Material's `Switch` itself. A remote landed on a 40 px thumb
/// at the far edge of the surface, no ring was drawn, and the value the row
/// exists to report - `On`, `Off`, `P2P Active` - stayed in the muted role it
/// shares with every unselected row. Reported from the device as "you go to
/// like the adult setting toggle, that row does not highlight the selected
/// option".
///
/// These drive the real page with real key events rather than asserting on
/// widget types, because the failure is behavioural: a control can be a `Focus`
/// node in the tree and still be unreachable, unactivatable, or give no
/// indication of where it is or what it holds.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/pages/settings/settings_page.dart';
import 'package:zplay/services/content/content_settings.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/services/theme/design_tokens.dart';
import 'package:zplay/widgets/common/focusable_card.dart';

/// The ring [CardFocusRing] paints, and only that: a 2 px accent border. Every
/// ordinary border and hairline on the page is 1 px, so the width separates the
/// focus indicator from the surface's own outline.
Finder _focusRings() => find.byWidgetPredicate(
  (w) =>
      w is DecoratedBox &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).border?.top.width == 2.0,
);

/// The focusable row whose title is [title].
Finder _row(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(FocusableCard));

/// The `FocusNode` a card installs. `FocusableActionDetector` passes its own
/// node explicitly, so the outermost `Focus` inside the card is the card's.
FocusNode _nodeOf(WidgetTester tester, Finder card) {
  final focus = tester.widget<Focus>(
    find.descendant(of: card, matching: find.byType(Focus)).first,
  );
  return focus.focusNode!;
}

/// Walks down the page with the remote's own key until focus is on [row].
///
/// The wire is deliberately the D-pad and not `requestFocus`, because what
/// broke on the television was the path a remote takes, and a programmatically
/// focused node proves nothing about it.
///
/// The stop condition is where the focused node *is*, not which node it is:
/// a row installs more than one focusable (the card, and the `InkWell` the
/// framework puts inside it), and which of them a given key press picks is the
/// framework's business. A row the D-pad cannot reach is not.
Future<void> _dpadToRow(WidgetTester tester, Finder row) async {
  _nodeOf(tester, find.byType(FocusableCard).first).requestFocus();
  await tester.pump();

  final rowRect = tester.getRect(row);
  final path = <String>[];
  for (var press = 0; press < 30; press++) {
    final focused = tester.binding.focusManager.primaryFocus;
    if (_inside(rowRect, focused)) return;
    path.add(_describe(focused));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
  }
  fail('the D-pad never reached the row; it walked: ${path.join(' -> ')}');
}

/// Whether [node]'s centre is inside [rect] - i.e. the row is what is marked.
bool _inside(Rect rect, FocusNode? node) {
  final box = node?.context?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return false;
  return rect.contains(box.localToGlobal(box.size.center(Offset.zero)));
}

/// Where a node is on screen, for a failure message that says which way the
/// traversal actually went.
String _describe(FocusNode? node) {
  final box = node?.context?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return '${node?.context?.widget}';
  final origin = box.localToGlobal(Offset.zero);
  return '${origin.dy.toStringAsFixed(0)}y/${origin.dx.toStringAsFixed(0)}x';
}

/// The row's value label - the text that states what the setting holds.
Text _valueText(WidgetTester tester, Finder row, String value) =>
    tester.widget<Text>(find.descendant(of: row, matching: find.text(value)));

bool _switchValue(WidgetTester tester, Finder row) => tester
    .widget<Switch>(find.descendant(of: row, matching: find.byType(Switch)))
    .value;

Future<void> _pumpSettings(WidgetTester tester) async {
  // Tall enough that the ListView builds every section, CONTENT included, so
  // the adult-content row is in the tree rather than waiting below the fold.
  tester.view.physicalSize = const Size(1280, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  DeviceProfile.debugSetTelevision(value: true);
  addTearDown(() => DeviceProfile.debugSetTelevision(value: false));

  await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
  await tester.pump();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ContentSettings.adultEnabled.value = false;
    // A TV has no touch and no pointer, so a focus highlight is always drawn.
    // Under the default `automatic` strategy the app starts in touch mode and
    // `FocusableActionDetector` never reports the focus highlight at all.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });

  testWidgets('the adult-content toggle row rings and states its value', (
    tester,
  ) async {
    await _pumpSettings(tester);

    final row = _row('Adult Content');
    expect(row, findsOneWidget, reason: 'the row is not a focusable card');
    final tokens = ZplayTokens.of(tester.element(row));

    // Idle: the row carries its value, and nothing is drawn around it.
    expect(_valueText(tester, row, 'Off').style!.color, tokens.textMuted);
    expect(find.descendant(of: row, matching: _focusRings()), findsNothing);
    expect(_switchValue(tester, row), isFalse);

    await _dpadToRow(tester, row);

    expect(
      find.descendant(of: row, matching: _focusRings()),
      findsOneWidget,
      reason: 'a remote on this row has to see where it is',
    );
    expect(
      _valueText(tester, row, 'Off').style!.color,
      tokens.textPrimary,
      reason: 'the value has to be legible in the same glance as the ring',
    );

    // The remote's centre key is the row's, and runs the setting's own change.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump();

    expect(ContentSettings.adultEnabled.value, isTrue);
    expect(_switchValue(tester, row), isTrue);
    expect(
      find.descendant(of: row, matching: find.text('On')),
      findsOneWidget,
      reason: 'the row has to say what it is now set to',
    );
    expect(
      find.descendant(of: row, matching: _focusRings()),
      findsOneWidget,
      reason: 'changing the value must not drop the focus indicator',
    );
  });

  testWidgets('a pointer tap toggles the row exactly once', (tester) async {
    await _pumpSettings(tester);

    final row = _row('Adult Content');

    // The row is the target now, so a pointer press anywhere on it has to run
    // the setting - and only once, because both the row and the switch under
    // it own a tap handler.
    await tester.tap(find.descendant(of: row, matching: find.text('Adult Content')));
    await tester.pump();
    expect(ContentSettings.adultEnabled.value, isTrue);

    await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
    await tester.pump();
    expect(ContentSettings.adultEnabled.value, isFalse);
  });

  testWidgets('every toggle row on the page is a card that rings', (
    tester,
  ) async {
    await _pumpSettings(tester);

    // The Discord row is desktop-only and the test host decides whether it
    // exists, so it is not in this list.
    for (final title in const [
      'Built-in P2P Torrent Source',
      'TV Airing Calendar',
      'AI Recommendation Quiz',
      'Adult Content',
    ]) {
      final row = _row(title);
      expect(row, findsOneWidget, reason: '$title is not a focusable card');

      await _dpadToRow(tester, row);

      expect(
        find.descendant(of: row, matching: _focusRings()),
        findsOneWidget,
        reason: '$title does not mark focus',
      );
      expect(
        find.descendant(of: row, matching: find.byType(Switch)),
        findsOneWidget,
        reason: '$title has to keep the switch that shows its state',
      );
    }
  });
}