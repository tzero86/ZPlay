import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'video_engine.dart';

/// [VideoEngine] backed by Android's ExoPlayer/Media3, rendering into a
/// SurfaceView platform view.
///
/// This is the engine that makes 4K work on a small TV. mpv composites through a
/// Flutter texture and its bundled hardware decoders are copy-in only, so a 4K
/// frame costs a 12 MB copy per frame on top of the composite. Media3 hands
/// MediaCodec a Surface it owns, and the decoder writes to the display directly.
///
/// Measured on a 2 GB Chromecast with Google TV, same file, same device:
///
/// | | mpv | Media3 |
/// |---|---|---|
/// | first frame | 1,389-1,917 ms | 904 ms |
/// | dropped frames | ~1.5/sec | 0 |
/// | CPU | 51% | 19% |
/// | RSS | ~620 MB | 249 MB |
///
/// Android-only by construction: there is no Media3 on desktop, so [isSupported]
/// is what a caller checks and everything else can assume the platform view
/// exists.
class ExoPlayerEngine implements VideoEngine {
  ExoPlayerEngine();

  /// The platform view id registered by the native `ExoPlayerBridge`. Must
  /// match `ExoPlayerBridge.VIEW_ID`.
  static const String viewType = 'io.github.tzero86.zplay/exo_surface';
  static const MethodChannel _methods =
      MethodChannel('io.github.tzero86.zplay/exo_player');
  static const EventChannel _events =
      EventChannel('io.github.tzero86.zplay/exo_player/events');

  /// True when Media3 can be used at all. False on desktop and on any platform
  /// where the bridge is not registered.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.fuchsia);

  final StreamController<EngineState> _stateStream =
      StreamController<EngineState>.broadcast();
  final ValueNotifier<bool> surfaceMounted = ValueNotifier<bool>(false);

  EngineState _state = const EngineState();
  StreamSubscription<dynamic>? _eventSub;
  bool _disposed = false;

