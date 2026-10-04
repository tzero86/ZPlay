/// Home's "Because you're watching / because you have ... on your list" rows
/// come from the BestSimilar scraper, whose items carry a scraper id
/// (`bestsimilar_10856`) and never an IMDb id: the site publishes none (its
/// pages contain no `tt` id and no imdb link). Opening one of those rows used
/// to end in 'Details unavailable.' whenever the single fuzzy title lookup
/// failed, which was often, because IMDb suggestion rows whose kind is not
/// feature/movie/series come back as `video` or `TV movie` and are dropped by
/// the typed lookup entirely — Wrong Turn 5: Bloodlines exists on IMDb as
/// tt2375779 and still resolved to nothing.
///
/// These tests drive the row from the scraper's real parsed output (captured
/// from the live pages on 2026-10-04: `/movies/25871-wrong-turn` and
/// `/movies/145-sinister`, similar lists) through the production row
/// construction and the real DetailsPage resolution, against suggestion and
/// meta responses captured from the live IMDb suggestion endpoint and
/// Cinemeta. Response lists are trimmed to the rows the assertions need; the
/// rows themselves are unedited.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/pages/details/details_page.dart';
import 'package:zplay/services/home/home_page_settings.dart';
import 'package:zplay/services/metadata/bestsimilar_scraper.dart';
import 'package:zplay/services/metadata/metadata_service.dart';

// ── The scraper's real parsed output ────────────────────────────────────
//
// Field-for-field what `BestSimilarScraper` parses out of the similar-item
// markup on the live pages listed above.

final BSItem _wrongTurn5 = BSItem(
  id: 10856,
  slug: '10856-wrong-turn-5-bloodlines',
  title: 'Wrong Turn 5: Bloodlines',
  year: 2012,
  rating: 4.1,
  voteCount: '26K',
  thumbUrl: 'https://bestsimilar.com/img/movie/thumb/f2/10856.jpg',
  similarityPercent: 67,
  genre: 'Adventure, Crime, Horror, Thriller',
  country: 'Germany, USA, Bulgaria',
  duration: '91 min.',
  story:
      'A small West Virginia town is hosting the legendary Mountain Man Festival '
      'on Halloween, where throngs of costumed party goers gather for a wild '
      'night of music and mischief. But an inbred family of hillbilly cannibals '
      'kill the fun when they trick and ...',
  styleTags: const ['scary', 'rough', 'serious', 'realistic', 'suspenseful'],
  plotTags: const [
    'cannibal',
    'cannibalism',
    'survival',
    'characters killed one by one',
    'outdoor sex',
    'female nudity',
    'no survivors',
    'psychopath',
    'halloween',
    'small town',
    'woods',
    'isolation',
  ],
  audienceTags: const ['teens'],
  timeTags: const ['2010s', '21st century'],
  placeTags: const ['west virginia', 'usa'],
);

final BSItem _sinister2 = BSItem(
  id: 27665,
  slug: '27665-sinister-2',
  title: 'Sinister 2',
  year: 2015,
  rating: 5.3,
  voteCount: '68K',
  thumbUrl: 'https://bestsimilar.com/img/movie/thumb/5b/27665.jpg',
  similarityPercent: 82,
  genre: 'Horror, Mystery, Thriller',
  country: 'UK, Canada, USA',
  duration: '97 min.',
  story: "A young mother and her twin sons move into a rural house that's "
      'marked for death.',
  styleTags: const ['brutal', 'suspenseful', 'suspense', 'disturbing', 'scary'],
  plotTags: const [
    'supernatural',
    'ghost',
    'murder',
    'evil child',
    'haunted house',
    'burned alive',
    'nightmare',
    'ghost child',
    'abusive husband',
    'deputy',
    'investigation',
    'found footage',
  ],
  audienceTags: const ['teens', 'kids'],
  timeTags: const ['year 2016', '21st century'],
  placeTags: const ['usa', 'illinois'],
);

// ── Live responses, trimmed ─────────────────────────────────────────────

// v3.sg.media-imdb.com/suggestion/x/Wrong Turn 5: Bloodlines.json — every
// title row IMDb returns for this title reports the `video` kind, which the
// typed lookup drops, so this is the whole failure class in one fixture.
const _wrongTurn5Suggestions = '''
{"d":[
  {"id":"tt2375779","l":"Wrong Turn 5: Bloodlines","q":"video","y":2012},
  {"id":"tt4596890","l":"Wrong Turn 5: Bloodlines, Wrong Turn 5 Director's Die-aries","q":"video","y":2012},
  {"id":"tt4596916","l":"Wrong Turn 5: Bloodlines - A Day in the Death","q":"video","y":2012}
]}''';

// v3.sg.media-imdb.com/suggestion/x/Sinister 2.json — the winning row.
const _sinister2Suggestions = '''
{"d":[
  {"id":"tt2752772","l":"Sinister 2","q":"feature","y":2015}
]}''';

