import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/scraper/sites/kisskh.dart';

/// KissKH is the reported failure: the search endpoint happily answers a title
/// it has never heard of with a page of unrelated Asian dramas, so accepting
/// "whatever came back first" is how a viewer ends up playing a Korean drama
/// they did not ask for.
void main() {
  group('KissKH picking a drama out of search results', () {
    final unrelated = [
      {'id': '1', 'title': 'Squid Game'},
      {'id': '2', 'title': 'Crash Landing on You'},
    ];

    test('returns nothing when no result names the requested title', () {
      expect(KissKhScraper.pickBestDrama(unrelated, 'The Bear'), isNull);
    });

    test('still accepts the looser match when a title really is a substring', () {
      final results = [
        {'id': '1', 'title': 'Squid Game'},
        {'id': '2', 'title': 'The Bear and the Wild Thing'},
      ];

      expect(KissKhScraper.pickBestDrama(results, 'The Bear'), results[1]);
    });

    test('returns nothing when the result list is empty', () {
      expect(KissKhScraper.pickBestDrama(const [], 'The Bear'), isNull);
    });

    test('ignores malformed entries instead of letting one score', () {
      expect(KissKhScraper.pickBestDrama(['Squid Game', 42], 'The Bear'), isNull);
    });

    test('still picks an exact title match', () {
      final results = [
        {'id': '1', 'title': 'Squid Game'},
        {'id': '2', 'title': 'The Bear'},
      ];

      expect(KissKhScraper.pickBestDrama(results, 'The Bear'), results[1]);
    });

    test('matches across the dash-separated alternate titles a listing carries', () {
      final results = [
        {'id': '1', 'title': 'Squid Game'},
        {'id': '2', 'title': 'The Bear - La Ola'},
      ];

      expect(KissKhScraper.pickBestDrama(results, 'The Bear'), results[1]);
    });

    test('drops the trailing year before comparing', () {
      final results = [
        {'id': '1', 'title': 'Squid Game (2021)'},
        {'id': '2', 'title': 'The Bear (2022)'},
      ];

      expect(KissKhScraper.pickBestDrama(results, 'The Bear (2022)'), results[1]);
    });
  });
}