  @override
  String get debugName => 'media3';

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
        // Media3 renders subtitles with its own renderer, so libass styling has
        // no equivalent here. A caller that needs styled subtitles must ask
        // before offering the option, which is why this is a capability rather
        // than a silently ignored setting.
        subtitleStyling: false,
        supportsTorrents: false,
        zeroCopyVideo: true,
      );

  @override
  EngineState get state => _state;

  @override
  Stream<EngineState> get events => _stateStream.stream;

  /// The video surface. Mount this where the frames belong.
  ///
  /// Kept as a widget rather than an implicit side effect because the SurfaceView
  /// has to exist before a player can render, and the native side joins the two
  /// whenever both are present - a platform view can be created and destroyed
  /// independently of any load.
  Widget buildVideoSurface() => ExoPlayerSurface(
        onSurfaceAvailable: _onSurfaceAvailable,
      );

  void _onSurfaceAvailable() {
    surfaceMounted.value = true;
    // The player may already be playing; joining the surface to a live player is
    // a no-op if the native side has already done it, and is required if the
    // view was recreated after the load.
    unawaited(_invoke('attachSurface'));
  }

  void _emit(EngineState next) {
    if (_disposed) return;
    _state = next;
    if (!_stateStream.isClosed) _stateStream.add(next);
  }

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    if (!isSupported) {
      throw const EngineUnsupported('Media3 is only available on Android');
    }
    try {
      await _methods.invokeMethod<void>(method, args);
    } on MissingPluginException {
      throw const EngineUnsupported(
        'The ExoPlayer bridge is not registered on this build',
      );
    }
  }

  /// Listens for the first native event so state is live from the moment the
  /// engine is created, not only after a load.
  void start() {
    _eventSub ??= _events.receiveBroadcastStream().listen(
      (dynamic raw) {
        if (raw is! Map) return;
        _applyEvent(Map<Object?, Object?>.from(raw));
      },
      onError: (Object _) {
        // A stream error means the bridge went away mid-playback. The player
        // screen's watchdog owns what happens next; here it only stops the
        // stream so a rebuild can re-listen.
        unawaited(_eventSub?.cancel());
        _eventSub = null;
      },
    );
  }

  void _applyEvent(Map<Object?, Object?> event) {
    final Object? type = event['type'];
    switch (type) {
      case 'state':
        _emit(_state.copyWith(
          ready: _readyFrom(event['state'] as String?),
          buffering: event['state'] == 'buffering',
        ));
      case 'isPlaying':
        _emit(_state.copyWith(playing: event['value'] == true));
      case 'position':
        _emit(_state.copyWith(
          position: Duration(milliseconds: (event['value'] as num?)?.toInt() ?? 0),
        ));
      case 'duration':
        _emit(_state.copyWith(
          duration: Duration(milliseconds: (event['value'] as num?)?.toInt() ?? 0),
        ));
      case 'buffering':
        _emit(_state.copyWith(
          buffering: event['value'] == true,
          buffer: Duration(milliseconds: (event['ms'] as num?)?.toInt() ?? 0),
        ));
      case 'videoSize':
        final int? width = (event['width'] as num?)?.toInt();
        final int? height = (event['height'] as num?)?.toInt();
        _emit(_state.copyWith(
          decodedWidth: (width == null || width <= 0) ? null : width,
          decodedHeight: (height == null || height <= 0) ? null : height,
        ));
      case 'tracks':
        _emit(_state.copyWith(
          audioTracks: _tracks(event['audio'], 'Audio'),
          videoTracks: _tracks(event['video'], 'Video'),
          subtitleTracks: _tracks(event['subtitle'], 'Subtitle'),
        ));
      case 'error':
        _emit(_state.copyWith(ready: EngineReadyState.error));
      default:
        break;
    }
  }

  static List<EngineTrack> _tracks(Object? raw, String fallback) {
    if (raw is! List) return const <EngineTrack>[];
    final List<EngineTrack> out = <EngineTrack>[];
    for (final Object? entry in raw) {
      if (entry is! Map) continue;
      final Map<Object?, Object?> track = Map<Object?, Object?>.from(entry);
      final Object? title = track['title'];
      out.add(EngineTrack(
        id: (track['id'] as num?)?.toInt() ?? out.length,
        title: title is String && title.isNotEmpty ? title : '$fallback ${out.length + 1}',
        language: track['language'] as String?,
        codec: track['codec'] as String?,
      ));
    }
    return out;
  }

  static EngineReadyState _readyFrom(String? name) {
    switch (name) {
      case 'buffering':
        return EngineReadyState.buffering;
      case 'ready':
        return EngineReadyState.ready;
      case 'ended':
        return EngineReadyState.ended;
      default:
        return EngineReadyState.idle;
    }
  }

  @override
  Future<void> open(EngineRequest request) async {
    if (_disposed) return;
    if (request.needsMpv) {
      // Better to refuse immediately than to hand a torrent URL to Media3 and
      // let it fail slowly: the caller falls back to mpv in the same tick.
      throw const EngineUnsupported(
        'Torrents are played by the mpv engine',
      );
    }
    _emit(const EngineState());
    start();
    await _invoke('load', <String, dynamic>{
      'url': request.url,
      'headers': request.headers,
      'startMs': request.start.inMilliseconds,
      'isLive': request.isLive,
    });
  }

  @override
  Future<void> play() => _invoke('play');

  @override
  Future<void> pause() => _invoke('pause');

  @override
  Future<void> playOrPause() => _invoke('playOrPause');

  @override
  Future<void> stop() => _invoke('stop');

  @override
  Future<void> seek(Duration position) => _invoke(
        'seek',
        <String, dynamic>{'positionMs': position.inMilliseconds},
      );

  @override
  Future<void> setRate(double rate) => _invoke(
        'setRate',
        <String, dynamic>{'rate': rate},
      );

  @override
  Future<void> setVolume(double volume) => _invoke(
        'setVolume',
        <String, dynamic>{'volume': volume},
      );

  @override
  Future<void> setAudioTrack(EngineTrack? track) => _invoke(
        'selectAudioTrack',
        <String, dynamic>{'trackId': track?.id},
      );

  @override
  Future<void> setSubtitleTrack(EngineTrack? track) => _invoke(
        'selectSubtitleTrack',
        <String, dynamic>{'trackId': track?.id},
      );

  @override
  Future<void> setSubtitlesVisible(bool visible) => _invoke(
        'setSubtitlesVisible',
        <String, dynamic>{'visible': visible},
      );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventSub?.cancel();
    _eventSub = null;
    surfaceMounted.dispose();
    await _stateStream.close();
    try {
      await _invoke('release');
    } on EngineUnsupported {
      // Nothing to release if the bridge was never there.
    }
  }
}

/// Hosts the native SurfaceView. Reports the first time it is on screen so the
/// engine can join it to a live player.
class ExoPlayerSurface extends StatefulWidget {
  const ExoPlayerSurface({super.key, required this.onSurfaceAvailable});

  final VoidCallback onSurfaceAvailable;

  @override
  State<ExoPlayerSurface> createState() => _ExoPlayerSurfaceState();
}

class _ExoPlayerSurfaceState extends State<ExoPlayerSurface> {
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    // The native side reports availability over the event channel, but the
    // Dart side also nudges on the first frame: the platform view's own attach
    // can land before the listener is subscribed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reported) return;
      _reported = true;
      widget.onSurfaceAvailable();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ExoPlayerEngine.isSupported) {
      return const SizedBox.shrink();
    }
    return const AndroidView(viewType: ExoPlayerEngine.viewType);
  }
}
