/// Pins the player's memory budget and the no-video watchdog's policy.
///
/// Reported on a Chromecast with Google TV (2 GB): 4K playback gets the process
/// killed.
///
/// ```
/// lowmemorykiller: Kill 'io.github.tzero86.zplay' ... oom_score_adj 0 to free 836112kB rss
///   reason: min watermark is breached and swap is low
/// lowmemorykiller: ... device is low on swap (0kB < 49572kB) and thrashing (300%)
/// ```
///
/// Two things the app decided for itself are pinned here, because both are
/// invisible in a running player:
///
/// 1. The demuxer cache was allowed 150 MiB forward + 50 MiB back, and the two
///    settings that place it (`PlayerConfiguration.bufferSize` and the mpv
///    `demuxer-max-*` properties) had drifted apart. The budget now lives in one
///    place and this file checks that both halves write it.
/// 2. The frame watchdog answered every "no video" condition with `hwdec: no`,
///    including a stream that is not delivering data — where software decoding
///    cannot help and, at 4K, costs ~200-300 MB of reference frames on a device
///    that had 0 kB of swap left. The property that must *not* be written is the
///    thing worth a test, so the recovery is exercised against a recording
///    platform double.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/player/player_settings.dart';

/// Stands in for `player.platform`, which media_kit only provides on a device.
/// Records the writes in order of arrival.
class _RecordingPlatform {
  final Map<String, String> properties = <String, String>{};
  final List<String> writes = <String>[];

  Future<void> setProperty(String name, String value) async {
    properties[name] = value;
    writes.add('$name=$value');
  }
}

/// A 4K stream's bitrate, in bytes per second, used for the arithmetic below:
/// 40 Mbit/s is a mid-range 4K encode and 80 Mbit/s is the worst case named in
/// the budget's own comment.
const double _bytesPerSecondAt40Mbit = 40 * 1000 * 1000 / 8;
const double _bytesPerSecondAt8Mbit = 8 * 1000 * 1000 / 8;

