@Tags(['network'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/scraper/sites/movy.dart';

void main() {
  test('MovyScraper decrypts live stream ciphertext', () async {
    final scraper = MovyScraper();
    final streams = await scraper.scrape(
      type: 'movie',
      title: 'Fight Club',
      year: 1999,
      imdbId: 'tt0137523',
    );

    print('Movy scraped streams count: ${streams.length}');
    for (final s in streams) {
      print(' - ${s.title}: ${s.url}');
    }

    expect(streams.isNotEmpty, true);
  });
}
