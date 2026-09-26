@Tags(['network'])
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/scraper/sites/lookmovie.dart';
import 'package:zplay/services/scraper/sites/hexa.dart';
import 'package:zplay/services/scraper/sites/bcine.dart';
import 'package:zplay/services/scraper/sites/nova.dart';

class _AllowAllHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _AllowAllHttpOverrides();

  group('Chunk 3 Vyla Scrapers Tests', () {
    test('Bcine scraper generates master HLS for Fight Club', () async {
      final scraper = BcineScraper();
      final stream = scraper.scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        year: 1999,
        imdbId: 'tt0137523',
      );
      final sources = await stream.toList();
      print('[Bcine] streams resolved: ${sources.length}');
      for (final s in sources) {
        print('  -> ${s.title} (${s.url})');
      }
      expect(sources, isNotEmpty);
      expect(sources.first.url, startsWith('http'));
      expect(sources.first.addonName, 'ZPlayHTTP');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('LookMovie scraper queries for Fight Club', () async {
      final scraper = LookMovieScraper();
      final stream = scraper.scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        year: 1999,
        imdbId: 'tt0137523',
      );
      final sources = await stream.toList();
      print('[LookMovie] streams resolved: ${sources.length}');
      for (final s in sources) {
        print('  -> ${s.title} (${s.url})');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Hexa scraper queries for Fight Club', () async {
      final scraper = HexaScraper();
      final stream = scraper.scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        year: 1999,
        imdbId: 'tt0137523',
      );
      final sources = await stream.toList();
      print('[Hexa] streams resolved: ${sources.length}');
      for (final s in sources) {
        print('  -> ${s.title} (${s.url})');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Nova scraper queries for Fight Club', () async {
      final scraper = NovaScraper();
      final stream = scraper.scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        year: 1999,
        imdbId: 'tt0137523',
      );
      final sources = await stream.toList();
      print('[Nova] streams resolved: ${sources.length}');
      for (final s in sources) {
        print('  -> ${s.title} (${s.url})');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
