import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/models/cloudstream/cloudstream_source.dart';
import 'package:zplay/pages/search/search_page.dart';
import 'package:zplay/services/addon/addon_manager.dart';
import 'package:zplay/services/cloudstream/cloudstream_manager.dart';
import 'package:zplay/services/cloudstream/runtime/cloudstream_dispatcher.dart';
import 'package:zplay/services/metadata/metadata_service.dart';

/// Failure propagation from the search sources up to the page's ledger.
///
/// Every source used to answer a failed search with an empty list, which the
/// page could not tell from a title that does not exist, so a dead addon and an
/// offline device both rendered `No results for "The Bear"`. Each source now
/// reports the failure it used to swallow, and the page classifies the run from
/// that ledger. Every request here is scripted: no network, no sidecar.

const _addonHost = 'dead-addon.test';
const _suggestionHost = 'v3.sg.media-imdb.com';

/// A response that never arrives, so the service's own timeout is what ends the
/// request rather than the transport failing it.
class _Hang {
  const _Hang();
}

/// A scripted answer: the body plus the status it comes back under.
class _Reply {
  const _Reply(this.status, this.body);

  final int status;
  final String body;
}

/// Routes each request to a canned answer. Rules are matched most recently
/// registered first, so a specific path can override a whole host. A request
/// matching nothing throws, which is what an offline device or a dead addon
/// looks like to `package:http`.
class _Routes {
  final List<({bool Function(Uri) matches, Object Function() reply})> _rules = [];
  final List<Uri> requested = [];

  void answer(bool Function(Uri) matches, Object Function() reply) =>
      _rules.insert(0, (matches: matches, reply: reply));

  void answerHost(String host, Object Function() reply) =>
      answer((url) => url.host == host, reply);

  void answerPath(String host, String fragment, Object Function() reply) =>
      answer((url) => url.host == host && url.path.contains(fragment), reply);

  void neverAnswers(String host) => answerHost(host, () => const _Hang());

  /// Drops every rule for a host, so a host that answered its manifest goes
  /// dark and its requests start failing the way a dead addon's do.
  void forget(String host) =>
      _rules.removeWhere((r) => r.matches(Uri.parse('https://$host/')));

  http.Client get client => MockClient((request) async {
        requested.add(request.url);
        for (final rule in _rules) {
          if (!rule.matches(request.url)) continue;
          final answer = rule.reply();
          if (answer is _Hang) {
            // Never completing is what a stalled server does; the service's
            // own timeout is expected to fire.
            return Completer<http.Response>().future;
          }
          final reply = answer as _Reply;
          return http.Response(reply.body, reply.status);
        }
        throw http.ClientException('offline', request.url);
      });
}

String _catalogBody(int count) => jsonEncode({
      'metas': [
        for (var i = 0; i < count; i++)
          {
            'id': 'tt000000${i + 1}',
            'name': 'Match ${i + 1}',
            'type': 'movie',
          }
      ]
    });

String _suggestionBody(int count) => jsonEncode({
      'd': [
        for (var i = 0; i < count; i++)
          {'id': 'tt100000${i + 1}', 'l': 'Title ${i + 1}', 'q': 'feature'}
      ]
    });

/// A manifest advertising [catalogCount] search-capable catalogs.
String _manifest(int catalogCount) => jsonEncode({
      'id': 'org.deadaddons.testsource',
      'name': 'Dead Addon',
      'version': '1.0.0',
      'resources': ['catalog'],
      'types': ['movie', 'series'],
      'catalogs': [
        for (var i = 0; i < catalogCount; i++)
          {
            'type': i.isEven ? 'movie' : 'series',
            'id': 'search-${i.isEven ? 'movie' : 'series'}',
            'name': 'Search ${i + 1}',
            'extra': ['search'],
          }
      ],
    });

/// Answers each extension search with [reply], or fails it with [error].
class _FakeDispatcher implements CloudStreamDispatcher {
  _FakeDispatcher({this.reply, this.error});

  final Object? Function()? reply;
  final Object? error;
  final List<String> searchedSourceIds = [];

