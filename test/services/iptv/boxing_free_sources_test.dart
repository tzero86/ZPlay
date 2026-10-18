/// The Boxing bucket holds two families of rows: the premium rights holders a
/// card is bought from, and - since the free public sources landed - the free
/// 24/7 combat channels a card is watched on when no portal carries it.
///
/// The second family is only honest if the playlist that ships it really
/// carries the channel, so these rows are proven against that playlist itself
/// rather than against a sample written by hand. `test/fixtures/iptv/
/// iptvorg_sports_combat.m3u` is a faithful slice of the shipped
/// `https://iptv-org.github.io/iptv/categories/sports.m3u` - every entry whose
/// name mentions boxing, combat or a fight, copied verbatim (the `#EXTM3U`
/// header, each `#EXTINF`, the `#EXTVLCOPT` the one entry that carries it, and
/// the URL), 13 entries in all - and it is parsed here with the same
/// `M3uParser` the app uses, so a name that stops parsing stops proving a row.
///
/// Two things are deliberately not proven here, because they cannot be: whether
/// a feed answers right now (that is what `IptvAliveChecker` is for, and it
/// sniffs real bytes rather than trusting a name), and whether a panel's own
/// numbering matches the playlist's names one for one. The playlist only
/// publishes what its own line-up calls the channel, and that is exactly what
/// these rows are named after.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/models/iptv/m3u_models.dart';
import 'package:zplay/services/iptv/hardcoded_channels.dart';
import 'package:zplay/services/iptv/m3u_parser.dart';

/// The fixture, read from the package root the way `flutter test` runs.
final File _fixture = File('test/fixtures/iptv/iptvorg_sports_combat.m3u');

/// The names the shipped slice publishes, in playlist order.
const List<String> _playlistNames = [
  'Combate (720p)',
  'DAZN Combat (684p)',
  'Fast&FunBox',
  'Fight Network (1080p)',
  'FightBox',
  'FightBox HD',
  'FightBox Poland (576i)',
  'Glory Kickboxing Poland (720p)',
  'Persiana Fight',
  'Polsat Sport Fight (1080p)',
  'Swerve Combat (1080p)',
  'TVMatic Fight (720p)',
  'TVS Boxing (360p)',
];

