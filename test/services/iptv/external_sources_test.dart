import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/iptv/hardcoded_channels.dart';
import 'package:zplay/services/iptv/iptv_settings.dart';
import 'package:zplay/services/iptv/sources/external_channel_source.dart';
import 'package:zplay/services/iptv/sources/m3u_remote_source.dart';

/// The second source family: public and user M3U playlists reaching a curated
/// channel that no verified portal carries.
///
/// The channel used throughout is the real Boxing rail entry for Sky Sports Box
/// Office, so the keyword and exclude rules under test are the ones the app
/// actually ships: `movie` and `cinema` are excluded because panels use "BOX
/// OFFICE" for movie pay-per-view too, and "Sky Sports News" shares its name
/// with the news channel.
const String _skyBoxOffice = 'boxing_sky_box_office';

/// One entry with a logo, one without, one that the channel's exclude list
/// rejects, and one that simply is not this channel.
const String _playlist = '''
#EXTM3U
#EXTINF:-1 tvg-logo="http://logo.test/skybo.png" group-title="Sports",Sky Sports Box Office HD
https://example.test/free/skybo.m3u8
#EXTINF:-1 group-title="Sports",Sky Sports Box Office Cinema
https://example.test/free/skybo-cinema.m3u8
#EXTINF:-1 group-title="Sports",Sky Sports News
https://example.test/free/skynews.m3u8
#EXTINF:-1 group-title="Sports",FightBox
https://example.test/free/fightbox.m3u8
''';

ExternalStream _stream(String name, String url,
        [String label = 'Free Sports (iptv-org)']) =>
    ExternalStream(name: name, url: url, label: label);

/// A source with no I/O: what the hub does with an answer, and with a source
/// that breaks the "never throws" promise.
class _FakeSource implements ExternalChannelSource {
  _FakeSource(this.label, {this.streams = const [], this.fails = false});

  @override
  final String label;

  final List<ExternalStream> streams;
  final bool fails;

  int calls = 0;

