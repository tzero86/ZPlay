@Tags(['network'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/scraper/sites/cinejoy.dart';

void main() {
  test('Test Cinejoy Encrypted Query Directly', () async {
    debugPrint = (String? message, {int? wrapWidth}) => print(message);

    final scraper = CinejoyScraper();
    final stream = scraper.scrapeStream(
      type: 'movie',
      title: 'Fight Club',
      year: 1999,
      imdbId: 'tt0137523',
    );

    await for (final s in stream) {
      print('FOUND CINEJOY STREAM: ${s.title} -> ${s.url}');
    }
  });
}
