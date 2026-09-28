/// Pins the RAM budget handed to the embedded TorrServer engine.
///
/// Reported on a Chromecast with Google TV (2 GB): 4K torrent playback runs at
/// roughly 40% of real time while audio is perfect. Measured on that device,
/// the player's own pages were being evicted to eMMC (56 MB of the app in swap,
/// ~24 major faults/s) against a swap file that was 100% full, so the video
/// path — 12.4 MB per 4K frame — stalled on storage while audio, ~5 KB per
/// frame and resident, played on.
///
/// The engine is the second process and the one holding the largest single term
/// the app can reach. TorrServer keeps its pieces in RAM (`UseDisk` is false by
/// default), so `CacheSize` is its whole piece-memory budget, and its default is
/// 64 MiB. This file pins the budget the app now applies on a small device and
/// the two properties that make applying it safe:
///
/// 1. It is only applied on a device small enough to need it, because 32 MiB of
///    cache on a desktop is a regression.
/// 2. It is written as a *merge* into the engine's own settings JSON, because
///    the package's `TorrServerSettings.toJson()` omits the engine's tracker
///    fields and a plain `set` would clear them.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/player/player_settings.dart';
import 'package:zplay/services/stream/torrent_stream_service.dart';

/// Exactly what the television reported for `/proc/meminfo`.
const String _chromecastMeminfo = '''
MemTotal:        1982996 kB
MemFree:          547292 kB
MemAvailable:     904068 kB
Buffers:           10496 kB
Cached:           406944 kB
SwapCached:        17388 kB
Active:           535792 kB
Inactive:         210736 kB
SwapTotal:        495744 kB
SwapFree:          77180 kB
''';

/// A 40 Mbit/s 4K encode, in bytes per second: the mid-range case the budget's
/// own comment names.
const double _bytesPerSecondAt40Mbit = 40 * 1000 * 1000 / 8;

/// The engine's `action: get` payload, trimmed to the fields that matter here:
/// the setting being changed and the tracker fields the package's typed model
/// does not know about.
const Map<String, dynamic> _engineSettings = {
  'CacheSize': 67108864,
  'ReaderReadAHead': 95,
  'PreloadCache': 50,
  'UseDisk': false,
  'TorrentsSavePath': '',
  'TrackersListURL': '',
  'DefaultTrackers': 'udp://tracker.opentrackr.org:1337/announce',
  'MergeAllM3U': false,
};

void main() {
  group('engine cache budget', () {
    test('the engine is not left holding a desktop-sized cache', () {
      expect(TorrentStreamService.engineDefaultCacheBytes, 64 * 1024 * 1024);
      expect(TorrentStreamService.engineCacheBytes, 32 * 1024 * 1024);
      expect(
        TorrentStreamService.engineCacheBytes,
        lessThan(TorrentStreamService.engineDefaultCacheBytes),
      );
      // The saving on the device this exists for: half of the engine's
      // piece memory, ~32 MiB handed back to a 2 GB system without swap.
      expect(
        TorrentStreamService.engineDefaultCacheBytes -
            TorrentStreamService.engineCacheBytes,
        32 * 1024 * 1024,
      );
    });

    test('the floor still covers a reader window over a 4K stream', () {
      // The engine's retention window is capacity x ReaderReadAHead%, so the
      // budget must exceed what a 4K stream spends in the seconds a swarm gap
      // lasts, or the budget converts stutter into re-buffering instead of
      // removing it.
      const double fiveSecondsOfFourK = 5 * _bytesPerSecondAt40Mbit;
      const double engineWindowSeconds =
          TorrentStreamService.engineCacheBytes / _bytesPerSecondAt40Mbit;

      // At 40 Mbit/s the budget is worth over six seconds of video. The exact
      // figure is pinned so a later cut has to argue with it.
      expect(TorrentStreamService.engineCacheBytes, greaterThan(fiveSecondsOfFourK));
      expect(engineWindowSeconds, greaterThan(6.0));
      expect(engineWindowSeconds, lessThan(7.0));

      // And it is not alone: mpv's forward demuxer cache adds its own seconds on
      // top, which is what makes a stalled engine read survivable. The two
      // together must clear 15 s of a 40 Mbit/s stream.
      const double demuxerSeconds =
          PlayerSettings.demuxerForwardCacheBytes / _bytesPerSecondAt40Mbit;
      expect(engineWindowSeconds + demuxerSeconds, greaterThan(15.0));
    });

    test('halving the budget again would fall below the floor', () {
      // A 16 MiB cache leaves a ~3 s window, where the engine starts evicting
      // pieces the reader is about to ask for and the cushion stops being
      // additive with mpv's. This is the line the budget must not cross.
      const int halved = TorrentStreamService.engineCacheBytes ~/ 2;
      expect(halved / _bytesPerSecondAt40Mbit, lessThan(4.0));
    });
  });

  group('device gate', () {
    test('the 2 GB television is recognised as low memory', () {
      final total = TorrentStreamService.parseMemTotalBytes(_chromecastMeminfo);
      expect(total, 1982996 * 1024);
      expect(TorrentStreamService.isLowMemoryTotal(total), isTrue);
    });

    test('a 4 GB box and an unknown size keep the engine default', () {
      expect(TorrentStreamService.isLowMemoryTotal(4 * 1024 * 1024 * 1024), isFalse);
      // Windows and iOS have no /proc/meminfo; an unknown device must not be
      // guessed at, or the cache would be cut on hardware with memory to spare.
      expect(TorrentStreamService.isLowMemoryTotal(null), isFalse);
    });

    test('MemTotal is read from its own line, not from a longer key', () {
      // `MemTotal:` is a prefix of no other field, but a naive `contains` would
      // also match a hypothetical `MemTotalSwap:`; the parse is line-anchored.
      const body = 'MemFree: 1 kB\nMemTotalFree: 999 kB\nMemTotal: 2048 kB\n';
      expect(TorrentStreamService.parseMemTotalBytes(body), 2048 * 1024);
      expect(TorrentStreamService.parseMemTotalBytes('MemFree: 1 kB\n'), isNull);
      expect(TorrentStreamService.parseMemTotalBytes(''), isNull);
    });
  });

  group('settings merge', () {
    test('only CacheSize changes and the engine keeps its trackers', () {
      final merged = TorrentStreamService.budgetedSettings(_engineSettings);

      expect(merged['CacheSize'], TorrentStreamService.engineCacheBytes);
      // A `set` replaces the engine's whole BTSets struct, so every field the
      // package's typed model cannot express has to survive the round trip or
      // the swarm loses the peers those trackers find.
      expect(merged['DefaultTrackers'], _engineSettings['DefaultTrackers']);
      expect(merged['TrackersListURL'], _engineSettings['TrackersListURL']);
      expect(merged['MergeAllM3U'], _engineSettings['MergeAllM3U']);
      expect(merged['ReaderReadAHead'], 95);
      expect(merged['UseDisk'], isFalse);
      // The original map is not mutated in place.
      expect(_engineSettings['CacheSize'], 67108864);
    });

    test('the merge does not invent settings the engine never reported', () {
      final merged = TorrentStreamService.budgetedSettings(const {'CacheSize': 1});
      expect(merged.keys, unorderedEquals(<String>['CacheSize']));
    });
  });
}