  @override
  Future<dynamic> search({
    required String sourceId,
    required String query,
    int page = 1,
  }) {
    searchedSourceIds.add(sourceId);
    final failure = error;
    if (failure != null) return Future<dynamic>.error(failure);
    final answer = reply;
    // No reply means the runtime never comes back with anything.
    if (answer == null) return Completer<dynamic>().future;
    return Future<dynamic>.value(answer());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The one extension these tests install. The manager is a singleton, so it is
/// installed once and re-pointed at a new dispatcher per test rather than
/// appended again.
final _extension = CloudStreamSource(
  id: 'dead-extension',
  name: 'Dead Extension',
  internalName: 'dead-extension',
);

void main() {
  late _Routes routes;
  late List<String> failures;
  int resultSections = 0;

  void onSourceError(String source, Object error) => failures.add(source);

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    routes = _Routes();
    failures = <String>[];
    resultSections = 0;
    MetadataService.client = routes.client;
    MetadataService.clearCache();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    MetadataService.client = http.Client();
    MetadataService.clearCache();
  });

  /// Installs one search-enabled addon serving [catalogCount] search catalogs,
  /// through the same manifest fetch a pasted addon URL goes through. The
  /// manager is a singleton, so an addon left by an earlier test is removed
  /// rather than reinstalled on top of it.
  Future<void> installAddon({int catalogCount = 1}) async {
    routes.answerHost(_addonHost, () => _Reply(200, _manifest(catalogCount)));
    for (final addon in AddonManager.instance.addons) {
      if (addon.baseUrl == 'https://$_addonHost') {
        await AddonManager.instance.removeAddon(addon.manifest.id);
      }
    }
    await AddonManager.instance.addAddon('https://$_addonHost');
  }

  /// Points the single installed extension at [dispatcher], enabling it.
  Future<void> installExtension(_FakeDispatcher dispatcher) async {
    CloudStreamManager.instance.dispatcher = dispatcher;
    for (final ext in CloudStreamManager.instance.installedExtensions) {
      await CloudStreamManager.instance.toggleExtension(ext.id, true);
    }
    if (!CloudStreamManager.instance.installedExtensions
        .any((e) => e.id == _extension.id)) {
      CloudStreamManager.instance.installExtensionForTest(_extension);
    }
  }

  /// Hides the extension again, so a run that queried no extension does not
  /// pick up a leftover leg.
  Future<void> hideExtension() async {
    for (final ext in CloudStreamManager.instance.installedExtensions) {
      await CloudStreamManager.instance.toggleExtension(ext.id, false);
    }
    CloudStreamManager.instance.dispatcher = CloudStreamDispatcher.instance;
  }

  /// One search run through the same entry points the page calls, in the same
  /// order, into the same ledger the page keeps.
  Future<SearchFailureLedger> runSearch({String query = 'The Bear'}) async {
    final ledger = SearchFailureLedger();
    void record(String source, Object error) {
      ledger.sourceErrors.add(source);
      onSourceError(source, error);
    }

    final addonSections = await AddonManager.instance
        .searchAll(query, onSourceError: record);
    if (addonSections.isNotEmpty) resultSections++;

    // The page only runs this leg when an extension is installed.
    if (CloudStreamManager.instance.activeExtensions.isNotEmpty) {
      final providers = await CloudStreamManager.instance.searchAcrossExtensions(
        query,
        onSourceError: record,
      );
      if (providers.isNotEmpty) resultSections++;
    }

    final titles = await MetadataService.suggestionSearch(
      query: query,
      onSourceError: record,
    );
    if (titles.isNotEmpty) resultSections++;

    // The denominator the page's copy divides by: one per leg it queried.
    ledger.searchedSourceCount = 1 +
        (CloudStreamManager.instance.activeExtensions.isNotEmpty ? 1 : 0) +
        1;
    return ledger;
  }

  tearDown(hideExtension);

