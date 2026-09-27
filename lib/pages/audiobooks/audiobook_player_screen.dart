import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:media_kit/media_kit.dart';

import '../../models/audiobook/audiobook_model.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/audiobook/audiobook_progress_service.dart';
import '../../services/audiobook/audiobook_settings.dart';
import '../../services/debrid/debrid_service.dart';
import '../../services/stream/torrent_stream_service.dart';
import '../../services/discord/discord_rpc_service.dart';
import '../../services/player/player_settings.dart';
import '../../services/playback/now_playing_service.dart';
import '../../widgets/audiobook/audiobook_interactive_physics_button.dart';
import '../../widgets/audiobook/audiobook_waveform_seekbar.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/segmented_tabs.dart';
import '../settings/appearance/audiobook_player_studio_page.dart';
import '../../services/storage/app_image_cache.dart';

class AudiobookPlayerScreen extends StatefulWidget {
  final Audiobook audiobook;
  final List<AudiobookChapter> chapters;
  final int initialChapterIndex;
  final Duration? initialPosition;

  const AudiobookPlayerScreen({
    super.key,
    required this.audiobook,
    required this.chapters,
    this.initialChapterIndex = 0,
    this.initialPosition,
  });

  @override
  State<AudiobookPlayerScreen> createState() => _AudiobookPlayerScreenState();
}

