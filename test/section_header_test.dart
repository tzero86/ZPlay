/// Guards the shared section header.
///
/// "See All" was a [TextButton] with `minimumSize: Size.zero` and
/// `tapTargetSize: shrinkWrap` — roughly 28px tall, on the control most likely
/// to be wanted from the far side of a room, and unreachable by D-pad.
///
/// The count is new, and its absence was the less obvious problem: three rails
/// showed no number at all while Continue Watching showed one in an accent pill,
/// so one piece of information looked like two different features.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/common/focusable_card.dart';
import 'package:zplay/widgets/common/section_header.dart';

void main() {
  setUp(() {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });

  Widget host({int? count, VoidCallback? onSeeAll}) => MaterialApp(
    home: Scaffold(
      body: SectionHeader(
        title: 'Because you watched',
        count: count,
        onSeeAll: onSeeAll,
      ),
    ),
  );

  testWidgets('a rail header is its title alone', (tester) async {
    // The count used to sit beside the title; it was detail nobody browses by,
    // so the header prints the name and nothing else.
    await tester.pumpWidget(host(count: 24));
    await tester.pump();
    expect(find.text('24'), findsNothing);
    expect(find.text('Because you watched'), findsOneWidget);
  });

  testWidgets('See All is a comfortable target reachable from a remote', (
    tester,
  ) async {
    var hits = 0;
    await tester.pumpWidget(host(count: 3, onSeeAll: () => hits += 1));
    await tester.pump();

    final action = find.byType(FocusableCard);
    expect(
      action,
      findsOneWidget,
      reason: 'the action must be built on the focus primitive',
    );
    expect(
      tester.getSize(action).height,
      greaterThanOrEqualTo(44),
      reason: 'See All must clear the comfortable minimum target',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(hits, 1, reason: 'select is the Android TV centre key');
  });

  testWidgets('a header without a See All offers nothing to focus', (
    tester,
  ) async {
    await tester.pumpWidget(host(count: 5));
    await tester.pump();

    expect(find.byType(FocusableCard), findsNothing);
  });
}