  group('AddonManager.searchAll', () {
    test('a dead addon is reported once, naming it', () async {
      await installAddon();
      // The manifest answered; every catalog behind it throws, which is what a
      // dead addon looks like once it is installed.
      routes.forget(_addonHost);

      final sections = await AddonManager.instance.searchAll(
        'The Bear',
        onSourceError: onSourceError,
      );

      expect(sections, isEmpty);
      expect(failures, ['Dead Addon'],
          reason: 'a dead addon was indistinguishable from an empty catalog');
    });

    test('every failing catalog on one addon still reports once', () async {
      await installAddon(catalogCount: 3);
      // The manifest answered; the three catalog endpoints behind it do not.
      routes.forget(_addonHost);

      await AddonManager.instance.searchAll(
        'The Bear',
        onSourceError: onSourceError,
      );

      expect(
        routes.requested.where((u) => u.path.contains('/search=')).length,
        3,
        reason: 'all three catalogs really were queried',
      );
      expect(failures, ['Dead Addon'],
          reason: 'one dead addon is one source, not one per catalog');
    });

    test('an addon matching nothing is not a failure', () async {
      await installAddon();
      routes.answerPath(_addonHost, '/catalog/', () => _Reply(200, _catalogBody(0)));

      final sections = await AddonManager.instance.searchAll(
        'The Bear',
        onSourceError: onSourceError,
      );

      expect(sections, isEmpty);
      expect(failures, isEmpty,
          reason: 'a healthy source that matched nothing is a miss, not an outage');
    });

    test('a healthy non-empty answer is not a failure', () async {
      await installAddon();
      routes.answerPath(_addonHost, '/catalog/', () => _Reply(200, _catalogBody(2)));

      final sections = await AddonManager.instance.searchAll(
        'The Bear',
        onSourceError: onSourceError,
      );

      expect(sections, isNotEmpty);
      expect(failures, isEmpty);
    });

    test('omitting the callback leaves the result set unchanged', () async {
      await installAddon();
      routes.answerPath(_addonHost, '/catalog/', () => _Reply(200, _catalogBody(2)));

      final sections = await AddonManager.instance.searchAll('The Bear');

      expect(sections, isNotEmpty);
    });
  });

  group('CloudStreamManager.searchAcrossExtensions', () {
    test('a dispatcher answering with nothing is a dead runtime', () async {
      await installExtension(_FakeDispatcher(reply: () => null));

      final results = await CloudStreamManager.instance.searchAcrossExtensions(
        'The Bear',
        onSourceError: onSourceError,
      );

      expect(results, isEmpty);
      expect(failures, ['Dead Extension'],
          reason: 'an expired CloudStream runtime read as an empty result');
    });

    test('a throwing extension is reported', () async {
      await installExtension(
        _FakeDispatcher(error: StateError('sidecar died')),
      );

      final results = await CloudStreamManager.instance.searchAcrossExtensions(
        'The Bear',
        onSourceError: onSourceError,
      );

      expect(results, isEmpty);
      expect(failures, ['Dead Extension']);
    });

    test('an extension that never answers is reported as a timeout', () async {
      await installExtension(_FakeDispatcher());

      final errors = <Object>[];
      final results = await CloudStreamManager.instance.searchAcrossExtensions(
        'The Bear',
        onSourceError: (source, error) {
          failures.add(source);
          errors.add(error);
        },
      );

      expect(results, isEmpty);
      expect(failures, ['Dead Extension']);
      expect(errors.single, isA<TimeoutException>());
    });

    test('an extension matching nothing is not a failure', () async {
      await installExtension(
        _FakeDispatcher(reply: () => <String, dynamic>{'list': <dynamic>[]}),
      );

      final results = await CloudStreamManager.instance.searchAcrossExtensions(
        'The Bear',
        onSourceError: onSourceError,
      );

      expect(results, isEmpty);
      expect(failures, isEmpty,
          reason: 'a live extension that matched nothing is a miss, not an outage');
    });

    test('a healthy non-empty answer is not a failure', () async {
      await installExtension(
        _FakeDispatcher(
          reply: () => <String, dynamic>{
            'list': [
              {'title': 'The Bear', 'url': 'https://example.test/1'}
            ],
          },
        ),
      );

      final results = await CloudStreamManager.instance.searchAcrossExtensions(
        'The Bear',
        onSourceError: onSourceError,
      );

      expect(results['Dead Extension'], isNotEmpty);
      expect(failures, isEmpty);
    });

    test('omitting the callback leaves the result set unchanged', () async {
      await installExtension(_FakeDispatcher(reply: () => null));

      final results =
          await CloudStreamManager.instance.searchAcrossExtensions('The Bear');

      expect(results, isEmpty);
    });
  });