void main() {
  group('demuxer cache budget', () {
    test('the demuxer is not handed a desktop-sized cache', () {
      // mpv's own default is 150 MiB per property, and this app used to write
      // 150 MiB forward + 50 MiB back on every network stream. `demuxer-donate-buffer`
      // defaults to `yes`, so the sum is the ceiling the demuxer will reach.
      const int previousBudget = 157286400 + 52428800;
      const int budget =
          PlayerSettings.demuxerForwardCacheBytes + PlayerSettings.demuxerBackCacheBytes;

      expect(PlayerSettings.demuxerForwardCacheBytes, 64 * 1024 * 1024);
      expect(PlayerSettings.demuxerBackCacheBytes, 16 * 1024 * 1024);
      expect(budget, lessThan(previousBudget));
      // The saving this buys on a 2 GB device: 120 MiB of playback memory.
      expect(previousBudget - budget, 120 * 1024 * 1024);
    });

    test('the PlayerConfiguration half agrees with the mpv property half', () async {
      final configuration = PlayerSettings.getMediaKitPlayerConfiguration();

      final torrent = _RecordingPlatform();
      await PlayerSettings.applyPreOpenPropertiesToPlatform(torrent, isTorrent: true);
      final vod = _RecordingPlatform();
      await PlayerSettings.applyPreOpenPropertiesToPlatform(vod);

      for (final platform in <_RecordingPlatform>[torrent, vod]) {
        // media_kit fills BOTH properties from bufferSize at player creation, so
        // bufferSize is the forward cache by definition; the back buffer is
        // narrowed to its own constant at open.
        expect(
          platform.properties['demuxer-max-bytes'],
          '${PlayerSettings.demuxerForwardCacheBytes}',
        );
        expect(
          platform.properties['demuxer-max-back-bytes'],
          '${PlayerSettings.demuxerBackCacheBytes}',
        );
        expect(platform.properties['demuxer-max-bytes'], configuration.bufferSize.toString());
      }
    });

    test('readahead seconds fit inside the bytes they are cached in', () {
      // `demuxer-readahead-secs` is ignored while the cache is on: `cache-secs`
      // overrides it and mpv uses the larger of the two, so the second is the one
      // that acts and the pair is written to the same value.
      final torrent = _RecordingPlatform();
      return PlayerSettings.applyPreOpenPropertiesToPlatform(torrent, isTorrent: true).then((_) {
        expect(torrent.properties['cache-secs'], '${PlayerSettings.streamReadaheadSecs}');
        expect(
          torrent.properties['demuxer-readahead-secs'],
          '${PlayerSettings.streamReadaheadSecs}',
        );

        // On a 4K stream the seconds target and the byte cap are reached
        // together, which is what stops the two settings fighting. At the old
        // 30 s the target asked for ~150 MB that a 150 MB cap could not hold.
        const double fourKTarget =
            PlayerSettings.streamReadaheadSecs * _bytesPerSecondAt40Mbit;
        expect(fourKTarget, lessThanOrEqualTo(PlayerSettings.demuxerForwardCacheBytes.toDouble()));

        // And a low-bitrate stream never touches the cap, so the cap cannot
        // starve what it is protecting.
        const double hdTarget =
            PlayerSettings.streamReadaheadSecs * _bytesPerSecondAt8Mbit;
        expect(hdTarget, lessThan(PlayerSettings.demuxerForwardCacheBytes / 4));
      });
    });

    test('live keeps its own readahead, which is not a memory question', () async {
      final live = _RecordingPlatform();
      await PlayerSettings.applyPreOpenPropertiesToPlatform(live, isLive: true);

      expect(live.properties['cache-secs'], '${PlayerSettings.liveReadaheadSecs}');
      expect(live.properties['demuxer-readahead-secs'], '${PlayerSettings.liveReadaheadSecs}');
      expect(live.properties['demuxer-max-bytes'], '${PlayerSettings.demuxerForwardCacheBytes}');
    });
  });

  group('no-video watchdog policy', () {
    const int uhd = 2160;
    const int hd = 1080;
    const int unknown = 0;
    const int androidCeiling = PlayerWatchdogPolicy.softwareDecodeMaxHeight;

    Future<({PlayerWatchdogAction action, _RecordingPlatform platform, List<Duration> seeks})>
        recover(
      WatchdogSignal signal, {
      required int sourceHeight,
      int? ceiling = androidCeiling,
    }) async {
      final platform = _RecordingPlatform();
      final seeks = <Duration>[];
      final action = await PlayerSettings.applyNoVideoRecovery(
        platform,
        signal: signal,
        sourceHeight: sourceHeight,
        maxSoftwareDecodeHeight: ceiling,
        position: const Duration(minutes: 3),
        seek: (position) async => seeks.add(position),
      );
      return (action: action, platform: platform, seeks: seeks);
    }

    test('a stream that is not delivering data is never handed to a software decoder', () async {
      // Its own reason string is "not delivering data": the bytes are missing, so
      // no decoder can help, and the on-device sequence was `hwdec: no` followed
      // by `thrashing (300%)`.
      for (final int height in <int>[uhd, 1440, hd, 720, unknown]) {
        final result = await recover(
          WatchdogSignal.streamNotDeliveringData,
          sourceHeight: height,
        );
        expect(result.action, PlayerWatchdogAction.waitForData, reason: 'at ${height}px');
        expect(result.platform.properties, isEmpty, reason: 'at ${height}px');
        expect(result.platform.writes, isEmpty, reason: 'at ${height}px');
        expect(result.seeks, isEmpty, reason: 'at ${height}px');
      }
    });

    test('the audio-ghosting decoder fault still switches to software decoding', () async {
      final result = await recover(WatchdogSignal.audioWithoutVideo, sourceHeight: hd);

      expect(result.action, PlayerWatchdogAction.softwareDecode);
      expect(result.platform.properties['hwdec'], 'no');
      expect(result.platform.properties['vid'], 'auto');
      expect(result.platform.properties['glsl-shaders'], '');
      // The decoder change is followed by a refresh at the position it is at.
      expect(result.seeks, <Duration>[const Duration(minutes: 3)]);
    });

    test('a reported hardware decoder error is treated the same way', () async {
      final result = await recover(WatchdogSignal.hardwareDecoderError, sourceHeight: hd);

      expect(result.action, PlayerWatchdogAction.softwareDecode);
      expect(result.platform.properties['hwdec'], 'no');
    });

    test('UHD is re-synced on the hardware decoder, never in software', () async {
      // YUV420 4K is 3840x2160x1.5 = 12.4 MB per frame and an HEVC reference pool
      // holds 16-24 of them: the software decoder alone asks for 200-300 MB.
      for (final int height in <int>[uhd, 1600, 1440]) {
        final result = await recover(WatchdogSignal.audioWithoutVideo, sourceHeight: height);

        expect(result.action, PlayerWatchdogAction.resyncHardwareDecoder, reason: 'at ${height}px');
        expect(
          result.platform.properties.containsKey('hwdec'),
          isFalse,
          reason: 'hwdec must not be written at ${height}px: ${result.platform.writes}',
        );
        expect(result.platform.properties['vid'], 'auto', reason: 'at ${height}px');
      }
    });

    test('an unknown frame size is refused where a ceiling exists', () async {
      // The frame size is what is missing in the condition being judged, which is
      // exactly the case the ceiling exists for: refusing costs a source change,
      // guessing wrong costs the process.
      final result = await recover(WatchdogSignal.audioWithoutVideo, sourceHeight: unknown);

      expect(result.action, PlayerWatchdogAction.resyncHardwareDecoder);
      expect(result.platform.properties.containsKey('hwdec'), isFalse);
    });

    test('a device with no ceiling keeps the unconditional fallback', () async {
      // Desktop: software 4K is slow rather than fatal, and hardware decoding is
      // already the user's own setting.
      final result = await recover(
        WatchdogSignal.audioWithoutVideo,
        sourceHeight: uhd,
        ceiling: null,
      );

      expect(result.action, PlayerWatchdogAction.softwareDecode);
      expect(result.platform.properties['hwdec'], 'no');
    });

    test('the rule itself: signal decides first, then resolution', () {
      const int ceiling = PlayerWatchdogPolicy.softwareDecodeMaxHeight;

      expect(
        PlayerWatchdogPolicy.decide(
          signal: WatchdogSignal.streamNotDeliveringData,
          sourceHeight: hd,
          maxSoftwareDecodeHeight: ceiling,
        ),
        PlayerWatchdogAction.waitForData,
      );
      for (final WatchdogSignal fault in <WatchdogSignal>[
        WatchdogSignal.audioWithoutVideo,
        WatchdogSignal.hardwareDecoderError,
      ]) {
        expect(
          PlayerWatchdogPolicy.decide(
            signal: fault,
            sourceHeight: hd,
            maxSoftwareDecodeHeight: ceiling,
          ),
          PlayerWatchdogAction.softwareDecode,
        );
        expect(
          PlayerWatchdogPolicy.decide(
            signal: fault,
            sourceHeight: uhd,
            maxSoftwareDecodeHeight: ceiling,
          ),
          PlayerWatchdogAction.resyncHardwareDecoder,
        );
      }
    });

    test('a missing platform applies nothing and reports nothing applied', () async {
      final action = await PlayerSettings.applyNoVideoRecovery(
        null,
        signal: WatchdogSignal.audioWithoutVideo,
        sourceHeight: hd,
        maxSoftwareDecodeHeight: androidCeiling,
        position: Duration.zero,
        seek: (_) async {},
      );

      expect(action, PlayerWatchdogAction.waitForData);
    });
  });
}