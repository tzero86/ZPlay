/// Guards *which* command the sound control sends.
///
/// The control was wired so that a muted trailer was asked to stay muted:
/// the state the trailer was being asked to take is the opposite of the one
/// it is in, and the script chosen for that state was the wrong one. The
/// button therefore muted a muted trailer, the unmute was never sent, and
/// the video stayed silent however many times the user pressed it.
///
/// Nothing about the button's *appearance* was wrong, and the embed's own
/// script was correct - the mistake was in the choice between the two
/// scripts, which is invisible until the command is watched.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/common/trailer_embed.dart';
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
      // The embed's answer: its live state, as a JSON string.
      return '{"muted":$embedMuted,"ready":true}';
    };
  });

  tearDown(() {
    TrailerPreview.debugBuilder = null;
    TrailerPreview.debugRunScript = null;
  });

  Future<TrailerPreviewHandle> pumpPreview(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TrailerPreview(trailerKey: 'abcdefghijk')),
      ),
    );
    await tester.pump();
    final state = tester.state<State>(find.byType(TrailerPreview));
    return state as TrailerPreviewHandle;
  }

  /// The commands the app sent, without the state reads.
  List<String> commandsSent() =>
      sent.where((s) => s.contains('zplayTrailerCommand')).toList();

  /// Lets the app read the embed's state, then lets its timers run out.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('a muted trailer is asked to unmute', (tester) async {
    final preview = await pumpPreview(tester);
    await settle(tester);
    sent.clear();

    await preview.toggleSound();
    await tester.pump();

    final commands = commandsSent();
    expect(commands, isNotEmpty, reason: 'a command must have been sent');
    expect(
      commands.first,
      contains('zplayTrailerCommand("unmute")'),
      reason: 'a muted trailer must be asked to unmute',
    );
  });

  testWidgets('a trailer with sound is asked to mute', (tester) async {
    // The embed is already making noise, and says so. The app learns the
    // state by reading it back, which is the only way it knows.
    embedMuted = false;
    final preview = await pumpPreview(tester);
    await settle(tester);
    sent.clear();

    await preview.toggleSound();
    await tester.pump();

    final commands = commandsSent();
    expect(commands, isNotEmpty, reason: 'a command must have been sent');
    expect(
      commands.first,
      contains('zplayTrailerCommand("mute")'),
      reason: 'a trailer with sound must be asked to mute',
    );
  });

  test('the two commands are different scripts', () {
    // The scripts must not be interchangeable: the whole defect was that
    // one was used where the other belonged.
    expect(TrailerEmbed.muteScript, isNot(TrailerEmbed.unmuteScript));
    expect(TrailerEmbed.muteScript, contains('"mute"'));
    expect(TrailerEmbed.unmuteScript, contains('"unmute"'));
  });
}
