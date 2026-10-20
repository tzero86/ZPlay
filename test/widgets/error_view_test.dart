/// `ErrorView`'s optional second action: the failure surfaces that can hand a
/// user a diagnostic report need a control for it, and every existing caller
/// must render exactly what it rendered before.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/common/error_view.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  testWidgets('secondary action renders and fires without retrying', (
    tester,
  ) async {
    var secondary = 0;
    var retried = 0;

    await _pump(
      tester,
      ErrorView(
        error: 'no source answered',
        onRetry: () => retried++,
        secondaryActionLabel: 'Copy diagnostic',
        onSecondaryAction: () => secondary++,
      ),
    );

    expect(find.text('Copy diagnostic'), findsOneWidget);
    await tester.tap(find.text('Copy diagnostic'));
    await tester.pump();

    expect(secondary, 1);
    expect(retried, 0);
  });

  testWidgets('no secondary action when the caller passes none', (
    tester,
  ) async {
    await _pump(tester, ErrorView(error: 'boom', onRetry: () {}));

    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('a label without a callback draws nothing', (tester) async {
    await _pump(
      tester,
      ErrorView(
        error: 'boom',
        onRetry: () {},
        secondaryActionLabel: 'Copy diagnostic',
      ),
    );

    expect(find.text('Copy diagnostic'), findsNothing);
  });
}
