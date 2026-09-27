/// Guards the P2P advisory against a short viewport.
///
/// The dialog is three bands: a fixed header, a scrolling body and a fixed
/// action bar. It laid the column out with `mainAxisSize.min`, so the column
/// sized itself to its content and the `Flexible` body was offered the full
/// height of its content rather than what was actually left over. On a short
/// viewport the column overflowed instead of shrinking the scroll area.
///
/// Found on a Chromecast with Google TV, which reports 960x540 dp: the third
/// engine row, "ZPlay (Torrent Engine)", was sliced in half and hidden behind
/// the buttons, with no scroll affordance to suggest there was more. A user
/// choosing between streaming sources could not read one of the three.
///
/// A desktop window could never have caught this: at 1080 dp tall the content
/// fits, `min` and `max` agree, and the dialog is correct either way.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/p2p/p2p_warning_dialog.dart';

/// Pumps the dialog at a given logical size and reports whether the framework
/// recorded a render overflow, which is the real invariant: not "it looks right"
/// but "Flutter did not complain".
Future<bool> _overflowsAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Opened the way the app opens it. A `Dialog` is a route with its own inset
  // and minimum width, so pumping it as `home` hands it an unbounded width and
  // it overflows horizontally at *every* size - a harness artefact that has
  // nothing to do with the height under test.
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const P2pWarningDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump();
  return tester.takeException() != null;
}

void main() {
  testWidgets('a television-sized viewport does not overflow', (tester) async {
    // The reported device: 1920x1080 at density 320 is 960x540 dp.
    expect(
      await _overflowsAt(tester, const Size(960, 540)),
      isFalse,
      reason: 'the third engine row was sliced in half and hidden behind the '
          'buttons at this height',
    );
  });

  testWidgets('a phone-sized viewport does not overflow', (tester) async {
    expect(await _overflowsAt(tester, const Size(390, 844)), isFalse);
  });

  testWidgets('a desktop viewport still does not overflow', (tester) async {
    expect(await _overflowsAt(tester, const Size(1920, 1080)), isFalse);
  });

  testWidgets('every engine choice is present and readable', (tester) async {
    expect(await _overflowsAt(tester, const Size(960, 540)), isFalse);

    // The content that was being cut off on the television.

    for (final label in [
      'ZPlayHTTP (Direct Stream)',
      'ZPlay (Torrent Engine)',
    ]) {
      expect(find.text(label), findsOneWidget,
          reason: 'a user cannot choose between sources they cannot read');
    }
  });
}
