/// Runs the trailer page's own JavaScript against a fake YouTube player.
///
/// The state read and the mute command are JavaScript, and the bug that
/// shipped was a JavaScript bug: the page published the state *before* the
/// player had applied the change, so the host read the state from before
/// the change and the control never moved.
///
/// A test that asserts the source contains a string cannot catch that. This
/// runs the shipped script in a JavaScript engine with a player that
/// applies its changes asynchronously, the way YouTube's does, and checks
/// what the host is actually told.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/common/trailer_embed.dart';

void main() {
  final node = _findNode();
  // The bridge is written into the page inside a <script> element; a
  // JavaScript engine wants the script itself.
  final bridge = _stripScriptTags(TrailerEmbed.bridgeFor('abcdefghijk'));

  // The JavaScript is only testable where a JavaScript engine is. A
  // machine without one skips rather than fails.
  if (node == null) {
    test('the bridge is testable', () {}, skip: 'no JavaScript engine here');
    return;
  }

  test('the page reports the state the player reached, not the one before', () {
    final result = _run(node, bridge, _playerScript);
    expect(
      result['stateAfterSettle'],
      isFalse,
      reason: 'the page must report the player as unmuted once it settles',
    );
  });

  test('the host is told the truth right after the command', () {
    // The player applies the change a moment after the call returns, so
    // right after the command the truth is *not* yet available: the report
    // says "still muted", because that is what the player is. The host
    // therefore has to read again - and the read it gets later says
    // "unmuted".
    //
    // What must never happen is the report disagreeing with the player.
    final result = _run(node, bridge, _playerScript);
    expect(
      result['settledReport'],
      isTrue,
      reason: 'right after the command the player has not changed yet',
    );
    expect(
      result['stateAfterSettle'],
      isFalse,
      reason: 'and a moment later the player has changed',
    );
  });

  test('a player that changes at once is reported unmuted at once', () {
    // The other shape: a player that applies the change synchronously has
    // nothing to wait for, and the host must not be made to wait for it.
    final result = _run(node, bridge, _instantPlayerScript);
    expect(result['settledReport'], isFalse);
  });

  test('a player that refuses to change is reported as it is', () {
    // An embed that will not make noise must still say so. The control is
    // drawn from this answer, and a control that says "unmuted" over a
    // silent video is a lie.
    final result = _run(node, bridge, _stubbornPlayerScript);
    expect(result['settledReport'], isTrue);
  });

  test('the mute command is reported as a mute', () {
    final result = _run(node, bridge, _playerScript, command: 'mute');
    expect(result['stateAfterSettle'], isTrue);
  });

  group('the video id', () {
    test('cannot close the script literal it is written into', () {
      // The id goes into the page's script as a string literal. An id
      // carrying a quote would otherwise close the literal, and the rest of
      // it would run as code.
      const hostile = "x'; globalThis.__pwned = true; //";
      final html = TrailerEmbed.bridgeFor(hostile);

      expect(
        html,
        contains(r"zplayTrailerVideoId = 'x\'; globalThis.__pwned = true; //'"),
        reason: 'the quote must be escaped inside the literal',
      );
    });

    test('a hostile id does not run when the script is evaluated', () {
      // The escaping is checked by running it, not by reading it: the
      // script is evaluated with a hostile id and must come out clean.
      final result = _run(
        node,
        _stripScriptTags(
          TrailerEmbed.bridgeFor("x'; globalThis.__pwned = true; //"),
        ),
        _playerScript,
      );
      expect(result['stateAfterSettle'], isNotNull);
      expect(
        result['pwned'],
        isNot(true),
        reason: 'the hostile id must not have run',
      );
    });
  });
}

/// A player that applies its changes a moment after the call returns, the
/// way YouTube's does.
const String _playerScript = r'''
const fakePlayer = {
  _muted: true,
  isMuted() { return this._muted; },
  getVolume() { return 100; },
  getPlayerState() { return 1; },
  setVolume(v) { this._volume = v; },
  mute() { setTimeout(() => { this._muted = true; }, 120); },
  unMute() { setTimeout(() => { this._muted = false; }, 120); },
  hideVideoControls() {}
};
global.YT = {
  Player: function (id, opts) {
    // The real API fires onReady once the player is up.
    setTimeout(() => {
      if (opts && opts.events && opts.events.onReady) {
        opts.events.onReady({ target: fakePlayer });
      }
    }, 10);
    return fakePlayer;
  },
  ready: function (fn) { fn(); }
};
''';

