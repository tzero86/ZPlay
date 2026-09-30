/// The one seam every video surface in the app goes through.
///
/// ZPlay used to talk to `media_kit`'s `Player` directly from five places, with
/// no interface at all. That worked until the 4K problem, which is a property of
/// the engine rather than of the device: the libmpv we bundle only ships
/// `mediacodec-copy` hardware decoding, so every 4K frame is copied out of the
/// hardware decoder into system memory and then composited into a Flutter
/// texture. Measured on a 2 GB Chromecast with Google TV, that is 1,389-1,917 ms
/// of decoder latency and roughly 1.5 dropped frames a second. The same file
/// through Android's own ExoPlayer/Media3, rendering into a SurfaceView, came up
/// in 904 ms with zero dropped frames.
///
/// Two engines therefore sit behind this contract:
///
///  * `MediaKitEngine` - the existing mpv path. Kept because it plays things
///    Media3 does not: torrent streams over the local engine, odd containers,
///    and anything the hardware decoder refuses.
///  * `ExoPlayerEngine` - Media3 on a SurfaceView. The fast path for mainstream
///    formats, and the only one that can do 4K properly on a small TV.
///
/// Deliberately *not* modelled here: mpv property names, `hwdec`, libass, and
/// anything else engine-specific. The contract is what a player screen actually
/// needs, so a setting that only one engine can honour is a capability of that
/// engine, not a field on the interface. Callers that need one ask
/// [VideoEngine.capabilities] whether it is there.
library;

import 'dart:async';

/// One audio or subtitle track, as the player surfaces report them.
class EngineTrack {
  const EngineTrack({
    required this.id,
    required this.title,
    this.language,
    this.codec,
    this.isExternal = false,
    this.width,
    this.height,
  });

  final int id;
  final String title;
  final String? language;
  final String? codec;

  /// A sidecar subtitle file rather than one inside the container.
  final bool isExternal;

  /// Container-reported dimensions. Available before any frame is decoded, which
  /// is why the no-video watchdog reads these rather than waiting on a frame.
  final int? width;
  final int? height;
}

/// What an engine is able to do on this device.
///
/// The player screen asks before offering a choice, so an mpv-only feature is
/// never presented while ExoPlayer is driving and then quietly ignored.
class EngineCapabilities {
  const EngineCapabilities({
    this.hardwareDecoding = true,
    this.subtitleStyling = true,
    this.playbackSpeed = true,
    this.audioTrackSelection = true,
    this.supportsTorrents = false,
    this.zeroCopyVideo = false,
  });

  final bool hardwareDecoding;

  /// Font, size, colour, border and margin control over rendered subtitles.
  final bool subtitleStyling;
  final bool playbackSpeed;
  final bool audioTrackSelection;

  /// Whether this engine can open a stream served by the local torrent engine.
  final bool supportsTorrents;

  /// True when decoded frames reach the display without a per-frame copy.
  final bool zeroCopyVideo;

  static const EngineCapabilities full = EngineCapabilities();
}

/// How far along a load is.
enum EngineReadyState { idle, buffering, ready, ended, error }

/// Everything a caller needs to know without holding an engine type.
class EngineState {
  const EngineState({
    this.ready = EngineReadyState.idle,
    this.playing = false,
    this.completed = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffering = false,
    this.buffer = Duration.zero,
    this.rate = 1.0,
    this.decodedWidth,
    this.decodedHeight,
    this.audioTracks = const <EngineTrack>[],
    this.videoTracks = const <EngineTrack>[],
    this.subtitleTracks = const <EngineTrack>[],
    this.activeAudioTrack,
    this.activeSubtitleTrack,
  });

  final EngineReadyState ready;
  final bool playing;
  final bool completed;
  final Duration position;
  final Duration duration;
  final bool buffering;
  final Duration buffer;
  final double rate;

  /// The *decoded* frame size, or null before a frame has arrived.
  final int? decodedWidth;
  final int? decodedHeight;

  final List<EngineTrack> audioTracks;
  final List<EngineTrack> videoTracks;
  final List<EngineTrack> subtitleTracks;
  final EngineTrack? activeAudioTrack;
  final EngineTrack? activeSubtitleTrack;

  EngineState copyWith({
    EngineReadyState? ready,
    bool? playing,
    bool? completed,
    Duration? position,
    Duration? duration,
    bool? buffering,
    Duration? buffer,
    double? rate,
    int? decodedWidth,
    int? decodedHeight,
    List<EngineTrack>? audioTracks,
    List<EngineTrack>? videoTracks,
    List<EngineTrack>? subtitleTracks,
    EngineTrack? activeAudioTrack,
    EngineTrack? activeSubtitleTrack,
  }) {
    return EngineState(
      ready: ready ?? this.ready,
      playing: playing ?? this.playing,
      completed: completed ?? this.completed,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffering: buffering ?? this.buffering,
      buffer: buffer ?? this.buffer,
      rate: rate ?? this.rate,
      decodedWidth: decodedWidth ?? this.decodedWidth,
      decodedHeight: decodedHeight ?? this.decodedHeight,
      audioTracks: audioTracks ?? this.audioTracks,
      videoTracks: videoTracks ?? this.videoTracks,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      activeAudioTrack: activeAudioTrack ?? this.activeAudioTrack,
      activeSubtitleTrack: activeSubtitleTrack ?? this.activeSubtitleTrack,
    );
  }
}

/// A request to play something. The engine decides how to satisfy it, or refuses.
class EngineRequest {
  const EngineRequest({
    required this.url,
    this.headers = const <String, String>{},
    this.start = Duration.zero,
    this.isLive = false,
    this.isTorrent = false,
    this.userAgent,
    this.referrer,
  });

  final String url;
  final Map<String, String> headers;
  final Duration start;
  final bool isLive;

  /// The URL is served by the local torrent engine rather than the network.
  final bool isTorrent;

  final String? userAgent;
  final String? referrer;

  /// Whether this request is something an engine should refuse outright.
  ///
  /// Torrents are the case that matters: only mpv can play them today, and
  /// handing one to Media3 would fail slowly and unhelpfully.
  bool get needsMpv => isTorrent;
}

/// Thrown when an engine cannot play a request. The player screen catches this
/// and falls back to another engine, so it must not be fatal to playback.
class EngineUnsupported implements Exception {
  const EngineUnsupported(this.reason);

  final String reason;

  @override
  String toString() => 'EngineUnsupported: $reason';
}

/// A video engine.
///
/// Implementations are expected to be safe to call before [open] and after
/// [dispose] - the player screen's watchdog fires at times that do not care
/// whether a load is in flight.
abstract class VideoEngine {
  /// A short label for diagnostics, never shown to the user.
  String get debugName;

  EngineCapabilities get capabilities;

  /// The latest state, updated by [state] as well as pushed through [events].
  EngineState get state;

  /// State changes. A broadcast stream so a screen can take what it needs.
  Stream<EngineState> get events;

  /// Load [request] and start playing it.
  ///
  /// Throws [EngineUnsupported] when this engine cannot play it, so a caller can
  /// try another rather than showing an error.
  Future<void> open(EngineRequest request);

  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);

  Future<void> setAudioTrack(EngineTrack? track);
  Future<void> setSubtitleTrack(EngineTrack? track);

  /// Show or hide subtitles without changing which track is selected.
  Future<void> setSubtitlesVisible(bool visible);

  Future<void> dispose();
}
