/// The hero never paints a soft still.
///
/// The defect: hero slides showed visibly pixelated artwork - an addon's
/// `background` that was a few hundred pixels wide, or the 2:3 poster tail,
/// stretched across a band that is the window's full width. A bigger decode
/// cannot add detail the file does not have, so the only fix is to measure the
/// source before painting it. [HeroArtQuality] is that measurement;
/// [HeroArtwork] walks past anything that fails it, and [HeroBanner] drops a
/// title whose art all fails it rather than show it soft.
library;

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/services/hero/hero_art_quality.dart';
import 'package:zplay/services/home/home_page_settings.dart';
import 'package:zplay/services/metadata/metadata_service.dart';
import 'package:zplay/widgets/home/hero_banner.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Answers nothing, so the only thing that moves the chain is the probe.
class _SilentCacheManager extends BaseCacheManager with ImageCacheManager {
  final List<String> requested = [];

  Stream<FileResponse> _pending(String url) {
    requested.add(url);
    return StreamController<FileResponse>.broadcast().stream;
  }

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => _pending(url);

  @override
  Stream<FileResponse> getImageFile(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
    int? maxHeight,
    int? maxWidth,
  }) => _pending(url);

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

HeroArtProbe _sizes(Map<String, Size?> sizes) =>
    (url) async => sizes[url];

class _NotFound extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(const <int>[]), 404);
}

void main() {
  setUp(() {
    imageCache.clear();
    HeroArtQuality.clear();
  });
  tearDown(HeroArtQuality.clear);

  group('HeroArtQuality.isSharp', () {
    test('a full-size wide still passes', () {
      expect(HeroArtQuality.isSharp(const Size(1920, 1080)), isTrue);
      expect(HeroArtQuality.isSharp(const Size(1280, 720)), isTrue);
      expect(HeroArtQuality.isSharp(const Size(3840, 2160)), isTrue);
    });

    test('a small still fails however wide its shape', () {
      expect(HeroArtQuality.isSharp(const Size(780, 439)), isFalse);
      expect(HeroArtQuality.isSharp(const Size(1000, 562)), isFalse);
    });

    test('a poster or a square fails however large it is', () {
      expect(HeroArtQuality.isSharp(const Size(2000, 3000)), isFalse);
      expect(HeroArtQuality.isSharp(const Size(1500, 1500)), isFalse);
    });

    test('an unreadable still fails', () {
      expect(HeroArtQuality.isSharp(null), isFalse);
    });
  });

  test('the poster is no longer a hero candidate', () {
    expect(heroWideArtworkCandidates(null, null, 'probe'), isEmpty);
  });

  group('HeroArtwork', () {
    testWidgets('a soft still is skipped for the next sharp one', (
      tester,
    ) async {
      const soft = 'https://cdn.example/gate/soft.jpg';
      const sharp = 'https://cdn.example/gate/sharp.jpg';
      final cache = _SilentCacheManager();
      final reported = <String?>[];
      var rejected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeroArtwork(
              candidates: const [soft, sharp],
              cacheManager: cache,
              probe: _sizes({
                soft: const Size(640, 360),
                sharp: const Size(1920, 1080),
              }),
              onActiveUrlChanged: reported.add,
              onRejected: () => rejected++,
            ),
          ),
        ),
      );
      await _settle(tester);

      expect(
        tester
            .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .imageUrl,
        sharp,
      );
      expect(cache.requested, [sharp], reason: 'the soft still never paints');
      expect(reported, [sharp], reason: 'nor reaches the band behind rails');
      expect(rejected, 0);
    });

    testWidgets('nothing paints while a still is being measured', (
      tester,
    ) async {
      const url = 'https://cdn.example/gate/pending.jpg';
      final pending = Completer<Size?>();
      final reported = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeroArtwork(
              candidates: const [url],
              cacheManager: _SilentCacheManager(),
              probe: (_) => pending.future,
              onActiveUrlChanged: reported.add,
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(reported, isEmpty);

      pending.complete(const Size(1920, 1080));
      await _settle(tester);
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(reported, [url]);
    });

    testWidgets('when every still is soft the band is empty and the slide is '
        'rejected', (tester) async {
      const soft = 'https://cdn.example/gate/all-soft.jpg';
      const poster = 'https://cdn.example/gate/poster-shaped.jpg';
      final reported = <String?>[];
      var rejected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeroArtwork(
              candidates: const [soft, poster],
              cacheManager: _SilentCacheManager(),
              probe: _sizes({
                soft: const Size(780, 439),
                poster: const Size(2000, 3000),
              }),
              onActiveUrlChanged: reported.add,
              onRejected: () => rejected++,
            ),
          ),
        ),
      );
      await _settle(tester);

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(reported, [null]);
      expect(rejected, 1);
    });

    testWidgets('art that could not be fetched does not reject the slide', (
      tester,
    ) async {
      const dead = 'https://dead.example/gate/offline.jpg';
      var rejected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeroArtwork(
              candidates: const [dead],
              cacheManager: _SilentCacheManager(),
              probe: _sizes({dead: null}),
              onRejected: () => rejected++,
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(rejected, 0, reason: 'offline is not blurry; the title stays');
    });
  });

  group('HeroBanner', () {
    setUp(() {
      HomePageSettings.heroAutoRotate.value = false;
      MetadataService.client = _NotFound();
    });
    tearDown(() {
      HomePageSettings.heroAutoRotate.value = true;
      MetadataService.clearCache();
      MetadataService.client = http.Client();
    });

    Movie movie(String id, String name) => Movie(
      id: id,
      name: name,
      type: 'movie',
      addonBaseUrl: 'https://addon.invalid',
      year: '2026',
      backdrop: 'https://cdn.example/banner/$id.jpg',
    );

    testWidgets('a title with only soft art is dropped from the carousel', (
      tester,
    ) async {
      HeroArtQuality.debugProbe = _sizes({
        'https://cdn.example/banner/soft-1.jpg': const Size(700, 394),
        'https://cdn.example/banner/sharp-2.jpg': const Size(1920, 1080),
        'https://cdn.example/banner/sharp-3.jpg': const Size(1920, 1080),
      });
      final backdrops = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HeroBanner(
                movies: [
                  movie('soft-1', 'Soft Title'),
                  movie('sharp-2', 'Sharp Title'),
                  movie('sharp-3', 'Another Sharp'),
                ],
                onBackdropChanged: backdrops.add,
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      await _settle(tester);

      expect(find.text('Soft Title'), findsNothing);
      expect(find.text('Sharp Title'), findsWidgets);
      expect(
        backdrops.whereType<String>(),
        isNot(contains('https://cdn.example/banner/soft-1.jpg')),
        reason: 'the soft still never reaches the band behind the rails',
      );
      expect(backdrops.last, 'https://cdn.example/banner/sharp-2.jpg');

      // Let image loads and the slide's artwork drift wind down.
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
    });
  });
}
