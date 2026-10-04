/// Guards that Settings' "Clear cache" control really empties the caches it
/// claims to - the artwork disk store, the metadata memory caches and the hero
/// media table - and leaves user state alone.
///
/// Before the control existed, a stale artwork response stuck for 30 days with
/// no way out short of a reinstall, and a reinstall wiped the profile and
/// addons the user cared about. The cache clean is the escape hatch, so it has
/// to provably reach all three stores and provably not reach anything else.
///
/// The two memory caches are observed through real state: a scripted HTTP
/// client counts lookups, the primed caches answer without a request, and a
/// clean that actually happened makes the next lookup go back to the network.
/// The artwork store is observed through [AppImageCache.emptyCacheForTesting],
/// because `CacheManager`'s store is an sqflite database behind a platform
/// channel a widget test cannot open.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/pages/settings/settings_page.dart';
import 'package:zplay/services/hero/hero_media_resolver.dart';
import 'package:zplay/services/metadata/metadata_service.dart';
import 'package:zplay/services/metadata/tmdb_service.dart';
import 'package:zplay/services/storage/app_image_cache.dart';
import 'package:zplay/widgets/common/focusable_card.dart';

/// The focusable row whose title is [title], the same shape the other settings
/// tests use: a bare `InkWell` would be invisible to a remote.
Finder _row(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(FocusableCard));

Future<void> _pumpSettings(WidgetTester tester) async {
  // Tall enough that every section is in the tree, so the APP group's row is
  // tappable without scrolling a `SingleChildScrollView`.
  tester.view.physicalSize = const Size(1280, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
  await tester.pump();
}

/// Presses the control exactly as a pointer or remote does: the row, then the
/// confirm button of the dialog it opens. Not `pumpAndSettle` - the ambient
/// background animates forever and would time out rather than fail.
Future<void> _driveClearCacheControl(WidgetTester tester) async {
  await _pumpSettings(tester);

  final row = _row('Clear cache');
  expect(
    row,
    findsOneWidget,
    reason: 'the clear-cache row has to be a focusable card or a remote '
        'cannot reach it',
  );
  await tester.tap(row);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  await tester.tap(find.text('Clear'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MetadataService.clearCache();
    HeroMediaResolver.clearCache();
    TmdbService.apiKey.value = '';
  });

  tearDown(() {
    MetadataService.client = http.Client();
    TmdbService.client = http.Client();
    TmdbService.apiKey.value = '';
    AppImageCache.emptyCacheForTesting = null;
    MetadataService.clearCache();
    HeroMediaResolver.clearCache();
  });

  testWidgets(
    'the clear-cache control drops the artwork, metadata and hero caches',
    (tester) async {
      var imageClears = 0;
      AppImageCache.emptyCacheForTesting = () async => imageClears++;
      var metaRequests = 0;
      MetadataService.client = MockClient((request) async {
        metaRequests++;
        return http.Response('{"d":[]}', 200);
      });
      var heroRequests = 0;
      TmdbService.client = MockClient((request) async {
        heroRequests++;
        return http.Response('{"movie_results":[],"tv_results":[]}', 200);
      });
      TmdbService.apiKey.value = 'test-key';

      final movie = Movie(
        id: 'tt0000001',
        name: 'Primed',
        type: 'movie',
        addonBaseUrl: 'https://example.invalid',
      );

      // Prime the memory caches: the first lookup goes to the network...
      await MetadataService.suggestionSearch(query: 'primed');
      await HeroMediaResolver.enrich([movie]);
      expect(
        metaRequests,
        1,
        reason: 'precondition: the metadata lookup must hit the network',
      );
      expect(
        heroRequests,
        1,
        reason: 'precondition: the hero lookup must hit the network',
      );

      // ...and is then served from cache.
      await MetadataService.suggestionSearch(query: 'primed');
      await HeroMediaResolver.enrich([movie]);
      expect(
        metaRequests,
        1,
        reason: 'precondition: the metadata lookup must be cached',
      );
      expect(
        heroRequests,
        1,
        reason: 'precondition: the hero lookup must be cached',
      );

      // User state that has to survive the clean.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rd_access_token', 'KEEP');

      await _driveClearCacheControl(tester);

      expect(
        imageClears,
        1,
        reason: 'the artwork disk cache must be emptied',
      );
      await MetadataService.suggestionSearch(query: 'primed');
      expect(
        metaRequests,
        2,
        reason: 'the metadata cache must be dropped so the lookup refetches',
      );
      await HeroMediaResolver.enrich([movie]);
      expect(
        heroRequests,
        2,
        reason: 'the hero media cache must be dropped so the lookup refetches',
      );

      expect(
        prefs.getString('rd_access_token'),
        'KEEP',
        reason: 'cleaning the cache must not touch user state',
      );
      expect(
        find.textContaining('still signed in'),
        findsOneWidget,
        reason: 'the report has to say what the clean did not do',
      );
    },
  );

  testWidgets('a clear step that fails is named in the report, not swallowed', (
    tester,
  ) async {
    AppImageCache.emptyCacheForTesting = () async =>
        throw Exception('store is locked');
    var metaRequests = 0;
    MetadataService.client = MockClient((request) async {
      metaRequests++;
      return http.Response('{"d":[]}', 200);
    });
    await MetadataService.suggestionSearch(query: 'primed');
    expect(metaRequests, 1);

    await _driveClearCacheControl(tester);

    expect(
      find.textContaining('except the artwork cache'),
      findsOneWidget,
      reason: 'a failed clear step has to be reported, not swallowed',
    );
    expect(
      find.textContaining('store is locked'),
      findsOneWidget,
      reason: 'the report has to say why the step failed',
    );
    await MetadataService.suggestionSearch(query: 'primed');
    expect(
      metaRequests,
      2,
      reason: 'a failed step must not spare the caches behind it',
    );
  });
}