/// Audiobook playback lives here rather than in a controller, so the shell's bar
/// is fed from this screen while it is mounted and falls silent when it is
/// disposed.
///
/// Lifting playback into a controller is a deliberate follow up rather than an
/// oversight: it would be a product change, not a refactor, because playback
/// would then survive the route. Until then this screen is the audiobook owner
/// and registers itself as such.
class _AudiobookPlayerScreenState extends State<AudiobookPlayerScreen>
    with SingleTickerProviderStateMixin implements NowPlayingCommands {
  Player? _player;
  final List<StreamSubscription> _playerSubscriptions = [];
  late int _currentChapterIndex;

  bool _isLoading = true;
  bool _isPlaying = false;
  bool _autoplayNext = true;
  String _statusMessage = 'Initializing chapter...';
  String? _errorMessage;

  double _volume = 1.0;
  double _playbackSpeed = 1.0;
  final List<double> _speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool _showChaptersDrawer = false;
  String _chapterSearchQuery = '';
  late AnimationController _discAnimController;
  Timer? _progressTimer;
  bool _hasRestoredPosition = false;

  @override
  void initState() {
    super.initState();
    _currentChapterIndex = widget.initialChapterIndex;
    _discAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );

    AudiobookSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onSettingsChanged);

    NowPlayingService.register(this);
    _publishNowPlaying();

    _initChapter(_currentChapterIndex);

    // Save progress every 5 seconds
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveProgress();
    });
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  AudiobookChapter? get _currentChapter =>
      (widget.chapters.isNotEmpty && _currentChapterIndex < widget.chapters.length)
          ? widget.chapters[_currentChapterIndex]
          : null;

  /// Publishes this screen's frame to the shell's bar.
  ///
  /// Called from the few places that move a published field rather than from
  /// `build`: a position tick rebuilds far more often than the bar needs to hear
  /// about, and every publish allocates a snapshot.
  void _publishNowPlaying() {
    final chapter = _currentChapter;
    final author = widget.audiobook.author?.trim() ?? '';
    final chapterTitle = chapter == null ? '' : chapter.title.trim();
    final cover = widget.audiobook.coverImage.trim();

    // The bar gives the subtitle one line, so it reads "author · chapter". Either
    // half can be missing on a sideloaded file, and a stranded separator reads
    // worse than the half that is there.
    final subtitle = author.isEmpty
        ? chapterTitle
        : (chapterTitle.isEmpty ? author : '$author · $chapterTitle');

    NowPlayingService.publish(
      NowPlayingSnapshot(
        kind: NowPlayingKind.audiobook,
        title: widget.audiobook.title,
        subtitle: subtitle,
        artworkUrl: cover.isEmpty ? null : cover,
        isPlaying: _isPlaying,
        position: _position,
        duration: _duration,
        // Chapters are this player's queue, so the transport walks them. The bar
        // greys a button instead of hiding it, which keeps the four controls in
        // place for a book that is one long chapter.
        canPrevious: _currentChapterIndex > 0,
        canNext: _currentChapterIndex < widget.chapters.length - 1,
      ),
    );
  }

  /// Nothing to expand into: this screen is already the full size surface, and it
  /// only owns the bar for as long as it is mounted on top of the shell.
  @override
  void openFullPlayer(BuildContext context) {}

  @override
  Future<void> togglePlayPause() async {
    _togglePlayPause();
  }

  @override
  Future<void> next() async {
    if (_currentChapterIndex >= widget.chapters.length - 1) return;
    await _initChapter(_currentChapterIndex + 1);
  }

  @override
  Future<void> previous() async {
    // The first chapter has nowhere to go back to, so the button restarts it,
    // which is what a listener reaching for it at the start of a book expects.
    if (_currentChapterIndex == 0) {
      await _player?.seek(Duration.zero);
      return;
    }
    await _initChapter(_currentChapterIndex - 1);
  }

  @override
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
    if (!mounted) return;
    setState(() => _position = position);
  }

  void _updateDiscordRpc({bool? isPaused}) {
    final chapter = _currentChapter;
    DiscordRpcService.instance.setListeningAudiobook(
      title: widget.audiobook.title,
      author: widget.audiobook.author,
      chapter: chapter?.title,
      coverUrl: widget.audiobook.coverImage,
      position: _position,
      duration: _duration,
      isPaused: isPaused ?? !_isPlaying,
    );
  }

  @override
  void dispose() {
    // The music bridge is the owner underneath once this screen goes away, so
    // give the commands back and clear the frame instead of leaving the bar on a
    // snapshot that no owner will ever update again.
    NowPlayingService.unregister(this);
    NowPlayingService.publish(null);
    _saveProgress();
    _progressTimer?.cancel();
    AudiobookSettings.changeNotifier.removeListener(_onSettingsChanged);
    AppThemeService.currentPalette.removeListener(_onSettingsChanged);
    for (final s in _playerSubscriptions) {
      s.cancel();
    }
    _playerSubscriptions.clear();
    _player?.dispose();
    _discAnimController.dispose();
    TorrentStreamService().cleanup();
    DiscordRpcService.instance.clearToIdle();
    super.dispose();
  }

  void _saveProgress() {
    if (_player != null && _duration > Duration.zero) {
      AudiobookProgressService.instance.saveProgress(
        audiobook: widget.audiobook,
        chapters: widget.chapters,
        chapterIndex: _currentChapterIndex,
        position: _position,
        duration: _duration,
      );
    }
  }

  Future<void> _initChapter(int index) async {
    if (index < 0 || index >= widget.chapters.length) return;

    _saveProgress();

    for (final s in _playerSubscriptions) {
      s.cancel();
    }
    _playerSubscriptions.clear();

    if (_player != null) {
      await _player!.dispose();
      _player = null;
    }

    setState(() {
      _currentChapterIndex = index;
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = 'Preparing ${widget.chapters[index].title}...';
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    _publishNowPlaying();

    final chapter = widget.chapters[index];
    String? streamUrl;

    try {
      if (chapter.isTorrent) {
        final useDebrid = await DebridService().isDebridActiveForStreams();
        if (useDebrid) {
          final activeService = await DebridService().getSelectedService();
          if (!mounted) return;
          setState(() => _statusMessage = 'Resolving audio via $activeService cloud...');

          final debridFiles = await DebridService().resolveMagnet(
            magnet: chapter.url,
            fileIndex: chapter.torrentFileIndex,
            filename: chapter.title,
          );

          if (debridFiles.isEmpty || debridFiles.first.downloadUrl.isEmpty) {
            throw Exception('$activeService could not resolve audio stream.');
          }

          streamUrl = debridFiles.first.downloadUrl;
        } else {
          setState(() => _statusMessage = 'Fetching torrent metadata & peers...');
          streamUrl = await TorrentStreamService().streamTorrent(
            chapter.url,
            fileIdx: chapter.torrentFileIndex,
          );
        }
      } else {
        streamUrl = chapter.url;
      }

      if (streamUrl == null || streamUrl.isEmpty) {
        throw Exception('Audio stream URL could not be resolved.');
      }

      final isLocal = !streamUrl.startsWith('http://') && !streamUrl.startsWith('https://');
      final player = Player();

      final Media media;
      if (isLocal) {
        media = Media(File(streamUrl).uri.toString());
      } else {
        final sanitizedUrlStr = streamUrl.contains('::')
            ? streamUrl.replaceAll('::', '%3A%3A')
            : streamUrl;
        final cleanUri = Uri.parse(sanitizedUrlStr);

        final headers = <String, String>{
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        };
        if (chapter.httpHeaders != null) {
          headers.addAll(chapter.httpHeaders!);
        }

        media = Media(cleanUri.toString(), httpHeaders: headers);
      }

      _playerSubscriptions.addAll([
        player.stream.playing.listen((playing) {
          if (mounted) {
            setState(() => _isPlaying = playing);
            _updateDiscordRpc(isPaused: !playing);
            _publishNowPlaying();
            if (playing && !_discAnimController.isAnimating) {
              _discAnimController.repeat();
            } else if (!playing && _discAnimController.isAnimating) {
              _discAnimController.stop();
            }
          }
        }),
        player.stream.position.listen((pos) {
          if (mounted) {
            setState(() => _position = pos);
            _publishNowPlaying();
          }
        }),
        player.stream.duration.listen((dur) {
          if (mounted && dur > Duration.zero) {
            setState(() {
              _duration = dur;
              _isLoading = false;
            });
            _updateDiscordRpc();
            _publishNowPlaying();
          }
        }),
        player.stream.completed.listen((completed) {
          if (completed && mounted) {
            if (_autoplayNext && _currentChapterIndex < widget.chapters.length - 1) {
              _initChapter(_currentChapterIndex + 1);
            }
          }
        }),
        player.stream.error.listen((err) {
          if (PlayerSettings.isNonFatalError(err)) {
            debugPrint('[AudiobookPlayer] Ignored non-fatal error: $err');
            return;
          }
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'Playback Error: $err';
            });
          }
        }),
      ]);

      await player.open(media);
      await player.setVolume(_volume * 100.0);
      await player.setRate(_playbackSpeed);

      // Auto-seek if resuming initial position
      if (!_hasRestoredPosition &&
          index == widget.initialChapterIndex &&
          widget.initialPosition != null &&
          widget.initialPosition! > Duration.zero) {
        await player.seek(widget.initialPosition!);
        _hasRestoredPosition = true;
      }

      if (!mounted) return;

      setState(() {
        _player = player;
        _isLoading = false;
        _isPlaying = true;
      });
      _publishNowPlaying();

      _discAnimController.repeat();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Playback Error: $e';
      });
    }
  }

  void _togglePlayPause() {
    if (_player == null) return;

    if (_isPlaying) {
      _player!.pause();
      _discAnimController.stop();
      setState(() => _isPlaying = false);
    } else {
      _player!.play();
      _discAnimController.repeat();
      setState(() => _isPlaying = true);
    }
    // Paused playback produces no position ticks, so the bar would otherwise keep
    // the play state from before the tap.
    _publishNowPlaying();
  }

  void _seekRelative(int seconds) {
    if (_player == null) return;
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    _player!.seek(clamped);
  }

  void _cycleSpeed() {
    final nextIdx = (_speeds.indexOf(_playbackSpeed) + 1) % _speeds.length;
    final newSpeed = _speeds[nextIdx];
    setState(() => _playbackSpeed = newSpeed);
    _player?.setRate(newSpeed);
  }

  void _showPlayerCustomizer(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final tokens = context.tokens;

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: tokens.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 490),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune_rounded, color: palette.primaryColor, size: 20),
                      const SizedBox(width: 10),
                      const Text(
                        'Audio Player Style & Studio',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: Colors.white.withValues(alpha: 0.08)),
                  const SizedBox(height: 12),

                  const Text('Select Player Design Preset', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<AudiobookPlayerPreset>(
                    valueListenable: AudiobookSettings.selectedPlayerPreset,
                    builder: (context, currentPreset, _) {
                      return SegmentedTabs<AudiobookPlayerPreset>(
                        semanticsLabel: 'Audio player design preset',
                        selected: currentPreset,
                        onSelected: AudiobookSettings.setSelectedPlayerPreset,
                        options: [
                          for (final preset in AudiobookPlayerPreset.values)
                            SegmentedTabOption(
                              value: preset,
                              label: preset.label,
                            ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 14),

                  const Text('Seek Bar Scrubber Style', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<AudiobookSeekbarStyle>(
                    valueListenable: AudiobookSettings.customSeekbarStyle,
                    builder: (context, currentStyle, _) {
                      return SegmentedTabs<AudiobookSeekbarStyle>(
                        semanticsLabel: 'Seek bar scrubber style',
                        selected: currentStyle,
                        onSelected: AudiobookSettings.setCustomSeekbarStyle,
                        options: [
                          for (final style in AudiobookSeekbarStyle.values)
                            SegmentedTabOption(
                              value: style,
                              label: style.label,
                            ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 14),

                  const Text('Play / Pause Button Style', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<AudiobookPlayButtonStyle>(
                    valueListenable: AudiobookSettings.customPlayButtonStyle,
                    builder: (context, currentStyle, _) {
                      return SegmentedTabs<AudiobookPlayButtonStyle>(
                        semanticsLabel: 'Play pause button style',
                        selected: currentStyle,
                        onSelected: AudiobookSettings.setCustomPlayButtonStyle,
                        options: [
                          for (final style in AudiobookPlayButtonStyle.values)
                            SegmentedTabOption(
                              value: style,
                              label: style.label,
                            ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 16),
                  Divider(color: Colors.white.withValues(alpha: 0.08)),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.primaryColor.withValues(alpha: 0.15),
                        foregroundColor: palette.primaryColor,
                        side: BorderSide(color: palette.primaryColor.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.dashboard_customize_rounded, size: 18),
                      label: const Text('Open Drag & Drop Player Studio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AudiobookPlayerStudioPage()),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCover = widget.audiobook.coverImage.isNotEmpty;
    final currentChapter = widget.chapters.isNotEmpty && _currentChapterIndex < widget.chapters.length
        ? widget.chapters[_currentChapterIndex]
        : null;

    final palette = AppThemeService.currentPalette.value;
    final preset = AudiobookSettings.selectedPlayerPreset.value;
    final tokens = context.tokens;

    final screenSize = MediaQuery.sizeOf(context);
    final isDesktop = screenSize.width >= 800;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          alignment: Alignment.center,
          children: [
            // Dismissible Scrim with blur
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(color: Colors.black.withValues(alpha: 0.65)),
                ),
              ),
            ),

            // Floating Modal Window
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 680,
                  maxHeight: math.min(780, screenSize.height * 0.90),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    // A raised modal, not a menu: [surface] is the darkest of the
                    // three steps, so the glass island and the search field — both
                    // [surface] — keep reading as panels on top of this.
                    color: tokens.surface,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.75),
                        blurRadius: 40,
                        spreadRadius: 8,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      children: [
                        // Background ambient cover blur & atmosphere
                        if (hasCover && widget.audiobook.coverImage.trim().isNotEmpty)
                          Positioned.fill(
                            child: Opacity(
                              opacity: 0.22,
                              child: CachedNetworkImage(
                                imageUrl: widget.audiobook.coverImage.trim(),
                                cacheManager: AppImageCache.manager,
                                httpHeaders: const {
                                  'User-Agent':
                                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                                },
                                fit: BoxFit.cover,
                                placeholder: (_, __) => const SizedBox.shrink(),
                                errorWidget: (_, __, ___) => const SizedBox.shrink()),
                            ),
                          ),
                        Positioned.fill(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
                            child: Container(color: Colors.black.withValues(alpha: 0.68)),
                          ),
                        ),

                        // Main Modal Content
                        Column(
                          children: [
                            // Top App Bar
                            _buildTopAppBar(context, palette, isDesktop: true),

                            // Main Content Rendered by Selected Player Preset
                            Expanded(
                              child: _buildPlayerContentByPreset(preset, false, hasCover, currentChapter, palette),
                            ),
                          ],
                        ),

                        // Sliding Premade Chapters Drawer Overlay
                        if (_showChaptersDrawer)
                          Positioned.fill(
                            child: _buildPremadeChaptersDrawer(palette),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: tokens.bg,
      body: Stack(
        children: [
          // Background ambient cover blur & atmosphere
          if (hasCover && widget.audiobook.coverImage.trim().isNotEmpty)
            Positioned.fill(
              child: Opacity(
                opacity: 0.22,
                child: CachedNetworkImage(
                  imageUrl: widget.audiobook.coverImage.trim(),
                  cacheManager: AppImageCache.manager,
                  httpHeaders: const {
                    'User-Agent':
                        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  },
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const SizedBox.shrink(),
                  errorWidget: (_, __, ___) => const SizedBox.shrink()),
              ),
            ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
              child: Container(color: Colors.black.withValues(alpha: 0.68)),
            ),
          ),

          // Main Layout
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;

                return Column(
                  children: [
                    // Top App Bar
                    _buildTopAppBar(context, palette),

                    // Main Content Rendered by Selected Player Preset
                    Expanded(
                      child: _buildPlayerContentByPreset(preset, isWide, hasCover, currentChapter, palette),
                    ),
                  ],
                );
              },
            ),
          ),

          // Sliding Premade Chapters Drawer Overlay
          if (_showChaptersDrawer)
            Positioned.fill(
              child: _buildPremadeChaptersDrawer(palette),
            ),
        ],
      ),
    );
  }

  // ── Top Header Bar ──
  Widget _buildTopAppBar(BuildContext context, AppThemePalette palette, {bool isDesktop = false}) {
    final screenW = MediaQuery.sizeOf(context).width;
    final isMobile = screenW < 560;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 8),
      child: Row(
        children: [
          _PlayerIconButton(
            icon: isDesktop ? Icons.close_rounded : Icons.arrow_back_ios_new_rounded,
            palette: palette,
            size: isMobile ? 20 : 24,
            onTap: () => Navigator.pop(context),
          ),
          SizedBox(width: isMobile ? 8 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.audiobook.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isMobile ? 14.5 : 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Builder(
                  builder: (context) {
                    final isTorrent = widget.audiobook.source.toLowerCase().contains('audiobookbay');
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isTorrent) ...[
                          // #FFB74D is the Material Amber 300 warning shade, the same
                          // role `tokens.warning` carries — the source badge is a
                          // status, not an accent, so it stays palette-independent.
                          Icon(
                            Icons.warning_amber_rounded,
                            color: context.tokens.warning,
                            size: 11,
                          ),
                          const SizedBox(width: 3),
                        ],
                        Flexible(
                          child: Text(
                            isTorrent ? 'AUDIOBOOKBAY (TORRENT)' : widget.audiobook.source.toUpperCase(),
                            style: TextStyle(
                              color: isTorrent ? context.tokens.warning : palette.primaryColor,
                              fontSize: isMobile ? 9.5 : 11,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          SizedBox(width: isMobile ? 6 : 10),
          // Autoplay Switch
          Container(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 10, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isMobile) ...[
                  const Text(
                    'Autoplay',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Transform.scale(
                  scale: isMobile ? 0.75 : 0.85,
                  child: Switch(
                    value: _autoplayNext,
                    onChanged: (val) => setState(() => _autoplayNext = val),
                    activeColor: palette.primaryColor,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: isMobile ? 4 : 8),
          // Customizer Button
          _PlayerIconButton(
            icon: Icons.tune_rounded,
            size: isMobile ? 20 : 24,
            palette: palette,
            tooltip: 'Customize Audio Player',
            onTap: () => _showPlayerCustomizer(context),
          ),
          SizedBox(width: isMobile ? 4 : 6),
          // Chapters Button
          _PlayerIconButton(
            icon: Icons.format_list_bulleted_rounded,
            size: isMobile ? 20 : 24,
            palette: palette,
            tooltip: 'Chapters List',
            onTap: () => setState(() => _showChaptersDrawer = true),
          ),
        ],
      ),
    );
  }

  // ── Multi-Player Preset Dispatcher ──
  Widget _buildPlayerContentByPreset(
    AudiobookPlayerPreset preset,
    bool isWide,
    bool hasCover,
    AudiobookChapter? currentChapter,
    AppThemePalette palette,
  ) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: palette.primaryColor),
            const SizedBox(height: 18),
            Text(
              _statusMessage,
              style: const TextStyle(color: Colors.white70, fontSize: 13.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _initChapter(_currentChapterIndex),
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                label: const Text('Retry Chapter', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: palette.primaryColor),
              ),
            ],
          ),
        ),
      );
    }

    if (preset == AudiobookPlayerPreset.vinylStudio) {
      return _buildVinylStudioPlayer(isWide, hasCover, currentChapter, palette);
    }
    if (preset == AudiobookPlayerPreset.minimalCapsule) {
      return _buildMinimalCapsulePlayer(isWide, hasCover, currentChapter, palette);
    }
    if (preset == AudiobookPlayerPreset.immersiveCanvas) {
      return _buildImmersiveCanvasPlayer(isWide, hasCover, currentChapter, palette);
    }
    if (preset == AudiobookPlayerPreset.customStudio) {
      return _buildCustomStudioPlayer(isWide, hasCover, currentChapter, palette);
    }
    // Default: Modern Glass Island
    return _buildModernGlassPlayer(isWide, hasCover, currentChapter, palette);
  }

  // ── 1. Modern Glass Island Player ──
  Widget _buildModernGlassPlayer(
    bool isWide,
    bool hasCover,
    AudiobookChapter? currentChapter,
    AppThemePalette palette,
  ) {
    final seekStyle = AudiobookSettings.customSeekbarStyle.value;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              // Cover Art with 3D Float Shadow
              _buildCoverArtCard(hasCover, palette, size: isWide ? 220 : 160),
              const SizedBox(height: 18),
              _buildTitleSection(currentChapter),
              const SizedBox(height: 18),

              // Glass Control Island
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  // 0.88 sat between the scale's `overlayHover` (0.15) and
                  // `textPrimary` (0.90); the scale tops out at 0.90 because it was
                  // cut for text, not scrims, so this panel takes the highest
                  // defined step. Going opaque instead would flatten the blurred
                  // cover art it is deliberately floating over.
                  color: context.tokens.surfaceOverlay.withValues(alpha: ZplayOpacity.textPrimary),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: palette.primaryColor.withValues(alpha: 0.22),
                      blurRadius: 28,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Waveform Seekbar
                    AudiobookWaveformSeekbar(
                      position: _position,
                      duration: _duration,
                      isPlaying: _isPlaying,
                      style: seekStyle,
                      onSeek: (pos) => _player?.seek(pos),
                    ),
                    const SizedBox(height: 12),

                    // Controls Row
                    _buildMainControlsCluster(palette),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // ── 2. Vinyl Turntable Studio Player ──
  Widget _buildVinylStudioPlayer(
    bool isWide,
    bool hasCover,
    AudiobookChapter? currentChapter,
    AppThemePalette palette,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Spinning Vinyl Disc
              _buildVinylDiscWidget(hasCover, palette, size: isWide ? 240 : 190),
              const SizedBox(height: 18),
              _buildTitleSection(currentChapter),
              const SizedBox(height: 18),

              // Animated VU Meters
              _buildVuMetersWidget(palette),
              const SizedBox(height: 16),

              // Waveform Seekbar
              AudiobookWaveformSeekbar(
                position: _position,
                duration: _duration,
                isPlaying: _isPlaying,
                style: AudiobookSeekbarStyle.audioWaveformCanvas,
                onSeek: (pos) => _player?.seek(pos),
              ),
              const SizedBox(height: 14),

              // Controls Cluster
              _buildMainControlsCluster(palette),
            ],
          ),
        ),
      ),
    );
  }

  // ── 3. Minimalist Focus Capsule Player ──
  Widget _buildMinimalCapsulePlayer(
    bool isWide,
    bool hasCover,
    AudiobookChapter? currentChapter,
    AppThemePalette palette,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              // The token doc files a sheet under [surface], not [surfaceOverlay];
              // 0.94 was an almost-opaque carve-out and [textPrimary] (0.90) is
              // the top of the defined scale, so this is the nearest step.
              color: context.tokens.surface.withValues(alpha: ZplayOpacity.textPrimary),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: palette.primaryColor.withValues(alpha: 0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: palette.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 30,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: hasCover
                          ? CachedNetworkImage(imageUrl: widget.audiobook.coverImage,
                                               cacheManager: AppImageCache.manager,
                                               memCacheWidth: 144,
                                               width: 48, height: 48, fit: BoxFit.cover)
                          : Container(width: 48, height: 48, color: Colors.white12),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentChapter?.title ?? 'Chapter ${_currentChapterIndex + 1}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.5),
                          ),
                          Text(
                            widget.audiobook.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AudiobookWaveformSeekbar(
                  position: _position,
                  duration: _duration,
                  isPlaying: _isPlaying,
                  style: AudiobookSeekbarStyle.gradientProgress,
                  onSeek: (pos) => _player?.seek(pos),
                ),
                const SizedBox(height: 12),
                _buildMainControlsCluster(palette),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 4. Immersive Canvas Studio Player ──
  Widget _buildImmersiveCanvasPlayer(
    bool isWide,
    bool hasCover,
    AudiobookChapter? currentChapter,
    AppThemePalette palette,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              // Oversized 3D Card
              _buildCoverArtCard(hasCover, palette, size: isWide ? 260 : 180),
              const SizedBox(height: 20),
              _buildTitleSection(currentChapter),
              const SizedBox(height: 20),
              AudiobookWaveformSeekbar(
                position: _position,
                duration: _duration,
                isPlaying: _isPlaying,
                style: AudiobookSeekbarStyle.audioWaveformCanvas,
                onSeek: (pos) => _player?.seek(pos),
              ),
              const SizedBox(height: 16),
              _buildMainControlsCluster(palette),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── 5. Custom Drag & Drop Studio Player ──
  Widget _buildCustomStudioPlayer(
    bool isWide,
    bool hasCover,
    AudiobookChapter? currentChapter,
    AppThemePalette palette,
  ) {
    final order = AudiobookSettings.componentOrder.value;
    final seekStyle = AudiobookSettings.customSeekbarStyle.value;
    final artStyle = AudiobookSettings.customArtworkStyle.value;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            children: order.map((key) {
              switch (key) {
                case 'artwork':
                  if (artStyle == AudiobookArtworkStyle.hidden) return const SizedBox.shrink();
                  if (artStyle == AudiobookArtworkStyle.vinylDisc) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildVinylDiscWidget(hasCover, palette, size: isWide ? 220 : 170),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildCoverArtCard(hasCover, palette, size: isWide ? 210 : 160),
                  );
                case 'title':
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildTitleSection(currentChapter),
                  );
                case 'seekbar':
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: AudiobookWaveformSeekbar(
                      position: _position,
                      duration: _duration,
                      isPlaying: _isPlaying,
                      style: seekStyle,
                      onSeek: (pos) => _player?.seek(pos),
                    ),
                  );
                case 'mainControls':
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _buildMainControlsCluster(palette),
                  );
                case 'secondaryControls':
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildSpeedSelectorPill(palette),
                        const SizedBox(width: 16),
                        _VolumeButton(
                          volume: _volume,
                          palette: palette,
                          onVolumeChanged: (v) {
                            setState(() => _volume = v);
                            _player?.setVolume(v * 100.0);
                          },
                        ),
                      ],
                    ),
                  );
                case 'chaptersButton':
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _showChaptersDrawer = true),
                      icon: Icon(Icons.format_list_bulleted_rounded, color: palette.primaryColor, size: 18),
                      label: const Text('Open Chapters Panel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: palette.primaryColor.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                  );
                default:
                  return const SizedBox.shrink();
              }
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ── Cover Art Card ──
  Widget _buildCoverArtCard(bool hasCover, AppThemePalette palette, {double size = 200}) {
    final tokens = context.tokens;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: palette.primaryColor.withValues(alpha: _isPlaying ? 0.45 : 0.25),
            blurRadius: _isPlaying ? 32 : 18,
            spreadRadius: _isPlaying ? 3 : 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: hasCover
            ? CachedNetworkImage(
                imageUrl: widget.audiobook.coverImage,
                cacheManager: AppImageCache.manager,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: tokens.surface),
                errorWidget: (_, __, ___) => Container(
                  color: tokens.surface,
                  child: const Icon(Icons.headphones_rounded, size: 64, color: Colors.white54),
                ))
            : Container(
                color: tokens.surface,
                child: const Icon(Icons.headphones_rounded, size: 64, color: Colors.white54),
              ),
      ),
    );
  }

  // ── Spinning Vinyl Disc Widget ──
  Widget _buildVinylDiscWidget(bool hasCover, AppThemePalette palette, {double size = 220}) {
    final tokens = context.tokens;
    return AnimatedBuilder(
      animation: _discAnimController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _discAnimController.value * 2 * 3.14159,
          child: child,
        );
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: palette.primaryColor.withValues(alpha: _isPlaying ? 0.45 : 0.2),
              blurRadius: _isPlaying ? 32 : 16,
              spreadRadius: _isPlaying ? 4 : 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (hasCover)
                CachedNetworkImage(
                  imageUrl: widget.audiobook.coverImage,
                  cacheManager: AppImageCache.manager,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    color: tokens.surface,
                    child: const Icon(Icons.headphones_rounded, size: 64, color: Colors.white54),
                  ))
              else
                Container(
                  color: tokens.surface,
                  child: const Icon(Icons.headphones_rounded, size: 64, color: Colors.white54),
                ),
              // Center Vinyl Ring Hole
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tokens.bg,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── VU Audio Meters Widget ──
  Widget _buildVuMetersWidget(AppThemePalette palette) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(16, (i) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 4,
          height: _isPlaying ? (8 + ((i % 5) * 4.5)) : 6,
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          decoration: BoxDecoration(
            color: _isPlaying ? palette.primaryColor : Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  // ── Title Section ──
  Widget _buildTitleSection(AudiobookChapter? currentChapter) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Text(
            currentChapter?.title ?? 'Chapter ${_currentChapterIndex + 1}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            'Chapter ${_currentChapterIndex + 1} of ${widget.chapters.length} • ${widget.audiobook.title}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Main Controls Cluster (Prev, Rewind, Play, Forward, Next, Speed, Volume) ──
  Widget _buildMainControlsCluster(AppThemePalette palette) {
    final playBtnStyle = AudiobookSettings.customPlayButtonStyle.value;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 560;

        final prevBtn = _PlayerIconButton(
          icon: Icons.skip_previous_rounded,
          size: isNarrow ? 24 : 28,
          palette: palette,
          tooltip: 'Previous Chapter',
          onTap: _currentChapterIndex > 0 ? () => _initChapter(_currentChapterIndex - 1) : null,
        );

        final rewBtn = _PlayerIconButton(
          icon: Icons.replay_10_rounded,
          size: isNarrow ? 24 : 28,
          palette: palette,
          tooltip: 'Rewind 10s',
          onTap: () => _seekRelative(-10),
        );

        final playButton = FocusableCard(
          onTap: _togglePlayPause,
          builder: (context, _) => _buildPlayButtonByStyle(playBtnStyle, palette),
        );

        final fwdBtn = _PlayerIconButton(
          icon: Icons.forward_10_rounded,
          size: isNarrow ? 24 : 28,
          palette: palette,
          tooltip: 'Forward 10s',
          onTap: () => _seekRelative(10),
        );

        final nextBtn = _PlayerIconButton(
          icon: Icons.skip_next_rounded,
          size: isNarrow ? 24 : 28,
          palette: palette,
          tooltip: 'Next Chapter',
          onTap: _currentChapterIndex < widget.chapters.length - 1
              ? () => _initChapter(_currentChapterIndex + 1)
              : null,
        );

        final speedPill = _buildSpeedSelectorPill(palette);

        final volumeBtn = _VolumeButton(
          volume: _volume,
          palette: palette,
          onVolumeChanged: (v) {
            setState(() => _volume = v);
            _player?.setVolume(v * 100.0);
          },
        );

        if (isNarrow) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Primary 5 Playback Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  prevBtn,
                  rewBtn,
                  playButton,
                  fwdBtn,
                  nextBtn,
                ],
              ),
              const SizedBox(height: 12),
              // Secondary Utility Row: Speed and Volume
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    speedPill,
                    volumeBtn,
                  ],
                ),
              ),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            speedPill,
            prevBtn,
            rewBtn,
            playButton,
            fwdBtn,
            nextBtn,
            volumeBtn,
          ],
        );
      },
    );
  }

  Widget _buildSpeedSelectorPill(AppThemePalette palette) {
    return InkWell(
      onTap: _cycleSpeed,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Text(
          '${_playbackSpeed}x',
          style: TextStyle(
            color: palette.primaryColor,
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildPlayButtonByStyle(AudiobookPlayButtonStyle style, AppThemePalette palette) {
    final icon = _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;
    final hoverEffect = AudiobookSettings.customHoverEffect.value;

    Widget buttonCore;
    BorderRadius borderRadius;

    if (style == AudiobookPlayButtonStyle.liquidGlassNeo) {
      borderRadius = BorderRadius.circular(20);
      final glassStyle = LiquidGlassStyle(
        shape: LiquidGlassShape.continuousRoundedRectangle(
          cornerRadius: 20,
          clipQuality: LiquidGlassClipQuality.exact,
          borderWidth: 1.6,
          lightIntensity: 1.5,
          // 0xE6 is 0.90 alpha, so this is the [textPrimary] white at its
          // existing ARGB weight. It is the glass lens's light source, not a
          // surface, but it belongs to the same "near-white" family and no
          // separate token carries it.
          lightColor: Colors.white.withValues(alpha: ZplayOpacity.textPrimary),
          lightDirection: 115,
          borderType: const OpticalBorder(
            borderSaturation: 1.5,
            ambientIntensity: 1.2,
            borderSolidity: 0.2,
            lightSpread: 0.7,
          ),
        ),
        appearance: LiquidGlassAppearance(
          color: palette.primaryColor.withValues(alpha: 0.16),
          saturation: 1.25,
          blur: const LiquidGlassBlur(sigmaX: 3.5, sigmaY: 3.5),
          shadow: LiquidGlassShadow(
            blur: 18,
            opacity: 0.45,
            color: palette.primaryColor,
          ),
        ),
        refraction: const LiquidGlassRefraction(
          magnification: 1.04,
          chromaticAberration: 0.0035,
          refractionType: OpticalRefraction(
            refraction: 1.55,
            refractionWidth: 24,
            depth: 0.85,
          ),
        ),
      );

      buttonCore = LiquidGlassLens(
        style: glassStyle,
        visibility: true,
        useImpellerBackdrop: true,
        child: Container(
          width: 58,
          height: 58,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: 34),
        ),
      );
    } else if (style == AudiobookPlayButtonStyle.roundedSquare) {
      borderRadius = BorderRadius.circular(16);
      buttonCore = Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: palette.primaryColor,
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: palette.primaryColor.withValues(alpha: 0.5),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 32),
      );
    } else if (style == AudiobookPlayButtonStyle.accentPill) {
      borderRadius = BorderRadius.circular(24);
      buttonCore = Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: palette.primaryColor,
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: palette.primaryColor.withValues(alpha: 0.4),
              blurRadius: 14,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 6),
            Text(
              _isPlaying ? 'PAUSE' : 'PLAY',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.8),
            ),
          ],
        ),
      );
    } else {
      borderRadius = BorderRadius.circular(29);
      buttonCore = Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.primaryColor,
          boxShadow: [
            BoxShadow(
              color: palette.primaryColor.withValues(alpha: 0.6),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 36),
      );
    }

    return AudiobookInteractivePhysicsButton(
      effect: hoverEffect,
      glowColor: palette.primaryColor,
      borderRadius: borderRadius,
      onTap: _togglePlayPause,
      child: buttonCore,
    );
  }

  // ── Premade Sliding Glass Chapters Drawer ──
  Widget _buildPremadeChaptersDrawer(AppThemePalette palette) {
    final filteredChapters = widget.chapters.where((c) {
      if (_chapterSearchQuery.isEmpty) return true;
      return c.title.toLowerCase().contains(_chapterSearchQuery.toLowerCase());
    }).toList();

    return GestureDetector(
      onTap: () => setState(() => _showChaptersDrawer = false),
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // Catch taps inside drawer
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.72,
                  decoration: BoxDecoration(
                    // Same reasoning as the capsule: a sheet is a [surface], and
                    // 0.92 rounds to the scale's 0.90 step.
                    color: context.tokens.surface.withValues(alpha: ZplayOpacity.textPrimary),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Column(
                    children: [
                      // Handle bar
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(top: 10, bottom: 6),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.format_list_bulleted_rounded, color: palette.primaryColor, size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  'Audiobook Chapters',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: palette.primaryColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${widget.chapters.length} CHAPTERS',
                                style: TextStyle(color: palette.primaryColor, fontSize: 10.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                              onPressed: () => setState(() => _showChaptersDrawer = false),
                            ),
                          ],
                        ),
                      ),

                      // Chapter Search Bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: context.tokens.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: TextField(
                            onChanged: (val) => setState(() => _chapterSearchQuery = val),
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Filter chapters by name...',
                              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13),
                              prefixIcon: Icon(Icons.search_rounded, color: palette.primaryColor, size: 16),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                      ),

                      // Chapters List
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: filteredChapters.length,
                          itemBuilder: (context, index) {
                            final chapter = filteredChapters[index];
                            final originalIndex = widget.chapters.indexOf(chapter);
                            final isSelected = originalIndex == _currentChapterIndex;

                            return _ChapterListItemTile(
                              chapter: chapter,
                              index: originalIndex,
                              isSelected: isSelected,
                              isPlaying: isSelected && _isPlaying,
                              palette: palette,
                              onTap: () {
                                setState(() => _showChaptersDrawer = false);
                                _initChapter(originalIndex);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerIconButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final AppThemePalette palette;
  final String? tooltip;
  final VoidCallback? onTap;

  const _PlayerIconButton({
    required this.icon,
    required this.palette,
    this.size = 24,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final padding = size <= 22 ? 7.0 : 10.0;

    final btn = Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Icon(
        icon,
        size: size,
        color: enabled ? Colors.white : Colors.white24,
      ),
    );

    return Tooltip(
      message: tooltip ?? '',
      child: AudiobookInteractivePhysicsButton(
        effect: AudiobookSettings.customHoverEffect.value,
        glowColor: palette.primaryColor,
        borderRadius: BorderRadius.circular(size + 10),
        enabled: enabled,
        onTap: onTap,
        child: btn,
      ),
    );
  }
}

class _VolumeButton extends StatefulWidget {
  final double volume;
  final AppThemePalette palette;
  final ValueChanged<double> onVolumeChanged;

  const _VolumeButton({
    required this.volume,
    required this.palette,
    required this.onVolumeChanged,
  });

  @override
  State<_VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<_VolumeButton> {
  bool _showSlider = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlayerIconButton(
          icon: widget.volume == 0
              ? Icons.volume_off_rounded
              : (widget.volume > 0.5 ? Icons.volume_up_rounded : Icons.volume_down_rounded),
          size: 22,
          palette: widget.palette,
          tooltip: 'Volume',
          onTap: () {
            setState(() => _showSlider = !_showSlider);
          },
        ),
        if (_showSlider)
          SizedBox(
            width: 80,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                activeTrackColor: widget.palette.primaryColor,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: widget.volume,
                min: 0.0,
                max: 1.0,
                onChanged: widget.onVolumeChanged,
              ),
            ),
          ),
      ],
    );
  }
}

class _ChapterListItemTile extends StatelessWidget {
  final AudiobookChapter chapter;
  final int index;
  final bool isSelected;
  final bool isPlaying;
  final AppThemePalette palette;
  final VoidCallback onTap;

  const _ChapterListItemTile({
    required this.chapter,
    required this.index,
    required this.isSelected,
    required this.isPlaying,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: FocusableCard(
        onTap: onTap,
        builder: (context, state) {
          final scale = state.pressed ? 0.98 : (state.highlighted ? 1.015 : 1.0);

          return AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 150),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? palette.primaryColor.withValues(alpha: 0.22)
                    : (state.highlighted ? Colors.white.withValues(alpha: 0.08) : Colors.transparent),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? palette.primaryColor.withValues(alpha: 0.6)
                      : (state.highlighted ? Colors.white.withValues(alpha: 0.12) : Colors.transparent),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? (isPlaying ? Icons.graphic_eq_rounded : Icons.pause_circle_filled_rounded)
                        : Icons.play_circle_outline_rounded,
                    color: isSelected ? palette.primaryColor : Colors.white54,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      chapter.title,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
