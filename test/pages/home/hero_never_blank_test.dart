/// Never-blank hero artwork: a slide with no wide art must still paint its
/// poster.
///
/// The defect: some hero slides rendered a bare black band with only a title
/// and a year - reproduced on desktop with 2026 titles (`The Mortuary
/// Assistant`, `Killer Whale`). `heroWideArtworkCandidates` ended at
/// `MetahubArt.backdropUrl`, and for a very new title metahub has nothing, so
/// every candidate failed and the terminal state was `SizedBox.shrink()` over
/// the scrim. A black band is strictly worse than imperfect art.
///
/// Both edges are pinned here. The movie's poster - whether its data carries
/// the metahub poster or the catalog's own - is the final candidate, so the
/// chain lands on it instead of nothing after the metahub backdrop 404s. And
/// it stays *last*: real wide art still wins over a 2:3 poster cropped into a
/// 16:9 band.
library;

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/pages/home/home_page.dart';
import 'package:zplay/services/metadata/metahub_art.dart';

/// Lets one fallback step settle: the load error, the error widget's deferred
/// `setState`, and the next candidate's request each land on their own frame.
/// Mirrors the helper in `hero_freshness_test.dart`; test files are standalone
/// libraries and the shared `ImageCache` makes cross-file harness imports more
/// surprising than the copy is costly.
Future<void> _settleStep(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A cache manager whose loads only ever fail, on the test's command.
///
/// Same seam `hero_freshness_test.dart` scripts: `CachedNetworkImage` reaches
/// the network through a `BaseCacheManager`, so failing a URL here drives the
/// same `errorWidget` path a dead image host would - which is exactly how
/// metahub 404s an id it has not indexed.
class _ScriptedCacheManager extends BaseCacheManager with ImageCacheManager {
  final Map<String, StreamController<FileResponse>> _streams = {};

  /// Every URL the artwork asked for, in order.
  final List<String> requested = [];

  /// Fails the in-flight load for [url], like a dead image host would.
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
  }) =>
      _scripted(url);

  @override
  Stream<FileResponse> getImageFile(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
    int? maxHeight,
    int? maxWidth,
  }) =>
      _scripted(url);

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async =>
      null;

  // Everything else the interface carries is never reached by the artwork
  // path; the forwarder keeps the stubs out of the test's sight.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // Unique URLs per test: `ImageCache` is shared across the tests of a file
  // and keeps pending loads, so a URL left pending here would answer (or fail
  // to answer) the next test's requests.
  setUp(() => imageCache.clear());

  group('heroWideArtworkCandidates keeps the poster last', () {
    test('the poster is appended after every wide candidate', () {
      expect(
        heroWideArtworkCandidates(
          'https://cdn.example/detail.jpg',
          'https://cdn.example/backdrop.jpg',
          'tt0468569',
          'https://cdn.example/poster.jpg',
        ),
        [
          'https://cdn.example/detail.jpg',
          'https://cdn.example/backdrop.jpg',
          'https://images.metahub.space/background/large/tt0468569/img',
          'https://cdn.example/poster.jpg',
        ],
        reason: 'real wide art first, poster last - a 2:3 poster in a 16:9 '
            'band crops badly and is the last resort against a black band',
      );
    });

    test('a blank poster is dropped, like any other blank URL', () {
      expect(
        heroWideArtworkCandidates(null, null, 'probe', '   '),
        isEmpty,
      );
    });

    test('a poster duplicating an earlier candidate is not asked for twice',
        () {
      expect(
        heroWideArtworkCandidates(
          null,
          'https://cdn.example/same.jpg',
          'probe',
          ' https://cdn.example/same.jpg ',
        ),
        ['https://cdn.example/same.jpg'],
      );
    });
  });

  group('a slide with no wide art still paints', () {
    // The 2026 repro shape: no `MovieDetail.background`, no `Movie.backdrop`,
    // and metahub 404s the keyless still. What is left is the poster.
    testWidgets('the movie\'s own poster paints when the metahub backdrop dies',
        (tester) async {
      const imdb = 'tt99000011';
      const poster = 'https://cdn.example/never-blank/own-poster.jpg';
      final candidates = heroWideArtworkCandidates(null, null, imdb, poster);
      final cache = _ScriptedCacheManager();
      final reported = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeroArtwork(
              candidates: candidates,
              cacheManager: cache,
              onActiveUrlChanged: reported.add,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final metahubBackdrop = MetahubArt.backdropUrl(imdb);
      expect(cache.requested, [metahubBackdrop]);

      cache.fail(metahubBackdrop);
      await _settleStep(tester);

      expect(
        find.byType(CachedNetworkImage),
        findsOneWidget,
        reason: 'the band paints the poster instead of going black',
      );
      expect(
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .imageUrl,
        poster,
      );
      expect(cache.requested, [metahubBackdrop, poster]);
      expect(
        reported,
        [metahubBackdrop, poster],
        reason: 'the carousel\'s blurred band follows the painted URL',
      );
    });

    // `Movie.poster` carries either flavor in this app: the metahub poster
    // (that is what collections assign) or the catalog's own still (bestsimilar
    // rows). The band must paint either one rather than nothing - the fix is
    // the movie's poster as the final candidate, whichever host it is on.
    testWidgets('a metahub-hosted poster paints when the metahub backdrop dies',
        (tester) async {
      const imdb = 'tt99000022';
      final poster = MetahubArt.posterUrl(imdb);
      final candidates = heroWideArtworkCandidates(null, null, imdb, poster);
      final cache = _ScriptedCacheManager();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeroArtwork(
              candidates: candidates,
              cacheManager: cache,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final metahubBackdrop = MetahubArt.backdropUrl(imdb);
      cache.fail(metahubBackdrop);
      await _settleStep(tester);

      expect(
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .imageUrl,
        poster,
        reason: 'the poster tail paints instead of a black band, even when it '
            'is metahub-hosted',
      );
      expect(cache.requested, [metahubBackdrop, poster]);
    });

    testWidgets('real wide art still wins over the poster', (tester) async {
      const detail = 'https://cdn.example/precedence/detail.jpg';
      const poster = 'https://cdn.example/precedence/poster.jpg';
      final candidates =
          heroWideArtworkCandidates(detail, null, 'tt99000033', poster);
      final cache = _ScriptedCacheManager();
      final reported = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeroArtwork(
              candidates: candidates,
              cacheManager: cache,
              onActiveUrlChanged: reported.add,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .imageUrl,
        detail,
        reason: 'a real wide still beats a 2:3 poster cropped into the band',
      );
      expect(
        cache.requested,
        [detail],
        reason: 'the poster is last resort only - never requested while wide '
            'art is on screen',
      );
      expect(reported, [detail]);
    });
  });
}