  @override
  Future<List<ExternalStream>> fetch() async {
    calls++;
    if (fails) throw StateError('source is broken');
    return streams;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sky = HardcodedChannels.byId(_skyBoxOffice)!;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ExternalSources.sourcesOverride = null;
    IptvSettings.includeFreeSources.value = true;
    // The hub's saved-playlist source reads the store once and caches it for a
    // moment, so each test starts from the store state it just installed.
    ExternalSources.savedPlaylists.clearCache();
  });

  tearDown(() {
    ExternalSources.sourcesOverride = null;
    IptvSettings.includeFreeSources.value = true;
    ExternalSources.savedPlaylists.clearCache();
  });

  group('RemoteM3uSource', () {
    test('maps a playlist entry to an external stream', () {
      final streams = RemoteM3uSource.parseToStreams(
          _playlist, 'Free Sports (iptv-org)');

      expect(streams.length, 4);
      expect(streams.first.name, 'Sky Sports Box Office HD');
      expect(streams.first.url, 'https://example.test/free/skybo.m3u8');
      expect(streams.first.label, 'Free Sports (iptv-org)');
      expect(streams.first.icon, 'http://logo.test/skybo.png');
      // No tvg-logo means no icon, not an empty string, so the UI can tell the
      // difference between "no artwork" and "artwork that failed to load".
      expect(streams[1].icon, isNull);
    });

    test('downloads once and serves the rest from its cache', () async {
      var calls = 0;
      final source = RemoteM3uSource(
        'Free Sports (iptv-org)',
        'https://playlist.test/sports.m3u',
        fetchText: (_) async {
          calls++;
          return _playlist;
        },
      );

      final first = await source.fetch();
      final second = await source.fetch();

      expect(first.length, 4);
      expect(second, first);
      expect(calls, 1);
    });

    test('two overlapping scans share one download', () async {
      var calls = 0;
      final body = Completer<String>();
      final source = RemoteM3uSource(
        'Free Sports (iptv-org)',
        'https://playlist.test/sports.m3u',
        fetchText: (_) {
          calls++;
          return body.future;
        },
      );

      final first = source.fetch();
      final second = source.fetch();
      body.complete(_playlist);

      expect(await first, isNotEmpty);
      expect(await second, isNotEmpty);
      expect(calls, 1);
    });

    test('a failed download yields no streams and is not cached', () async {
      var calls = 0;
      final source = RemoteM3uSource(
        'Free Sports (iptv-org)',
        'https://playlist.test/sports.m3u',
        fetchText: (_) async {
          calls++;
          throw Exception('host is down');
        },
      );

      expect(await source.fetch(), isEmpty);
      // Retried rather than remembered: a host that was down for a minute must
      // not take the source out for the playlist's whole freshness window.
      expect(await source.fetch(), isEmpty);
      expect(calls, 2);
    });

    test('text that is not a playlist is a failure, not a throw', () async {
      final source = RemoteM3uSource(
        'Free Sports (iptv-org)',
        'https://playlist.test/sports.m3u',
        fetchText: (_) async => '<html><body>404 Not Found</body></html>',
      );

      expect(await source.fetch(), isEmpty);
    });
  });

  group('ExternalSources.active', () {
    test('offers the free sports playlist by default and drops it when off',
        () {
      expect(
        ExternalSources.freeSportsUrl,
        'https://iptv-org.github.io/iptv/categories/sports.m3u',
      );

      final on = ExternalSources.active().map((s) => s.label).toList();
      expect(on, contains(ExternalSources.freeSportsLabel));

      IptvSettings.includeFreeSources.value = false;
      final off = ExternalSources.active().map((s) => s.label).toList();
      expect(off, isNot(contains(ExternalSources.freeSportsLabel)));
      // The user's own playlists are not a "free public source" and survive the
      // switch: turning it off means "do not go outside my stuff", not "forget
      // the playlists I imported".
      expect(off, contains('Your playlist'));
    });
  });

  group('ExternalSources.candidatesFor', () {
    test('admits only the entries the channel\'s keywords allow', () async {
      ExternalSources.sourcesOverride = [
        RemoteM3uSource(
          'Free Sports (iptv-org)',
          'https://playlist.test/sports.m3u',
          fetchText: (_) async => _playlist,
        ),
      ];

      final hits = await ExternalSources.candidatesFor(sky);

      // Matched: "Sky Sports Box Office HD". Rejected: the same name ending in
      // "Cinema" (excluded), "Sky Sports News" (excluded), and "FightBox" (no
      // keyword).
      expect(hits.map((s) => s.name).toList(), ['Sky Sports Box Office HD']);
    });

    test('offers the same URL from two sources only once', () async {
      ExternalSources.sourcesOverride = [
        _FakeSource('Free Sports (iptv-org)', streams: [
          _stream('Sky Sports Box Office', 'https://example.test/free/x.m3u8'),
          _stream('Sky Sports Action', 'https://example.test/free/y.m3u8'),
        ]),
        _FakeSource('Your playlist: Boxing Night', streams: [
          _stream('Sky Sports Box Office HD', 'https://example.test/free/x.m3u8',
              'Your playlist: Boxing Night'),
        ]),
      ];

      final hits = await ExternalSources.candidatesFor(sky);

      expect(
        hits.map((s) => s.url).toList(),
        ['https://example.test/free/x.m3u8', 'https://example.test/free/y.m3u8'],
      );
      // The first source to name it wins, so the label stays honest about where
      // the stream was taken from.
      expect(hits.first.label, 'Free Sports (iptv-org)');
    });

    test('stops at twelve candidates', () async {
      ExternalSources.sourcesOverride = [
        _FakeSource('Free Sports (iptv-org)', streams: [
          for (var i = 0; i < 30; i++)
            _stream('Sky Sports Box Office $i',
                'https://example.test/free/$i.m3u8'),
        ]),
      ];

      final hits = await ExternalSources.candidatesFor(sky);

      expect(ExternalSources.maxCandidates, 12);
      expect(hits.length, 12);
    });

    test('a source that throws is dropped and the rest still answer', () async {
      ExternalSources.sourcesOverride = [
        _FakeSource('broken', fails: true),
        _FakeSource('Your playlist: Boxing Night', streams: [
          _stream('Sky Sports Box Office', 'https://example.test/free/ok.m3u8'),
        ]),
      ];

      final hits = await ExternalSources.candidatesFor(sky);

      expect(hits.map((s) => s.url).toList(),
          ['https://example.test/free/ok.m3u8']);
    });

    test('a lone failing source yields no candidates and no exception',
        () async {
      ExternalSources.sourcesOverride = [_FakeSource('broken', fails: true)];

      expect(await ExternalSources.candidatesFor(sky), isEmpty);
    });

    test('an entry with no URL never reaches the scan', () async {
      ExternalSources.sourcesOverride = [
        _FakeSource('Free Sports (iptv-org)', streams: [
          _stream('Sky Sports Box Office', ''),
          _stream('Sky Sports Action', 'https://example.test/free/ok.m3u8'),
        ]),
      ];

      // The scan hands these straight to the sniffer, which would spend an 8s
      // timeout on a URL that cannot resolve, so the hub is where a URL-less
      // entry is refused.
      expect(
        (await ExternalSources.candidatesFor(sky)).map((s) => s.url).toList(),
        ['https://example.test/free/ok.m3u8'],
      );
    });

    test('with free sources off, only the imported playlist answers', () async {
      // The persisted playlist key is a contract of its own — renaming it drops
      // every imported playlist — so the test spells it out instead of reading
      // it from the store class.
      SharedPreferences.setMockInitialValues({
        'pt_iptv_m3u_playlists_v1': json.encode([
          {
            'id': 'p1',
            'name': 'Boxing Night',
            'sourceUrl': null,
            'addedAt': 1,
            'updatedAt': 1,
            'channels': [
              {
                'n': 'Sky Sports Box Office HD',
                'u': 'https://example.test/mine/boxoffice.m3u8',
                'l': 'http://logo.test/mine.png',
              },
              {'n': 'FightBox', 'u': 'https://example.test/mine/fightbox.m3u8'},
            ],
          },
        ]),
      });
      IptvSettings.includeFreeSources.value = false;

      final hits = await ExternalSources.candidatesFor(sky);

      expect(hits.map((s) => '${s.label}|${s.name}|${s.icon}').toList(), [
        'Your playlist: Boxing Night|Sky Sports Box Office HD|'
            'http://logo.test/mine.png',
      ]);
    });
  });
}
