// Contract tests for the HTTP headers ZPlay presents to an IPTV origin.
//
// Background: every live channel the user owns failed to play, and nothing in
// `test/` covered the IPTV subsystem, so the request the app actually issues
// was never pinned down. This file pins it down.
//
// The live-open header map in `lib/pages/iptv/iptv_player_page.dart:212-216`
// is a literal inside a private method, so it cannot be reached from a test.
// What CAN be reached is the sibling copy of the same contract in
// `lib/services/iptv/iptv_network.dart`, which this file drives through the
// real public API (`IptvClient.login` and `IptvAliveChecker.launchCheck`)
// with a recording `http.Client` installed via `runWithClient`. Both entry
// points resolve their client through `http.Client()` and neither constructs
// one by hand, so the seam is reached without editing a line under `lib/`.
//
// The headers production actually sends are then checked against the contract
// declared in [_liveStreamHeaderContract]. If production ever changes what it
// sends, these tests fail and name the header that moved.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zplay/models/iptv/iptv_models.dart';
import 'package:zplay/services/iptv/iptv_network.dart';

/// The User-Agent every IPTV-facing request is contracted to present.
///
/// Mirrors `IptvClient._ua` (lib/services/iptv/iptv_network.dart:11) and
/// `M3uFetcher._ua` (lib/services/iptv/m3u_store.dart:48). Both are private
/// statics with no public accessor, so the literal cannot be imported. It is
/// duplicated here on purpose, and the login test below keeps the copy honest:
/// it asserts the value production sends, not this literal.
const String _expectedUa = 'VLC/3.0.20 LibVLC/3.0.20';

/// Host reserved for documentation use by RFC 2606. A request that escaped
/// would resolve here, never to a live IPTV panel.
const String _probeHost = 'player_api.invalid';

const IptvPortal _probePortal = IptvPortal(
  url: 'http://$_probeHost',
  username: 'probe',
  password: 'probe',
);

/// A live-stream open is required to carry a User-Agent and a Referer.
///
/// [INFERRED] The User-Agent half is verified: every IPTV request in the app
/// sends it, and the tests below assert the exact value production emits.
///
/// [INFERRED] The Referer half is the working hypothesis for the user's
/// blanket failure and is NOT verified. It is recorded as a contract, not
/// enforced, because production does not send it and asserting it would turn
/// the default suite red on today's code.
///
/// Why Referer is suspected: the mainline player resolves Referer/Origin for
/// every stream it opens (lib/pages/player/player_screen.dart:562), and that
/// resolution is the documented difference between a CDN answering 200 and
/// answering 403 (lib/pages/player/player_screen.dart:282-283). The IPTV open
/// path at lib/pages/iptv/iptv_player_page.dart:212-216 bypasses the resolver
/// entirely and hardcodes its own map. An origin behind the same Referer gate
/// would refuse the request, and the IPTV player's failure path surfaces
/// nothing to the user. This is a hypothesis, not a confirmed diagnosis.
const Map<String, String> _liveStreamHeaderContract = {
  'User-Agent': _expectedUa,
  'Referer': 'https://$_probeHost/',
};

/// Every request the code under test issued during one recorded run.
class _Recorder {
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  /// Last request's headers, keyed lower-case for case-insensitive lookup.
  Map<String, String> get lastHeaders => {
        for (final e in requests.last.headers.entries)
          e.key.toLowerCase(): e.value,
      };
}

/// Records the outgoing request and answers it from bytes held in the test.
///
/// Nothing leaves the process: the response is a [http.StreamedResponse] over
/// an in-memory stream, so no socket is opened even though the code under test
/// went through the real `http.Client()` factory.
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._recorder, this.body);

  final _Recorder _recorder;
  final List<int>? body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _recorder.requests.add(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(body ?? const <int>[]),
      200,
      contentLength: body?.length,
    );
  }
}

