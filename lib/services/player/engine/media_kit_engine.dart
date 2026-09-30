import 'dart:async';

import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import '../player_settings.dart';
import 'video_engine.dart';

/// [VideoEngine] backed by the bundled mpv, through `media_kit`.
///
/// This is the existing behaviour, wrapped rather than rewritten. It stays the
/// fallback for torrents and for anything the hardware decoder refuses, because
/// mpv plays containers and stream shapes Media3 will not.
///
/// mpv-specific configuration is applied here and nowhere else. Callers use
/// [VideoEngine] and cannot see the property names, which is the point: the
/// reason this engine is slow at 4K is that the bundled libmpv only ships
/// `mediacodec-copy` hardware decoding, and that is an implementation detail of
/// *this* class, not something a player screen should have to reason about.
class MediaKitEngine implements VideoEngine {
  MediaKitEngine()
      : player = mk.Player(
          configuration: PlayerSettings.getMediaKitPlayerConfiguration(),
        ) {
    _wireStreams();
  }

  final mk.Player player;

  late final mkv.VideoController videoController = mkv.VideoController(
    player,
    configuration: PlayerSettings.getVideoControllerConfiguration(),
  );

  final StreamController<EngineState> _events =
      StreamController<EngineState>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  EngineState _state = const EngineState();
  bool _disposed = false;

