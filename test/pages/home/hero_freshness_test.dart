/// Hero freshness and hero artwork fallback.
///
/// Two regressions are locked here. First, the featured picker must surface the
/// *newest* title in each section and must not pin the same handful of titles on
/// every call - the old picker took `section.movies[0]` deterministically, which
/// is how `Dredd` (2012) sat in the hero on every visit. Second, the hero band
/// must walk its artwork candidates on *load errors*, not only on absence: a
/// dead `Movie.backdrop` used to blank the band because the first non-empty URL
/// won and its failure rendered nothing.
library;

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/models/addon/addon.dart';
import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/models/movie/movie_section.dart';
import 'package:zplay/pages/home/home_page.dart';

Movie _movie(String id, [String? year]) => Movie(
      id: id,
      name: id,
      year: year,
      type: 'movie',
      addonBaseUrl: 'https://addon.example.com',
    );

MovieSection _section(String title, List<Movie> movies) => MovieSection(
      title: title,
      subtitle: '',
      contentType: 'movie',
      addonBaseUrl: 'https://addon.example.com',
      catalog: AddonCatalog(type: 'movie', id: title),
      movies: movies,
    );

/// Lets one fallback step settle: the load error, the error widget's deferred
/// `setState`, and the next candidate's request each land on their own frame.
Future<void> _settleStep(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A cache manager whose loads only ever fail, on the test's command.
///
/// `CachedNetworkImage` reaches the network through a `BaseCacheManager`, so
/// this is the seam the hero's fallback chain actually stands on: each URL gets
/// a stream the test fails by hand, which drives the same `errorWidget` path a
/// dead CDN would.
class _ScriptedCacheManager extends BaseCacheManager with ImageCacheManager {
  final Map<String, StreamController<FileResponse>> _streams = {};

  /// Every URL the artwork asked for, in order. The fallback chain is asserted
  /// through this - the next candidate getting its turn is the regression.
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
  group('pickFeatured', () {
    test('prefers the newest title in a section over older ones', () {
      final sections = [
        _section('one', [_movie('old', '1999'), _movie('new', '2026')]),
        _section('two', [_movie('stale', '2001'), _movie('fresh', '2025')]),
      ];

      expect(
        pickFeatured(sections, variation: 0).map((m) => m.id),
        ['new', 'fresh'],
      );
    });

    test('a year that is not a plain number sorts last, never throws', () {
      final sections = [
        _section('one', [_movie('junk', 'Season 3'), _movie('dated', '2026')]),
        _section('two', [_movie('none'), _movie('ranged', '2019–2021')]),
      ];

      // `2019–2021` reads as 2019; `Season 3` and a missing year sort last.
      expect(
        pickFeatured(sections, variation: 0).map((m) => m.id),
        ['dated', 'ranged'],
      );
    });

    test('variation rotates the pick within the newest titles', () {
      final sections = [
        _section('one', [
          _movie('a1', '2026'),
          _movie('a2', '2025'),
          _movie('a3', '2024'),
        ]),
        _section('two', [_movie('b1', '2026'), _movie('b2', '2025')]),
      ];

      expect(
        pickFeatured(sections, variation: 0).map((m) => m.id),
        ['a1', 'b1'],
      );
      expect(
        pickFeatured(sections, variation: 1).map((m) => m.id),
        ['a2', 'b2'],
        reason: 'the hero must not be pinned to one set of titles',
      );
    });

    test('the same variation replays the same set, no flicker on rebuild', () {
      final sections = [
        _section('one', [_movie('a1', '2026'), _movie('a2', '2025')]),
        _section('two', [_movie('b1', '2026'), _movie('b2', '2025')]),
      ];

      final first = pickFeatured(sections, variation: 2).map((m) => m.id);
      final second = pickFeatured(sections, variation: 2).map((m) => m.id);
      expect(first, second);
    });

    test('sparse sections still top up from the first section', () {
      final sections = [
        _section('one', [
          _movie('a', '2026'),
          _movie('b', '2025'),
          _movie('c', '2024'),
        ]),
        // Its only title is already featured, so it contributes nothing.
        _section('two', [_movie('a', '2026')]),
      ];

      expect(
        pickFeatured(sections, variation: 0).map((m) => m.id),
        ['a', 'b', 'c'],
      );
    });
  });

  group('heroWideArtworkCandidates', () {
    test('orders detail background, catalog backdrop, then metahub', () {
      expect(
        heroWideArtworkCandidates(
          ' https://cdn.example/detail.jpg ',
          'https://cdn.example/backdrop.jpg',
          'tt0468569',
        ),
        [
          'https://cdn.example/detail.jpg',
          'https://cdn.example/backdrop.jpg',
          'https://images.metahub.space/background/large/tt0468569/img',
        ],
      );
    });

    test('blanks and duplicates are dropped', () {
      expect(
        heroWideArtworkCandidates(
          '   ',
          'https://cdn.example/backdrop.jpg',
          'tt0468569',
        ),
        [
          'https://cdn.example/backdrop.jpg',
          'https://images.metahub.space/background/large/tt0468569/img',
        ],
      );
      expect(
        heroWideArtworkCandidates(
          'https://cdn.example/same.jpg',
          'https://cdn.example/same.jpg',
          'probe',
        ),
        ['https://cdn.example/same.jpg'],
      );
    });

    test('an unusable id gets no metahub candidate, and none is still empty', () {
      expect(
        heroWideArtworkCandidates(null, null, 'probe'),
        isEmpty,
      );
    });
  });

  group('HeroArtwork fallback chain', () {
    // Unique URLs per test: `ImageCache` is shared across the tests of a file
    // and keeps pending loads, so a URL left pending here would answer (or
    // fail to answer) the next test's requests.
    setUp(() => imageCache.clear());

    testWidgets('a dead candidate advances to the next one instead of blanking',
        (tester) async {
      const dead = 'https://dead.example/advance/still.jpg';
      const alive = 'https://cdn.example/advance/still.jpg';
      final cache = _ScriptedCacheManager();
      final reported = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeroArtwork(
              candidates: const [dead, alive],
              cacheManager: cache,
              onActiveUrlChanged: reported.add,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(cache.requested, [dead]);
      final first =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(first.imageUrl, dead);
      expect(first.memCacheWidth, 1920, reason: 'the panel is 1920 physical px');
      expect(first.cacheManager, same(cache));
      expect(reported, [dead]);

      cache.fail(dead);
      await _settleStep(tester);

      expect(
        cache.requested,
        [dead, alive],
        reason: 'the next candidate gets its turn on load error',
      );
      expect(
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .imageUrl,
        alive,
      );
      expect(
        reported,
        [dead, alive],
        reason: 'the reported URL follows what is actually painted',
      );
    });

    testWidgets('after every candidate fails the band renders nothing',
        (tester) async {
      const dead = 'https://dead.example/terminal/still.jpg';
      const alive = 'https://dead.example/terminal/also.jpg';
      final cache = _ScriptedCacheManager();
      final reported = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeroArtwork(
              candidates: const [dead, alive],
              cacheManager: cache,
              onActiveUrlChanged: reported.add,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      cache.fail(dead);
      await _settleStep(tester);
      cache.fail(alive);
      await _settleStep(tester);

      expect(cache.requested, [dead, alive]);
      expect(
        find.byType(CachedNetworkImage),
        findsNothing,
        reason: 'the terminal state is the existing empty band',
      );
      expect(reported, [dead, alive, null]);
    });

    testWidgets('a new candidate list retries, an unchanged one never does',
        (tester) async {
      const first = 'https://dead.example/retry/still.jpg';
      const second = 'https://cdn.example/retry/still.jpg';
      const third = 'https://cdn.example/retry/detail.jpg';
      final cache = _ScriptedCacheManager();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeroArtwork(
              candidates: const [first, second],
              cacheManager: cache,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      cache.fail(first);
      await _settleStep(tester);
      expect(cache.requested, [first, second]);

      // A detail landing adds `MovieDetail.background`: the list changes, so
      // the chain is retried from the top - a transient failure must not pin
      // the slide to the fallback forever.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeroArtwork(
              candidates: const [first, second, third],
              cacheManager: cache,
            ),
          ),
        ),
      );
      await _settleStep(tester);
      expect(cache.requested, [first, second, first]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeroArtwork(
              candidates: const [first, second, third],
              cacheManager: cache,
            ),
          ),
        ),
      );
      await _settleStep(tester);
      expect(
        cache.requested,
        [first, second, first],
        reason: 'an unchanged candidate list never re-requests',
      );
    });
  });
}
