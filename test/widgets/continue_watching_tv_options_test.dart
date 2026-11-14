import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zplay/models/continue_watching/continue_watching_item.dart';
import 'package:zplay/services/continue_watching/continue_watching_service.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/widgets/common/focusable_card.dart';
import 'package:zplay/widgets/home/continue_watching_slider.dart';

/// On a television the Continue Watching card's corner icons (details,
/// remove) cannot be reached - a remote lands on the card, never on a 22 dp
/// icon inside it. The card takes those actions itself: holding OK, or the
/// Menu key, opens an options panel a remote can walk.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DeviceProfile.debugSetTelevision(value: true);
    ContinueWatchingService.activeItems.value = [
      ContinueWatchingItem(
        id: 'probe',
        title: 'Probe Show',
        type: 'movie',
        positionSeconds: 2520,
        totalDurationSeconds: 6000,
        lastWatchedAt: DateTime(2024),
        isTorrent: false,
      ),
    ];
  });

  tearDown(() {
    DeviceProfile.debugSetTelevision(value: false);
    ContinueWatchingService.activeItems.value = const [];
  });

  Future<FocusNode> focusCard(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 420,
            child: ContinueWatchingSlider(),
          ),
        ),
      ),
    );
    await tester.pump();
    final card = find.ancestor(
      of: find.text('Probe Show'),
      matching: find.byType(FocusableCard),
    );
    final node = tester.widget<FocusableCard>(card.first).focusNode;
    expect(node, isNotNull, reason: 'the card owns the node that sees OK');
    node!.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return node;
  }

  testWidgets('the focused card says how to reach its options', (tester) async {
    await focusCard(tester);
    expect(find.text('Hold OK for options'), findsOneWidget);
    // The unreachable corner icons are not drawn on a television.
    expect(find.byTooltip('Remove from Continue Watching'), findsNothing);
  });

  testWidgets('holding OK opens the options instead of resuming', (
    tester,
  ) async {
    await focusCard(tester);

    await simulateKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(
      find.text('Remove from Continue Watching'),
      findsNothing,
      reason: 'a press is not a hold until the remote starts repeating',
    );
    await simulateKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await simulateKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('View details'), findsOneWidget);
    expect(find.text('Remove from Continue Watching'), findsOneWidget);
  });

  testWidgets('the Menu key opens the options too, and Back closes them', (
    tester,
  ) async {
    await focusCard(tester);

    await simulateKeyDownEvent(LogicalKeyboardKey.contextMenu);
    await simulateKeyUpEvent(LogicalKeyboardKey.contextMenu);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Remove from Continue Watching'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Remove from Continue Watching'), findsNothing);
  });
}
