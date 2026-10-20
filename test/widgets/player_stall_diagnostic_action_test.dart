/// The dead-stream overlay's third action: copying the diagnostic report.
///
/// It is an escape hatch beside the two that get a viewer off a dead source, so
/// it must stay *after* them in traversal order: the overlay's contract is that
/// the remote lands on "Choose another source", and a diagnostics action that
/// took that landing would make the one screen a stuck viewer sees worse.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/common/focusable_card.dart';
import 'package:zplay/widgets/player/player_loading_overlay.dart';

import '../support/tv_nav_harness.dart';

const String _message =
    'This stream is not responding - the source may be expired.';

void main() {
  late FocusNode entry;

  setUp(() {
    entry = FocusNode(debugLabel: 'PlayerStallChooseSource');
  });

  tearDown(() {
    entry.dispose();
  });

  testWidgets('the copy action renders and fires beside the escape actions', (
    tester,
  ) async {
    final actions = <String>[];

    await pumpTelevision(
      tester,
      PlayerLoadingOverlay(
        message: _message,
        stalled: true,
        entryFocusNode: entry,
        onChooseSource: () => actions.add('choose-source'),
        onGoBack: () => actions.add('go-back'),
        onCopyDiagnostic: () => actions.add('copy-diagnostic'),
      ),
    );

    expect(find.text('Copy diagnostic'), findsOneWidget);

    await tester.tap(find.text('Copy diagnostic'));
    await tester.pump();

    expect(actions, <String>['copy-diagnostic']);
  });

  testWidgets('focus still lands on the first escape action', (tester) async {
    await pumpTelevision(
      tester,
      PlayerLoadingOverlay(
        message: _message,
        stalled: true,
        entryFocusNode: entry,
        onChooseSource: () {},
        onGoBack: () {},
        onCopyDiagnostic: () {},
      ),
    );

    expect(entry.hasPrimaryFocus, isTrue);
    expect(
      tester
          .widgetList<CardFocusRing>(find.byType(CardFocusRing))
          .any((ring) => ring.focused),
      isTrue,
    );
  });

  testWidgets('the action is absent when no handler is supplied', (
    tester,
  ) async {
    await pumpTelevision(
      tester,
      PlayerLoadingOverlay(
        message: _message,
        stalled: true,
        entryFocusNode: entry,
        onChooseSource: () {},
        onGoBack: () {},
      ),
    );

    expect(find.text('Copy diagnostic'), findsNothing);
    expect(find.text('Choose another source'), findsOneWidget);
  });
}
