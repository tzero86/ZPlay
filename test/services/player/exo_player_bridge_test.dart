import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/player/engine/exo_player_engine.dart';
import 'package:zplay/services/player/engine/video_engine.dart';

/// The Media3 bridge is a platform channel, so these tests pin the contract
/// between the Dart engine and the Kotlin side: the method names it invokes and
/// the shape of the events it expects back.
///
/// That contract has already broken once, and the failure was silent. A method
/// name that does not exist on the native side throws a MissingPluginException
/// at playback time, on a device, with no test failing. Pinning both directions
/// here is what makes the next rename loud.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  const MethodChannel channel = MethodChannel('io.github.tzero86.zplay/exo_player');

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  /// The view id must match `ExoPlayerBridge.VIEW_ID` in Kotlin. These are two
  /// constants in two languages that nothing else ties together.
  test('the platform view id matches the native bridge', () {
    expect(ExoPlayerEngine.viewType, 'io.github.tzero86.zplay/exo_surface');
  });

  test('open sends url, headers and the resume offset', () async {
    final ExoPlayerEngine engine = ExoPlayerEngine();
    addTearDown(engine.dispose);

    await engine.open(
      const EngineRequest(
        url: 'https://cdn.example/movie.mkv',
        headers: <String, String>{'Referer': 'https://example.com'},
        start: Duration(minutes: 12),
      ),
    );

    final MethodCall load =
        calls.firstWhere((MethodCall c) => c.method == 'load');
    final Map<Object?, Object?> args =
        load.arguments as Map<Object?, Object?>;
    expect(args['url'], 'https://cdn.example/movie.mkv');
    expect(
      (args['headers'] as Map<Object?, Object?>)['Referer'],
      'https://example.com',
    );
    expect(args['startMs'], 12 * 60 * 1000);
  });

  test('open refuses a torrent rather than failing slowly on the device', () async {
    final ExoPlayerEngine engine = ExoPlayerEngine();
    addTearDown(engine.dispose);

    await expectLater(
      engine.open(
        const EngineRequest(url: 'http://127.0.0.1:8080/s', isTorrent: true),
      ),
      throwsA(isA<EngineUnsupported>()),
    );
    // The refusal has to happen before the channel is touched, so the other
    // engine can take over in the same tick.
    expect(calls.where((MethodCall c) => c.method == 'load'), isEmpty);
  });

  test('transport and selection map to distinct native methods', () async {
    final ExoPlayerEngine engine = ExoPlayerEngine();
    addTearDown(engine.dispose);

    await engine.play();
    await engine.pause();
    await engine.playOrPause();
    await engine.seek(const Duration(seconds: 45));
    await engine.setRate(1.5);
    await engine.setVolume(0.4);
    await engine.setSubtitlesVisible(false);
    await engine.setAudioTrack(null);
    await engine.setSubtitleTrack(null);

    expect(
      calls.map((MethodCall c) => c.method),
      containsAll(<String>[
        'play',
        'pause',
        'playOrPause',
        'seek',
        'setRate',
        'setVolume',
        'setSubtitlesVisible',
        'selectAudioTrack',
        'selectSubtitleTrack',
      ]),
    );

    final MethodCall seek =
        calls.firstWhere((MethodCall c) => c.method == 'seek');
    expect((seek.arguments as Map<Object?, Object?>)['positionMs'], 45000);
  });

  test('a missing native bridge is an unsupported engine, not a crash', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    final ExoPlayerEngine engine = ExoPlayerEngine();
    addTearDown(engine.dispose);

    await expectLater(engine.play(), throwsA(isA<EngineUnsupported>()));
  });

  test('a fresh engine reports no decoded size, so the watchdog can tell', () {
    final ExoPlayerEngine engine = ExoPlayerEngine();
    addTearDown(engine.dispose);

    // Null rather than zero: this is the only signal that distinguishes a
    // stream that is decoding from one that is decoding without rendering,
    // which is the failure the first spike had.
    expect(engine.state.decodedWidth, isNull);
    expect(engine.state.decodedHeight, isNull);
  });
}