// v3-cinemeta.strem.io/meta/movie/tt2375779.json and .../tt2752772.json —
// trimmed to the fields MovieDetail reads.
const _metaWrongTurn5 = '''
{"meta":{"id":"tt2375779","type":"movie","name":"Wrong Turn 5: Bloodlines",
 "releaseInfo":"2012",
 "description":"A group of college students, on a trip to the Mountain Man Festival on Halloween in West Virginia, encounter a clan of cannibals.",
 "runtime":"91 min","genres":["Adventure","Horror"],"imdbRating":"4.1"}}''';

const _metaSinister2 = '''
{"meta":{"id":"tt2752772","type":"movie","name":"Sinister 2",
 "releaseInfo":"2015",
 "description":"A young mother and her twin sons move into a rural house that's marked for death.",
 "runtime":"97 min","genres":["Horror","Mystery","Thriller"],"imdbRating":"5.3"}}''';

/// Serves the captured IMDb suggestion and Cinemeta meta responses and 404s
/// anything else, so a title lookup that misses is indistinguishable from one
/// the page could not have made.
class _ScriptedSources extends http.BaseClient {
  final Map<String, String> _suggestions = {
    'Wrong Turn 5: Bloodlines': _wrongTurn5Suggestions,
    'Sinister 2': _sinister2Suggestions,
  };

  final Map<String, String> _metas = {
    'movie/tt2375779': _metaWrongTurn5,
    'movie/tt2752772': _metaSinister2,
  };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url;
    if (url.host == 'v3.sg.media-imdb.com') {
      final last = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
      final query = last.endsWith('.json') ? last.substring(0, last.length - 5) : last;
      final body = _suggestions[query];
      if (body != null) return _ok(body);
    }
    if (url.host == 'v3-cinemeta.strem.io') {
      // fetchMeta also retries behind a /%7B%7D config prefix on a 404.
      final path = url.path.replaceFirst('/%7B%7D', '');
      final match = RegExp(r'^/meta/([^/]+)/([^/]+)\.json$').firstMatch(path);
      final body = match == null ? null : _metas['${match.group(1)}/${match.group(2)}'];
      if (body != null) return _ok(body);
    }
    return _ok('', status: 404);
  }

  http.StreamedResponse _ok(String body, {int status = 200}) =>
      http.StreamedResponse(Stream.value(utf8.encode(body)), status);
}

Future<void> _pumpDetails(WidgetTester tester, Movie row) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(home: DetailsPage(movie: row)));

  // The resolution chain is scripted HTTP: a few pumps land every hop, then
  // the entrance animation has its 650ms to run out.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MetadataService.clearCache();
    MetadataService.client = _ScriptedSources();
  });

  tearDown(() {
    MetadataService.clearCache();
    MetadataService.client = http.Client();
  });

  test('the BestSimilar row keeps the scraper art and a real meta addon', () {
    final row = HomePageSettings.movieFromBestsimilarItem(_wrongTurn5);

    expect(row.id, 'bestsimilar_10856',
        reason: 'the details page keys title resolution off this prefix');
    expect(row.name, 'Wrong Turn 5: Bloodlines');
    expect(row.type, 'movie');
    expect(row.year, '2012',
        reason: 'the row year steers the title lookup, so it must survive');
    expect(row.poster, 'https://bestsimilar.com/img/movie/thumb/f2/10856.jpg',
        reason: 'the scraper thumb is the only art the source gave us');
    expect(row.addonBaseUrl, 'https://v3-cinemeta.strem.io',
        reason: 'the row must point at a real meta server, never the scraper');

    final tvRow = HomePageSettings.movieFromBestsimilarItem(_sinister2);
    expect(tvRow.id, 'bestsimilar_27665');
    expect(tvRow.poster, 'https://bestsimilar.com/img/movie/thumb/5b/27665.jpg');
  });

  testWidgets('a BestSimilar row with a plain IMDb match opens Details',
      (tester) async {
    await _pumpDetails(tester, HomePageSettings.movieFromBestsimilarItem(_sinister2));

    expect(find.text('Details unavailable.'), findsNothing);
    expect(find.textContaining('marked for death'), findsOneWidget,
        reason: 'the description only exists when a real detail loaded');
    expect(find.text('Sinister 2'), findsOneWidget,
        reason: 'the hero title comes from the loaded detail');
  });

  testWidgets(
      'a BestSimilar row whose only IMDb rows are dropped kinds still opens Details',
      (tester) async {
    await _pumpDetails(
        tester, HomePageSettings.movieFromBestsimilarItem(_wrongTurn5));

    expect(find.text('Details unavailable.'), findsNothing,
        reason: 'Wrong Turn 5: Bloodlines exists on IMDb as tt2375779; the '
            'lookup dropping its `video`-kind rows is a lookup problem, not '
            'a missing title');
    expect(find.textContaining('clan of cannibals'), findsOneWidget,
        reason: 'the description only exists when a real detail loaded');
    expect(find.text('Wrong Turn 5: Bloodlines'), findsOneWidget,
        reason: 'the hero title comes from the loaded detail');
  });
}
