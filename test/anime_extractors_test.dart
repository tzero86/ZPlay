// ignore_for_file: avoid_print
@Tags(['network'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/models/anime/anime_media.dart';
import 'package:zplay/services/anime/anime_scraper_service.dart';

void main() {
  test('AnimeScraperService scrapes streams for Solo Leveling S2 Ep 1', () async {
    final scraper = AnimeScraperService.instance;
    const anime = AnimeMedia(
      id: 176189,
      titleEnglish: 'Solo Leveling Season 2: Arise from the Shadow',
      titleRomaji: 'Ore dake Level Up na Ken Season 2: Arise from the Shadow',
      titleNative: '俺だけレベルアップな件 Season 2 -Arise from the Shadow-',
      totalEpisodes: 13,
    );

    final stream = scraper.scrapeStreamsStream(
      anime: anime,
      episodeNumber: 1,
    );

    final sources = await stream.toList();
    print('Scraped ${sources.length} sources for Solo Leveling S2 Ep 1:');
    for (final s in sources) {
      print('  - ${s.name} | ${s.description} -> ${s.url}');
    }

    expect(sources.isNotEmpty, isTrue);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('AnimeScraperService scrapes streams for Demon Slayer Ep 1', () async {
    final scraper = AnimeScraperService.instance;
    const anime = AnimeMedia(
      id: 101922,
      titleEnglish: 'Demon Slayer: Kimetsu no Yaiba',
      titleRomaji: 'Kimetsu no Yaiba',
      titleNative: '鬼滅の刃',
      totalEpisodes: 26,
    );

    final stream = scraper.scrapeStreamsStream(
      anime: anime,
      episodeNumber: 1,
    );

    final sources = await stream.toList();
    print('Scraped ${sources.length} sources for Demon Slayer Ep 1:');
    for (final s in sources) {
      print('  - ${s.name} | ${s.description} -> ${s.url}');
    }

    expect(sources.isNotEmpty, isTrue);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('AnimeScraperService scrapes streams for Jujutsu Kaisen Ep 1', () async {
    final scraper = AnimeScraperService.instance;
    const anime = AnimeMedia(
      id: 113415,
      titleEnglish: 'Jujutsu Kaisen',
      titleRomaji: 'Jujutsu Kaisen',
      titleNative: '呪術廻戦',
      totalEpisodes: 24,
    );

    final stream = scraper.scrapeStreamsStream(
      anime: anime,
      episodeNumber: 1,
    );

    final sources = await stream.toList();
    print('Scraped ${sources.length} sources for Jujutsu Kaisen Ep 1:');
    for (final s in sources) {
      print('  - ${s.name} | ${s.description} -> ${s.url}');
    }

    expect(sources.isNotEmpty, isTrue);
  }, timeout: const Timeout(Duration(seconds: 40)));
}
