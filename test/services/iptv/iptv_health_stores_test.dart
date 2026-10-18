import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/iptv/iptv_storage.dart';

/// The two stores the live path ranks streams with.
///
/// `IptvDeadUrlStore` is what turns a stream that just failed into a source the
/// pages stop offering first, and `IptvAliveStore.ttl` is what stops a probe
/// from an earlier session being treated as the state of the world now. Both
/// windows are minutes on purpose - a panel reshuffles its line-up inside the
/// hour - so an answer older than the window has to fall back to "unknown"
/// rather than to "alive" or "dead".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const deadUrl = 'http://panel.example:8080/live/john/secret/2041.ts';
  const otherUrl = 'http://panel.example:8080/live/john/secret/2042.ts';

  group('IptvDeadUrlStore', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await IptvDeadUrlStore.instance.initialize();
    });

    test('remembers a URL the player could not play', () async {
      expect(IptvDeadUrlStore.instance.isDead(deadUrl), isFalse);

      await IptvDeadUrlStore.instance
          .remember(deadUrl, reason: 'failed to open');

      expect(IptvDeadUrlStore.instance.isDead(deadUrl), isTrue);
      // Matched on the trimmed string, because a URL reaches the player padded
      // from one path and clean from another.
      expect(IptvDeadUrlStore.instance.isDead('  $deadUrl  '), isTrue);
      expect(IptvDeadUrlStore.instance.isDead(otherUrl), isFalse);
      expect(IptvDeadUrlStore.instance.isDead(''), isFalse);
      expect(IptvDeadUrlStore.instance.isDead(null), isFalse);
    });

    test('forget clears one URL and leaves the rest', () async {
      await IptvDeadUrlStore.instance.remember(deadUrl);
      await IptvDeadUrlStore.instance.remember(otherUrl);

      await IptvDeadUrlStore.instance.forget(deadUrl);

      expect(IptvDeadUrlStore.instance.isDead(deadUrl), isFalse);
      expect(IptvDeadUrlStore.instance.isDead(otherUrl), isTrue);
    });

    test('revision bumps on remember and on forget, and not otherwise', () async {
      final start = IptvDeadUrlStore.instance.revision.value;

      await IptvDeadUrlStore.instance.remember(deadUrl);
      final remembered = IptvDeadUrlStore.instance.revision.value;
      expect(remembered, greaterThan(start));

      await IptvDeadUrlStore.instance.forget(deadUrl);
      final forgotten = IptvDeadUrlStore.instance.revision.value;
      expect(forgotten, greaterThan(remembered));

      // A forget of something never recorded is not a change, so a listener
      // rebuilt from it cannot loop.
      await IptvDeadUrlStore.instance.forget(deadUrl);
      expect(IptvDeadUrlStore.instance.revision.value, forgotten);
    });

    test('a failure inside the window survives a reload', () async {
      await IptvDeadUrlStore.instance.remember(deadUrl, reason: 'stalled');

      await IptvDeadUrlStore.instance.initialize();

      expect(IptvDeadUrlStore.instance.isDead(deadUrl), isTrue);
    });

    test('a failure older than the window is dropped, not reloaded', () async {
      final stale = DateTime.now()
          .subtract(IptvDeadUrlStore.ttl + const Duration(minutes: 1));
      SharedPreferences.setMockInitialValues({
        'pt_iptv_dead_urls': jsonEncode({
          deadUrl: {'reason': 'stalled', 'at': stale.toIso8601String()},
        }),
      });

      await IptvDeadUrlStore.instance.initialize();

      expect(IptvDeadUrlStore.instance.isDead(deadUrl), isFalse);
    });

    test('the window is the 30 minutes the live pages rely on', () {
      expect(IptvDeadUrlStore.ttl, const Duration(minutes: 30));
    });
  });

  group('IptvAliveStore staleness', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    int minutesAgo(int minutes) => DateTime.now()
        .subtract(Duration(minutes: minutes))
        .millisecondsSinceEpoch;

    test('a snapshot inside the window is fresh', () {
      expect(
        IptvAliveStore.isFresh(
          AliveSnapshot(checkedAt: minutesAgo(0), aliveIds: const {'2041'}),
        ),
        isTrue,
      );
      expect(IptvAliveStore.isFreshSince(minutesAgo(20)), isTrue);
    });

    test('a snapshot older than the window no longer counts as already checked',
        () {
      // `startAliveCheck` re-probes exactly when this is false: the old gate was
      // "a timestamp exists", which meant a portal was probed once per install
      // and its Live-only filter and health ranking stayed on that answer.
      final stale = minutesAgo(IptvAliveStore.ttl.inMinutes + 1);
      expect(
        IptvAliveStore.isFresh(
          AliveSnapshot(checkedAt: stale, aliveIds: const {'2041'}),
        ),
        isFalse,
      );
      expect(IptvAliveStore.isFreshSince(stale), isFalse);
    });

    test('no snapshot at all is not fresh', () {
      expect(IptvAliveStore.isFresh(null), isFalse);
      expect(IptvAliveStore.isFreshSince(null), isFalse);
      expect(IptvAliveStore.isFreshSince(0), isFalse);
    });

    test('the window is the 30 minutes the live pages rely on', () {
      expect(IptvAliveStore.ttl, const Duration(minutes: 30));
    });

    test('load and save both hand the snapshot to the synchronous reader',
        () async {
      const key = 'http://panel.example:8080|john|secret';
      final snapshot = AliveSnapshot(
        checkedAt: minutesAgo(0),
        aliveIds: const {'2041'},
      );

      await IptvAliveStore.save(key, snapshot);

      expect(IptvAliveStore.cached(key)?.aliveIds, contains('2041'));

      await IptvAliveStore.clear(key);

      expect(IptvAliveStore.cached(key), isNull);
      expect(await IptvAliveStore.load(key), isNull);
      expect(IptvAliveStore.cached(key), isNull);
    });

    test('load fills the synchronous reader from prefs', () async {
      const key = 'http://panel.example:8080|john|secret';
      SharedPreferences.setMockInitialValues({
        'pt_iptv_alive_$key': jsonEncode({
          'at': minutesAgo(0),
          'ids': ['2041'],
        }),
      });
      expect(IptvAliveStore.cached(key), isNull);

      final loaded = await IptvAliveStore.load(key);

      expect(loaded?.aliveIds, contains('2041'));
      expect(IptvAliveStore.cached(key)?.aliveIds, contains('2041'));
    });
  });
}
