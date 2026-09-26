@Tags(['network'])
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/scraper/sites/vidapi.dart';
import 'package:zplay/services/scraper/sites/vidrock.dart';
import 'package:zplay/services/scraper/sites/vidvault.dart';
import 'package:zplay/services/scraper/sites/vidzee.dart';

class _AllowAllHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _AllowAllHttpOverrides();

  group('Chunk 5 Vyla Scrapers Tests', () {
    test('VidAPI scraper queries for Fight Club', () async {
      final scraper = VidApiScraper();
      final stream = scraper.scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        year: 1999,
        imdbId: 'tt0137523',
      );
      final sources = await stream.toList();
      print('[VidAPI] streams resolved: ${sources.length}');
      for (final s in sources) {
        print('  -> ${s.title} (${s.url})');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('VidVault scraper queries for Fight Club', () async {
      final scraper = VidVaultScraper();
      final stream = scraper.scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        year: 1999,
        imdbId: 'tt0137523',
      );
      final sources = await stream.toList();
      print('[VidVault] streams resolved: ${sources.length}');
      for (final s in sources) {
        print('  -> ${s.title} (${s.url})');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('VidRock scraper queries for Fight Club', () async {
      final scraper = VidRockScraper();
      final stream = scraper.scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        year: 1999,
        imdbId: 'tt0137523',
      );
      final sources = await stream.toList();
      print('[VidRock] streams resolved: ${sources.length}');
      for (final s in sources) {
        print('  -> ${s.title} (${s.url})');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('VidZee scraper queries for Fight Club', () async {
      final scraper = VidZeeScraper();
      final stream = scraper.scrapeStream(
        type: 'movie',
        title: 'Fight Club',
        year: 1999,
        imdbId: 'tt0137523',
      );
      final sources = await stream.toList();
      print('[VidZee] streams resolved: ${sources.length}');
      for (final s in sources) {
        print('  -> ${s.title} (${s.url})');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