/// The 14 premium rows, in the order the bucket has always drawn them. The free
/// rows are appended after these, so this list is also where the shipped
/// head of the bucket ends.
///
/// Pinned in full - name, short code, keywords and excludes - because the
/// ticket that added the free rows promised these would not be reordered,
/// renamed or retuned, and a keyword silently changed here is a fight night
/// that silently draws nothing.
const List<
    ({
      String id,
      String name,
      String short,
      List<String> keywords,
      List<String> exclude,
    })> _premiumRows = [
  (
    id: 'boxing_sky_box_office',
    name: 'Sky Sports Box Office',
    short: 'SSBO',
    keywords: ['sky sports box office', 'sky box office', 'sky sports action'],
    exclude: ['cinema', 'movie', 'sky sports news', 'sky news'],
  ),
  (
    id: 'boxing_dazn',
    name: 'DAZN Boxing & PPV',
    short: 'DAZN',
    keywords: ['dazn boxing', 'dazn combat', 'dazn ppv', 'dazn fight', 'dazn 1', 'dazn 2'],
    exclude: ['f1', 'formula', 'motogp', 'moto gp', 'nfl', 'nba', 'football', 'soccer', 'laliga', 'liga'],
  ),
  (
    id: 'boxing_tnt_box_office',
    name: 'TNT Sports Box Office',
    short: 'TNTBO',
    keywords: ['tnt sports box office', 'tnt box office', 'bt sport box office', 'bt box office'],
    exclude: [],
  ),
  (
    id: 'boxing_espn',
    name: 'ESPN Boxing & PPV',
    short: 'ESPN+',
    keywords: ['espn boxing', 'espn ppv', 'espn+ boxing', 'espn plus boxing', 'espn pay per view'],
    exclude: [],
  ),
  (
    id: 'boxing_ppv_events',
    name: 'PPV Fight Events',
    short: 'PPV',
    keywords: ['ppv boxing', 'boxing ppv', 'fight ppv', 'ppv fight', 'boxing pay per view', 'ppv main event'],
    exclude: ['movie', 'cinema', 'adult', 'xxx'],
  ),
  (
    id: 'boxing_premier_sports',
    name: 'Premier Sports',
    short: 'PREM',
    keywords: ['premier sports'],
    exclude: ['sports cup'],
  ),
  (
    id: 'boxing_fight_sports',
    name: 'Fight Sports',
    short: 'FSPT',
    keywords: ['fight sports'],
    exclude: [],
  ),
  (
    id: 'boxing_matchroom',
    name: 'Matchroom Boxing',
    short: 'MATCH',
    keywords: ['matchroom'],
    exclude: ['darts', 'snooker', 'billiards'],
  ),
  (
    id: 'boxing_top_rank',
    name: 'Top Rank Boxing',
    short: 'TOPR',
    keywords: ['top rank'],
    exclude: ['bingo', 'club'],
  ),
  (
    id: 'boxing_pbc',
    name: 'Premier Boxing Champions',
    short: 'PBC',
    keywords: ['pbc', 'premier boxing champions', 'premier boxing'],
    exclude: ['palestine', 'palestinian', 'news', 'radio'],
  ),
  (
    id: 'boxing_golden_boy',
    name: 'Golden Boy Boxing',
    short: 'GBP',
    keywords: ['golden boy'],
    exclude: ['novela', 'telenovela', 'dizi', 'drama'],
  ),
  (
    id: 'boxing_queensberry',
    name: 'Queensberry Promotions',
    short: 'QUEEN',
    keywords: ['queensberry', 'frank warren promotions'],
    exclude: [],
  ),
  (
    id: 'boxing_boxnation',
    name: 'BoxNation',
    short: 'BOXN',
    keywords: ['boxnation', 'box nation', 'boxing nation'],
    exclude: [],
  ),
  (
    id: 'boxing_world_boxing',
    name: 'World Boxing',
    short: 'WORLD',
    keywords: ['world boxing', 'worldboxing'],
    exclude: ['news', 'magazine'],
  ),
];

/// The free rows, in the order they are appended, each named after the channel
/// the slice publishes - never after a premium rights holder.
const List<
    ({
      String id,
      String name,
      List<String> keywords,
    })> _freeRows = [
  (id: 'boxing_fightbox', name: 'FightBox', keywords: ['fightbox', 'fight box']),
  (id: 'boxing_fight_network', name: 'Fight Network', keywords: ['fight network']),
  (id: 'boxing_combate', name: 'Combate', keywords: ['combate']),
  (id: 'boxing_fast_and_funbox', name: 'Fast&FunBox', keywords: ['fast&funbox', 'fast & funbox', 'fast and funbox']),
  (id: 'boxing_glory_kickboxing', name: 'Glory Kickboxing', keywords: ['glory kickboxing', 'kickboxing']),
  (id: 'boxing_persiana_fight', name: 'Persiana Fight', keywords: ['persiana fight']),
  (id: 'boxing_polsat_sport_fight', name: 'Polsat Sport Fight', keywords: ['polsat sport fight', 'polsat fight']),
  (id: 'boxing_swerve_combat', name: 'Swerve Combat', keywords: ['swerve combat']),
  (id: 'boxing_tvmatic_fight', name: 'TVMatic Fight', keywords: ['tvmatic fight']),
  (id: 'boxing_tvs_boxing', name: 'TVS Boxing', keywords: ['tvs boxing']),
];

