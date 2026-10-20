/// Guards the hand-off from the sound control to the live preview.
///
/// The control lives in the surface's own row - it has to, because the
/// hero's layers are painted above the preview - so the press cannot reach
/// the preview directly. It travels through the gate, which holds the
/// preview by a key.
///
/// That hand-off was broken: the key named the *gate's* own state while
/// holding the *preview*, so asking it for the preview found nothing and
/// the press ended there. The button was drawn, it was pressed, and the
/// video stayed silent - which is indistinguishable from a button that
/// does not work.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/movie/trailer_preview.dart';

void main() {
  late List<String> sent;
  late bool embedMuted;

  setUp(() {
    sent = <String>[];
    embedMuted = true;
    TrailerPreview.debugBuilder = (key) => const SizedBox.expand();
    TrailerPreview.debugRunScript = (script) async {
      sent.add(script);
      return '{"muted":$embedMuted,"ready":true}';
    };
  });

  tearDown(() {
    TrailerPreview.debugBuilder = null;
    TrailerPreview.debugRunScript = null;
  });

  testWidgets('the gate passes the press on to the preview', (tester) async {
    final gateKey = GlobalKey<TrailerPreviewGateState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrailerPreviewGate(
            key: gateKey,
            hovered: true,
            trailerKey: 'abcdefghijk',
            resolveTrailerKey: () async => 'abcdefghijk',
          ),
        ),
      ),
    );
    // Let the dwell run and the preview mount.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(
      find.byType(TrailerPreview),
      findsOneWidget,
      reason: 'the preview must be up for the control to act on it',
    );

    sent.clear();
    await gateKey.currentState!.toggleSound();
    await tester.pump();

    final commands = sent
        .where((s) => s.contains('zplayTrailerCommand'))
        .toList();
    expect(
      commands,
      isNotEmpty,
      reason: 'the press must reach the preview and become a command',
    );
    expect(
      commands.first,
      contains('zplayTrailerCommand("unmute")'),
      reason: 'a muted trailer must be asked to unmute',
    );
  });

  testWidgets('the gate is what the surface talks to', (tester) async {
    // The surface's control is typed against the handle, so it can ask
    // either the gate or the preview. The gate is the one that owns the
    // live preview.
    final gateKey = GlobalKey<TrailerPreviewGateState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrailerPreviewGate(
            key: gateKey,
            hovered: true,
            trailerKey: 'abcdefghijk',
            resolveTrailerKey: () async => 'abcdefghijk',
          ),
        ),
      ),
    );
    await tester.pump();

    final handle = gateKey.currentState;
    expect(handle, isNotNull);
    expect(handle, isA<TrailerPreviewHandle>());
  });
}
