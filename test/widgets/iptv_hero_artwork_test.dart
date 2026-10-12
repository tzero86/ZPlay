/// The Live TV hero's picture area is never left bare.
///
/// The defect, from a device sweep: the featured channel resolved no artwork,
/// so the hero reserved the band's height for a picture and put nothing in it -
/// about 120 dp of empty background above the channel title. A `backdropUrl`
/// that 404s is the same hole, so both states are pinned here: no URL paints
/// the channel's own wordmark, and a dead URL flips to it rather than leaving
/// the band as it was.
library;

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/services/iptv/hardcoded_channels.dart';
import 'package:zplay/widgets/iptv/iptv_hero_artwork.dart';

/// The band's height on the 960 x 540 television canvas, so the artwork is laid
/// out against the box it is drawn into rather than against a test default.
const Size _band = Size(960, 380);

HardcodedChannel _channel({String? backdrop, String short = 'CBB'}) =>
    HardcodedChannel(
      id: 'probe',
      name: 'NCAA College Basketball',
      short: short,
      category: 'Sports',
      keywords: const ['ncaa'],
      gradient: const [Color(0xFF123456), Color(0xFF000000)],
      backdropUrl: backdrop,
    );

/// A cache manager whose loads only ever fail, on the test's command - the same
/// seam `hero_never_blank_test.dart` scripts, because `CachedNetworkImage`
/// reaches the network through a [BaseCacheManager] and that is where a dead
/// backdrop URL has to be reproduced.
class _ScriptedCacheManager extends BaseCacheManager with ImageCacheManager {
  final Map<String, StreamController<FileResponse>> _streams = {};

  /// Every URL the artwork asked for, in order.
  final List<String> requested = [];

  void fail(String url) {
    _streams[url]?.addError('load failed: $url');
  }

  Stream<FileResponse> _scripted(String url) {
    requested.add(url);
    return _streams
        .putIfAbsent(url, () => StreamController<FileResponse>.broadcast())
        .stream;
  }

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => _scripted(url);

  @override
  Stream<FileResponse> getImageFile(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
    int? maxHeight,
    int? maxWidth,
  }) => _scripted(url);

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Lets the load error, the deferred `setState` and the next frame each land.
Future<void> _settleStep(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pump(
  WidgetTester tester,
  HardcodedChannel channel,
  BaseCacheManager cache,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _band.width,
            height: _band.height,
            child: IptvHeroArtwork(channel: channel, cacheManager: cache),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  // Unique URLs per test: `ImageCache` is shared across a file's tests.
  setUp(() => imageCache.clear());

  testWidgets('a channel with no backdrop paints its short code, not a hole',
      (tester) async {
    final cache = _ScriptedCacheManager();
    await _pump(tester, _channel(), cache);

    expect(
      find.byType(CachedNetworkImage),
      findsNothing,
      reason: 'there is no URL to ask for, so the band must not reserve a '
          'picture it will never paint',
    );
    expect(
      find.text('CBB'),
      findsOneWidget,
      reason: 'the band carries the channel instead of standing empty',
    );
    expect(cache.requested, isEmpty);
  });

  testWidgets('a channel with no short code falls back to its name',
      (tester) async {
    final cache = _ScriptedCacheManager();
    await _pump(tester, _channel(short: '  '), cache);

    expect(find.text('NCAA College Basketball'), findsOneWidget);
  });

  testWidgets('a live backdrop paints full-bleed, and the wordmark is absent',
      (tester) async {
    const backdrop = 'https://cdn.example/iptv/hero/live.jpg';
    final cache = _ScriptedCacheManager();
    await _pump(tester, _channel(backdrop: backdrop), cache);

    final image =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(image.imageUrl, backdrop);
    expect(image.fit, BoxFit.cover);
    expect(cache.requested, [backdrop]);
    expect(
      find.text('CBB'),
      findsNothing,
      reason: 'art that loads is the whole of the band',
    );
  });

  testWidgets('a backdrop that fails to load is replaced by the wordmark',
      (tester) async {
    const backdrop = 'https://dead.example/iptv/hero/still.jpg';
    final cache = _ScriptedCacheManager();
    await _pump(tester, _channel(backdrop: backdrop), cache);
    expect(cache.requested, [backdrop]);

    cache.fail(backdrop);
    await _settleStep(tester);

    expect(
      find.byType(CachedNetworkImage),
      findsNothing,
      reason: 'a dead URL is the same hole as a missing one, so it cannot stay',
    );
    expect(find.text('CBB'), findsOneWidget);
    expect(
      cache.requested,
      [backdrop],
      reason: 'a channel\'s data is fixed for the page\'s life, so the dead URL '
          'is not asked for again',
    );
  });
}
