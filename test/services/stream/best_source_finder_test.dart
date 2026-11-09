/// The ranked-candidate search a stalled player runs on the viewer's behalf.
///
/// Every probe here is a fake: the finder's contract is the *order* it spends
/// its budget in, not what an HTTP probe answers, and a test that opened sockets
/// could not exercise dead, slow and hanging candidates on demand.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/models/stream/stream_model.dart';
import 'package:zplay/services/stream/best_source_finder.dart';

StreamSource _source(
  String name, {
  String? title,
  String? url,
  String? externalUrl,
  String? infoHash,
  String addon = 'TestAddon',
}) => StreamSource(
  name: name,
  title: title,
  url: url,
  externalUrl: externalUrl,
  infoHash: infoHash,
  addonName: addon,
);

/// A probe that records who it was asked about.
Future<bool> Function(StreamSource) _probe(
  List<String> seen,
  bool Function(StreamSource) alive,
) => (StreamSource source) async {
  seen.add(source.name ?? '');
  return alive(source);
};

void main() {
  group('find', () {
    test(
      'keeps rank order: every candidate alive means the first wins',
      () async {
        final seen = <String>[];
        final found = await BestSourceFinder.find([
          _source('one'),
          _source('two'),
          _source('three'),
        ], probe: _probe(seen, (_) => true));

        expect(found?.name, 'one');
        expect(seen, ['one', 'two', 'three']);
      },
    );

    test(
      'returns the earliest ranked live source of the earliest batch',
      () async {
        final seen = <String>[];
        final found = await BestSourceFinder.find(
          [_source('one'), _source('two'), _source('three'), _source('four')],
          // Two and three both answer; two is ranked higher.
          probe: _probe(seen, (s) => s.name == 'three' || s.name == 'two'),
        );

        expect(found?.name, 'two');
      },
    );

    test('skips dead candidates', () async {
      final seen = <String>[];
      final found = await BestSourceFinder.find([
        _source('one'),
        _source('two'),
        _source('three'),
      ], probe: _probe(seen, (s) => s.name == 'three'));

      expect(found?.name, 'three');
      expect(seen, containsAll(<String>['one', 'two', 'three']));
    });

    test('all dead is null', () async {
      final found = await BestSourceFinder.find([
        _source('one'),
        _source('two'),
      ], probe: _probe(<String>[], (_) => false));

      expect(found, isNull);
    });

    test('a throwing probe counts as dead', () async {
      final found = await BestSourceFinder.find(
        [_source('one'), _source('two')],
        probe: (StreamSource source) async {
          if (source.name == 'one') throw StateError('probe exploded');
          return true;
        },
      );

      expect(found?.name, 'two');
    });

    test('a probe that never answers is cut off by the budget', () async {
      final found = await BestSourceFinder.find(
        [_source('hang')],
        probe: (_) => Completer<bool>().future,
        budget: const Duration(milliseconds: 60),
      );

      expect(found, isNull);
    });

    test(
      'a torrent is the fallback only when no HTTP source answers',
      () async {
        final torrent = _source('torrent', infoHash: 'abc123');
        final dead = _source('dead', url: 'http://example.test/1.m3u8');
        final seen = <String>[];

        final fallback = await BestSourceFinder.find([
          torrent,
          dead,
        ], probe: _probe(seen, (_) => false));

        expect(fallback?.name, 'torrent');
        expect(seen, ['dead'], reason: 'a torrent has no endpoint to probe');

        final victor = await BestSourceFinder.find([
          torrent,
          _source('alive', url: 'http://example.test/2.m3u8'),
        ], probe: _probe(<String>[], (_) => true));
        expect(victor?.name, 'alive');
      },
    );

    test('a torrent-only list returns the first torrent, unprobed', () async {
      final seen = <String>[];
      final found = await BestSourceFinder.find([
        _source('a', infoHash: 'hash-a'),
        _source('b', infoHash: 'hash-b'),
      ], probe: _probe(seen, (_) => true));

      expect(found?.name, 'a');
      expect(seen, isEmpty);
    });

    test('cancellation returns null and stops further batches', () async {
      final sources = List<StreamSource>.generate(8, (int i) => _source('s$i'));
      final seen = <String>[];
      bool cancelled = false;

      final found = await BestSourceFinder.find(
        sources,
        probe: (StreamSource source) async {
          seen.add(source.name ?? '');
          if (seen.length >= BestSourceFinder.concurrency) cancelled = true;
          return false;
        },
        isCancelled: () => cancelled,
      );

      expect(found, isNull);
      expect(
        seen.length,
        BestSourceFinder.concurrency,
        reason: 'the second batch is never started',
      );
    });

    test(
      'cancellation before the batch starts returns null immediately',
      () async {
        final seen = <String>[];
        final found = await BestSourceFinder.find(
          [_source('one'), _source('two')],
          probe: _probe(seen, (_) => true),
          isCancelled: () => true,
        );

        expect(found, isNull);
        expect(seen, isEmpty);
      },
    );

    test(
      'progress counts completed probes against the HTTP candidates',
      () async {
        final progress = <String>[];
        await BestSourceFinder.find(
          List<StreamSource>.generate(6, (int i) => _source('s$i')),
          probe: (_) async => false,
          onProgress: (int checked, int total) =>
              progress.add('$checked/$total'),
        );

        expect(progress, ['4/6', '6/6']);
      },
    );

    test('a spent budget returns null without probing', () async {
      final seen = <String>[];
      final found = await BestSourceFinder.find(
        [_source('one')],
        probe: _probe(seen, (_) => true),
        budget: Duration.zero,
      );

      expect(found, isNull);
      expect(seen, isEmpty);
    });
  });

  group('prepare', () {
    test('dedupes by infoHash, then url, then name|title, keeping order', () {
      final prepared = BestSourceFinder.prepare([
        _source('by-hash', infoHash: 'same-hash'),
        _source('by-hash-again', infoHash: 'same-hash'),
        _source('by-url', url: 'http://example.test/a.m3u8'),
        _source('by-url-again', url: 'http://example.test/a.m3u8'),
        _source('by-external', externalUrl: 'http://example.test/b.mp4'),
        _source('by-external-again', externalUrl: 'http://example.test/b.mp4'),
        _source('By Name', title: 'Same Title'),
        _source('By Name', title: 'Same Title'),
      ]);

      expect(prepared.map((StreamSource s) => s.name), [
        'by-hash',
        'by-url',
        'by-external',
        'By Name',
      ]);
    });

    test('excludes the playing source by url and by infoHash', () {
      final current = _source(
        'playing',
        url: 'http://example.test/1.m3u8',
        infoHash: 'playing-hash',
      );

      final prepared = BestSourceFinder.prepare([
        // Same object.
        current,
        // Only the url, as a re-scrape of the same provider would report it.
        _source('url-twin', url: 'http://example.test/1.m3u8'),
        // Only the hash, as a torrent listing would report it.
        _source('hash-twin', infoHash: 'playing-hash'),
        _source('other', url: 'http://example.test/2.m3u8'),
      ], exclude: current);

      expect(prepared.map((StreamSource s) => s.name), ['other']);
    });

    test('an empty list prepares to empty', () {
      expect(BestSourceFinder.prepare(const <StreamSource>[]), isEmpty);
    });
  });
}