/// A player that applies its changes at once.
const String _instantPlayerScript = r'''
const fakePlayer = {
  _muted: true,
  isMuted() { return this._muted; },
  getVolume() { return 100; },
  getPlayerState() { return 1; },
  setVolume(v) { this._volume = v; },
  mute() { this._muted = true; },
  unMute() { this._muted = false; },
  hideVideoControls() {}
};
global.YT = {
  Player: function (id, opts) {
    setTimeout(() => {
      if (opts && opts.events && opts.events.onReady) {
        opts.events.onReady({ target: fakePlayer });
      }
    }, 10);
    return fakePlayer;
  },
  ready: function (fn) { fn(); }
};
''';

/// A player that never changes its mind.
const String _stubbornPlayerScript = r'''
const fakePlayer = {
  _muted: true,
  isMuted() { return this._muted; },
  getVolume() { return 100; },
  getPlayerState() { return 1; },
  setVolume(v) {},
  mute() {},
  unMute() {},
  hideVideoControls() {}
};
global.YT = {
  Player: function (id, opts) {
    setTimeout(() => {
      if (opts && opts.events && opts.events.onReady) {
        opts.events.onReady({ target: fakePlayer });
      }
    }, 10);
    return fakePlayer;
  },
  ready: function (fn) { fn(); }
};
''';

/// Runs the page's bridge and asks it the questions the host asks.
Map<String, dynamic> _run(
  String node,
  String bridge,
  String playerSetup, {
  String command = 'unmute',
}) {
  final script =
      '''
$_domShim
$playerSetup
$bridge

(async function () {
  // The page's own command, as the host runs it.
  window.zplayTrailerCommand('$command');

  // What the host reads back through the settled helper.
  const settledReport = window.zplayTrailerSettled().muted;

  // And what the page says after the player has applied the change.
  await new Promise((r) => setTimeout(r, 400));
  const stateAfterSettle = window.zplayTrailerState.muted;

  process.stdout.write(JSON.stringify({
    settledReport, stateAfterSettle, pwned: !!globalThis.__pwned
  }));
})();
''';
  final file = File(
    '${Directory.systemTemp.path}/zplay_bridge_test_${DateTime.now().microsecondsSinceEpoch}.js',
  );
  file.writeAsStringSync(script);
  try {
    final result = Process.runSync(node, [file.path]);
    final stdout = (result.stdout as String).trim();
    if (stdout.isEmpty) {
      throw StateError(
        'node produced no output (stderr: ${result.stderr})\n$script',
      );
    }
    return jsonDecode(stdout) as Map<String, dynamic>;
  } finally {
    file.deleteSync();
  }
}

String? _findNode() {
  for (final candidate in <String>['node', 'node.exe']) {
    try {
      final result = Process.runSync(candidate, ['--version']);
      if (result.exitCode == 0) return candidate;
    } catch (_) {
      continue;
    }
  }
  return null;
}

/// The script inside a `<script>` element, without the element.
String _stripScriptTags(String html) {
  final open = html.indexOf('<script>');
  final close = html.lastIndexOf('</script>');
  if (open < 0 || close < 0 || close < open) return html;
  return html.substring(open + '<script>'.length, close);
}

/// The smallest page the bridge needs.
///
/// The bridge is a browser script: it looks for a frame, loads the YouTube
/// API and owns a player. A JavaScript engine has neither, so the page is
/// faked just far enough for the bridge to run its own logic - which is
/// what is under test.
const String _domShim = r'''
const _fakeFrame = { contentWindow: {}, src: '' };
global.window = global;
global.document = {
  querySelector: (sel) => (sel === 'iframe' ? _fakeFrame : null),
  createElement: (tag) => ({
    src: '', onerror: null,
    setAttribute() {},
    appendChild() {},
    tagName: tag.toUpperCase()
  }),
  head: { appendChild() {} },
  body: { appendChild() {} }
};
''';
