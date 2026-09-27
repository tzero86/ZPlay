import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../models/iptv/iptv_models.dart';
import '../../services/iptv/hardcoded_channels.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/player/player_settings.dart';
import '../../services/window/window_service.dart';
import '../../services/discord/discord_rpc_service.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/player/player_aspect_menu.dart';
import '../../services/storage/app_image_cache.dart';

class IptvPlayerPage extends StatefulWidget {
  final HardcodedChannel channel;
  final List<ChannelHit> hits;
  final int initialHitIndex;
  final bool? isLive;
  final String? categoryTitle;

  const IptvPlayerPage({
    super.key,
    required this.channel,
    required this.hits,
    this.initialHitIndex = 0,
    this.isLive,
    this.categoryTitle,
  });

  @override
  State<IptvPlayerPage> createState() => _IptvPlayerPageState();
}

class _IptvPlayerPageState extends State<IptvPlayerPage>
    with SingleTickerProviderStateMixin {
  late final Player _player = Player(configuration: PlayerSettings.getMediaKitPlayerConfiguration());
  late final VideoController _videoController = VideoController(
    _player,
    configuration: PlayerSettings.getVideoControllerConfiguration(),
  );
  final List<StreamSubscription> _subscriptions = [];

  late int _activeHitIndex;
  bool _isLoading = true;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration?> _bufferedNotifier = ValueNotifier<Duration?>(null);

  String _statusMessage = 'Connecting to stream…';
  bool _showControls = true;
  bool _showSourcesDrawer = false;
  Timer? _hideControlsTimer;
  Timer? _watchdogTimer;
  late final ScrollController _sourcesScrollController;

  BoxFit _videoFit = BoxFit.contain;
  bool _showAspectMenu = false;
  bool _showAspectHud = false;
  String _aspectHudText = '';
  Timer? _aspectHudTimer;
  late double _volume = PlayerSettings.savedVolume.value;
  bool _isMuted = false;
  bool _showVolumeHud = false;
  Timer? _volumeHudTimer;

  // Stream watchdog metrics
  Duration _lastPosition = Duration.zero;
  DateTime _lastPositionChange = DateTime.now();
  int _retryCount = 0;
  bool _hasFallenBackToSoftware = false;

  /// Set when a feed could not be opened. Separate from [_isLoading] because
  /// the status line is only painted while loading, so a failure that just
  /// cleared the spinner told the user nothing at all.
  String? _feedError;

  /// Highest consecutive reconnect attempts before the player stops trying.
  /// A stalled live feed re-enters through the watchdog, which is not the
  /// catch path [_retryCount] used to guard, so the old cap never applied and
  /// the player looped on the same dead URL forever.
  static const int _maxReconnects = 3;

  bool get _isLiveStream {
    if (widget.isLive != null) return widget.isLive!;
    final currentHit = widget.hits.isNotEmpty && _activeHitIndex < widget.hits.length
        ? widget.hits[_activeHitIndex]
        : null;
    final kind = currentHit?.stream.kind.toLowerCase();
    if (kind == 'movie' || kind == 'series' || kind == 'vod') return false;
    final cat = widget.channel.category.toLowerCase();
    if (cat.contains('movie') || cat.contains('series') || cat.contains('vod') || cat.contains('show')) {
      return false;
    }
    return true;
  }

  bool get _isCategoryList {
    if (widget.hits.length <= 1) return false;
    if (widget.categoryTitle != null && widget.categoryTitle!.isNotEmpty) return true;
    return widget.hits.first.stream.streamId != widget.hits.last.stream.streamId;
  }

  bool _wasFullscreenBeforeEntering = false;

  @override
  void initState() {
    super.initState();
    _volume = PlayerSettings.savedVolume.value;
    _isMuted = _volume == 0;
    _wasFullscreenBeforeEntering = WindowService.instance.isFullscreen;
    WakelockPlus.enable();
    _activeHitIndex = widget.initialHitIndex.clamp(0, widget.hits.length - 1);
    _sourcesScrollController = ScrollController();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    PlayerSettings.applyToPlayer(_player);
    PlayerSettings.changeNotifier.addListener(_onPlayerSettingsChanged);

    _subscriptions.addAll([
      _player.stream.playing.listen((playing) {
        if (mounted && _isPlaying != playing) setState(() => _isPlaying = playing);
      }),
      _player.stream.position.listen((pos) {
        _position = pos;
        _positionNotifier.value = pos;
      }),
      _player.stream.duration.listen((dur) {
        if (mounted && _duration != dur) setState(() => _duration = dur);
      }),
      _player.stream.buffer.listen((buf) {
        _bufferedNotifier.value = buf;
      }),
      _player.stream.error.listen((error) {
        debugPrint('[IPTV Player Error] $error');
        if (PlayerSettings.isHardwareDecoderError(error) &&
            !_hasFallenBackToSoftware &&
            PlayerSettings.autoRecoverBlackScreen.value) {
          _hasFallenBackToSoftware = true;
          debugPrint('[IPTV Player Error] Hardware decoder failed. Falling back to software decoding...');
          PlayerSettings.fallbackToSoftware(_player);
          return;
        }
        // Anything else is a dead feed. It used to be logged and dropped, which
        // is why a channel that never played looked identical to one that was
        // merely still buffering.
        if (!mounted || _isLoading) return;
        setState(() {
          _isLoading = false;
          _feedError = 'This feed stopped: $error';
        });
      }),
    ]);

    _initPlayer();
    if (_isLiveStream) {
      _startWatchdog();
    }
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    PlayerSettings.changeNotifier.removeListener(_onPlayerSettingsChanged);
    WakelockPlus.disable();
    _hideControlsTimer?.cancel();
    _watchdogTimer?.cancel();
    _volumeHudTimer?.cancel();
    _aspectHudTimer?.cancel();
    _sourcesScrollController.dispose();
    _positionNotifier.dispose();
    _bufferedNotifier.dispose();
    // No VideoController.dispose in pinned media_kit_video (video_controller.dart:56-172); Player.dispose owns the texture.
    _player.dispose();
    if (!_wasFullscreenBeforeEntering &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
        WindowService.instance.isFullscreen) {
      WindowService.instance.exitFullscreen();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    DiscordRpcService.instance.clearToIdle();
    super.dispose();
  }

  void _onPlayerSettingsChanged() {
    PlayerSettings.applyToPlayer(_player);
  }

  Future<void> _initPlayer() async {
    DiscordRpcService.instance.setWatchingLiveTv(
      channelName: widget.channel.name,
      logoUrl: widget.channel.iconUrl,
    );
    if (widget.hits.isEmpty) {
      setState(() {
        _isLoading = false;
        _feedError = 'This channel has no stream sources.';
      });
      return;
    }

    final currentHit = widget.hits[_activeHitIndex];
    final streamUrl = currentHit.streamUrl;
    _hasFallenBackToSoftware = false;

    setState(() {
      _isLoading = true;
      _feedError = null;
      _statusMessage = 'Buffering ${currentHit.stream.name.isNotEmpty ? currentHit.stream.name : currentHit.portal.name}…';
    });

    try {
      await PlayerSettings.applyToPlayer(_player, isLive: true);

      // Resolve headers the same way the mainline player does. IPTV used to
      // hand media_kit a fixed VLC user agent and nothing else, so it was the
      // one playback path in the app that could never obtain a Referer or
      // Origin, and many IPTV origins answer 403 for a request that has none.
      final headers = PlayerSettings.resolveStreamHeaders(
        streamUrl,
        const {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20'},
      );

      await _player.open(
        Media(streamUrl, httpHeaders: headers),
        play: true,
      );

      await PlayerSettings.applyToPlayer(_player, isLive: true);
      _player.setVolume(_isMuted ? 0.0 : _volume * 100.0);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _feedError = null;
        _retryCount = 0;
        _lastPosition = Duration.zero;
        _lastPositionChange = DateTime.now();
      });

      _startHideControlsTimer();
    } catch (e) {
      debugPrint('[IPTV Player Error] $e');
      if (!mounted) return;
      final willRetry = widget.hits.length > 1 && _retryCount < _maxReconnects;
      setState(() {
        _isLoading = false;
        _feedError = willRetry
            ? 'Feed failed. Trying an alternative source…'
            : 'This feed would not play. ${widget.hits.length > 1 ? 'Every source has been tried.' : 'The portal returned no working stream for this channel.'}';
      });

      // Auto-failover to next hit if available
      if (willRetry) {
        _retryCount++;
        Future.delayed(const Duration(seconds: 1), () {
          if (!mounted) return;
          final nextIdx = (_activeHitIndex + 1) % widget.hits.length;
          _switchSource(nextIdx);
        });
      }
    }
  }

  void _switchSource(int index) {
    if (index < 0 || index >= widget.hits.length) return;
    setState(() {
      _activeHitIndex = index;
      _showSourcesDrawer = false;
    });
    _initPlayer();
  }

  void _openSourcesDrawer() {
    setState(() => _showSourcesDrawer = true);
    _hideControlsTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sourcesScrollController.hasClients) {
        final targetOffset = (_activeHitIndex * 62.0) - 120.0;
        final maxOffset = _sourcesScrollController.position.maxScrollExtent;
        final safeOffset = targetOffset.clamp(0.0, maxOffset);
        _sourcesScrollController.animateTo(
          safeOffset,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;

      final isPlaying = _isPlaying;
      final currentPos = _position;

      if (isPlaying && currentPos != _lastPosition) {
        _lastPosition = currentPos;
        _lastPositionChange = DateTime.now();
      }

      // Black screen detection: Audio playing, position advancing past 2.5s, but video width is null/0
      if (isPlaying &&
          currentPos > const Duration(milliseconds: 2500) &&
          (_player.state.width == null || _player.state.width == 0) &&
          !_hasFallenBackToSoftware &&
          PlayerSettings.autoRecoverBlackScreen.value) {
        _hasFallenBackToSoftware = true;
        debugPrint('[IPTV Watchdog] Black screen detected on channel stream! Falling back to software decoding...');
        PlayerSettings.fallbackToSoftware(_player);
      }

      // If live and position frozen for > 10 seconds, trigger reconnect. The
      // stall path never reaches the catch block in _initPlayer, so it used to
      // reconnect forever on a dead URL. Bounded by the same cap, and once it
      // runs out the failure is stated on screen instead of silently spinning.
      if (_isLiveStream &&
          isPlaying &&
          DateTime.now().difference(_lastPositionChange).inSeconds > 10 &&
          !_isLoading) {
        if (_retryCount < _maxReconnects) {
          _retryCount++;
          debugPrint('[IPTV Watchdog] Stream frozen > 10s — reconnecting '
              '(attempt $_retryCount/$_maxReconnects)…');
          _initPlayer();
        } else {
          debugPrint('[IPTV Watchdog] Stream frozen > 10s — giving up after '
              '$_maxReconnects attempts.');
          if (mounted) {
            setState(() {
              _isLoading = false;
              _feedError = 'This feed stalled and would not keep playing.';
            });
          }
        }
      }
    });
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _showControls && !_showSourcesDrawer) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_showAspectMenu) {
      setState(() => _showAspectMenu = false);
      return;
    }
    setState(() {
      _showControls = !_showControls;
      if (!_showControls) {
        _showSourcesDrawer = false;
        _showAspectMenu = false;
      }
    });
    if (_showControls) _startHideControlsTimer();
  }

  void _setVideoFit(BoxFit fit) {
    setState(() {
      _videoFit = fit;
      _aspectHudText = _fitLabel(fit);
      _showAspectHud = true;
      _showAspectMenu = false;
    });
    _aspectHudTimer?.cancel();
    _aspectHudTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _showAspectHud = false);
    });
    _startHideControlsTimer();
  }

  String _fitLabel(BoxFit fit) {
    switch (fit) {
      case BoxFit.contain:
        return 'ASPECT: FIT (CONTAIN)';
      case BoxFit.cover:
        return 'ASPECT: FILL (ZOOM / CROP)';
      case BoxFit.fill:
        return 'ASPECT: STRETCH (FILL)';
      default:
        return 'ASPECT: ${fit.name.toUpperCase()}';
    }
  }

  void _cycleVideoFit() {
    final nextFit = _videoFit == BoxFit.contain
        ? BoxFit.cover
        : (_videoFit == BoxFit.cover ? BoxFit.fill : BoxFit.contain);
    _setVideoFit(nextFit);
  }

  void _seekRelative(int seconds) {
    if (_isLiveStream) return;
    final cur = _position;
    final max = _duration;
    final target = cur + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > max ? max : target);
    _player.seek(clamped);
    _startHideControlsTimer();
  }

  void _togglePlayPause() {
    _player.playOrPause();
    _startHideControlsTimer();
  }

  void _adjustVolume(double delta) {
    setState(() {
      if (_isMuted && delta > 0) {
        _isMuted = false;
      }
      _volume = (_volume + delta).clamp(0.0, 1.0);
      if (_volume == 0.0) {
        _isMuted = true;
      } else if (_isMuted) {
        _isMuted = false;
      }
      _player.setVolume(_isMuted ? 0.0 : _volume * 100.0);
      _showVolumeHud = true;
    });
    PlayerSettings.setSavedVolume(_volume);
    _volumeHudTimer?.cancel();
    _volumeHudTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _showVolumeHud = false);
    });
    _startHideControlsTimer();
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      if (!_isMuted && _volume == 0) {
        _volume = 0.5;
      }
      _player.setVolume(_isMuted ? 0.0 : _volume * 100.0);
      _showVolumeHud = true;
    });
    _volumeHudTimer?.cancel();
    _volumeHudTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _showVolumeHud = false);
    });
    _startHideControlsTimer();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final ch = widget.channel;
    final currentHit = widget.hits.isNotEmpty ? widget.hits[_activeHitIndex] : null;
    final isLive = _isLiveStream;
    final isCategoryList = _isCategoryList;
    final currentTitle = currentHit != null && currentHit.stream.name.isNotEmpty
        ? currentHit.stream.name
        : ch.name;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.space) {
            _togglePlayPause();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft && !isLive) {
            _seekRelative(-10);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight && !isLive) {
            _seekRelative(10);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _adjustVolume(0.05);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _adjustVolume(-0.05);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.pageDown || event.logicalKey == LogicalKeyboardKey.keyN) {
            if (_activeHitIndex + 1 < widget.hits.length) {
              _switchSource(_activeHitIndex + 1);
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.pageUp || event.logicalKey == LogicalKeyboardKey.keyP) {
            if (_activeHitIndex - 1 >= 0) {
              _switchSource(_activeHitIndex - 1);
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
            _toggleMute();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyF ||
              event.logicalKey == LogicalKeyboardKey.f11) {
            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
              WindowService.instance.toggleFullscreen();
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyC) {
            _cycleVideoFit();
            _startHideControlsTimer();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            if ((Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
                WindowService.instance.isFullscreen) {
              WindowService.instance.exitFullscreen();
            } else {
              Navigator.pop(context);
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: tokens.bg,
        body: Listener(
          onPointerSignal: (pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              // Register on the resolver instead of acting here: a Scrollable under the pointer
              // claims the event first and scrolling it must not also change the volume.
              GestureBinding.instance.pointerSignalResolver.register(pointerSignal, (_) {
                if (pointerSignal.scrollDelta.dy < 0) {
                  _adjustVolume(0.05); // Scroll up -> Volume up
                } else if (pointerSignal.scrollDelta.dy > 0) {
                  _adjustVolume(-0.05); // Scroll down -> Volume down
                }
              });
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            onDoubleTap: () {
              if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
                WindowService.instance.toggleFullscreen();
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Video Surface is ALWAYS mounted to prevent texture/surface detachment and black screens
                Center(
                  child: SizedBox.expand(
                    child: ValueListenableBuilder<int>(
                      valueListenable: PlayerSettings.changeNotifier,
                      builder: (context, _, __) {
                        return Video(
                          controller: _videoController,
                          fit: _videoFit,
                          controls: NoVideoControls,
                          subtitleViewConfiguration: PlayerSettings.getSubtitleViewConfiguration(),
                        );
                      },
                    ),
                  ),
                ),

                // Loading / Buffering Banner
                if (_isLoading)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s24, vertical: 14),
                      decoration: BoxDecoration(
                        color: tokens.bg.withValues(alpha: 0.75),
                        borderRadius: ZplayRadius.mdAll,
                        border: Border.all(color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppThemeService.currentPalette.value.primaryColor,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            _statusMessage,
                            style: ZplayType.body
                                .copyWith(weight: FontWeight.w600)
                                .toStyle(color: tokens.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),

                // A failed feed has to say so. Previously the only status text
                // lived inside the loading branch, so the message written on
                // failure was never painted and the player just went dark.
                if (!_isLoading && _feedError != null)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.all(ZplaySpacing.s24),
                      padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s24, vertical: ZplaySpacing.s20),
                      decoration: BoxDecoration(
                        color: tokens.bg.withValues(alpha: 0.9),
                        borderRadius: ZplayRadius.mdAll,
                        border: Border.all(color: tokens.danger.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.tv_off_rounded,
                            size: 40,
                            color: tokens.danger,
                          ),
                          const SizedBox(height: ZplaySpacing.s12),
                          Text(
                            _feedError!,
                            textAlign: TextAlign.center,
                            style: ZplayType.body
                                .copyWith(weight: FontWeight.w600)
                                .toStyle(color: tokens.textPrimary),
                          ),
                          const SizedBox(height: ZplaySpacing.s16),
                          FilledButton.icon(
                            onPressed: () {
                              setState(() {
                                _retryCount = 0;
                                _feedError = null;
                                _isLoading = true;
                                _statusMessage = 'Reconnecting…';
                              });
                              _lastPositionChange = DateTime.now();
                              _initPlayer();
                            },
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Try again'),
                            style: FilledButton.styleFrom(
                              backgroundColor: tokens.accent,
                              foregroundColor: tokens.onAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Volume HUD Overlay (when changing volume)
                if (_showVolumeHud)
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                        decoration: BoxDecoration(
                          color: tokens.surfaceOverlay.withValues(alpha: 0.90),
                          borderRadius: ZplayRadius.mdAll,
                          border: Border.all(color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.6), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isMuted || _volume == 0
                                  ? Icons.volume_off_rounded
                                  : (_volume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                              color: _isMuted ? tokens.danger : tokens.info,
                              size: 28,
                            ),
                            const SizedBox(width: 14),
                            SizedBox(
                              width: 130,
                              child: ClipRRect(
                                borderRadius: ZplayRadius.xsAll,
                                child: LinearProgressIndicator(
                                  value: _isMuted ? 0.0 : _volume,
                                  backgroundColor: tokens.textDisabled,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _isMuted ? tokens.danger : AppThemeService.currentPalette.value.primaryColor,
                                  ),
                                  minHeight: 7,
                                ),
                              ),
                            ),
                            const SizedBox(width: ZplaySpacing.s12),
                            Text(
                              _isMuted ? 'MUTED' : '${(_volume * 100).toInt()}%',
                              style: ZplayType.labelNumeric.toStyle(
                                color: _isMuted ? tokens.danger : tokens.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Aspect Ratio HUD Overlay (when changing aspect ratio)
                if (_showAspectHud)
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                        decoration: BoxDecoration(
                          color: tokens.surfaceOverlay.withValues(alpha: 0.90),
                          borderRadius: ZplayRadius.mdAll,
                          border: Border.all(color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.6), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.aspect_ratio_rounded, color: tokens.info, size: 26),
                            const SizedBox(width: ZplaySpacing.s12),
                            Text(
                              _aspectHudText,
                              style: ZplayType.body
                                  .copyWith(weight: FontWeight.w700, letterSpacing: 0.5)
                                  .toStyle(color: tokens.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Controls Overlay
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _showControls ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Top Bar
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(ZplaySpacing.s16, ZplaySpacing.s16, ZplaySpacing.s16, ZplaySpacing.s24),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [tokens.bg.withValues(alpha: 0.80), Colors.transparent],
                              ),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: Icon(Icons.arrow_back_rounded, color: tokens.textPrimary, size: 24),
                                  onPressed: () => Navigator.pop(context),
                                ),
                                const SizedBox(width: ZplaySpacing.s8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: ZplaySpacing.s2),
                                            decoration: BoxDecoration(
                                              color: isLive ? tokens.danger : AppThemeService.currentPalette.value.primaryColor,
                                              borderRadius: ZplayRadius.xsAll,
                                            ),
                                            child: Text(
                                              isLive
                                                  ? 'LIVE'
                                                  : (ch.category.isNotEmpty ? ch.category.toUpperCase() : 'VOD'),
                                              style: ZplayType.overline
                                                  .copyWith(weight: FontWeight.w700)
                                                  .toStyle(color: tokens.textPrimary),
                                            ),
                                          ),
                                          const SizedBox(width: ZplaySpacing.s8),
                                          Expanded(
                                            child: Text(
                                              currentTitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: ZplayType.title
                                                  .copyWith(weight: FontWeight.w700)
                                                  .toStyle(color: tokens.textPrimary),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (currentHit != null) ...[
                                        const SizedBox(height: ZplaySpacing.s2),
                                        Text(
                                          isCategoryList
                                              ? 'Channel ${_activeHitIndex + 1}/${widget.hits.length} · ${currentHit.portal.name}'
                                              : 'Source ${_activeHitIndex + 1}/${widget.hits.length} · ${currentHit.portal.name}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: ZplayType.bodySmall.toStyle(color: tokens.textEmphasis),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: ZplaySpacing.s12),
                                // Category Channels / Sources Drawer Toggle
                                if (widget.hits.length > 1)
                                  IconButton(
                                    icon: Icon(
                                      isCategoryList ? Icons.format_list_bulleted_rounded : Icons.video_library_rounded,
                                      color: tokens.textPrimary,
                                    ),
                                    tooltip: isCategoryList
                                        ? (widget.categoryTitle ?? 'Category Channels')
                                        : 'Alternative Feeds',
                                    onPressed: _openSourcesDrawer,
                                  ),
                                if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) ...[
                                  const SizedBox(width: ZplaySpacing.s4),
                                  ValueListenableBuilder<bool>(
                                    valueListenable: WindowService.instance.isFullscreenNotifier,
                                    builder: (context, isFullscreen, _) {
                                      return IconButton(
                                        icon: Icon(
                                          isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                          color: tokens.textPrimary,
                                          size: 24,
                                        ),
                                        tooltip: isFullscreen ? 'Exit Fullscreen (F11)' : 'Fullscreen (F11)',
                                        onPressed: () => WindowService.instance.toggleFullscreen(),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        // Bottom Bar
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(ZplaySpacing.s20, ZplaySpacing.s20, ZplaySpacing.s20, ZplaySpacing.s16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [tokens.bg.withValues(alpha: 0.80), Colors.transparent],
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // ── SEEKBAR (ONLY FOR MOVIES & SHOWS / VOD) ──
                                if (!isLive) ...[
                                  _IptvCustomProgressBar(
                                    player: _player,
                                    positionNotifier: _positionNotifier,
                                    duration: _duration,
                                    bufferedNotifier: _bufferedNotifier,
                                    onSeekStart: () => _hideControlsTimer?.cancel(),
                                    onSeekEnd: () => _startHideControlsTimer(),
                                  ),
                                  const SizedBox(height: 6),
                                ],

                                // Controls Buttons Row
                                Row(
                                  children: [
                                    // Play / Pause
                                    IconButton(
                                      icon: Icon(
                                        _isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: tokens.textPrimary,
                                        size: 30,
                                      ),
                                      onPressed: _togglePlayPause,
                                    ),

                                    if (!isLive) ...[
                                      const SizedBox(width: ZplaySpacing.s4),
                                      // Replay -10s
                                      IconButton(
                                        icon: Icon(Icons.replay_10_rounded, color: tokens.textPrimary, size: 24),
                                        tooltip: 'Seek -10s',
                                        onPressed: () => _seekRelative(-10),
                                      ),
                                      // Forward +10s
                                      IconButton(
                                        icon: Icon(Icons.forward_10_rounded, color: tokens.textPrimary, size: 24),
                                        tooltip: 'Seek +10s',
                                        onPressed: () => _seekRelative(10),
                                      ),
                                      const SizedBox(width: ZplaySpacing.s8),
                                      // Position / Duration Readout
                                      ValueListenableBuilder<Duration>(
                                        valueListenable: _positionNotifier,
                                        builder: (context, pos, _) {
                                          return Text(
                                            '${_formatDuration(pos)} / ${_formatDuration(_duration)}',
                                            style: ZplayType.labelNumeric.toStyle(color: tokens.textEmphasis),
                                          );
                                        },
                                      ),
                                    ],

                                    const SizedBox(width: ZplaySpacing.s8),

                                    // ── INTERACTIVE VOLUME SLIDER & MUTE TOGGLE ──
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            _isMuted || _volume == 0
                                                ? Icons.volume_off_rounded
                                                : (_volume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                                            color: _isMuted ? tokens.danger : tokens.textPrimary,
                                            size: 22,
                                          ),
                                          tooltip: _isMuted ? 'Unmute (M)' : 'Mute (M)',
                                          onPressed: _toggleMute,
                                        ),
                                        SizedBox(
                                          width: 86,
                                          child: SliderTheme(
                                            data: SliderTheme.of(context).copyWith(
                                              trackHeight: 3.5,
                                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
                                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                              activeTrackColor: AppThemeService.currentPalette.value.primaryColor,
                                              inactiveTrackColor: tokens.textDisabled,
                                              thumbColor: tokens.textPrimary,
                                            ),
                                            child: Slider(
                                              value: _isMuted ? 0.0 : _volume,
                                              min: 0.0,
                                              max: 1.0,
                                              onChanged: (val) {
                                                setState(() {
                                                  _volume = val;
                                                  _isMuted = val == 0.0;
                                                  _player.setVolume(_isMuted ? 0.0 : val * 100.0);
                                                  _showVolumeHud = true;
                                                });
                                                _volumeHudTimer?.cancel();
                                                _volumeHudTimer = Timer(const Duration(milliseconds: 1600), () {
                                                  if (mounted) setState(() => _showVolumeHud = false);
                                                });
                                                _hideControlsTimer?.cancel();
                                              },
                                              onChangeEnd: (val) {
                                                PlayerSettings.setSavedVolume(val);
                                                _startHideControlsTimer();
                                              },
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${((_isMuted ? 0.0 : _volume) * 100).toInt()}%',
                                          style: ZplayType.labelNumeric.toStyle(
                                            color: _isMuted ? tokens.danger : tokens.textEmphasis,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const Spacer(),

                                    // Aspect Ratio Selector / Popover Button
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          setState(() {
                                            _showAspectMenu = !_showAspectMenu;
                                            _showSourcesDrawer = false;
                                          });
                                          if (_showAspectMenu) {
                                            _hideControlsTimer?.cancel();
                                          } else {
                                            _startHideControlsTimer();
                                          }
                                        },
                                        borderRadius: ZplayRadius.smAll,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s8, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: _showAspectMenu
                                                ? AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.3)
                                                : tokens.textPrimary.withValues(alpha: ZplayOpacity.borderStrong),
                                            borderRadius: ZplayRadius.smAll,
                                            border: Border.all(
                                              color: _showAspectMenu
                                                  ? AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.6)
                                                  : tokens.textPrimary.withValues(alpha: ZplayOpacity.overlayHover),
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.aspect_ratio_rounded, color: tokens.textPrimary, size: 16),
                                              const SizedBox(width: 6),
                                              Text(
                                                _videoFit == BoxFit.contain
                                                    ? 'FIT'
                                                    : (_videoFit == BoxFit.cover ? 'ZOOM' : 'STRETCH'),
                                                style: ZplayType.caption
                                                    .copyWith(weight: FontWeight.w700, letterSpacing: 0.4)
                                                    .toStyle(color: tokens.textPrimary),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Fullscreen toggle on desktop
                                    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) ...[
                                      const SizedBox(width: ZplaySpacing.s8),
                                      ValueListenableBuilder<bool>(
                                        valueListenable: WindowService.instance.isFullscreenNotifier,
                                        builder: (context, isFullscreen, _) {
                                          return IconButton(
                                            icon: Icon(
                                              isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                              color: tokens.textPrimary,
                                              size: 24,
                                            ),
                                            tooltip: isFullscreen ? 'Exit Fullscreen (F11)' : 'Fullscreen (F11)',
                                            onPressed: () => WindowService.instance.toggleFullscreen(),
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Floating Aspect Ratio Popover
                if (_showAspectMenu)
                  Positioned(
                    bottom: 74,
                    right: 20,
                    child: PlayerAspectMenu(
                      currentFit: _videoFit,
                      subtitleScale: PlayerSettings.subScale.value,
                      onFitSelected: (fit) => _setVideoFit(fit),
                      onSubtitleScaleChanged: (scale) {
                        PlayerSettings.setSubScale(scale, player: _player);
                      },
                      onClose: () => setState(() => _showAspectMenu = false),
                    ),
                  ),

                // Channels / Feeds Side Drawer
                if (_showSourcesDrawer)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: 360,
                    child: Container(
                      decoration: BoxDecoration(
                        color: tokens.bg.withValues(alpha: 0.95),
                        border: Border(left: BorderSide(color: tokens.surfaceOverlay, width: 1.2)),
                        boxShadow: const [
                          BoxShadow(color: Colors.black87, blurRadius: 24, offset: Offset(-6, 0)),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s16, vertical: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isCategoryList ? Icons.format_list_bulleted_rounded : Icons.tune_rounded,
                                color: AppThemeService.currentPalette.value.primaryColor,
                                size: 20,
                              ),
                              const SizedBox(width: ZplaySpacing.s8),
                              Expanded(
                                child: Text(
                                  widget.categoryTitle ?? (isCategoryList ? 'Category Channels' : 'Stream Feeds'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ZplayType.title
                                      .copyWith(weight: FontWeight.w700)
                                      .toStyle(color: tokens.textPrimary),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: ZplaySpacing.s2),
                                decoration: BoxDecoration(
                                  color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.2),
                                  borderRadius: ZplayRadius.smAll,
                                ),
                                child: Text(
                                  '${widget.hits.length}',
                                  style: ZplayType.caption
                                      .copyWith(weight: FontWeight.w700)
                                      .toStyle(color: tokens.accent),
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: Icon(Icons.close_rounded, color: tokens.textMuted, size: 20),
                                onPressed: () => setState(() => _showSourcesDrawer = false),
                              ),
                            ],
                          ),
                          const SizedBox(height: ZplaySpacing.s12),
                          Expanded(
                            child: ListView.separated(
                              controller: _sourcesScrollController,
                              itemCount: widget.hits.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final hit = widget.hits[index];
                                final isSelected = index == _activeHitIndex;
                                final numFormatted = (index + 1).toString().padLeft(3, '0');

                                return FocusableCard(
                                  onTap: () => _switchSource(index),
                                  builder: (context, state) => CardFocusRing(
                                    focused: state.focused,
                                    radius: ZplayRadius.smAll,
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 120),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: ZplaySpacing.s8),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.25)
                                            : tokens.textPrimary.withValues(alpha: ZplayOpacity.borderFaint),
                                        borderRadius: ZplayRadius.smAll,
                                        border: Border.all(
                                          color: isSelected
                                              ? AppThemeService.currentPalette.value.primaryColor
                                              : tokens.borderDefault,
                                          width: isSelected ? 1.4 : 1.0,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          // Number
                                          SizedBox(
                                            width: 28,
                                            child: Text(
                                              numFormatted,
                                              style: ZplayType.caption
                                                  .copyWith(weight: FontWeight.w700)
                                                  .toStyle(
                                                    color: isSelected ? tokens.info : tokens.textDisabled,
                                                  ),
                                            ),
                                          ),

                                          const SizedBox(width: 6),

                                          // Icon / Logo
                                          Container(
                                            width: 38,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: tokens.bg,
                                              borderRadius: ZplayRadius.xsAll,
                                              border: Border.all(color: tokens.surfaceOverlay),
                                            ),
                                            child: hit.stream.icon.isNotEmpty
                                                ? ClipRRect(
                                                    borderRadius: ZplayRadius.xsAll,
                                                    child: CachedNetworkImage(
                                                      imageUrl: hit.stream.icon,
                                                      cacheManager: AppImageCache.manager,
                                                      fit: BoxFit.contain,
                                                      memCacheWidth: 64,
                                                      errorWidget: (_, _, _) => Icon(
                                                        isLive ? Icons.live_tv_rounded : Icons.movie_rounded,
                                                        color: tokens.textMuted,
                                                        size: 16,
                                                      )),
                                                  )
                                                : Icon(
                                                    isLive ? Icons.live_tv_rounded : Icons.movie_rounded,
                                                    color: tokens.textMuted,
                                                    size: 16,
                                                  ),
                                          ),

                                          const SizedBox(width: 10),

                                          // Channel Title
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  hit.stream.name,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: ZplayType.label
                                                      .copyWith(
                                                        weight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                                      )
                                                      .toStyle(
                                                        color: isSelected ? tokens.textPrimary : tokens.textEmphasis,
                                                      ),
                                                ),
                                                const SizedBox(height: ZplaySpacing.s2),
                                                Text(
                                                  hit.portal.portal.username.isNotEmpty
                                                      ? hit.portal.portal.username
                                                      : hit.portal.name,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: ZplayType.caption
                                                      .copyWith(weight: FontWeight.w600)
                                                      .toStyle(color: tokens.textMuted),
                                                ),
                                              ],
                                            ),
                                          ),

                                          if (isSelected) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.all(ZplaySpacing.s4),
                                              decoration: BoxDecoration(
                                                color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.3),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.play_arrow_rounded,
                                                color: tokens.info,
                                                size: 16,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
  String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
  if (duration.inHours > 0) {
    return '${duration.inHours}:$twoDigitMinutes:$twoDigitSeconds';
  }
  return '$twoDigitMinutes:$twoDigitSeconds';
}

class _IptvCustomProgressBar extends StatefulWidget {
  final Player player;
  final ValueNotifier<Duration> positionNotifier;
  final Duration duration;
  final ValueNotifier<Duration?> bufferedNotifier;
  final VoidCallback? onSeekStart;
  final VoidCallback? onSeekEnd;

  const _IptvCustomProgressBar({
    required this.player,
    required this.positionNotifier,
    required this.duration,
    required this.bufferedNotifier,
    this.onSeekStart,
    this.onSeekEnd,
  });

  @override
  State<_IptvCustomProgressBar> createState() => _IptvCustomProgressBarState();
}

class _IptvCustomProgressBarState extends State<_IptvCustomProgressBar> {
  double? _hoverX;
  bool _isDragging = false;
  Duration? _dragPosition;

  void _seekTo(double x, double width, Duration totalDuration) {
    if (width <= 0 || totalDuration <= Duration.zero) return;
    final percent = (x / width).clamp(0.0, 1.0);
    final position = totalDuration * percent;
    widget.player.seek(position);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final duration = widget.duration;

    return ValueListenableBuilder<Duration>(
      valueListenable: widget.positionNotifier,
      builder: (context, livePosition, _) {
        final position = _isDragging ? (_dragPosition ?? livePosition) : livePosition;

        return ValueListenableBuilder<Duration?>(
          valueListenable: widget.bufferedNotifier,
          builder: (context, bufferedDuration, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;

                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onHover: (event) {
                    setState(() {
                      _hoverX = event.localPosition.dx.clamp(0.0, width);
                    });
                  },
                  onExit: (event) {
                    setState(() {
                      _hoverX = null;
                    });
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (details) {
                      widget.onSeekStart?.call();
                      setState(() {
                        _isDragging = true;
                        _hoverX = details.localPosition.dx.clamp(0.0, width);
                        if (duration > Duration.zero) {
                          _dragPosition = duration * (_hoverX! / width);
                        }
                      });
                    },
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _hoverX = details.localPosition.dx.clamp(0.0, width);
                        if (duration > Duration.zero) {
                          _dragPosition = duration * (_hoverX! / width);
                        }
                      });
                    },
                    onHorizontalDragEnd: (details) {
                      if (_dragPosition != null) {
                        widget.player.seek(_dragPosition!);
                      }
                      setState(() {
                        _isDragging = false;
                        _dragPosition = null;
                      });
                      widget.onSeekEnd?.call();
                    },
                    onTapDown: (details) {
                      _seekTo(details.localPosition.dx, width, duration);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s8),
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.centerLeft,
                        children: [
                          // Invisible hit target
                          Container(
                            height: 24,
                            width: double.infinity,
                            color: Colors.transparent,
                          ),

                          // Background Bar
                          Container(
                            height: 5,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: tokens.textDisabled,
                              borderRadius: ZplayRadius.xsAll,
                            ),
                          ),

                          // Buffered Bar
                          if (bufferedDuration != null && duration.inMilliseconds > 0)
                            Positioned(
                              left: 0,
                              child: Container(
                                height: 5,
                                width: (width * (bufferedDuration.inMilliseconds / duration.inMilliseconds)).clamp(0.0, width),
                                decoration: BoxDecoration(
                                  color: tokens.textMuted,
                                  borderRadius: ZplayRadius.xsAll,
                                ),
                              ),
                            ),

                          // Played Bar
                          Container(
                            height: 5,
                            width: duration.inMilliseconds > 0
                                ? (width * (position.inMilliseconds / duration.inMilliseconds)).clamp(0.0, width)
                                : 0,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppThemeService.currentPalette.value.primaryColor, tokens.info],
                              ),
                              borderRadius: ZplayRadius.xsAll,
                            ),
                          ),

                          // Scrubber Handle
                          Positioned(
                            left: duration.inMilliseconds > 0
                                ? (width * (position.inMilliseconds / duration.inMilliseconds)).clamp(0.0, width) - 7
                                : -7,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: tokens.textPrimary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.5),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Hover Tooltip
                          if (_hoverX != null && duration > Duration.zero)
                            Positioned(
                              left: (_hoverX! - 30).clamp(0.0, width - 60),
                              bottom: 20,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: tokens.surface,
                                  borderRadius: ZplayRadius.xsAll,
                                  border: Border.all(
                                    color: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium),
                                    width: 1,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2)),
                                  ],
                                ),
                                child: Text(
                                  _formatDuration(duration * (_hoverX! / width)),
                                  style: ZplayType.labelNumeric.toStyle(color: tokens.textPrimary),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