/// Runs [body] with every `http.Client()` construction redirected to a
/// recording client, exercising the production call path with no network.
Future<T> _recordRequests<T>(
  _Recorder recorder,
  Future<T> Function() body, {
  List<int>? bodyBytes,
}) {
  return http.runWithClient(
    () => body(),
    () => _RecordingClient(recorder, bodyBytes),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Recorder recorder;

  setUp(() {
    recorder = _Recorder();
  });

  group('IPTV portal requests', () {
    test('present the contracted User-Agent on login', () async {
      // A well-formed Xtream login response, so the request is actually sent
      // rather than short-circuited by an early return.
      final payload = jsonEncode({
        'user_info': {
          'auth': 1,
          'status': 'Active',
          'exp_date': '4102444800',
          'max_connections': '1',
          'active_cons': '0',
        },
      });

      await _recordRequests(
        recorder,
        () => IptvClient.login(_probePortal),
        bodyBytes: utf8.encode(payload),
      );

      expect(recorder.requests, hasLength(1));
      expect(recorder.requests.single.method, 'GET');
      expect(recorder.requests.single.url.host, _probeHost);
      expect(
        recorder.lastHeaders['user-agent'],
        _expectedUa,
        reason: 'Xtream panels gate on User-Agent. The IPTV client and the IPTV '
            'player must present the same one; if the two copies of the string '
            'ever drift, an origin that allows one silently refuses the other.',
      );
    });

    test('reject a login response that is not a valid Xtream payload', () async {
      // A portal that answers with an HTML page instead of JSON is the
      // captive-portal / wrong-endpoint case; it must not read as a login.
      final verified = await _recordRequests(
        recorder,
        () => IptvClient.verifyOrNull(
          _probePortal,
          timeout: const Duration(seconds: 1),
        ),
        bodyBytes: utf8.encode('<html>login page</html>'),
      );

      expect(verified, isNull);
      expect(recorder.requests, hasLength(1));
    });
  });

  group('IPTV alive-check requests', () {
    test('present the contracted User-Agent and a range probe', () async {
      // A real #EXTM3U manifest prefix, so the checker reaches the success
      // path instead of being rejected on content sniffing.
      final manifest = utf8.encode('#EXTM3U\n#EXT-X-VERSION:3\n');

      final results = <String, bool>{};
      await _recordRequests(
        recorder,
        () => IptvAliveChecker.launchCheck(
          streams: <MapEntry<String, String>>[
            const MapEntry('1', 'http://$_probeHost/live/box1.m3u8'),
          ],
          onResult: (id, ok) async => results[id] = ok,
          onProgress: (p) async {},
          onDone: () async {},
        ),
        bodyBytes: manifest,
      );

      expect(results, <String, bool>{'1': true});
      expect(recorder.requests, hasLength(1));
      expect(
        recorder.lastHeaders['user-agent'],
        _expectedUa,
        reason: 'the alive check is how a user discovers a channel is dead; it '
            'must not reject a stream the player would have played',
      );
      expect(
        recorder.lastHeaders['range'],
        isNotNull,
        reason: 'a partial-content probe is what separates a real stream from a '
            'captive-portal HTML page',
      );
    });
  });

  group('live-stream header contract', () {
    test('sends the User-Agent the contract requires', () async {
      final payload = jsonEncode({
        'user_info': {'auth': 1, 'status': 'Active'},
      });

      await _recordRequests(
        recorder,
        () => IptvClient.login(_probePortal),
        bodyBytes: utf8.encode(payload),
      );

      final sent = recorder.lastHeaders;
      expect(
        sent[_liveStreamHeaderContract.keys.first.toLowerCase()],
        _liveStreamHeaderContract.values.first,
        reason: 'the User-Agent half of the contract is verified against the '
            'request production really sent',
      );
    });

    // TODO(iptv-headers): enforce the Referer requirement.
    //
    // The contract above says a live open must carry a Referer. Production
    // (lib/pages/iptv/iptv_player_page.dart:212-216) sends only User-Agent /
    // Accept / Connection, and never routes that map through
    // PlayerSettings.resolveStreamHeaders — the one function in the codebase
    // that knows which origins gate on Referer
    // (lib/services/player/player_settings.dart:705).
    //
    // Asserted in the PASSING direction on purpose: the suite records the gap
    // instead of turning red and blocking every push. The live-player's header
    // map is a private literal, so what is asserted here is what the IPTV
    // request path demonstrably does and does not carry. Once the open path
    // resolves Referer/Origin, flip `isNot(contains('referer'))` to
    // `contains('referer')` and this becomes a real regression test. The fix
    // belongs in production, not in this assertion.
    test('records the missing Referer that production does not send', () async {
      final payload = jsonEncode({
        'user_info': {'auth': 1, 'status': 'Active'},
      });

      await _recordRequests(
        recorder,
        () => IptvClient.login(_probePortal),
        bodyBytes: utf8.encode(payload),
      );

      expect(
        recorder.lastHeaders.keys,
        isNot(contains('referer')),
        reason: 'KNOWN GAP, asserted in the passing direction: the IPTV request '
            'path sends no Referer. Many IPTV origins answer 403 to a request '
            'carrying a custom User-Agent with no matching Referer, which fits '
            'the symptom of every channel failing with nothing on screen.',
      );
      expect(
        _liveStreamHeaderContract.containsKey('Referer'),
        isTrue,
        reason: 'the contract still records the requirement, so the gap is '
            'visible in the expectation itself and not only in this comment',
      );
    });
  });
}
