import 'exo_player_engine.dart';
import 'media_kit_engine.dart';
import 'video_engine.dart';

/// Which engine should play a given source.
///
/// The rule is short on purpose. Media3 is the fast path and takes anything
/// mainstream, because it is the only engine here that renders 4K without a
/// per-frame copy. mpv stays for the two things Media3 will not do: streams from
/// the local torrent engine, and anything the user has explicitly asked to keep
/// on mpv.
///
/// A wrong guess is never fatal. The player screen catches [EngineUnsupported]
/// and opens the source on the other engine, so this is a preference rather
/// than a gate.
class EngineChoice {
  const EngineChoice._(this.useExoPlayer, this.reason);

  /// True when Media3 should play this source.
  final bool useExoPlayer;

  /// Why, for diagnostics. Never shown to the user.
  final String reason;

  static EngineChoice exo(String reason) => EngineChoice._(true, reason);
  static EngineChoice mpv(String reason) => EngineChoice._(false, reason);

  @override
  String toString() => 'EngineChoice(${useExoPlayer ? 'media3' : 'mpv'}: $reason)';
}

/// Decides the engine for a source.
///
/// Kept as plain functions over a request rather than a service, because it is a
/// pure policy and the only thing it needs to know is what kind of URL it is
/// looking at.
class EngineSelector {
  const EngineSelector({this.forceMpv = false});

  /// When set, every source goes to mpv. This is the escape hatch for a stream
  /// Media3 mis-handles, and the only reason [EngineChoice.useExoPlayer] can be
  /// overridden without touching the call site.
  final bool forceMpv;

  EngineChoice choose(EngineRequest request) {
    if (forceMpv) {
      return EngineChoice.mpv('user pinned the mpv engine');
    }
    if (!ExoPlayerEngine.isSupported) {
      return EngineChoice.mpv('Media3 is not available on this platform');
    }
    if (request.needsMpv) {
      return EngineChoice.mpv('torrent stream, which only mpv plays today');
    }
    if (request.isLive) {
      // Live stays on mpv for now. Media3's HLS/DASH support is good, but live
      // is where a wrong first guess shows up as a channel that will not tune,
      // and IPTV is the one surface we cannot easily fall back from because it
      // owns its own player. Revisit once the fallback path covers it.
      return EngineChoice.mpv('live stream, which still routes through the IPTV engine');
    }
    return EngineChoice.exo('mainstream container over http');
  }

  /// Builds the engine for [request]. Callers that need to try both engines
  /// should use [choose] and then construct the one it named.
  VideoEngine create(EngineRequest request) {
    final EngineChoice choice = choose(request);
    return choice.useExoPlayer ? ExoPlayerEngine() : MediaKitEngine();
  }
}