/// Names the shipped playlist really publishes that are not combat, plus the
/// brand near-misses the free rows introduced. Every one of them shares a whole
/// word with a free row's keyword and must still not be claimed by it: a row
/// that keyworded the brand instead of the channel would swallow the brand's
/// golf, bowling or football feed.
const List<String> _notCombat = [
  'TVS Bowling Network (720p)',
  'DAZN Darts x Pluto TV',
  'World of Freesports (1080p)',
  'NBA TV (720p)',
  'NFL Network (720p)',
  'Sky Racing 1 (720p)',
  'Golf Channel',
  'PokerGo',
  'Tennis Channel (1080p)',
  'FloHockey (1080p)',
  'Eurosport 1 Polska (1080p)',
  'Red Bull TV (1080p)',
  'Sky Sports NFL (720p)',
  'The Cycling Channel',
  'Pluto TV Fishing',
  'Esport3 (1080p) [Geo-blocked]',
  'Racing.com (720p)',
  'CCTV-Golf & Tennis (1080p)',
  'TVMATIC CINE HD',
  'SWERVE SPORTS (720P)',
  'POLSAT SPORT 1 HD',
  'PERSIANA COMEDY HD',
  'SET TOP BOX HD',
];

void main() {
  final List<M3uChannel> entries = M3uParser.parse(_fixture.readAsStringSync());
  final boxing = HardcodedChannels.byCategory('Boxing');

  /// The rows of the bucket that claim [name].
  List<String> claimers(String name) => boxing
      .where((row) => HardcodedChannels.matches(name, row.keywords, row.exclude))
      .map((row) => row.id)
      .toList();

  test('the fixture is the whole combat slice of the shipped playlist', () {
    expect(
      entries.map((entry) => entry.name).toList(),
      _playlistNames,
      reason: 'the slice is copied from the playlist, not written by hand, so a '
          'row proven against it is a row the playlist really carries',
    );
    for (final entry in entries) {
      expect(entry.url, startsWith('http'));
    }
    expect(
      _playlistNames.where((name) => name.toLowerCase().contains('dazn combat')),
      isNotEmpty,
      reason: 'the slice must keep the entry the premium DAZN row claims, or '
          'the coverage test below would pass by having nothing to cover',
    );
  });

  test('the premium rows still lead the bucket, unchanged and in order', () {
    expect(
      boxing.take(_premiumRows.length).map((row) => row.id).toList(),
      _premiumRows.map((row) => row.id).toList(),
      reason: 'the free rows are appended; the shipped rows keep their places',
    );
    expect(
      boxing.first.id,
      'boxing_sky_box_office',
      reason: 'the bucket is still led by the channel it was led by before',
    );
    for (final pinned in _premiumRows) {
      final row = HardcodedChannels.byId(pinned.id);
      expect(row, isNotNull, reason: '${pinned.id} was removed or renamed');
      expect(row!.name, pinned.name, reason: '${pinned.id} was renamed');
      expect(row.short, pinned.short, reason: '${pinned.id} lost its short code');
      expect(
        row.keywords,
        pinned.keywords,
        reason: '${pinned.id} was retuned, which is silent on the night',
      );
      expect(row.exclude, pinned.exclude, reason: '${pinned.id} was retuned');
    }
    expect(
      boxing.length,
      _premiumRows.length + _freeRows.length,
      reason: 'the bucket holds the premium rows and the free rows, nothing else',
    );
    expect(
      boxing.skip(_premiumRows.length).map((row) => row.id).toList(),
      _freeRows.map((row) => row.id).toList(),
      reason: 'the free rows are appended in one block, after the premium rows',
    );
  });

  test('every free row is one the playlist publishes, and only one row claims '
      'each playlist name', () {
    for (final pinned in _freeRows) {
      final row = HardcodedChannels.byId(pinned.id);
      expect(row, isNotNull, reason: '${pinned.id} is missing from the bucket');
      expect(row!.name, pinned.name);
      expect(row.category, 'Boxing');
      expect(
        row.keywords,
        pinned.keywords,
        reason: '${pinned.id} is proven below with exactly these keywords',
      );
    }

    for (final name in _playlistNames) {
      expect(
        claimers(name),
        hasLength(1),
        reason: '"$name" is published by the shipped playlist, so exactly one '
            'row must claim it - none leaves the channel unreachable from the '
            'rail, two would draw the same stream twice',
      );
    }

    // Which row claims which name, spelled out, because "exactly one" would
    // still hold if the free rows had been pointed at the wrong names.
    expect(claimers('Combate (720p)'), ['boxing_combate']);
    expect(claimers('DAZN Combat (684p)'), ['boxing_dazn']);
    expect(claimers('Fast&FunBox'), ['boxing_fast_and_funbox']);
    expect(claimers('Fight Network (1080p)'), ['boxing_fight_network']);
    expect(claimers('FightBox'), ['boxing_fightbox']);
    expect(claimers('FightBox HD'), ['boxing_fightbox']);
    expect(claimers('FightBox Poland (576i)'), ['boxing_fightbox']);
    expect(claimers('Glory Kickboxing Poland (720p)'), ['boxing_glory_kickboxing']);
    expect(claimers('Persiana Fight'), ['boxing_persiana_fight']);
    expect(claimers('Polsat Sport Fight (1080p)'), ['boxing_polsat_sport_fight']);
    expect(claimers('Swerve Combat (1080p)'), ['boxing_swerve_combat']);
    expect(claimers('TVMatic Fight (720p)'), ['boxing_tvmatic_fight']);
    expect(claimers('TVS Boxing (360p)'), ['boxing_tvs_boxing']);
  });

  test('a free row is named after the channel it claims', () {
    for (final pinned in _freeRows) {
      final row = HardcodedChannels.byId(pinned.id)!;
      final hits = entries
          .where((entry) =>
              HardcodedChannels.matches(entry.name, row.keywords, row.exclude))
          .map((entry) => entry.name)
          .toList();
      expect(
        hits,
        isNotEmpty,
        reason: '${row.id} is drawn on the strength of the shipped playlist, so '
            'the playlist has to carry it',
      );
      expect(
        hits.where((name) =>
            name.toLowerCase().startsWith(row.name.toLowerCase())),
        isNotEmpty,
        reason: '${row.id} advertises "${row.name}", and the playlist must '
            'publish a stream of that name - a row named after something the '
            'playlist does not carry is a tile that never draws',
      );
    }
  });

  test('no free row claims a stream that is not a combat channel', () {
    for (final name in _notCombat) {
      final claimed = _freeRows
          .where((pinned) => HardcodedChannels.matches(
                name,
                pinned.keywords,
                HardcodedChannels.byId(pinned.id)!.exclude,
              ))
          .map((pinned) => pinned.id)
          .toList();
      expect(claimed, isEmpty, reason: '"$name" is not a combat channel, but '
          '${claimed.join(', ')} claims it');
    }
  });

  test('a free row carries the logo the playlist publishes for it, or none', () {
    final logos = <String, String>{
      for (final entry in entries) entry.name: entry.logo,
    };
    for (final pinned in _freeRows) {
      final row = HardcodedChannels.byId(pinned.id)!;
      if (row.iconUrl == null) continue;
      final published = entries
          .where((entry) =>
              HardcodedChannels.matches(entry.name, row.keywords, row.exclude))
          .map((entry) => logos[entry.name])
          .toSet();
      expect(
        published,
        contains(row.iconUrl),
        reason: '${row.id} shows an icon the playlist does not publish for it, '
            'which means it was guessed',
      );
    }
    expect(
      HardcodedChannels.byId('boxing_persiana_fight')!.iconUrl,
      isNull,
      reason: 'the playlist publishes no logo for Persiana Fight, so the row '
          'carries none rather than guessing one',
    );
  });
}
