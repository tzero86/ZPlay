// ignore_for_file: avoid_print
@Tags(['network'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/iptv/hardcoded_channels.dart';
import 'package:zplay/services/iptv/iptv_network.dart';

void main() {
  test('Live Extractor and Channel Matching Engine Evaluation', () async {
    print('\n======================================================');
    print('   EVALUATING PRODUCTION EXTRACTOR & MATCHING ENGINE  ');
    print('======================================================\n');

    // 1. Run live scraper to get latest catalog portals from Reddit + Paste.sh
    print('--> Ingesting from Reddit and decrypting Paste.sh deep links...');
    final scrapePage = await IptvScraper.scrapeCatalogPage(maxResults: 50);

    print('Extracted ${scrapePage.portals.length} portals from Reddit.');
    for (var i = 0; i < scrapePage.portals.length; i++) {
      final p = scrapePage.portals[i];
      print(
        '  [$i] Portal: ${p.url} | User: ${p.username} | Pass: ${p.password} | Src: ${p.source}',
      );
      expect(p.url, startsWith('http'));
      expect(p.username.isNotEmpty, isTrue);
      expect(p.password.isNotEmpty, isTrue);
      expect(p.username.contains('http'), isFalse);
      expect(p.password.contains('http'), isFalse);
      expect(p.password.endsWith('.php'), isFalse);
    }

    // 2. Test Channel Matching Engine with HardcodedChannels
    print('\n--> Testing Channel Matching Engine across Hardcoded Channels...');
    final sampleStreams = [
      'US: UFC 300 MAIN EVENT FHD',
      'UK: SKY SPORTS MAIN EVENT 4K',
      'AR: BEIN SPORTS 1 PREMIUM HD',
      'US: ESPN 2 LIVE HD',
      'US: HBO MAX EAST HD',
      'US: NBA TV HD LIVE',
      'UK: SKY CINEMA PREMIERE FHD',
      'US: DISNEY CHANNEL HD (EAST)',
      'AR: SPACETOON KIDS TV',
      'FR: CANAL+ FOOTBALL HD',
    ];

    var matchCount = 0;
    for (final streamName in sampleStreams) {
      HardcodedChannel? matchedChannel;
      for (final ch in HardcodedChannels.all) {
        if (HardcodedChannels.matches(streamName, ch.keywords, ch.exclude)) {
          matchedChannel = ch;
          break;
        }
      }
      if (matchedChannel != null) {
        matchCount++;
        print(
          '  [MATCHED]: "$streamName" -> ${matchedChannel.name} (${matchedChannel.category})',
        );
      } else {
        print('  [UNMATCHED]: "$streamName"');
      }
    }

    print(
      '\nMatched $matchCount / ${sampleStreams.length} sample streams to curated channels.',
    );
    expect(matchCount, equals(9));
    print('======================================================\n');
  });
}