  group('MetadataService.suggestionSearch', () {
    test('a non-200 is reported, not a missing title', () async {
      routes.answerHost(_suggestionHost, () => const _Reply(503, 'unavailable'));

      final movies = await MetadataService.suggestionSearch(
        query: 'The Bear',
        onSourceError: onSourceError,
      );

      expect(movies, isEmpty);
      expect(failures, ['Title lookup'],
          reason: 'a 503 was indistinguishable from "no such title"');
    });

    test('an unreachable endpoint is reported, naming the source', () async {
      // No route for the suggestion host: the request throws, as offline does.
      final movies = await MetadataService.suggestionSearch(
        query: 'The Bear',
        onSourceError: onSourceError,
      );

      expect(movies, isEmpty);
      expect(failures, ['Title lookup'],
          reason: 'being offline looked exactly like "no such title"');
    });

    test('a timeout is reported', () async {
      routes.neverAnswers(_suggestionHost);

      final movies = await MetadataService.suggestionSearch(
        query: 'The Bear',
        onSourceError: onSourceError,
      );

      expect(movies, isEmpty);
      expect(failures, ['Title lookup']);
    });

    test('a cache hit is not a failure', () async {
      routes.answerHost(_suggestionHost, () => _Reply(200, _suggestionBody(1)));

      final first = await MetadataService.suggestionSearch(query: 'The Bear');
      expect(first, isNotEmpty);

      // The second identical query is served from the cache, not the transport.
      final second = await MetadataService.suggestionSearch(
        query: 'The Bear',
        onSourceError: onSourceError,
      );

      expect(second, isNotEmpty);
      expect(failures, isEmpty,
          reason: 'a cache hit is this source having answered, not a source down');
    });

    test('a healthy non-empty answer is not a failure', () async {
      routes.answerHost(_suggestionHost, () => _Reply(200, _suggestionBody(3)));

      final movies = await MetadataService.suggestionSearch(
        query: 'The Bear',
        onSourceError: onSourceError,
      );

      expect(movies, isNotEmpty);
      expect(failures, isEmpty);
    });

    test('a healthy but empty answer is not a failure', () async {
      routes.answerHost(_suggestionHost, () => _Reply(200, _suggestionBody(0)));

      final movies = await MetadataService.suggestionSearch(
        query: 'A Title Nobody Wrote',
        onSourceError: onSourceError,
      );

      expect(movies, isEmpty);
      expect(failures, isEmpty);
    });

    test('omitting the callback leaves the result set unchanged', () async {
      routes.answerHost(_suggestionHost, () => _Reply(200, _suggestionBody(1)));

      final movies = await MetadataService.suggestionSearch(query: 'The Bear');

      expect(movies, isNotEmpty);
    });
  });

  group('the page outcome the failures reach', () {
    test('a dead addon and an offline title lookup behind an empty list '
        'classify as a source failure', () async {
      await installAddon();
      routes.forget(_addonHost);
      final ledger = await runSearch();

      expect(failures, ['Dead Addon', 'Title lookup']);
      expect(resultSections, 0);
      expect(
        classifySearchResult(
          resultCount: resultSections,
          failureCount: ledger.failedSources,
        ),
        SearchOutcome.failed,
        reason: 'every leg failing must not read as a missing title',
      );
    });

    test('every source healthy behind an empty list stays a no-results',
        () async {
      await installAddon();
      routes.answerPath(_addonHost, '/catalog/', () => _Reply(200, _catalogBody(0)));
      routes.answerHost(_suggestionHost, () => _Reply(200, _suggestionBody(0)));

      final ledger = await runSearch();

      expect(ledger.failedSources, 0);
      expect(resultSections, 0);
      expect(
        classifySearchResult(
          resultCount: resultSections,
          failureCount: ledger.failedSources,
        ),
        SearchOutcome.noResults,
      );
    });

    test('partial results beside a dead source are incomplete', () async {
      await installAddon();
      // The addon goes dark; the keyless title rail still answers.
      routes.forget(_addonHost);
      routes.answerHost(_suggestionHost, () => _Reply(200, _suggestionBody(2)));

      final ledger = await runSearch();

      expect(ledger.failedSources, 1);
      expect(resultSections, 1);
      expect(
        classifySearchResult(
          resultCount: resultSections,
          failureCount: ledger.failedSources,
        ),
        SearchOutcome.incomplete,
      );
    });

    test('all three legs dead is still a source failure', () async {
      await installAddon();
      routes.forget(_addonHost);
      final dispatcher = _FakeDispatcher(error: StateError('runtime gone'));
      await installExtension(dispatcher);
      routes.neverAnswers(_suggestionHost);

      final ledger = await runSearch();

      expect(failures, containsAll(<String>['Dead Addon', 'Dead Extension']));
      expect(ledger.failedSources, 3);
      expect(ledger.searchedSourceCount, 3);
      expect(
        classifySearchResult(
          resultCount: resultSections,
          failureCount: ledger.failedSources,
        ),
        SearchOutcome.failed,
      );
    });
  });
}
