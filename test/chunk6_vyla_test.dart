@Tags(['network'])
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/scraper/sites/cinesrc.dart';
import 'package:zplay/services/scraper/sites/cinesu.dart';
import 'package:zplay/services/scraper/sites/frame.dart';

class _AllowAllHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _AllowAllHttpOverrides();

  group('Chunk 6 Vyla Scrapers Tests', () {
    test('CineSrc scraper generates master HLS for Fight Club', () async {
      final scraper = CineSrcScraper();
      final stream = scraper.scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        year: 1999,
        imdbId: 'tt0137523',
      );
      final sources = await stream.toList();
      print('[CineSrc] streams resolved: ${sources.length}');
      for (final s in sources) {
        print('  -> ${s.title} (${s.url})');
      }
      expect(sources, isNotEmpty);
      expect(sources.first.url, startsWith('http'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('CineSu scraper generates master HLS for Fight Club', () async {
      final scraper = CineSuScraper();
      final stream = scraper.scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        year: 1999,
        imdbId: 'tt0137523',
      );
      final sources = await stream.toList();
      print('[CineSu] streams resolved: ${sources.length}');
      for (final s in sources) {
        print('  -> ${s.title} (${s.url})');
      }
      expect(sources, isNotEmpty);
      expect(sources.first.url, startsWith('http'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Frame scraper queries for Fight Club', () async {
      final scraper = FrameScraper();
      final stream = scraper.scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        year: 1999,
        imdbId: 'tt0137523',
      );
      final sources = await stream.toList();
      print('[Frame] streams resolved: ${sources.length}');
      for (final s in sources) {
        print('  -> ${s.title} (${s.url})');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
