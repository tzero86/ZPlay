import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/iptv/hardcoded_channels.dart';
import 'package:zplay/services/iptv/iptv_settings.dart';
import 'package:zplay/services/iptv/iptv_storage.dart';
import 'package:zplay/widgets/iptv/iptv_channel_card.dart';
import 'package:zplay/widgets/iptv/iptv_health_badge.dart';

/// Pins the three feed verdicts, the marks that carry them, and where a card
/// puts one.
///
/// The whole feature exists because "this one does not play either" is the
/// user's experience of trial and error, so the verdicts must not blur: a feed
/// nobody has probed is not a feed the app knows to be broken, and this badge
/// is the only place that distinction is visible. Three states, three marks,
/// and a stale check is not evidence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const url = 'http://panel.example:8080/live/john/secret/4242.ts';
  const streamId = '4242';

  /// A snapshot taken [ago] before now that lists [streamId] as alive.
  AliveSnapshot snapshotAgo(Duration ago) => AliveSnapshot(
        checkedAt:
            DateTime.now().millisecondsSinceEpoch - ago.inMilliseconds,
        aliveIds: const {streamId},
      );

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('resolve', () {
    test('a fresh snapshot listing the stream reads working', () {
      expect(
        IptvHitHealth.resolve(
          streamUrl: url,
          streamId: streamId,
          snapshot: snapshotAgo(Duration.zero),
        ),
        IptvHitHealth.working,
      );
    });

    test('no snapshot at all reads unknown', () {
      expect(
        IptvHitHealth.resolve(streamUrl: url, streamId: streamId),
        IptvHitHealth.unknown,
      );
    });

    test('a fresh snapshot that does not list the stream reads unknown', () {
      expect(
        IptvHitHealth.resolve(
          streamUrl: url,
          streamId: streamId,
          snapshot: AliveSnapshot(
            checkedAt: DateTime.now().millisecondsSinceEpoch,
            aliveIds: const {'9999'},
          ),
        ),
        IptvHitHealth.unknown,
      );
    });

    test('a snapshot older than the refresh window is no evidence', () {
      expect(
        IptvHitHealth.resolve(
          streamUrl: url,
          streamId: streamId,
          snapshot: snapshotAgo(IptvAliveStore.ttl + const Duration(minutes: 1)),
        ),
        IptvHitHealth.unknown,
        reason: 'a lapsed check must degrade to unchecked, not to its old claim',
      );
    });

    test('a URL the player failed is dead, and only that URL is', () async {
      final store = IptvDeadUrlStore.instance;
      await store.forget(url);
      addTearDown(() => store.forget(url));

      await store.remember(url, reason: 'open failed');

      expect(
        IptvHitHealth.resolve(
          streamUrl: url,
          streamId: streamId,
          snapshot: snapshotAgo(Duration.zero),
        ),
        IptvHitHealth.dead,
        reason: 'a failed open is newer and more specific evidence than the '
            'portal-wide snapshot it contradicts',
      );
      expect(
        IptvHitHealth.resolve(
          streamUrl: 'http://panel.example:8080/live/john/secret/4243.ts',
          streamId: streamId,
          snapshot: snapshotAgo(Duration.zero),
        ),
        IptvHitHealth.working,
        reason: 'a failure is remembered per URL, not per portal',
      );
    });

    test('a fresh hit, an unprobed hit and a failed URL are three verdicts',
        () async {
      final store = IptvDeadUrlStore.instance;
      await store.forget(url);
      addTearDown(() => store.forget(url));
      await store.remember(url, reason: 'open failed');

      final verdicts = {
        IptvHitHealth.resolve(
          streamUrl: url,
          streamId: streamId,
          snapshot: snapshotAgo(Duration.zero),
        ),
        IptvHitHealth.resolve(
          streamUrl: 'http://panel.example:8080/live/john/secret/4243.ts',
          streamId: streamId,
          snapshot: snapshotAgo(Duration.zero),
        ),
        IptvHitHealth.resolve(
          streamUrl: 'http://panel.example:8080/live/john/secret/4244.ts',
          streamId: '4244',
          snapshot: snapshotAgo(Duration.zero),
        ),
      };
      expect(
        verdicts,
        hasLength(3),
        reason: 'the three states are a set, not a spectrum: no two hits may '
            'resolve the same way here',
      );
    });
  });

  group('ofChannel', () {
    test('a channel with no known feed is unknown, never dead', () {
      expect(IptvHitHealth.ofChannel(const []), IptvHitHealth.unknown);
    });

    test('one working feed is enough for the whole channel', () {
      expect(
        IptvHitHealth.ofChannel(
          const [IptvHitHealth.dead, IptvHitHealth.working],
        ),
        IptvHitHealth.working,
      );
    });

    test('only an all-dead line-up is dead', () {
      expect(
        IptvHitHealth.ofChannel(
          const [IptvHitHealth.dead, IptvHitHealth.dead],
        ),
        IptvHitHealth.dead,
      );
      expect(
        IptvHitHealth.ofChannel(
          const [IptvHitHealth.dead, IptvHitHealth.unknown],
        ),
        IptvHitHealth.unknown,
        reason: 'a dead feed beside an unprobed one still leaves something '
            'that might work',
      );
    });
  });

  group('the badge', () {
    /// The word the badge paints, which is what a colour-blind viewer reads.
    String labelOf(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byType(IptvHealthBadge),
            matching: find.byType(Text),
          ),
        )
        .data!;

    /// The coloured dot's fill.
    Color dotOf(WidgetTester tester) {
      final dot = tester.widget<Container>(
        find.descendant(
          of: find.byType(IptvHealthBadge),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).shape == BoxShape.circle,
          ),
        ),
      );
      return (dot.decoration as BoxDecoration).color!;
    }

    testWidgets('each verdict paints its own word and its own dot', (tester) async {
      final labels = <IptvHitHealth, String>{};
      final dots = <IptvHitHealth, Color>{};
      for (final health in IptvHitHealth.values) {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: IptvHealthBadge(health: health))),
        );
        await tester.pump();
        labels[health] = labelOf(tester);
        dots[health] = dotOf(tester);
      }

      expect(labels, {
        IptvHitHealth.working: 'ALIVE',
        IptvHitHealth.unknown: 'UNCHECKED',
        IptvHitHealth.dead: 'DEAD',
      });
      expect(
        dots.values.toSet(),
        hasLength(3),
        reason: 'the three verdicts must not share a colour either',
      );
    });
  });

  group('the channel card', () {
    const channel = HardcodedChannel(
      id: 'probe',
      name: 'Probe Channel',
      short: 'PRB',
      category: 'Boxing',
      keywords: ['probe'],
      gradient: [Color(0xFFD20A0A), Color(0xFF1A1A1A)],
    );

    Widget host(IptvChannelCard card) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 176, height: 340, child: card),
            ),
          ),
        );

    testWidgets('carries the mark when its caller has a verdict', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const IptvChannelCard(
            channel: channel,
            health: IptvHitHealth.dead,
            onTap: _noop,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(IptvHealthBadge), findsOneWidget);
      expect(find.text('DEAD'), findsOneWidget);
    });

    testWidgets('carries no mark when its caller has not looked', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const IptvChannelCard(channel: channel, onTap: _noop)),
      );
      await tester.pump();

      expect(
        find.byType(IptvHealthBadge),
        findsNothing,
        reason: 'a rail that never asked about health keeps its old poster',
      );
    });

    testWidgets('gives the mark up when the switch is off', (tester) async {
      IptvSettings.showHealthBadge.value = false;
      addTearDown(() => IptvSettings.showHealthBadge.value = true);

      await tester.pumpWidget(
        host(
          const IptvChannelCard(
            channel: channel,
            health: IptvHitHealth.working,
            onTap: _noop,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(IptvHealthBadge), findsNothing);
    });
  });
}

void _noop() {}
