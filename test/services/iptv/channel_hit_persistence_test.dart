import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/models/iptv/iptv_models.dart';

/// The channel-results cache writes one JSON object per hit under the channel
/// id. Those keys are the on-disk format of every installed build: a hit saved
/// by 1.6.18 has to load in this version, and a hit saved here has to stay
/// readable if the app is downgraded. `StoredHit` was the flat mirror that used
/// to own that shape; the model owns it now, so this pins the shape itself.
///
/// A silent rename here would not crash anything — it would quietly empty every
/// user's Boxing channel results on the next launch.
void main() {
  ChannelHit sample() => const ChannelHit(
    portal: VerifiedPortal(
      portal: IptvPortal(
        url: 'http://panel.example:8080',
        username: 'john',
        password: 'secret',
        source: 'Saved',
      ),
      name: 'Panel',
      expiry: '2027-01-01',
      maxConnections: '2',
      activeConnections: '1',
    ),
    stream: IptvStream(
      streamId: '2041',
      name: 'Boxing Main Event FHD',
      icon: 'http://panel.example/logo.png',
      categoryId: '12',
      containerExt: 'ts',
      kind: 'live',
    ),
    streamUrl: 'http://panel.example:8080/live/john/secret/2041.ts',
  );

  test('writes exactly the keys the shipped format uses', () {
    final json = sample().toJson();
    expect(
      json.keys.toSet(),
      <String>{
        'pu',
        'uu',
        'pp',
        'pn',
        'sid',
        'sn',
        'si',
        'scid',
        'sce',
        'sk',
        'url',
      },
      reason: 'these abbreviations are the persisted contract, not a style',
    );
    expect(json['pu'], 'http://panel.example:8080');
    expect(json['uu'], 'john');
    expect(json['sid'], '2041');
    expect(json['url'], 'http://panel.example:8080/live/john/secret/2041.ts');
  });

  test('round-trips a hit', () {
    final restored = ChannelHit.fromJson(sample().toJson());
    expect(restored.portal.portal.url, 'http://panel.example:8080');
    expect(restored.portal.portal.username, 'john');
    expect(restored.portal.name, 'Panel');
    expect(restored.stream.streamId, '2041');
    expect(restored.stream.name, 'Boxing Main Event FHD');
    expect(restored.stream.containerExt, 'ts');
    expect(restored.stream.kind, 'live');
    expect(restored.streamUrl, sample().streamUrl);
    // A restored hit is a "Saved" portal: its expiry and connection counts were
    // never persisted.
    expect(restored.portal.portal.source, 'Saved');
    expect(restored.portal.expiry, isEmpty);
  });

  test('tolerates a hit written before a key existed', () {
    // `sk` absent: the old reader defaulted to a live stream.
    final legacy = sample().toJson()..remove('sk');
    final restored = ChannelHit.fromJson(legacy);
    expect(restored.stream.kind, 'live');

    // Absent strings come back empty rather than null.
    final sparse = <String, dynamic>{'pu': 'http://panel.example:8080'};
    final fromSparse = ChannelHit.fromJson(sparse);
    expect(fromSparse.portal.portal.url, 'http://panel.example:8080');
    expect(fromSparse.stream.name, isEmpty);
    expect(fromSparse.streamUrl, isEmpty);
  });
}