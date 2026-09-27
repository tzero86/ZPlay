import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/models/iptv/iptv_models.dart';
import 'package:zplay/services/iptv/iptv_network.dart';

/// Pins the Xtream-Codes playback URL layout in `IptvClient.streamUrl` /
/// `episodeUrl`.
///
/// A live channel is dead the moment this layout drifts: a wrong segment, a raw
/// `@` in the password, or a stray slash produces a URL the panel answers with
/// 404, and the player reports nothing more specific than "this channel does
/// not play". So every expectation below is the whole URL, not a substring.
void main() {
  const host = 'http://panel.example:8080';

  IptvPortal portal({String username = 'john', String password = 'secret'}) =>
      IptvPortal(url: host, username: username, password: password);

  IptvStream stream(
    String kind,
    String streamId, {
    String containerExt = 'ts',
  }) =>
      IptvStream(
        streamId: streamId,
        name: 'Test channel',
        icon: '',
        categoryId: '12',
        containerExt: containerExt,
        kind: kind,
      );

  IptvEpisode episode(
    String id, {
    String containerExt = 'mp4',
  }) =>
      IptvEpisode(
        id: id,
        title: 'Pilot',
        containerExt: containerExt,
        season: 1,
        episode: 1,
        plot: '',
        image: '',
      );

  group('IptvClient.streamUrl', () {
    test('builds the /live path for a live stream', () {
      expect(
        IptvClient.streamUrl(portal(), stream('live', '2041')),
        '$host/live/john/secret/2041.ts',
      );
    });

    test('builds the /movie path for a vod stream', () {
      expect(
        IptvClient.streamUrl(portal(), stream('vod', '5150', containerExt: 'mp4')),
        '$host/movie/john/secret/5150.mp4',
      );
    });

    // The live test fails on a `/live/` → `/movie/` swap in the live branch, and
    // this one fails if VOD ever starts taking the live path, so a copy-paste
    // between the two arms cannot survive either direction.
    test('live and vod never resolve to the same path', () {
      final live = IptvClient.streamUrl(portal(), stream('live', '2041'));
      final vod = IptvClient.streamUrl(
        portal(),
        stream('vod', '2041', containerExt: 'mp4'),
      );
      expect(live, isNot(vod));
      expect(live, startsWith('$host/live/'));
      expect(vod, startsWith('$host/movie/'));
    });

    // `series` has no arm of its own, and `_openSeriesEpisodes` hands whatever
    // comes back to the player, so an empty string is the only safe answer.
    test('an unhandled kind resolves to the empty string', () {
      expect(IptvClient.streamUrl(portal(), stream('series', '77')), '');
    });

    test('an empty kind resolves to the empty string', () {
      expect(IptvClient.streamUrl(portal(), stream('', '2041')), '');
    });

    test('a kind that only differs in case resolves to the empty string', () {
      expect(IptvClient.streamUrl(portal(), stream('Live', '2041')), '');
    });

    test('percent-encodes a password containing @ : / & and a space', () {
      expect(
        IptvClient.streamUrl(
          portal(password: 'p@ss:w/rd&x z'),
          stream('live', '2041'),
        ),
        '$host/live/john/p%40ss%3Aw%2Frd%26x%20z/2041.ts',
      );
    });

    test('percent-encodes a username containing @', () {
      expect(
        IptvClient.streamUrl(
          portal(username: 'john.doe@isp'),
          stream('live', '2041'),
        ),
        '$host/live/john.doe%40isp/secret/2041.ts',
      );
    });

    test('encodes credentials on the vod path too', () {
      expect(
        IptvClient.streamUrl(
          portal(username: 'a b', password: 'p@ss'),
          stream('vod', '5150', containerExt: 'mp4'),
        ),
        '$host/movie/a%20b/p%40ss/5150.mp4',
      );
    });

    // Documented contract, not an endorsement: the id is interpolated raw. Xtream
    // ids are numeric so this never bites in practice, but if the function ever
    // starts encoding it, that change has to be a deliberate one.
    test('interpolates a stream id with characters verbatim', () {
      expect(
        IptvClient.streamUrl(
          portal(),
          stream('live', 'bbc one/sport hd', containerExt: 'ts'),
        ),
        '$host/live/john/secret/bbc one/sport hd.ts',
      );
    });

    // Not an endorsement: only the credentials go through _enc. `streams()`
    // already forces the live extension to 'ts' and defaults a blank VOD
    // extension to 'mp4', so a real panel cannot inject here, but the current
    // contract is raw and encoding it later is a deliberate change.
    test('interpolates the container extension verbatim', () {
      expect(
        IptvClient.streamUrl(
          portal(),
          stream('live', '2041', containerExt: 'ts?token=a b'),
        ),
        '$host/live/john/secret/2041.ts?token=a b',
      );
    });

    // `streams()` falls back through stream_id → id and finally to '', and
    // nothing between there and the player rejects the result, so an entry that
    // arrives without an id leaves as this - a URL no panel can answer, which is
    // exactly how an unplayable channel looks from the user's side.
    test('an empty stream id yields a dot-extension path', () {
      expect(
        IptvClient.streamUrl(portal(), stream('live', '')),
        '$host/live/john/secret/.ts',
      );
    });

    // `IptvPortal.fromJson` and `IptvStore.load` default a malformed stored
    // record to the empty string, so the host prefix can disappear the same way.
    test('an empty portal url yields a hostless path', () {
      expect(
        IptvClient.streamUrl(
          const IptvPortal(url: '', username: 'john', password: 'secret'),
          stream('live', '2041'),
        ),
        '/live/john/secret/2041.ts',
      );
    });
  });

  group('IptvClient.episodeUrl', () {
    test('builds the /series path for an episode', () {
      expect(
        IptvClient.episodeUrl(portal(), episode('431')),
        '$host/series/john/secret/431.mp4',
      );
    });

    test('keeps the series path when the extension is mkv', () {
      expect(
        IptvClient.episodeUrl(portal(), episode('431', containerExt: 'mkv')),
        '$host/series/john/secret/431.mkv',
      );
    });

    test('percent-encodes credentials', () {
      expect(
        IptvClient.episodeUrl(
          portal(username: 'john.doe@isp', password: 'p@ss:w/rd&x z'),
          episode('431'),
        ),
        '$host/series/john.doe%40isp/p%40ss%3Aw%2Frd%26x%20z/431.mp4',
      );
    });

    // `episodeUrl` has no default arm: an entry the panel omitted resolves to a
    // dot-extension path rather than the empty string `streamUrl` returns.
    test('an empty episode id yields a dot-extension path', () {
      expect(
        IptvClient.episodeUrl(portal(), episode('')),
        '$host/series/john/secret/.mp4',
      );
    });
  });
}