  @override
  String get debugName => 'mpv';

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
        // mpv is the one engine here that opens the local torrent engine's
        // streams, because it can follow the plain HTTP shape they arrive in
        // with no extra plumbing.
        supportsTorrents: true,
        // Every hardware mode in the bundled libmpv is `mediacodec-copy`, so
        // frames are copied out of the decoder before being composited into a
        // Flutter texture. This is why 4K needs Media3 instead.
        zeroCopyVideo: false,
      );

  @override
  EngineState get state => _state;

  @override
  Stream<EngineState> get events => _events.stream;

  void _emit(EngineState next) {
    if (_disposed) return;
    _state = next;
    if (!_events.isClosed) _events.add(next);
  }

  void _wireStreams() {
    _subscriptions.add(
      player.stream.playing.listen((bool playing) {
        _emit(_state.copyWith(playing: playing));
      }),
    );
    _subscriptions.add(
      player.stream.completed.listen((bool completed) {
        _emit(_state.copyWith(
          completed: completed,
          ready: completed ? EngineReadyState.ended : _state.ready,
        ));
      }),
    );
    _subscriptions.add(
      player.stream.position.listen((Duration position) {
        _emit(_state.copyWith(position: position));
      }),
    );
    _subscriptions.add(
      player.stream.duration.listen((Duration duration) {
        _emit(_state.copyWith(duration: duration));
      }),
    );
    _subscriptions.add(
      player.stream.buffering.listen((bool buffering) {
        _emit(_state.copyWith(
          buffering: buffering,
          ready: buffering ? EngineReadyState.buffering : _state.ready,
        ));
      }),
    );
    _subscriptions.add(
      player.stream.buffer.listen((Duration buffer) {
        _emit(_state.copyWith(buffer: buffer));
      }),
    );
    _subscriptions.add(
      player.stream.rate.listen((double rate) {
        _emit(_state.copyWith(rate: rate));
      }),
    );
    // Width and height are the *decoded* frame size, so they only become
    // non-null once a frame has actually arrived. The no-video watchdog leans on
    // that distinction: a container-reported height (see _containerHeight) can
    // exist with no frame ever rendering.
    _subscriptions.add(
      player.stream.width.listen((int? width) {
        _emit(_state.copyWith(decodedWidth: (width == null || width == 0) ? null : width));
      }),
    );
    _subscriptions.add(
      player.stream.height.listen((int? height) {
        _emit(_state.copyWith(decodedHeight: (height == null || height == 0) ? null : height));
      }),
    );
    _subscriptions.add(
      player.stream.tracks.listen((mk.Tracks tracks) {
        _emit(_state.copyWith(
          audioTracks: tracks.audio.map(_audioTrack).toList(growable: false),
          videoTracks: tracks.video.map(_videoTrack).toList(growable: false),
          subtitleTracks: tracks.subtitle.map(_subtitleTrack).toList(growable: false),
        ));
      }),
    );
    _subscriptions.add(
      // `mk.Track` is the bundle of currently-selected tracks, not a base class
      // for the individual track types, so this reports the selection rather
      // than switching on a type.
      player.stream.track.listen((mk.Track selected) {
        _emit(_state.copyWith(
          activeAudioTrack: _audioTrack(selected.audio),
          activeSubtitleTrack: _subtitleTrack(selected.subtitle),
        ));
      }),
    );
    _subscriptions.add(
      player.stream.error.listen((Object? error) {
        if (error == null) return;
        _emit(_state.copyWith(ready: EngineReadyState.error));
      }),
    );
  }

  EngineTrack _audioTrack(mk.AudioTrack track) => EngineTrack(
        id: _idOf(track.id),
        title: track.title ?? track.language ?? 'Audio ${track.id}',
        language: track.language,
        codec: track.codec,
      );

  EngineTrack _videoTrack(mk.VideoTrack track) => EngineTrack(
        id: _idOf(track.id),
        title: track.title ?? 'Video ${track.id}',
        language: track.language,
        codec: track.codec,
        width: (track.w == null || track.w == 0) ? null : track.w,
        height: (track.h == null || track.h == 0) ? null : track.h,
      );

  EngineTrack _subtitleTrack(mk.SubtitleTrack track) => EngineTrack(
        id: _idOf(track.id),
        title: track.title ?? track.language ?? 'Subtitle ${track.id}',
        language: track.language,
        codec: track.codec,
        isExternal: track.uri,
      );

  /// media_kit track ids are strings like `1` or `no`/`auto`; the contract
  /// carries ints because that is what every caller already had.
  static int _idOf(String id) => int.tryParse(id) ?? 0;

  @override
  Future<void> open(EngineRequest request) async {
    if (_disposed) return;
    _emit(const EngineState());
    await PlayerSettings.applyPreOpenProperties(player);
    await player.open(
      mk.Media(
        request.url,
        httpHeaders: request.headers,
        start: request.start,
      ),
      play: true,
    );
    await PlayerSettings.applyPostOpenProperties(player);
  }

  @override
  Future<void> play() async => player.play();

  @override
  Future<void> pause() async => player.pause();

  @override
  Future<void> playOrPause() => player.playOrPause();

  @override
  Future<void> stop() async => player.stop();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> setRate(double rate) => player.setRate(rate);

  @override
  Future<void> setVolume(double volume) => player.setVolume(volume);

  @override
  Future<void> setAudioTrack(EngineTrack? track) async {
    final mk.Tracks tracks = player.state.tracks;
    if (track == null) {
      await player.setAudioTrack(mk.AudioTrack.no());
      return;
    }
    final mk.AudioTrack? match = tracks.audio
        .where((mk.AudioTrack t) => _idOf(t.id) == track.id)
        .firstOrNull;
    if (match != null) await player.setAudioTrack(match);
  }

  @override
  Future<void> setSubtitleTrack(EngineTrack? track) async {
    final mk.Tracks tracks = player.state.tracks;
    if (track == null) {
      await player.setSubtitleTrack(mk.SubtitleTrack.no());
      return;
    }
    final mk.SubtitleTrack? match = tracks.subtitle
        .where((mk.SubtitleTrack t) => _idOf(t.id) == track.id)
        .firstOrNull;
    if (match != null) await player.setSubtitleTrack(match);
  }

  @override
  Future<void> setSubtitlesVisible(bool visible) async {
    // mpv hides subtitles through a property rather than by deselecting the
    // track, so the user's chosen subtitle language survives being toggled off.
    final dynamic platform = player.platform;
    await platform.setProperty('sub-visibility', visible ? 'yes' : 'no');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final StreamSubscription<dynamic> sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _events.close();
    await player.dispose();
  }
}
