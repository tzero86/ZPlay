@Tags(['network'])
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/scraper/sites/vidup.dart';
import 'package:zplay/services/scraper/sites/flaxmovies.dart';
import 'package:zplay/services/scraper/sites/vidgod.dart';
import 'package:zplay/services/scraper/sites/vidfast.dart';
import 'package:zplay/services/scraper/sites/peestream.dart';

class _AllowAllHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _AllowAllHttpOverrides();

  group('Chunk 1 Vyla Scrapers Tests', () {
    test('VidUp scraper fetches streams for Fight Club', () async {
      final scraper = VidUpScraper();
      final stream = scraper.scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        year: 1999,
        imdbId: 'tt0137523',
      );
      final sources = await stream.toList();
      print('[VidUp] streams resolved: ${sources.length}');
      for (final s in sources) {
        print('  -> ${s.title} (${s.url})');
      }
      expect(sources, isNotEmpty);
      expect(sources.first.url, startsWith('http'));
      expect(sources.first.addonName, 'ZPlayHTTP');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('FlaxMovies scraper fetches streams for Fight Club', () async {
      final scraper = FlaxMoviesScraper();
      final stream = scraper.scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        year: 1999,
        imdbId: 'tt0137523',
      );
      final sources = await stream.toList();
      print('[FlaxMovies] streams resolved: ${sources.length}');
      for (final s in sources) {
        print('  -> ${s.title} (${s.url})');
      }
      expect(sources, isNotEmpty);
      expect(sources.first.url, startsWith('http'));
      expect(sources.first.addonName, 'ZPlayHTTP');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('VidGod scraper fetches streams for Fight Club', () async {
      final scraper = VidGodScraper();
      final stream = scraper.scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        year: 1999,
        imdbId: 'tt0137523',
      );
      final sources = await stream.toList();
      print('[VidGod] streams resolved: ${sources.length}');
      for (final s in sources) {
        print('  -> ${s.title} (${s.url})');
      }
      expect(sources, isNotEmpty);
      expect(sources.first.url, startsWith('http'));
      expect(sources.first.addonName, 'ZPlayHTTP');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('VidFast scraper fetches streams for Fight Club', () async {
      final scraper = VidFastScraper();
      final stream = scraper.scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        year: 1999,
        imdbId: 'tt0137523',
      );
      final sources = await stream.toList();
      print('[VidFast] streams resolved: ${sources.length}');
      for (final s in sources) {
        print('  -> ${s.title} (${s.url})');
      }
      expect(sources, isNotEmpty);
      expect(sources.first.url, startsWith('http'));
      expect(sources.first.addonName, 'ZPlayHTTP');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('PeeStream scraper fetches streams for Fight Club', () async {
      final scraper = PeeStreamScraper();
      final stream = scraper.scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        year: 1999,
        imdbId: 'tt0137523',
      );
      final sources = await stream.toList();
      print('[PeeStream] streams resolved: ${sources.length}');
      for (final s in sources) {
        print('  -> ${s.title} (${s.url})');
      }
      expect(sources, isNotEmpty);
      expect(sources.first.url, startsWith('http'));
      expect(sources.first.addonName, 'ZPlayHTTP');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
