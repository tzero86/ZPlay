import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/models/iptv/iptv_models.dart';
import 'package:zplay/services/iptv/iptv_storage.dart';
import 'package:zplay/services/iptv/live_health_ordering.dart';

/// Ranking decides which of a channel's portals is opened first, and which one
/// the player moves to when the first dies. It is pure over the two health
/// stores, so both halves are pinned here without a player: `IptvPlayerPage`
/// cannot be pumped - it builds a media_kit `Player` in a field initialiser -
/// and this is the shipped code every failure path in that page calls.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  VerifiedPortal portalAt(String host) => VerifiedPortal(
        portal: IptvPortal(url: host, username: 'john', password: 'secret'),
        name: host,
        expiry: '',
        maxConnections: '1',
        activeConnections: '0',
      );

  IptvStream streamOf(String streamId) => IptvStream(
        streamId: streamId,
        name: 'Card $streamId',
        icon: '',
        categoryId: '12',
        containerExt: 'ts',
        kind: 'live',
      );

  ChannelHit hitAt(String host, String streamId) => ChannelHit(
        portal: portalAt(host),
        stream: streamOf(streamId),
        streamUrl: '$host/live/john/secret/$streamId.ts',
      );

  Future<void> probeAlive(ChannelHit hit, {int minutesAgo = 0}) =>
      IptvAliveStore.save(
        IptvAliveStore.portalKey(hit.portal.portal),
        AliveSnapshot(
          checkedAt: DateTime.now()
              .subtract(Duration(minutes: minutesAgo))
              .millisecondsSinceEpoch,
          aliveIds: {hit.stream.streamId},
        ),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await IptvDeadUrlStore.instance.initialize();
  });

  group('IptvHealthOrdering.sort', () {
    test('puts fresh-alive first, unknown next and known-dead last', () async {
      final alive = hitAt('http://alive.example:8080', '101');
      final unknownA = hitAt('http://unknown-a.example:8080', '202');
      final unknownB = hitAt('http://unknown-b.example:8080', '203');
      final dead = hitAt('http://dead.example:8080', '303');

      await probeAlive(alive);
      await IptvDeadUrlStore.instance.remember(dead.streamUrl, reason: 'stalled');

      final sorted = IptvHealthOrdering.sort([dead, unknownA, unknownB, alive]);

      expect(sorted, [alive, unknownA, unknownB, dead]);
    });

    test('is a permutation: same instances, same length, nothing dropped', () {
      final hits = [
        hitAt('http://one.example:8080', '1'),
        hitAt('http://two.example:8080', '2'),
        hitAt('http://three.example:8080', '3'),
        hitAt('http://four.example:8080', '4'),
      ];

      final sorted = IptvHealthOrdering.sort(hits);

      expect(sorted.length, hits.length);
      for (final hit in hits) {
        expect(
          sorted.where((h) => identical(h, hit)).length,
          1,
          reason: 'a hit was copied, dropped or duplicated',
        );
      }
    });

    test('keeps the incoming order inside a group (ranking is health only)',
        () {
      // The controller pins favourites first before handing the list over, and
      // the ranking must not have an opinion about that: whatever health says
      // nothing about has to keep the order it arrived in.
      final favourite = hitAt('http://favourite.example:8080', '401');
      final plain = hitAt('http://plain.example:8080', '402');

      final sorted = IptvHealthOrdering.sort([favourite, plain]);

      expect(sorted.first, same(favourite));
      expect(sorted.last, same(plain));
    });

    test('a stale probe does not lift a hit out of the unknown group', () async {
      final stale = hitAt('http://stale.example:8080', '501');
      final plain = hitAt('http://plain.example:8080', '502');

      await probeAlive(stale, minutesAgo: IptvAliveStore.ttl.inMinutes + 1);

      final sorted = IptvHealthOrdering.sort([plain, stale]);

      expect(
        sorted,
        [plain, stale],
        reason: 'both are unknown, so the incoming order stands',
      );
    });

    test('a probe for a different stream in the same portal proves nothing',
        () async {
      final probed = hitAt('http://shared.example:8080', '601');
      final unprobed = hitAt('http://shared.example:8080', '602');

      await probeAlive(probed);

      final sorted = IptvHealthOrdering.sort([unprobed, probed]);

      expect(sorted, [probed, unprobed]);
    });

    test('a probe does not rescue a URL playback has already failed', () async {
      final hit = hitAt('http://panel.example:8080', '701');
      final plain = hitAt('http://panel.example:8080', '702');

      await probeAlive(hit);
      await IptvDeadUrlStore.instance.remember(hit.streamUrl, reason: 'stalled');

      final sorted = IptvHealthOrdering.sort([hit, plain]);

      expect(sorted, [plain, hit]);
    });
  });

  group('IptvHealthOrdering.nextUntriedIndex', () {
    final hits = [
      hitAt('http://a.example:8080', '1'),
      hitAt('http://b.example:8080', '2'),
      hitAt('http://c.example:8080', '3'),
    ];

    test('advances to the next hit when one exists', () {
      // A runtime failure at index 0: the page records that URL and asks for
      // the next one, which is what makes a dead feed fail over instead of
      // reporting an error over four working portals.
      expect(
        IptvHealthOrdering.nextUntriedIndex(hits, 0, {hits[0].streamUrl}),
        1,
      );
    });

    test('skips sources that already failed in this run', () {
      expect(
        IptvHealthOrdering.nextUntriedIndex(
          hits,
          0,
          {hits[0].streamUrl, hits[1].streamUrl},
        ),
        2,
      );
    });

    test('wraps around to a source ahead of the current one', () {
      expect(
        IptvHealthOrdering.nextUntriedIndex(hits, 2, {hits[2].streamUrl}),
        0,
      );
    });

    test('skips a URL the dead store already knows', () async {
      await IptvDeadUrlStore.instance.remember(hits[1].streamUrl, reason: 'stalled');

      expect(
        IptvHealthOrdering.nextUntriedIndex(hits, 0, {hits[0].streamUrl}),
        2,
      );
    });

    test('returns null when every other source has been tried', () {
      // Null is the exhausted state: the page paints "All N sources for this
      // channel failed." instead of switching, which is what keeps a channel
      // with nothing left from cycling.
      expect(
        IptvHealthOrdering.nextUntriedIndex(
          hits,
          1,
          hits.map((h) => h.streamUrl).toSet(),
        ),
        isNull,
      );
    });

    test('returns null for a channel with one source', () {
      expect(
        IptvHealthOrdering.nextUntriedIndex(
          [hits.first],
          0,
          {hits.first.streamUrl},
        ),
        isNull,
      );
    });

    test('never switches to a hit with no URL', () {
      final blank = ChannelHit(
        portal: portalAt('http://blank.example:8080'),
        stream: streamOf(''),
        streamUrl: '',
      );

      expect(
        IptvHealthOrdering.nextUntriedIndex(
          [hits.first, blank],
          0,
          {hits.first.streamUrl},
        ),
        isNull,
      );
    });
  });
}
