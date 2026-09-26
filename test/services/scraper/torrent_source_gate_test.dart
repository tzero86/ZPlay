import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/models/stream/stream_model.dart';
import 'package:zplay/services/debrid/debrid_service.dart';
import 'package:zplay/services/p2p/p2p_settings_service.dart';
import 'package:zplay/services/scraper/stream_scraper.dart';

/// Torrent indexer stand-in. Named 'ZPlay' exactly like the built-in BitTorrent
/// scrapers, because that name is what the manager's torrent gate keys on.
class _FakeTorrentIndexer extends StreamScraper {
  @override
  String get name => 'ZPlay';

  @override
  Future<List<StreamSource>> scrape({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async {
    return [
      StreamSource(
        name: 'ZPlay',
        title: 'Example Movie 1080p\n2.1 GB',
        infoHash: '0123456789abcdef0123456789abcdef01234567',
        addonName: 'ZPlay',
        sources: const ['tracker:udp://tracker.example.org:80/announce'],
      ),
    ];
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ScraperManager.instance.unregisterTorrentScrapers();
    ScraperManager.instance.registerScraper(_FakeTorrentIndexer());
  });

  Future<List<StreamSource>> runIndexers() => ScraperManager.instance
      .scrapeAll(type: 'movie', title: 'Example Movie')
      .toList();

  group('BitTorrent indexers versus the local P2P engine', () {
    test('dropped when neither P2P nor Debrid could play them', () async {
      P2pSettingsService.isP2pEnabled.value = false;
      DebridService.isDebridReady.value = false;

      expect(await runIndexers(), isEmpty);
    });

    test('kept with P2P off when Debrid resolves magnets in the cloud', () async {
      P2pSettingsService.isP2pEnabled.value = false;
      DebridService.isDebridReady.value = true;

      final sources = await runIndexers();

      expect(sources, hasLength(1));
      expect(sources.single.isMagnet, isTrue);
      expect(sources.single.infoHash, isNotEmpty);
    });

    test('kept with the local P2P engine on', () async {
      P2pSettingsService.isP2pEnabled.value = true;
      DebridService.isDebridReady.value = false;

      expect(await runIndexers(), hasLength(1));
    });
  });

  group('the Debrid bucket the source list counts', () {
    test('a magnet counts as debrid only while a Debrid service is ready', () {
      final magnet = StreamSource(
        name: 'ZPlay',
        title: 'Example Movie 1080p\n2.1 GB',
        infoHash: '0123456789abcdef0123456789abcdef01234567',
        addonName: 'ZPlay',
      );

      expect(magnet.isDebrid, isFalse, reason: 'no debrid marker in the addon text');
      expect(magnet.isTorrent, isTrue, reason: 'the torrent filter must still list it');
      expect(magnet.isDebridPlayable(debridReady: false), isFalse);
      expect(magnet.isDebridPlayable(debridReady: true), isTrue);
    });

    test('a link an addon already resolved stays debrid with no ready service', () {
      final resolved = StreamSource(
        name: '[RD+] Example Movie 1080p',
        url: 'https://real-debrid.com/d/EXAMPLE',
        addonName: 'Torrentio',
      );

      expect(resolved.isDebridPlayable(debridReady: false), isTrue);
      expect(resolved.isMagnet, isFalse);
    });

    test('a plain HTTP stream is never counted as debrid', () {
      final http = StreamSource(
        name: 'ZPlayHTTP',
        url: 'https://cdn.example.org/movie.mp4',
        addonName: 'ZPlayHTTP',
      );

      expect(http.isDebridPlayable(debridReady: true), isFalse);
    });
  });
}
