/// The stalled overlay's new panel: what stopped, what was playing, and the
/// action that goes looking for a source instead of asking the viewer to.
///
/// The focus contract is the part worth a test. On a television the panel is
/// the only thing on screen, and the centre button has to land on the search -
/// not on the diagnostics copy, and not on the player's own shortcuts.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/player/player_loading_overlay.dart';

import '../support/tv_nav_harness.dart';

const String _message =
    'This stream is not responding - the source may be expired.';
const String _context = 'MovieBoxProviderIN · 1080p · CNCVerse Bridge';

Widget _overlay({
  required FocusNode entry,
  required void Function(String) onAction,
  VoidCallback? onFindSource,
  VoidCallback? onCancelFindSource,
  bool finding = false,
  String? progress,
}) {
  return PlayerLoadingOverlay(
    message: _message,
    stalled: true,
    entryFocusNode: entry,
    sourceContext: _context,
    onChooseSource: () => onAction('choose-source'),
    onGoBack: () => onAction('go-back'),
    onCopyDiagnostic: () => onAction('copy-diagnostic'),
    onFindSource: onFindSource,
    onCancelFindSource: onCancelFindSource,
    findingSource: finding,
    findSourceProgress: progress,
  );
}

void main() {
  late FocusNode entry;

  setUp(() {
    entry = FocusNode(debugLabel: 'PlayerStallFindSource');
  });

  tearDown(() {
    entry.dispose();
  });

  testWidgets('the panel names the issue, the source and both escape actions', (
    tester,
  ) async {
    await pumpTelevision(
      tester,
      _overlay(entry: entry, onAction: (_) {}, onFindSource: () {}),
    );

    expect(find.text('PLAYBACK ISSUE'), findsOneWidget);
    expect(find.text("This source isn't responding"), findsOneWidget);
    expect(find.text(_message), findsOneWidget);
    expect(find.text(_context), findsOneWidget);
    expect(find.text('Find best source'), findsOneWidget);
    expect(find.text('Choose another source'), findsOneWidget);
    expect(find.text('Go back'), findsOneWidget);
    expect(find.text('Copy diagnostic'), findsOneWidget);
  });

  testWidgets('entry focus lands on the search and the centre button runs it', (
    tester,
  ) async {
    final actions = <String>[];

    await pumpTelevision(
      tester,
      _overlay(
        entry: entry,
        onAction: actions.add,
        onFindSource: () => actions.add('find-source'),
      ),
    );

    expect(entry.hasPrimaryFocus, isTrue);
    expect(focusedId(tester), 'Find best source');

    await pressDpad(tester, LogicalKeyboardKey.select);

    expect(actions, ['find-source']);
  });

  testWidgets('a running search shows its progress and cancels on press', (
    tester,
  ) async {
    final actions = <String>[];

    await pumpTelevision(
      tester,
      _overlay(
        entry: entry,
        onAction: actions.add,
        onFindSource: () => actions.add('find-source'),
        onCancelFindSource: () => actions.add('cancel-find-source'),
        finding: true,
        progress: 'Testing 4 of 12…',
      ),
    );

    expect(find.text('Testing 4 of 12…'), findsOneWidget);
    expect(find.text('Find best source'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await pressDpad(tester, LogicalKeyboardKey.select);

    expect(actions, ['cancel-find-source']);
  });

  testWidgets('a search with no progress yet falls back to its own line', (
    tester,
  ) async {
    await pumpTelevision(
      tester,
      _overlay(
        entry: entry,
        onAction: (_) {},
        onFindSource: () {},
        finding: true,
      ),
    );

    expect(find.text('Finding a working source…'), findsOneWidget);
  });

  testWidgets('without a search the old focus target is unchanged', (
    tester,
  ) async {
    await pumpTelevision(tester, _overlay(entry: entry, onAction: (_) {}));

    expect(entry.hasPrimaryFocus, isTrue);
    expect(focusedId(tester), 'Choose another source');
    expect(find.text('Find best source'), findsNothing);
  });

  testWidgets('the panel fits a 320 dp phone without overflowing', (
    tester,
  ) async {
    await pumpTelevision(
      tester,
      _overlay(entry: entry, onAction: (_) {}, onFindSource: () {}),
    );

    tester.view.physicalSize = const Size(320 * tvDpr, 640 * tvDpr);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Find best source'), findsOneWidget);
    expect(find.text('Go back'), findsOneWidget);
  });
}
