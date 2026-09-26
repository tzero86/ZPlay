@Tags(['network'])
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/scraper/sites/a111477.dart';

class _AllowAllHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _AllowAllHttpOverrides();

  test('A111477Scraper fetches streams for movie and TV series', () async {
    final scraper = A111477Scraper();

    print('Testing 111477 for movie: Fight Club (tt0137523)...');
    final movieStream = scraper.scrapeStream(
      type: 'movie',
      title: 'Fight Club',
      imdbId: 'tt0137523',
      year: 1999,
    );

    final movieSources = await movieStream.toList();
    print('Received ${movieSources.length} movie streams:');
    for (final s in movieSources) {
      print('  - ${s.title} (Quality: ${s.quality}, Codec: ${s.codec})');
      print('    URL: ${s.url}');
    }

    expect(movieSources, isNotEmpty);
    expect(movieSources.first.url, startsWith('http'));
    expect(movieSources.first.addonName, 'ZPlayHTTP');

    print('\nTesting 111477 for series: Breaking Bad S01E01 (tt0903747)...');
    final tvStream = scraper.scrapeStream(
      type: 'series',
      title: 'Breaking Bad',
      imdbId: 'tt0903747',
      season: 1,
      episode: 1,
      year: 2008,
    );

    final tvSources = await tvStream.toList();
    print('Received ${tvSources.length} series streams:');
    for (final s in tvSources) {
      print('  - ${s.title} (Quality: ${s.quality}, Codec: ${s.codec})');
      print('    URL: ${s.url}');
    }

    expect(tvSources, isNotEmpty);
    expect(tvSources.first.url, startsWith('http'));
    expect(tvSources.first.addonName, 'ZPlayHTTP');
  });
}
