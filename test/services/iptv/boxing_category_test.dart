import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/iptv/hardcoded_channels.dart';

/// The Boxing bucket is what the Live page's Boxing rail is drawn from, so it is
/// pinned by behaviour rather than by count: which stream names panels actually
/// publish land in it, and which names only look similar do not.
///
/// Every sample is written the way a portal writes a line-up - country prefix,
/// brand, feed number, quality suffix - because the matcher is a substring and
/// word-boundary match over exactly that string. `HardcodedChannels.matches` is
/// the shipped matcher, so a keyword that stops working fails here and nowhere
/// else, which matters because a wrong keyword is silent: the row simply draws
/// nothing on the night of the fight.
void main() {
  final boxing = HardcodedChannels.byCategory('Boxing');

  /// Per row: names that must match it, and names that must not.
  const samples = <String, ({List<String> hits, List<String> misses})>{
    'boxing_sky_box_office': (
      hits: [
        'UK: SKY SPORTS BOX OFFICE HD',
        'SKY BOX OFFICE 1 FHD',
        'SKY SPORTS ACTION 2 HD',
      ],
      misses: [
        // BOX OFFICE is movie pay-per-view on the same panels.
        'SKY BOX OFFICE MOVIES 1',
        'UK: SKY SPORTS NEWS HD',
      ],
    ),
    'boxing_dazn': (
      hits: [
        'DAZN 1 FHD',
        'DAZN 2 HD',
        'DAZN BOXING',
        'DAZN PPV EVENT 01',
      ],
      misses: [
        // DAZN holds F1, LaLiga, NBA and NFL on the same feed numbers.
        'DAZN 1 F1 HD',
        'DAZN 1 LALIGA',
        'NBA LEAGUE PASS HD',
      ],
    ),
    'boxing_tnt_box_office': (
      hits: [
        'UK: TNT SPORTS BOX OFFICE 1 HD',
        'TNT BOX OFFICE FHD',
        'BT SPORT BOX OFFICE HD',
      ],
      misses: [
        'UK: TNT SPORTS 1 HD',
        'BT SPORT 2 HD',
      ],
    ),
    'boxing_espn': (
      hits: [
        'US: ESPN+ BOXING 01',
        'ESPN PPV 01',
        'ESPN PAY PER VIEW HD',
      ],
      misses: [
        'US: ESPN2 HD',
        'ESPN NEWS HD',
        'ESPN DEPORTES HD',
      ],
    ),
    'boxing_ppv_events': (
      hits: [
        'PPV BOXING 01',
        'BOXING PPV LIVE',
        'PPV MAIN EVENT 1',
      ],
      misses: [
        // Numbered PPV feeds are shared with movies and adult channels.
        'PPV MOVIES 1',
        'BOXING PPV ADULT',
      ],
    ),
    'boxing_premier_sports': (
      hits: [
        'UK: PREMIER SPORTS 1 HD',
        'PREMIER SPORTS 2 FHD',
      ],
      misses: [
        'PREMIER SPORTS CUP',
        'PREMIER LEAGUE TV HD',
      ],
    ),
    'boxing_fight_sports': (
      hits: [
        'FIGHT SPORTS MAX HD',
        'FIGHT SPORTS NETWORK',
      ],
      misses: [
        // Fight Network is the sibling brand, curated under Int. Sports.
        'FIGHT NETWORK HD',
        'UFC FIGHT PASS HD',
      ],
    ),
    'boxing_matchroom': (
      hits: [
        'MATCHROOM BOXING 01',
        'MATCHROOM FIGHT CAMP',
      ],
      misses: [
        // Matchroom promotes darts and snooker under the same brand.
        'MATCHROOM DARTS CH',
        'MATCHROOM SNOOKER HD',
      ],
    ),
    'boxing_top_rank': (
      hits: [
        'TOP RANK BOXING HD',
        'TOP RANK 01',
      ],
      misses: [
        // TOP RANK is also a bingo and nightclub brand.
        'TOP RANK BINGO',
        'UFC FIGHT PASS HD',
      ],
    ),
    'boxing_pbc': (
      hits: [
        'PBC BOXING 1 HD',
        'PBC ON FOX HD',
        'PREMIER BOXING CHAMPIONS HD',
      ],
      misses: [
        // PBC is also the Palestinian Broadcasting Corporation.
        'PBC PALESTINE',
        'PBC NEWS HD',
      ],
    ),
    'boxing_golden_boy': (
      hits: [
        'GOLDEN BOY BOXING HD',
        'GOLDEN BOY LIVE',
      ],
      misses: [
        // Golden Boy is also a drama and telenovela title panels carry.
        'GOLDEN BOY NOVELA',
        'GOLDEN BOY DIZI HD',
      ],
    ),
    'boxing_queensberry': (
      hits: [
        'QUEENSBERRY PROMOTIONS HD',
        'QUEENSBERRY BOXING 1',
      ],
      misses: [
        'SKY SPORTS RACING HD',
        'WORLD BOXING NEWS 24',
      ],
    ),
    'boxing_boxnation': (
      hits: [
        'BOX NATION HD',
        'BOXNATION 1 FHD',
        'BOXING NATION TV',
      ],
      misses: [
        // No bare "box" keyword, so a set-top-box or box-office channel is not a hit.
        'BOX OFFICE CINEMA 1',
        'SET TOP BOX HD',
      ],
    ),
    'boxing_world_boxing': (
      hits: [
        'WORLD BOXING TV HD',
        'WORLD BOXING SUPER SERIES',
      ],
      misses: [
        // WORLD BOXING is also a trade magazine title.
        'WORLD BOXING NEWS 24',
        'WORLD NEWS HD',
      ],
    ),
  };

  group('Boxing category', () {
    test('holds at least the six rows the rail needs, all uniquely prefixed', () {
      expect(boxing.length, greaterThanOrEqualTo(6));
      final ids = boxing.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'duplicate channel id');
      for (final row in boxing) {
        expect(row.id, startsWith('boxing_'));
        expect(row.category, 'Boxing');
        expect(row.keywords, isNotEmpty);
      }
    });

    test('every row has a pinned sample, and none is pinned twice', () {
      expect(
        samples.keys.toSet(),
        boxing.map((c) => c.id).toSet(),
        reason: 'a row was added or removed without a sample',
      );
    });

    for (final row in boxing) {
      final sample = samples[row.id]!;

      test('${row.id} matches its intended line-up names', () {
        for (final name in sample.hits) {
          expect(
            HardcodedChannels.matches(name, row.keywords, row.exclude),
            isTrue,
            reason: '"$name" should be a Boxing hit for ${row.id}',
          );
        }
      });

      test('${row.id} refuses its negative samples', () {
        for (final name in sample.misses) {
          expect(
            HardcodedChannels.matches(name, row.keywords, row.exclude),
            isFalse,
            reason: '"$name" must not be a Boxing hit for ${row.id}',
          );
        }
      });
    }

    test('no Boxing row swallows a non-boxing channel', () {
      const notBoxing = [
        'UK: SKY SPORTS NEWS HD',
        'SKY SPORTS F1 HD',
        'UK: SKY SPORTS RACING HD',
        'UK: TNT SPORTS 1 HD',
        'US: ESPN2 HD',
        'MATCHROOM DARTS CH',
        'PBC PALESTINE',
        'GOLDEN BOY NOVELA',
        'FIGHT NETWORK HD',
        'PPV MOVIES 1',
        'WORLD BOXING NEWS 24',
        'NBA TV HD',
        'PREMIER LEAGUE TV HD',
        'PREMIER SPORTS CUP',
        'SET TOP BOX HD',
      ];
      for (final name in notBoxing) {
        final matched = boxing
            .where((c) => HardcodedChannels.matches(name, c.keywords, c.exclude))
            .map((c) => c.id)
            .toList();
        expect(matched, isEmpty, reason: '"$name" matched $matched');
      }
    });
  });
}
