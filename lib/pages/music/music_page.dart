import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/music/music_track.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/layout/form_factor.dart';
import '../../services/music/music_download_service.dart';
import '../../services/music/music_library_service.dart';
import '../../services/music/music_player_controller.dart';
import '../../services/music/music_service.dart';
import '../../services/music/music_settings.dart';
import '../../services/playback/music_now_playing_bridge.dart';
import '../../shell/app_shell_scope.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/hero_meta_line.dart';
import '../../widgets/common/pill_button.dart';
import '../../widgets/common/performance_liquid_lens.dart';
import '../../widgets/common/slider_arrow.dart';
import '../../widgets/common/tab_strip.dart';
import '../../widgets/music/music_interactive_physics_button.dart';
import '../../widgets/music/music_waveform_seekbar.dart';
import '../settings/appearance/music_player_studio_page.dart';
import '../settings/appearance/music_settings_page.dart';
import '../../services/storage/app_image_cache.dart';

/// Music's five views. Declaration order is the switcher order.
enum MusicView { home, search, browse, radio, library }

extension MusicViewX on MusicView {
  String get label => switch (this) {
        MusicView.home => 'Home',
        MusicView.search => 'Search',
        MusicView.browse => 'Browse',
        MusicView.radio => 'Radio',
        MusicView.library => 'Library',
      };
}

/// Built once: the labels are constants, and rebuilding them on every switch
/// would churn the control for nothing.
final List<TabStripOption<MusicView>> _viewOptions = [
  for (final view in MusicView.values)
    TabStripOption<MusicView>(value: view, label: view.label),
];

class MusicPage extends StatefulWidget {
  const MusicPage({super.key});

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  final MusicService _musicService = MusicService.instance;
  final MusicPlayerController _playerController = MusicPlayerController.instance;
  final MusicLibraryService _libraryService = MusicLibraryService.instance;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();

  /// The view on screen, and the selection the header's switcher reports. The
  /// switcher is the only writer: the sidebar the shell replaced used to be
  /// what set Browse, Radio and Library, and without it those three views had
  /// no way to be reached at all. [_onSearchChanged] moves it too, because a
  /// query in the field is the switcher's own Search row.
  MusicView _view = MusicView.home;

  Map<String, List<MusicTrack>> _sections = {};
  List<MusicArtist> _trendingArtists = [];
  List<MusicAlbum> _newReleases = [];
  List<MusicPlaylist> _curatedPlaylists = [];
  MusicTrack? _heroTrack;

  MusicSearchData _searchData = MusicSearchData.empty;
  MusicArtistDetails? _activeArtistModal;
  MusicAlbumDetails? _activeAlbumModal;
  MusicPlaylistDetails? _activeCuratedPlaylistModal;
  UserPlaylist? _activeUserPlaylistModal;

  bool _isLoading = true;
  bool _isSearching = false;
  String _activeQuery = '';
  String _selectedFilter = 'All';
  Timer? _debounceTimer;

  bool _isPlayerExpanded = false;
  bool _showQueueDrawer = false;
  bool _showLyricsDrawer = false;
  bool _showShortcutsModal = false;
  bool _showDownloadsModal = false;
  String? _toastMessage;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _playerController.addListener(_onStateChanged);
    _libraryService.addListener(_onStateChanged);
    MusicDownloadService.instance.addListener(_onStateChanged);
    MusicSettings.changeNotifier.addListener(_onStateChanged);
    AppThemeService.currentPalette.addListener(_onStateChanged);
    MusicNowPlayingBridge.expandRequests.addListener(_onExpandRequested);
    _libraryService.init();
    MusicDownloadService.instance.init();
    _loadMusicData();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _toastTimer?.cancel();
    _playerController.removeListener(_onStateChanged);
    _libraryService.removeListener(_onStateChanged);
    MusicDownloadService.instance.removeListener(_onStateChanged);
    MusicSettings.changeNotifier.removeListener(_onStateChanged);
    AppThemeService.currentPalette.removeListener(_onStateChanged);
    MusicNowPlayingBridge.expandRequests.removeListener(_onExpandRequested);
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  /// The shell's bar cannot reach this page's expansion flag and must not import
  /// it, so its expand tap arrives through the bridge instead.
  void _onExpandRequested() {
    if (!mounted || !_playerController.hasTrack) return;
    setState(() => _isPlayerExpanded = true);
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toastMessage = message);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  Future<void> _loadMusicData() async {
    setState(() => _isLoading = true);

    try {
      final sectionsFuture = _musicService.fetchFeaturedSections();
      final artistsFuture = _musicService.fetchTrendingArtists();
      final releasesFuture = _musicService.fetchNewReleases();
      final playlistsFuture = _musicService.fetchCuratedPlaylists();

      final results = await Future.wait([
        sectionsFuture,
        artistsFuture,
        releasesFuture,
        playlistsFuture,
      ]);

      final sections = results[0] as Map<String, List<MusicTrack>>;
      final artists = results[1] as List<MusicArtist>;
      final releases = results[2] as List<MusicAlbum>;
      final playlists = results[3] as List<MusicPlaylist>;

      MusicTrack? hero;
      if (sections.isNotEmpty && sections.values.first.isNotEmpty) {
        hero = sections.values.first.first;
      }

      if (mounted) {
        setState(() {
          _sections = sections;
          _trendingArtists = artists;
          _newReleases = releases;
          _curatedPlaylists = playlists;
          _heroTrack = hero;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading music data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchData = MusicSearchData.empty;
        _activeQuery = '';
        // The band under the header carries the Home row, so an emptied field
        // returns to the featured view rather than leaving the search view
        // selected behind an empty field.
        _view = MusicView.home;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() {
        _isSearching = true;
        _activeQuery = trimmed;
        _view = MusicView.search;
      });

      final results = await _musicService.searchFull(trimmed);

      if (mounted) {
        setState(() {
          _searchData = results;
          _isSearching = false;
        });
      }
    });
  }

  void _onGenreTap(String query) {
    _searchController.text = query;
    _onSearchChanged(query);
  }

  Future<void> _openArtistModal(String artistId) async {
    _showToast('Loading artist details...');
    final details = await _musicService.fetchArtistDetails(artistId);
    if (details != null && mounted) {
      setState(() {
        _activeArtistModal = details;
      });
    }
  }

  Future<void> _openAlbumModal(String albumId) async {
    _showToast('Loading album...');
    final details = await _musicService.fetchAlbumDetails(albumId);
    if (details != null && mounted) {
      setState(() {
        _activeAlbumModal = details;
      });
    }
  }

  Future<void> _openCuratedPlaylistModal(String playlistId) async {
    _showToast('Loading playlist...');
    final details = await _musicService.fetchPlaylistDetails(playlistId);
    if (details != null && mounted) {
      setState(() {
        _activeCuratedPlaylistModal = details;
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (_searchFocusNode.hasFocus) return;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      _playerController.togglePlayPause();
    } else if (key == LogicalKeyboardKey.keyJ) {
      final newPos = _playerController.position - const Duration(seconds: 5);
      _playerController.seekTo(newPos.inSeconds < 0 ? Duration.zero : newPos);
      _showToast('Seek -5s');
    } else if (key == LogicalKeyboardKey.keyL) {
      final newPos = _playerController.position + const Duration(seconds: 5);
      _playerController.seekTo(newPos);
      _showToast('Seek +5s');
    } else if (key == LogicalKeyboardKey.keyM) {
      _playerController.setVolume(_playerController.volume > 0 ? 0.0 : 1.0);
      _showToast(_playerController.volume == 0 ? 'Muted' : 'Unmuted');
    } else if (key == LogicalKeyboardKey.keyQ) {
      setState(() => _showQueueDrawer = !_showQueueDrawer);
    } else if (key == LogicalKeyboardKey.keyF) {
      setState(() => _isPlayerExpanded = !_isPlayerExpanded);
    } else if (key == LogicalKeyboardKey.slash ||
        (HardwareKeyboard.instance.isShiftPressed &&
            key == LogicalKeyboardKey.slash)) {
      setState(() => _showShortcutsModal = !_showShortcutsModal);
    } else if (key == LogicalKeyboardKey.escape) {
      // Escape unwinds whatever overlay is open and stops there. Leaving Music is
      // the shell rail's job now, and a pop from inside a slot would take the
      // shell route with it.
      if (_isPlayerExpanded) {
        setState(() => _isPlayerExpanded = false);
      } else if (_showQueueDrawer) {
        setState(() => _showQueueDrawer = false);
      } else if (_showLyricsDrawer) {
        setState(() => _showLyricsDrawer = false);
      } else if (_showShortcutsModal) {
        setState(() => _showShortcutsModal = false);
      } else if (_showDownloadsModal) {
        setState(() => _showDownloadsModal = false);
      } else if (_activeArtistModal != null ||
          _activeAlbumModal != null ||
          _activeCuratedPlaylistModal != null ||
          _activeUserPlaylistModal != null) {
        setState(() {
          _activeArtistModal = null;
          _activeAlbumModal = null;
          _activeCuratedPlaylistModal = null;
          _activeUserPlaylistModal = null;
          _showDownloadsModal = false;
        });
      }
    }
  }

  void _showCreatePlaylistDialog({MusicTrack? initialTrack}) {
    final controller = TextEditingController();
    final tokens = context.tokens;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.surfaceOverlay,
        shape: RoundedRectangleBorder(
          borderRadius: ZplayRadius.lgAll,
          side: BorderSide(color: tokens.accent.withValues(alpha: 0.3)),
        ),
        title: Row(
          children: [
            Icon(
              Icons.playlist_add_rounded,
              color: tokens.accent,
              size: 26,
            ),
            const SizedBox(width: ZplaySpacing.s8),
            Text(
              'New Playlist',
              style: ZplayType.title.toStyle(color: tokens.textPrimary),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (initialTrack != null) ...[
              Row(
                children: [
                  ClipRRect(
                    borderRadius: ZplayRadius.smAll,
                    child: CachedNetworkImage(
                      imageUrl: initialTrack.coverUrl,
                      cacheManager: AppImageCache.manager,
                      memCacheWidth: 120,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover),
                  ),
                  const SizedBox(width: ZplaySpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          initialTrack.title,
                          style: ZplayType.label.toStyle(color: tokens.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          initialTrack.artist,
                          style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ZplaySpacing.s16),
            ],
            TextField(
              controller: controller,
              autofocus: true,
              style: ZplayType.body.toStyle(color: tokens.textPrimary),
              decoration: InputDecoration(
                hintText: 'Enter playlist title...',
                hintStyle: ZplayType.body.toStyle(color: tokens.textMuted),
                filled: true,
                fillColor: tokens.surface,
                border: const OutlineInputBorder(
                  borderRadius: ZplayRadius.smAll,
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: ZplayRadius.smAll,
                  borderSide: BorderSide(color: tokens.accent),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: ZplayType.label.toStyle(color: tokens.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tokens.accent,
              shape: const RoundedRectangleBorder(
                borderRadius: ZplayRadius.smAll,
              ),
            ),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final pl = await _libraryService.createPlaylist(name);
                if (initialTrack != null) {
                  await _libraryService.addTrackToPlaylist(pl.id, initialTrack);
                  _showToast('Added "${initialTrack.title}" to "$name"');
                } else {
                  _showToast('Created playlist "$name"');
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(
              'Create',
              style: ZplayType.label.toStyle(color: tokens.onAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddToPlaylistMenu(MusicTrack track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final playlists = _libraryService.userPlaylists;
        final tokens = context.tokens;
        return PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            margin: const EdgeInsets.all(ZplaySpacing.s16),
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay.withValues(alpha: 0.95),
              borderRadius: ZplayRadius.xlAll,
              border: Border.all(color: tokens.borderStrong),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 36,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            padding: const EdgeInsets.all(ZplaySpacing.s20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: ZplayRadius.smAll,
                      child: CachedNetworkImage(
                        imageUrl: track.coverUrl,
                        cacheManager: AppImageCache.manager,
                        memCacheWidth: 156,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover),
                    ),
                    const SizedBox(width: ZplaySpacing.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: ZplaySpacing.s2),
                          Text(
                            track.artist,
                            style: ZplayType.label.toStyle(color: tokens.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: tokens.textEmphasis,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: ZplaySpacing.s16),
                Divider(color: tokens.borderDefault),
                const SizedBox(height: ZplaySpacing.s8),

                // Quick Offline Download Action
                Builder(
                  builder: (context) {
                    final isDownloaded = MusicDownloadService.instance.isDownloaded(track.id);
                    final isQueued = MusicDownloadService.instance.isQueued(track.id);

                    return InkWell(
                      onTap: () async {
                        Navigator.pop(ctx);
                        if (isDownloaded) {
                          await MusicDownloadService.instance.deleteDownloadedTrack(track.id);
                          _showToast('Removed "${track.title}" from downloads');
                        } else if (!isQueued) {
                          MusicDownloadService.instance.queueTrack(track);
                          _showToast('Added "${track.title}" to download queue');
                        }
                      },
                      borderRadius: ZplayRadius.mdAll,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s12,
                          vertical: ZplaySpacing.s8,
                        ),
                        decoration: BoxDecoration(
                          color: isDownloaded
                              ? tokens.info.withValues(alpha: ZplayOpacity.overlayHover)
                              : tokens.borderSubtle,
                          borderRadius: ZplayRadius.mdAll,
                          border: Border.all(
                            color: isDownloaded
                                ? tokens.info.withValues(alpha: ZplayOpacity.textDisabled)
                                : tokens.borderDefault,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isDownloaded
                                  ? Icons.download_done_rounded
                                  : (isQueued ? Icons.hourglass_top_rounded : Icons.download_rounded),
                              color: isDownloaded ? tokens.info : tokens.textPrimary,
                              size: 20,
                            ),
                            const SizedBox(width: ZplaySpacing.s12),
                            Expanded(
                              child: Text(
                                isDownloaded
                                    ? 'Downloaded Offline (Tap to Remove)'
                                    : (isQueued ? 'Downloading / Queued...' : 'Download Track Offline'),
                                style: ZplayType.label.toStyle(
                                  color: isDownloaded ? tokens.info : tokens.textPrimary,
                                ),
                              ),
                            ),
                            if (isDownloaded)
                              Icon(Icons.delete_outline_rounded, color: tokens.danger, size: 18),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: ZplaySpacing.s12),
                Row(
                  children: [
                    Text(
                      'Save to Playlist',
                      style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showCreatePlaylistDialog(initialTrack: track);
                      },
                      icon: Icon(
                        Icons.add_rounded,
                        color: tokens.accent,
                        size: 18,
                      ),
                      label: Text(
                        'New Playlist',
                        style: ZplayType.label.toStyle(color: tokens.accent),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZplaySpacing.s12),
                if (playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.playlist_add_rounded,
                            color: tokens.textMuted,
                            size: 40,
                          ),
                          const SizedBox(height: ZplaySpacing.s8),
                          Text(
                            'No custom playlists yet',
                            style: ZplayType.body.toStyle(color: tokens.textEmphasis),
                          ),
                          const SizedBox(height: ZplaySpacing.s12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: tokens.accent,
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showCreatePlaylistDialog(initialTrack: track);
                            },
                            child: Text(
                              'Create First Playlist',
                              style: ZplayType.label.toStyle(color: tokens.onAccent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: playlists.length,
                      separatorBuilder: (_, __) => const SizedBox(height: ZplaySpacing.s8),
                      itemBuilder: (context, index) {
                        final pl = playlists[index];
                        final inPlaylist = pl.tracks.any((t) => t.id == track.id);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: ZplaySpacing.s12,
                            vertical: ZplaySpacing.s4,
                          ),
                          shape: const RoundedRectangleBorder(
                            borderRadius: ZplayRadius.mdAll,
                          ),
                          tileColor: tokens.surface,
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: tokens.accentSubtle,
                              borderRadius: ZplayRadius.smAll,
                            ),
                            child: Icon(
                              Icons.music_note_rounded,
                              color: tokens.accent,
                            ),
                          ),
                          title: Text(
                            pl.title,
                            style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                          ),
                          subtitle: Text(
                            '${pl.tracks.length} tracks',
                            style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                          ),
                          trailing: Icon(
                            inPlaylist
                                ? Icons.check_circle_rounded
                                : Icons.add_circle_outline_rounded,
                            color: inPlaylist
                                ? tokens.success
                                : tokens.textSecondary,
                          ),
                          onTap: () async {
                            if (inPlaylist) {
                              await _libraryService.removeTrackFromPlaylist(
                                pl.id,
                                track.id,
                              );
                              _showToast('Removed from "${pl.title}"');
                            } else {
                              await _libraryService.addTrackToPlaylist(
                                pl.id,
                                track,
                              );
                              _showToast('Added to "${pl.title}"');
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isDesktop(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= 900;
  }

  /// The header row's own height, per the breakpoint `_MusicTopHeader` uses.
  double _headerHeight(BuildContext context) {
    final desktop = _isDesktop(context);
    return desktop ? 68.0 : 58.0 + MediaQuery.paddingOf(context).top;
  }

  /// The height of the band under the header: its own padding, its control, its
  /// padding, and the hairline it closes with.
  static const double _viewBandHeight = 57;

  /// Top padding for a view's scroll list, so its content starts under the
  /// sticky chrome rather than behind it.
  ///
  /// Measured from the chrome rather than written down, because the header's
  /// height is not a constant: it is 68 on desktop, and below the desktop
  /// breakpoint it is 58 plus whatever status bar the platform reports. One
  /// number per view is the bug this replaced — each carried its own 75 or 80,
  /// none of which matched a header that had just grown a second row.
  double _contentTopPadding(BuildContext context) =>
      _headerHeight(context) + _viewBandHeight;

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop(context);
    final tokens = context.tokens;

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: tokens.bg,
        body: Stack(
          children: [
            // Dynamic Ambient Background Atmosphere
            if (MusicSettings.enableAmbientLights.value)
              const Positioned.fill(
                child: AnimatedAmbientBackground(),
              ),

            // Page content area. The shell owns navigation and the now playing
            // bar now, so this page is its own content with its own header over
            // it and nothing else.
            SizedBox.expand(
              child: Stack(
                children: [
                  Positioned.fill(child: _buildTabContent()),

                  // Sticky chrome: the header row (search, source, settings)
                  // and the view band under it.
                  // The band sits at whatever height the header took rather
                  // than at a second number that has to be kept matching it.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MusicTopHeader(
                          isDesktop: isDesktop,
                          searchController: _searchController,
                          searchFocusNode: _searchFocusNode,
                          isSearching: _isSearching,
                          onSearchChanged: _onSearchChanged,
                          onClearSearch: _clearSearch,
                          onSettingsTap: () {
                            // Settings is a shell slot, so this switches the shell
                            // instead of pushing a second copy of the page over it.
                            // Null outside the shell, where this then does nothing.
                            AppShellScope.of(context)?.go(ShellSlot.settings);
                          },
                        ),
                        _MusicViewBand(view: _view, onSelected: _selectView),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Queue Drawer
            if (_showQueueDrawer)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: _MusicQueueDrawer(
                  onClose: () => setState(() => _showQueueDrawer = false),
                ),
              ),

            // Synced Lyrics Drawer
            if (_showLyricsDrawer && _playerController.hasTrack)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: _MusicLyricsDrawer(
                  track: _playerController.currentTrack!,
                  playerController: _playerController,
                  onClose: () => setState(() => _showLyricsDrawer = false),
                ),
              ),

            // Modals: Artist Detail
            if (_activeArtistModal != null)
              Positioned.fill(
                child: _MusicArtistDetailModal(
                  details: _activeArtistModal!,
                  onClose: () => setState(() => _activeArtistModal = null),
                  onPlayTrack: (t, queue) => _playerController.playTrack(t, playlistQueue: queue),
                  onAddToPlaylist: _showAddToPlaylistMenu,
                  onOpenAlbum: _openAlbumModal,
                ),
              ),

            // Modals: Album Detail
            if (_activeAlbumModal != null)
              Positioned.fill(
                child: _MusicAlbumDetailModal(
                  details: _activeAlbumModal!,
                  onClose: () => setState(() => _activeAlbumModal = null),
                  onPlayTrack: (t, queue) => _playerController.playTrack(t, playlistQueue: queue),
                  onAddToPlaylist: _showAddToPlaylistMenu,
                ),
              ),

            // Modals: Curated Playlist Detail
            if (_activeCuratedPlaylistModal != null)
              Positioned.fill(
                child: _MusicCuratedPlaylistDetailModal(
                  details: _activeCuratedPlaylistModal!,
                  onClose: () => setState(() => _activeCuratedPlaylistModal = null),
                  onPlayTrack: (t, queue) => _playerController.playTrack(t, playlistQueue: queue),
                  onAddToPlaylist: _showAddToPlaylistMenu,
                ),
              ),

            // Modals: User Playlist Detail
            if (_activeUserPlaylistModal != null)
              Positioned.fill(
                child: _MusicUserPlaylistDetailModal(
                  playlist: _activeUserPlaylistModal!,
                  onClose: () => setState(() => _activeUserPlaylistModal = null),
                  onPlayTrack: (t, queue) => _playerController.playTrack(t, playlistQueue: queue),
                  onRemoveTrack: (trackId) async {
                    await _libraryService.removeTrackFromPlaylist(_activeUserPlaylistModal!.id, trackId);
                    setState(() {
                      final updated = _libraryService.userPlaylists.firstWhere(
                        (p) => p.id == _activeUserPlaylistModal!.id,
                        orElse: () => _activeUserPlaylistModal!,
                      );
                      _activeUserPlaylistModal = updated;
                    });
                  },
                ),
              ),

            // Modals: Shortcuts
            if (_showShortcutsModal)
              Positioned.fill(
                child: _MusicShortcutsModal(
                  onClose: () => setState(() => _showShortcutsModal = false),
                ),
              ),

            // Modals: Downloaded Offline Tracks
            if (_showDownloadsModal)
              Positioned.fill(
                child: _MusicDownloadedTracksModal(
                  onClose: () => setState(() => _showDownloadsModal = false),
                  onPlayTrack: (t, queue) => _playerController.playTrack(t, playlistQueue: queue),
                  onAddToPlaylist: _showAddToPlaylistMenu,
                ),
              ),

            // Fullscreen Expanded Now-Playing Player
            if (_isPlayerExpanded && _playerController.hasTrack)
              Positioned.fill(
                child: _MusicExpandedPlayer(
                  playerController: _playerController,
                  isSaved: _libraryService.isTrackLiked(
                    _playerController.currentTrack?.id ?? '',
                  ),
                  onToggleSave: () {
                    if (_playerController.currentTrack != null) {
                      _libraryService.toggleLikeTrack(_playerController.currentTrack!);
                    }
                  },
                  onCollapse: () => setState(() => _isPlayerExpanded = false),
                  onQueueTap: () => setState(() => _showQueueDrawer = true),
                  onAddToPlaylist: () {
                    if (_playerController.currentTrack != null) {
                      _showAddToPlaylistMenu(_playerController.currentTrack!);
                    }
                  },
                ),
              ),

            // Temporary Notification Toast
            if (_toastMessage != null)
              Positioned(
                top: 80,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZplaySpacing.s20,
                      vertical: ZplaySpacing.s8,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      borderRadius: ZplayRadius.lgAll,
                      boxShadow: [
                        BoxShadow(
                          color: tokens.accent.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      _toastMessage!,
                      style: ZplayType.label.toStyle(color: tokens.onAccent),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Switches view from the header's band.
  ///
  /// The pending debounce is dropped rather than left to fire: it selects
  /// Search, so a query typed a moment before the tap would drag the user back
  /// out of the view they just asked for.
  void _selectView(MusicView view) {
    _debounceTimer?.cancel();
    if (_view == view) return;
    setState(() => _view = view);
  }

  Widget _buildTabContent() {
    final tokens = context.tokens;

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: tokens.accent),
      );
    }

    // Exhaustive, so a view cannot be added without a body to show for it. The
    // search field no longer outranks the switcher either: a query moves the
    // selection to Search by itself, and honouring the text as well would leave
    // Browse, Radio and Library unreachable for the rest of the session once
    // anything had been searched.
    return switch (_view) {
      MusicView.home => _buildHomeView(),
      MusicView.search => _buildSearchView(),
      MusicView.browse => _buildBrowseView(),
      MusicView.radio => _buildRadioView(),
      MusicView.library => _buildLibraryView(),
    };
  }

  Widget _buildHomeView() {
    final tokens = context.tokens;

    // The shell reserves the space for its own now playing bar and rail, so the
    // page keeps a plain scroll margin instead of clearance for a bar that used
    // to float over the content.
    return RefreshIndicator(
      color: tokens.accent,
      backgroundColor: tokens.surfaceRaised,
      onRefresh: _loadMusicData,
      child: ListView(
        controller: _scrollController,
        padding: EdgeInsets.only(
          top: _contentTopPadding(context),
          bottom: ZplaySpacing.s24,
        ),
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        children: [
          if (MusicSettings.enableSpotlight.value && _heroTrack != null)
            _MusicHeroBillboard(
              track: _heroTrack!,
              onPlayTap: () => _playerController.playTrack(
                _heroTrack!,
                playlistQueue: _sections.values.isNotEmpty ? _sections.values.first : null,
              ),
              onSaveTap: () {
                _libraryService.toggleLikeTrack(_heroTrack!);
                _showToast(
                  _libraryService.isTrackLiked(_heroTrack!.id)
                      ? 'Saved to Library'
                      : 'Removed from Library',
                );
              },
              onAddToPlaylistTap: () => _showAddToPlaylistMenu(_heroTrack!),
              isSaved: _libraryService.isTrackLiked(_heroTrack!.id),
            ),
          const SizedBox(height: ZplaySpacing.s24),
          if (_trendingArtists.isNotEmpty)
            _MusicTrendingArtists(
              artists: _trendingArtists,
              onArtistTap: (artist) {
                if (artist.id.isNotEmpty) {
                  _openArtistModal(artist.id);
                } else {
                  _onGenreTap(artist.name);
                }
              },
            ),
          if (_newReleases.isNotEmpty)
            _MusicAlbumsRow(
              title: '💿 New Album Releases',
              albums: _newReleases,
              onAlbumTap: (album) => _openAlbumModal(album.id),
            ),
          if (_curatedPlaylists.isNotEmpty)
            _MusicPlaylistsRow(
              title: '🎧 Curated Charts & Mixes',
              playlists: _curatedPlaylists,
              onPlaylistTap: (pl) => _openCuratedPlaylistModal(pl.id),
            ),
          for (final entry in _sections.entries)
            _MusicCategorySlider(
              title: entry.key,
              tracks: entry.value,
              onAddToPlaylist: _showAddToPlaylistMenu,
            ),
        ],
      ),
    );
  }

  Widget _buildSearchView() {
    final sizing = _MusicCardSizing.fromWidth(MediaQuery.sizeOf(context).width);
    final tokens = context.tokens;

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.only(
        top: _contentTopPadding(context),
        left: ZplaySpacing.s24,
        right: ZplaySpacing.s24,
        bottom: ZplaySpacing.s24,
      ),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _filterTab('All'),
              const SizedBox(width: ZplaySpacing.s8),
              _filterTab('Tracks (${_searchData.tracks.length})'),
              const SizedBox(width: ZplaySpacing.s8),
              _filterTab('Artists (${_searchData.artists.length})'),
              const SizedBox(width: ZplaySpacing.s8),
              _filterTab('Albums (${_searchData.albums.length})'),
              const SizedBox(width: ZplaySpacing.s8),
              _filterTab('Playlists (${_searchData.playlists.length})'),
            ],
          ),
        ),
        const SizedBox(height: ZplaySpacing.s24),
        if (_isSearching)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s48),
            child: Center(
              child: CircularProgressIndicator(color: tokens.accent),
            ),
          )
        else if (_searchData.tracks.isEmpty &&
            _searchData.artists.isEmpty &&
            _searchData.albums.isEmpty &&
            _searchData.playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s48),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    color: tokens.textMuted,
                    size: 48,
                  ),
                  const SizedBox(height: ZplaySpacing.s16),
                  Text(
                    _activeQuery.isEmpty
                        ? 'Search to find tracks, artists, albums and playlists'
                        : 'No results for "$_activeQuery"',
                    textAlign: TextAlign.center,
                    style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                  ),
                ],
              ),
            ),
          )
        else ...[
          if ((_selectedFilter == 'All' || _selectedFilter.startsWith('Tracks')) &&
              _searchData.tracks.isNotEmpty) ...[
            Text(
              'Songs',
              style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
            ),
            const SizedBox(height: ZplaySpacing.s12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _searchData.tracks.length.clamp(0, 15),
              separatorBuilder: (_, __) => const SizedBox(height: ZplaySpacing.s8),
              itemBuilder: (context, index) {
                final track = _searchData.tracks[index];
                return _MusicTrackRow(
                  track: track,
                  isPlaying: _playerController.currentTrack?.id == track.id &&
                      _playerController.isPlaying,
                  isCurrent: _playerController.currentTrack?.id == track.id,
                  onTap: () => _playerController.playTrack(
                    track,
                    playlistQueue: _searchData.tracks,
                  ),
                  onMoreTap: () => _showAddToPlaylistMenu(track),
                );
              },
            ),
            const SizedBox(height: ZplaySpacing.s32),
          ],
          if ((_selectedFilter == 'All' || _selectedFilter.startsWith('Artists')) &&
              _searchData.artists.isNotEmpty) ...[
            Text(
              'Artists',
              style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
            ),
            const SizedBox(height: ZplaySpacing.s12),
            SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _searchData.artists.length,
                separatorBuilder: (_, __) => const SizedBox(width: ZplaySpacing.s16),
                itemBuilder: (context, index) {
                  final artist = _searchData.artists[index];
                  return FocusableCard(
                    onTap: () => _openArtistModal(artist.id),
                    builder: (context, state) => AnimatedScale(
                      scale: state.highlighted ? 1.06 : 1.0,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      child: Column(
                        children: [
                          ClipOval(
                            child: CachedNetworkImage(
                              imageUrl: artist.pictureUrl,
                              cacheManager: AppImageCache.manager,
                              memCacheWidth: 240,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover),
                          ),
                          const SizedBox(height: ZplaySpacing.s8),
                          SizedBox(
                            width: 90,
                            child: Text(
                              artist.name,
                              style: ZplayType.caption.toStyle(color: tokens.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: ZplaySpacing.s32),
          ],
          if ((_selectedFilter == 'All' || _selectedFilter.startsWith('Albums')) &&
              _searchData.albums.isNotEmpty) ...[
            Text(
              'Albums',
              style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
            ),
            const SizedBox(height: ZplaySpacing.s12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: (MediaQuery.sizeOf(context).width / sizing.cardWidth)
                    .floor()
                    .clamp(2, 6),
                mainAxisSpacing: ZplaySpacing.s20,
                crossAxisSpacing: ZplaySpacing.s16,
                childAspectRatio: sizing.cardWidth / sizing.totalHeight,
              ),
              itemCount: _searchData.albums.length.clamp(0, 12),
              itemBuilder: (context, index) {
                final album = _searchData.albums[index];
                return _MusicAlbumCard(
                  album: album,
                  onTap: () => _openAlbumModal(album.id),
                );
              },
            ),
            const SizedBox(height: ZplaySpacing.s32),
          ],
          if ((_selectedFilter == 'All' || _selectedFilter.startsWith('Playlists')) &&
              _searchData.playlists.isNotEmpty) ...[
            Text(
              'Playlists',
              style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
            ),
            const SizedBox(height: ZplaySpacing.s12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: (MediaQuery.sizeOf(context).width / sizing.cardWidth)
                    .floor()
                    .clamp(2, 6),
                mainAxisSpacing: ZplaySpacing.s20,
                crossAxisSpacing: ZplaySpacing.s16,
                childAspectRatio: sizing.cardWidth / sizing.totalHeight,
              ),
              itemCount: _searchData.playlists.length.clamp(0, 12),
              itemBuilder: (context, index) {
                final pl = _searchData.playlists[index];
                return _MusicPlaylistCard(
                  playlist: pl,
                  onTap: () => _openCuratedPlaylistModal(pl.id),
                );
              },
            ),
          ],
        ],
      ],
    );
  }

  Widget _filterTab(String label) {
    final isSelected = _selectedFilter == label ||
        (_selectedFilter == 'All' && label == 'All') ||
        (label.startsWith(_selectedFilter) && _selectedFilter != 'All');
    final tokens = context.tokens;

    return FocusableCard(
      onTap: () {
        setState(() {
          if (label.startsWith('Tracks')) {
            _selectedFilter = 'Tracks';
          } else if (label.startsWith('Artists')) {
            _selectedFilter = 'Artists';
          } else if (label.startsWith('Albums')) {
            _selectedFilter = 'Albums';
          } else if (label.startsWith('Playlists')) {
            _selectedFilter = 'Playlists';
          } else {
            _selectedFilter = 'All';
          }
        });
      },
      builder: (context, state) => AnimatedScale(
        scale: state.highlighted ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: ZplaySpacing.s16,
            vertical: ZplaySpacing.s8,
          ),
          decoration: BoxDecoration(
            color: isSelected ? tokens.accent : tokens.borderDefault,
            borderRadius: ZplayRadius.fullAll,
            border: Border.all(
              color: isSelected ? tokens.accent : tokens.borderStrong,
            ),
          ),
          child: Text(
            label,
            style: ZplayType.label.toStyle(
              color: isSelected ? tokens.onAccent : tokens.textEmphasis,
            ),
          ),
        ),
      ),
    );
  }

  /// Genre and station hue. The fork-era tables carried an eighteen-entry
  /// literal each; the chips instead cycle the palette's accent and status
  /// colours by index so they stay distinguishable without a second table.
  static Color _genreHue(BuildContext context, int index) {
    final tokens = context.tokens;
    final hues = [tokens.accent, tokens.info, tokens.success, tokens.warning];
    return hues[index % hues.length];
  }

  Widget _buildBrowseView() {
    final genres = [
      {'title': 'Pop Hits', 'query': 'Pop Hits'},
      {'title': 'Hip-Hop & Rap', 'query': 'Hip-Hop'},
      {'title': 'Electronic & EDM', 'query': 'EDM Dance'},
      {'title': 'Chill Lofi Beats', 'query': 'Chill Lofi'},
      {'title': 'Rock Classics', 'query': 'Rock Classics'},
      {'title': 'R&B & Soul', 'query': 'R&B Soul'},
      {'title': 'Soundtracks & Gaming', 'query': 'Soundtracks'},
      {'title': 'Heavy Metal', 'query': 'Heavy Metal'},
      {'title': 'Jazz & Blues', 'query': 'Jazz Blues'},
      {'title': 'Classical Piano', 'query': 'Classical Piano'},
    ];
    final tokens = context.tokens;

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.only(
        top: _contentTopPadding(context),
        left: ZplaySpacing.s24,
        right: ZplaySpacing.s24,
        bottom: ZplaySpacing.s24,
      ),
      children: [
        Text(
          'Browse Moods & Genres',
          style: ZplayType.display.toStyle(color: tokens.textPrimary),
        ),
        const SizedBox(height: ZplaySpacing.s16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: ZplaySpacing.s16,
            crossAxisSpacing: ZplaySpacing.s16,
            childAspectRatio: 1.6,
          ),
          itemCount: genres.length,
          itemBuilder: (context, index) {
            final g = genres[index];
            final color = _genreHue(context, index);
            return FocusableCard(
              onTap: () => _onGenreTap(g['query'] as String),
              builder: (context, state) => AnimatedScale(
                scale: state.highlighted ? 1.04 : 1.0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                child: PerformanceLiquidLens(
                  style: PerformanceGlassStyles.menu,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: ZplayRadius.mdAll,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          color.withValues(alpha: 0.85),
                          color.withValues(alpha: 0.40),
                        ],
                      ),
                      border: Border.all(color: tokens.borderStrong),
                    ),
                    padding: const EdgeInsets.all(ZplaySpacing.s16),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(
                        g['title'] as String,
                        style: ZplayType.title.toStyle(color: tokens.textPrimary),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRadioView() {
    final radioGenres = [
      {'name': 'Pop Radio', 'query': 'Pop Radio Hits'},
      {'name': 'Rap & Hip-Hop', 'query': 'Hip Hop Radio'},
      {'name': 'Rock Mix', 'query': 'Rock Radio'},
      {'name': 'Dance & Electro', 'query': 'Electro Radio'},
      {'name': 'R&B Station', 'query': 'R&B Radio'},
      {'name': 'Lofi & Ambient', 'query': 'Lofi Radio'},
      {'name': 'Heavy Metal Station', 'query': 'Metal Radio'},
      {'name': 'Jazz Club', 'query': 'Jazz Radio'},
    ];
    final tokens = context.tokens;

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.only(
        top: _contentTopPadding(context),
        left: ZplaySpacing.s24,
        right: ZplaySpacing.s24,
        bottom: ZplaySpacing.s24,
      ),
      children: [
        Text(
          'Radio Stations & Live Streams',
          style: ZplayType.display.toStyle(color: tokens.textPrimary),
        ),
        const SizedBox(height: ZplaySpacing.s4),
        Text(
          'Continuous music channels tuned to your mood.',
          style: ZplayType.body.toStyle(color: tokens.textSecondary),
        ),
        const SizedBox(height: ZplaySpacing.s20),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: ZplaySpacing.s16,
            crossAxisSpacing: ZplaySpacing.s16,
            childAspectRatio: 1.5,
          ),
          itemCount: radioGenres.length,
          itemBuilder: (context, index) {
            final station = radioGenres[index];
            final color = _genreHue(context, index);
            return FocusableCard(
              onTap: () => _onGenreTap(station['query'] as String),
              builder: (context, state) => AnimatedScale(
                scale: state.highlighted ? 1.04 : 1.0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                child: PerformanceLiquidLens(
                  style: PerformanceGlassStyles.menu,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: ZplayRadius.mdAll,
                      color: color.withValues(alpha: 0.20),
                      border: Border.all(color: color.withValues(alpha: 0.5)),
                    ),
                    padding: const EdgeInsets.all(ZplaySpacing.s16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.radio_rounded, color: color, size: 28),
                        const SizedBox(height: ZplaySpacing.s4),
                        // Flexible, because the grid fixes the tile's height at
                        // `width / 1.5` and a three-line station name overflowed
                        // the column by a few pixels. Two lines then ellipsise,
                        // and the name stays bottom-aligned as it was.
                        Flexible(
                          child: Text(
                            station['name'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLibraryView() {
    final liked = _libraryService.likedTracks;
    final playlists = _libraryService.userPlaylists;
    final recent = _libraryService.recentTracks;
    final tokens = context.tokens;

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.only(
        top: _contentTopPadding(context),
        left: ZplaySpacing.s24,
        right: ZplaySpacing.s24,
        bottom: ZplaySpacing.s24,
      ),
      children: [
        Row(
          children: [
            Text(
              'Your Library',
              style: ZplayType.display.toStyle(color: tokens.textPrimary),
            ),
            const Spacer(),
            _MusicHoverable(
              scaleFactor: 1.05,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.accent,
                  shape: const RoundedRectangleBorder(
                    borderRadius: ZplayRadius.mdAll,
                  ),
                ),
                onPressed: () => _showCreatePlaylistDialog(),
                icon: Icon(Icons.add_rounded, color: tokens.onAccent, size: 18),
                label: Text(
                  'New Playlist',
                  style: ZplayType.label.toStyle(color: tokens.onAccent),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: ZplaySpacing.s20),

        // Liked Songs Banner
        FocusableCard(
          onTap: () {
            if (liked.isNotEmpty) {
              _playerController.playTrack(liked.first, playlistQueue: liked);
            } else {
              _showToast('No liked songs yet');
            }
          },
          builder: (context, state) => AnimatedScale(
            scale: state.highlighted ? 1.02 : 1.0,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: PerformanceLiquidLens(
              style: PerformanceGlassStyles.menu,
              child: Container(
                height: 110,
                decoration: BoxDecoration(
                  borderRadius: ZplayRadius.lgAll,
                  gradient: LinearGradient(
                    colors: [tokens.accent, tokens.accentHover],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: tokens.accent.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(ZplaySpacing.s16),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: tokens.onAccent.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.favorite_rounded,
                        color: tokens.onAccent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: ZplaySpacing.s16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Liked Songs',
                            style: ZplayType.title.toStyle(color: tokens.onAccent),
                          ),
                          const SizedBox(height: ZplaySpacing.s4),
                          Text(
                            '${liked.length} favourite tracks',
                            style: ZplayType.bodySmall.toStyle(
                              color: tokens.onAccent.withValues(alpha: ZplayOpacity.textEmphasis),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (liked.isNotEmpty)
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: tokens.onAccent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: tokens.accent,
                          size: 30,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: ZplaySpacing.s12),

        // Downloaded Songs Banner (Offline Music)
        Builder(
          builder: (context) {
            final downloaded = MusicDownloadService.instance.downloadedTracks;
            final queue = MusicDownloadService.instance.queue;
            final totalBytes = MusicDownloadService.instance.totalDownloadedSizeBytes;
            final sizeMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);

            return FocusableCard(
              onTap: () {
                setState(() => _showDownloadsModal = true);
              },
              builder: (context, state) => AnimatedScale(
                scale: state.highlighted ? 1.02 : 1.0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                child: PerformanceLiquidLens(
                  style: PerformanceGlassStyles.menu,
                  child: Container(
                    height: 110,
                    decoration: BoxDecoration(
                      borderRadius: ZplayRadius.lgAll,
                      gradient: LinearGradient(
                        colors: [tokens.info, tokens.accent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: tokens.info.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(ZplaySpacing.s16),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: tokens.onAccent.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.download_done_rounded,
                            color: tokens.onAccent,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: ZplaySpacing.s16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Downloaded Songs',
                                    style: ZplayType.title.toStyle(color: tokens.onAccent),
                                  ),
                                  if (queue.isNotEmpty) ...[
                                    const SizedBox(width: ZplaySpacing.s8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: ZplaySpacing.s8,
                                        vertical: ZplaySpacing.s2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tokens.onAccent.withValues(alpha: ZplayOpacity.overlayHover),
                                        borderRadius: ZplayRadius.smAll,
                                      ),
                                      child: Text(
                                        'Queue (${queue.length})',
                                        style: ZplayType.overline.toStyle(color: tokens.onAccent),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: ZplaySpacing.s4),
                              Text(
                                '${downloaded.length} offline tracks • $sizeMb MB',
                                style: ZplayType.bodySmall.toStyle(
                                  color: tokens.onAccent.withValues(alpha: ZplayOpacity.textEmphasis),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: tokens.onAccent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: tokens.info,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),

        const SizedBox(height: ZplaySpacing.s24),

        // User Playlists Section
        if (playlists.isNotEmpty) ...[
          Text(
            'Custom Playlists',
            style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
          ),
          const SizedBox(height: ZplaySpacing.s12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: ZplaySpacing.s16,
              crossAxisSpacing: ZplaySpacing.s16,
              childAspectRatio: 1.1,
            ),
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final pl = playlists[index];
              return FocusableCard(
                onTap: () => setState(() => _activeUserPlaylistModal = pl),
                builder: (context, state) => AnimatedScale(
                  scale: state.highlighted ? 1.04 : 1.0,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  child: Container(
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: ZplayRadius.mdAll,
                      border: Border.all(color: tokens.borderDefault),
                    ),
                    padding: const EdgeInsets.all(ZplaySpacing.s12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 70,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: tokens.accentSubtle,
                            borderRadius: ZplayRadius.smAll,
                          ),
                          child: Icon(
                            Icons.queue_music_rounded,
                            color: tokens.accent,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: ZplaySpacing.s8),
                        Text(
                          pl.title,
                          style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${pl.tracks.length} tracks',
                          style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: ZplaySpacing.s24),
        ],

        // Recent History Section
        if (recent.isNotEmpty) ...[
          Text(
            'Recently Played',
            style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
          ),
          const SizedBox(height: ZplaySpacing.s12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recent.length.clamp(0, 10),
            separatorBuilder: (_, __) => const SizedBox(height: ZplaySpacing.s8),
            itemBuilder: (context, index) {
              final track = recent[index];
              return _MusicTrackRow(
                track: track,
                isPlaying: _playerController.currentTrack?.id == track.id &&
                    _playerController.isPlaying,
                isCurrent: _playerController.currentTrack?.id == track.id,
                onTap: () => _playerController.playTrack(track, playlistQueue: recent),
                onMoreTap: () => _showAddToPlaylistMenu(track),
              );
            },
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FPS-Friendly Hover Container
// ─────────────────────────────────────────────────────────────────────────────

class _MusicHoverable extends StatefulWidget {
  final Widget child;
  final double scaleFactor;

  const _MusicHoverable({
    required this.child,
    this.scaleFactor = 1.04,
  });

  @override
  State<_MusicHoverable> createState() => _MusicHoverableState();
}

class _MusicHoverableState extends State<_MusicHoverable> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? widget.scaleFactor : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable Horizontal Slider with Desktop Navigation Arrows
// ─────────────────────────────────────────────────────────────────────────────

class _MusicHorizontalScrollSection extends StatefulWidget {
  final String? title;
  final double height;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const _MusicHorizontalScrollSection({
    this.title,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  State<_MusicHorizontalScrollSection> createState() => _MusicHorizontalScrollSectionState();
}

class _MusicHorizontalScrollSectionState extends State<_MusicHorizontalScrollSection> {
  late final ScrollController _controller;
  bool _canScrollLeft = false;
  bool _canScrollRight = true;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _controller.addListener(_updateScrollButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateScrollButtons();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_updateScrollButtons);
    _controller.dispose();
    super.dispose();
  }

  void _updateScrollButtons() {
    if (!_controller.hasClients) return;
    final canLeft = _controller.position.pixels > 5;
    final canRight = _controller.position.pixels < _controller.position.maxScrollExtent - 5;
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scroll(double multiplier) {
    if (!_controller.hasClients) return;
    final viewportWidth = _controller.position.viewportDimension;
    final scrollAmount = viewportWidth * 0.75 * multiplier;
    final target = (_controller.position.pixels + scrollAmount)
        .clamp(0.0, _controller.position.maxScrollExtent);

    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  bool _isDesktop(BuildContext context) {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop(context);
    final tokens = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s24),
            child: Text(
              widget.title!,
              style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
            ),
          ),
          const SizedBox(height: ZplaySpacing.s12),
        ],
        MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ListView.separated(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s24),
                  itemCount: widget.itemCount,
                  separatorBuilder: (_, __) => const SizedBox(width: ZplaySpacing.s16),
                  itemBuilder: widget.itemBuilder,
                ),

                // Desktop Left & Right Floating Arrows
                if (isDesktop) ...[
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    left: _canScrollLeft && _isHovered ? 8 : -60,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: SliderArrow(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: () => _scroll(-1),
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    right: _canScrollRight && _isHovered ? 8 : -60,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: SliderArrow(
                        icon: Icons.arrow_forward_ios_rounded,
                        onTap: () => _scroll(1),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Components & Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _MusicTopHeader extends StatelessWidget {
  final bool isDesktop;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool isSearching;
  final Function(String) onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onSettingsTap;

  const _MusicTopHeader({
    required this.isDesktop,
    required this.searchController,
    required this.searchFocusNode,
    required this.isSearching,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final screenW = MediaQuery.sizeOf(context).width;
    final isMobile = screenW < 600;
    final isVeryNarrow = screenW < 400;
    final tokens = context.tokens;

    return Container(
      height: isDesktop ? 68.0 : (58.0 + topInset),
      padding: EdgeInsets.fromLTRB(
        isMobile ? ZplaySpacing.s8 : ZplaySpacing.s20,
        isDesktop ? 0 : topInset,
        isMobile ? ZplaySpacing.s8 : ZplaySpacing.s20,
        0,
      ),
      decoration: BoxDecoration(color: tokens.bg),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: ZplayRadius.fullAll,
                border: Border.all(color: tokens.borderStrong),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? ZplaySpacing.s8 : ZplaySpacing.s16,
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: tokens.textSecondary, size: isMobile ? 18 : 20),
                  const SizedBox(width: ZplaySpacing.s8),
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      focusNode: searchFocusNode,
                      onChanged: onSearchChanged,
                      style: (isMobile ? ZplayType.label : ZplayType.body)
                          .toStyle(color: tokens.textPrimary),
                      decoration: InputDecoration(
                        hintText: isVeryNarrow
                            ? 'Search…'
                            : (isMobile ? 'Search music…' : 'Search songs, artists, albums, playlists...'),
                        hintStyle: (isMobile ? ZplayType.bodySmall : ZplayType.label)
                            .toStyle(color: tokens.textMuted),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (searchController.text.isNotEmpty)
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(Icons.close_rounded, color: tokens.textSecondary, size: 16),
                      onPressed: onClearSearch,
                    ),
                ],
              ),
            ),
          ),
          SizedBox(width: isMobile ? ZplaySpacing.s4 : ZplaySpacing.s12),
          const _AudioSourceSelectorButton(),
          if (!isMobile) ...[
            SizedBox(width: isMobile ? ZplaySpacing.s4 : ZplaySpacing.s8),
            _MusicHoverable(
              scaleFactor: 1.1,
              child: IconButton(
                tooltip: 'Music Player Studio',
                icon: Icon(Icons.dashboard_customize_rounded, color: tokens.textEmphasis, size: 20),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MusicPlayerStudioPage()),
                  );
                },
              ),
            ),
            SizedBox(width: isMobile ? ZplaySpacing.s2 : ZplaySpacing.s4),
            _MusicHoverable(
              scaleFactor: 1.1,
              child: IconButton(
                tooltip: 'Music Atmosphere Settings',
                icon: Icon(Icons.palette_rounded, color: tokens.textEmphasis, size: 20),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MusicSettingsPage()),
                  );
                },
              ),
            ),
          ],
          SizedBox(width: isMobile ? ZplaySpacing.s2 : ZplaySpacing.s4),
          _MusicHoverable(
            scaleFactor: 1.1,
            child: IconButton(
              tooltip: 'App Settings',
              icon: Icon(Icons.settings_rounded, color: tokens.textEmphasis, size: 20),
              onPressed: onSettingsTap,
            ),
          ),
        ],
      ),
    );
  }
}

/// The page's own view switcher, under the header row.
///
/// A [TabStrip] rather than a [SegmentedTabs] for the same reason Browse's
/// eight verticals use one: five labels do not fit a phone. Measured, the pills
/// run about 390 px against roughly 370 px of usable width, so a segmented
/// track would spend its budget on `SegmentedTabs`' 78 px minimum and
/// ellipsise "Library" to a sliver. This control sizes every pill to its own
/// label, scrolls instead of truncating, brings the selected pill into view,
/// and keeps the 44 px target and D-pad story the segmented control has.
class _MusicViewBand extends StatelessWidget {
  const _MusicViewBand({required this.view, required this.onSelected});

  final MusicView view;
  final ValueChanged<MusicView> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // The header's own phone breakpoint, not the page's desktop one: the band
    // is a second row of the same bar, and a tablet-width window already had
    // room for the header's s20 gutter.
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final television =
        FormFactorService.of(context) == FormFactor.television;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.bg,
        border: Border(bottom: tokens.hairline),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isMobile ? ZplaySpacing.s12 : ZplaySpacing.s20,
          ZplaySpacing.s8,
          isMobile ? ZplaySpacing.s12 : ZplaySpacing.s20,
          ZplaySpacing.s8,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TabStrip<MusicView>(
            options: _viewOptions,
            selected: view,
            onSelected: onSelected,
            semanticsLabel: 'Music view',
            height: television ? ZplaySpacing.s48 : 40,
          ),
        ),
      ),
    );
  }
}

class _AudioSourceSelectorButton extends StatelessWidget {
  const _AudioSourceSelectorButton();

  @override
  Widget build(BuildContext context) {
    final player = MusicPlayerController.instance;
    final tokens = context.tokens;

    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final isFlac = player.audioSource == MusicAudioSource.flac;
        final sourceColor = isFlac ? tokens.info : tokens.danger;

        return _MusicHoverable(
          scaleFactor: 1.05,
          child: InkWell(
            onTap: () => _showAudioSourceDialog(context),
            borderRadius: ZplayRadius.mdAll,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ZplaySpacing.s12,
                vertical: ZplaySpacing.s8,
              ),
              decoration: BoxDecoration(
                color: sourceColor.withValues(alpha: ZplayOpacity.borderStrong),
                borderRadius: ZplayRadius.mdAll,
                border: Border.all(color: sourceColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isFlac ? Icons.diamond_rounded : Icons.play_circle_fill_rounded,
                    color: sourceColor,
                    size: 16,
                  ),
                  const SizedBox(width: ZplaySpacing.s4),
                  Text(
                    isFlac ? 'FLAC' : 'YouTube',
                    style: ZplayType.caption.toStyle(color: sourceColor),
                  ),
                  const SizedBox(width: ZplaySpacing.s4),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    color: sourceColor,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static void _showAudioSourceDialog(BuildContext context) {
    final tokens = context.tokens;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final player = MusicPlayerController.instance;

        return ListenableBuilder(
          listenable: player,
          builder: (context, _) {
            final isFlac = player.audioSource == MusicAudioSource.flac;

            return PerformanceLiquidLens(
              style: PerformanceGlassStyles.sheet,
              child: Container(
                padding: const EdgeInsets.all(ZplaySpacing.s24),
                decoration: BoxDecoration(
                  color: tokens.surfaceOverlay.withValues(alpha: 0.95),
                  borderRadius: ZplayRadius.sheetTop,
                  border: Border.all(color: tokens.borderDefault),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(ZplaySpacing.s8),
                          decoration: BoxDecoration(
                            color: tokens.accentSubtle,
                            borderRadius: ZplayRadius.mdAll,
                          ),
                          child: Icon(Icons.tune_rounded, color: tokens.accent, size: 22),
                        ),
                        const SizedBox(width: ZplaySpacing.s12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Audio Source & Quality',
                              style: ZplayType.title.toStyle(color: tokens.textPrimary),
                            ),
                            const SizedBox(height: ZplaySpacing.s2),
                            Text(
                              'Choose your preferred music extraction engine',
                              style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: ZplaySpacing.s20),
                    _sourceOptionCard(
                      context: context,
                      title: 'FLAC Lossless (Qobuz Hi-Res)',
                      subtitle: 'Studio master quality up to 24-bit/192kHz with zero compression',
                      icon: Icons.diamond_rounded,
                      iconColor: tokens.info,
                      isSelected: isFlac,
                      badge: 'LOSSLESS',
                      badgeColor: tokens.info,
                      onTap: () {
                        player.setAudioSource(MusicAudioSource.flac);
                        Navigator.pop(ctx);
                      },
                    ),
                    const SizedBox(height: ZplaySpacing.s12),
                    _sourceOptionCard(
                      context: context,
                      title: 'YouTube Audio',
                      subtitle: 'High-speed audio extraction with intelligent track & duration matching',
                      icon: Icons.play_circle_fill_rounded,
                      iconColor: tokens.danger,
                      isSelected: !isFlac,
                      badge: 'FAST',
                      badgeColor: tokens.danger,
                      onTap: () {
                        player.setAudioSource(MusicAudioSource.youtube);
                        Navigator.pop(ctx);
                      },
                    ),
                    const SizedBox(height: ZplaySpacing.s16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Widget _sourceOptionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool isSelected,
    required String badge,
    required Color badgeColor,
    required VoidCallback onTap,
  }) {
    final tokens = context.tokens;

    return _MusicHoverable(
      scaleFactor: 1.02,
      child: InkWell(
        onTap: onTap,
        borderRadius: ZplayRadius.mdAll,
        child: Container(
          padding: const EdgeInsets.all(ZplaySpacing.s16),
          decoration: BoxDecoration(
            color: isSelected
                ? iconColor.withValues(alpha: ZplayOpacity.borderStrong)
                : tokens.borderSubtle,
            borderRadius: ZplayRadius.mdAll,
            border: Border.all(
              color: isSelected
                  ? iconColor.withValues(alpha: 0.5)
                  : tokens.borderDefault,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(ZplaySpacing.s12),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: ZplayOpacity.overlayHover),
                  borderRadius: ZplayRadius.mdAll,
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: ZplaySpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                          ),
                        ),
                        const SizedBox(width: ZplaySpacing.s8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZplaySpacing.s4,
                            vertical: ZplaySpacing.s2,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.2),
                            borderRadius: ZplayRadius.xsAll,
                            border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            badge,
                            style: ZplayType.overline.toStyle(color: badgeColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: ZplaySpacing.s4),
                    Text(
                      subtitle,
                      style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ZplaySpacing.s8),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: iconColor, size: 22)
              else
                Icon(Icons.radio_button_unchecked_rounded, color: tokens.textDisabled, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _MusicHeroBillboard extends StatelessWidget {
  final MusicTrack track;
  final VoidCallback onPlayTap;
  final VoidCallback onSaveTap;
  final VoidCallback onAddToPlaylistTap;
  final bool isSaved;

  const _MusicHeroBillboard({
    required this.track,
    required this.onPlayTap,
    required this.onSaveTap,
    required this.onAddToPlaylistTap,
    required this.isSaved,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 600;
    final tokens = context.tokens;

    // The prototype's music vertical leads with the same horizontal banner its
    // audiobook studio uses (`.audiobook-hero-banner`): artwork at 88, the copy
    // beside it, and one row of controls. The overline carries the real quality
    // label while this track is the one playing; the catalogue carries no bit
    // depth or sample rate to print a "24-bit / 96kHz" claim from.
    final player = MusicPlayerController.instance;
    final isPlayingThis = track.id.isNotEmpty && player.currentTrack?.id == track.id;
    final overline = isPlayingThis
        ? (player.isCurrentTrackLossless
            ? 'HI-RES LOSSLESS · ${player.currentQualityLabel}'
            : player.currentQualityLabel)
        : 'TOP CHART HIT';

    // What there is to say about this track, in the reference's order: who
    // made it, what it is on, where it sits on that record, and how long it
    // runs. Every term comes from the catalogue object already in hand - no
    // fetch, and nothing invented where a field is absent.
    final metaTerms = <String>[
      if (track.artist.isNotEmpty) track.artist,
      if (track.album.isNotEmpty) track.album,
      if (track.trackNumber != null && track.trackNumber! > 0)
        'Track ${track.trackNumber}',
      if (track.durationSeconds > 0) track.formattedDuration,
    ];

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? ZplaySpacing.s16 : ZplaySpacing.s24),
      padding: const EdgeInsets.all(ZplaySpacing.s16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.smAll,
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: ClipRRect(
              borderRadius: ZplayRadius.smAll,
              child: CachedNetworkImage(
                imageUrl: track.coverUrl,
                cacheManager: AppImageCache.manager,
                fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: ZplaySpacing.s20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  overline,
                  style: ZplayType.overline.toStyle(color: tokens.accent),
                ),
                const SizedBox(height: ZplaySpacing.s4),
                Text(
                  track.title,
                  style: (isMobile ? ZplayType.title : ZplayType.titleLarge)
                      .toStyle(color: tokens.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                // One metadata line: the artist, the album, the track's
                // position on it where the catalogue has one, and its runtime.
                //
                // The artist and album were already joined by an interpunct
                // here by hand; the shared line is that join plus the two terms
                // the track actually carries, in the reference's order. A
                // track with no album, no track number or no duration prints
                // fewer terms rather than placeholders - `formattedDuration`
                // would have returned `--:--`, which is a gap in the sentence,
                // not a fact.
                if (metaTerms.isNotEmpty) ...[
                  const SizedBox(height: ZplaySpacing.s4),
                  HeroMetaLine(terms: metaTerms),
                ],
                const SizedBox(height: ZplaySpacing.s12),
                Row(
                  children: [
                    // The shared pill, so this banner's call to action is the
                    // same shape as Home's hero and the audiobook studio's.
                    // It replaced a 40 dp `ElevatedButton` that hand-rolled its
                    // own ten-foot height and swelled by 6% under a mouse -
                    // a lift that moves the two `IconButton`s beside it. The
                    // pill's box is identical in every state.
                    Builder(
                      builder: (context) => PillButton(
                        label: 'Play Now',
                        icon: Icons.play_arrow_rounded,
                        onPressed: onPlayTap,
                      ),
                    ),
                    const SizedBox(width: ZplaySpacing.s8),
                    _MusicHoverable(
                      scaleFactor: 1.1,
                      child: IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: tokens.surfaceRaised,
                          // The pill's own height, so the row is one line of
                          // controls rather than a 44 dp pill beside two 40 dp
                          // squares. `PillButton.heightFor` states the rule once
                          // for the whole app; these two were carrying their own
                          // copy of it and had already drifted 4 dp away from
                          // the button beside them.
                          minimumSize: Size.square(PillButton.heightFor(context)),
                        ),
                        icon: Icon(
                          isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: isSaved ? tokens.danger : tokens.textPrimary,
                        ),
                        onPressed: onSaveTap,
                      ),
                    ),
                    const SizedBox(width: ZplaySpacing.s8),
                    _MusicHoverable(
                      scaleFactor: 1.1,
                      child: IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: tokens.surfaceRaised,
                          minimumSize: Size.square(PillButton.heightFor(context)),
                        ),
                        icon: Icon(Icons.playlist_add_rounded, color: tokens.textPrimary),
                        onPressed: onAddToPlaylistTap,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MusicTrendingArtists extends StatelessWidget {
  final List<MusicArtist> artists;
  final Function(MusicArtist) onArtistTap;

  const _MusicTrendingArtists({
    required this.artists,
    required this.onArtistTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return _MusicHorizontalScrollSection(
      title: '🌟 Trending Artists',
      height: 130,
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return FocusableCard(
          onTap: () => onArtistTap(artist),
          builder: (context, state) => AnimatedScale(
            scale: state.highlighted ? 1.06 : 1.0,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: tokens.accent.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: artist.pictureUrl,
                      cacheManager: AppImageCache.manager,
                      memCacheWidth: 234,
                      width: 78,
                      height: 78,
                      fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: ZplaySpacing.s8),
                SizedBox(
                  width: 85,
                  child: Text(
                    artist.name,
                    style: ZplayType.caption.toStyle(color: tokens.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MusicAlbumsRow extends StatelessWidget {
  final String title;
  final List<MusicAlbum> albums;
  final Function(MusicAlbum) onAlbumTap;

  const _MusicAlbumsRow({
    required this.title,
    required this.albums,
    required this.onAlbumTap,
  });

  @override
  Widget build(BuildContext context) {
    return _MusicHorizontalScrollSection(
      title: title,
      height: 200,
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return _MusicAlbumCard(album: album, onTap: () => onAlbumTap(album));
      },
    );
  }
}

class _MusicPlaylistsRow extends StatelessWidget {
  final String title;
  final List<MusicPlaylist> playlists;
  final Function(MusicPlaylist) onPlaylistTap;

  const _MusicPlaylistsRow({
    required this.title,
    required this.playlists,
    required this.onPlaylistTap,
  });

  @override
  Widget build(BuildContext context) {
    return _MusicHorizontalScrollSection(
      title: title,
      height: 200,
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final pl = playlists[index];
        return _MusicPlaylistCard(playlist: pl, onTap: () => onPlaylistTap(pl));
      },
    );
  }
}

class _MusicCategorySlider extends StatelessWidget {
  final String title;
  final List<MusicTrack> tracks;
  final Function(MusicTrack) onAddToPlaylist;

  const _MusicCategorySlider({
    required this.title,
    required this.tracks,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return _MusicHorizontalScrollSection(
      title: title,
      height: 215,
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return _MusicTrackCard(
          track: track,
          onTap: () => MusicPlayerController.instance.playTrack(
            track,
            playlistQueue: tracks,
          ),
          onMoreTap: () => onAddToPlaylist(track),
        );
      },
    );
  }
}

class _MusicTrackCard extends StatelessWidget {
  final MusicTrack track;
  final VoidCallback onTap;
  final VoidCallback onMoreTap;

  const _MusicTrackCard({
    required this.track,
    required this.onTap,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => AnimatedScale(
        scale: state.highlighted ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: 145,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: ZplayRadius.mdAll,
                    child: CachedNetworkImage(
                      imageUrl: track.coverUrl,
                      cacheManager: AppImageCache.manager,
                      memCacheWidth: 435,
                      width: 145,
                      height: 145,
                      fit: BoxFit.cover),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(ZplaySpacing.s4),
                      decoration: BoxDecoration(
                        color: tokens.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: tokens.onAccent,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ZplaySpacing.s8),
              Text(
                track.title,
                style: ZplayType.label.toStyle(color: tokens.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: ZplaySpacing.s2),
              Text(
                track.artist,
                style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MusicAlbumCard extends StatelessWidget {
  final MusicAlbum album;
  final VoidCallback onTap;

  const _MusicAlbumCard({
    required this.album,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => AnimatedScale(
        scale: state.highlighted ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: 145,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: ZplayRadius.mdAll,
                child: CachedNetworkImage(
                  imageUrl: album.coverUrl,
                  cacheManager: AppImageCache.manager,
                  memCacheWidth: 435,
                  width: 145,
                  height: 145,
                  fit: BoxFit.cover),
              ),
              const SizedBox(height: ZplaySpacing.s8),
              Text(
                album.title,
                style: ZplayType.label.toStyle(color: tokens.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: ZplaySpacing.s2),
              Text(
                album.artistName,
                style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MusicPlaylistCard extends StatelessWidget {
  final MusicPlaylist playlist;
  final VoidCallback onTap;

  const _MusicPlaylistCard({
    required this.playlist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => AnimatedScale(
        scale: state.highlighted ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: 145,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: ZplayRadius.mdAll,
                child: CachedNetworkImage(
                  imageUrl: playlist.coverUrl,
                  cacheManager: AppImageCache.manager,
                  memCacheWidth: 435,
                  width: 145,
                  height: 145,
                  fit: BoxFit.cover),
              ),
              const SizedBox(height: ZplaySpacing.s8),
              Text(
                playlist.title,
                style: ZplayType.label.toStyle(color: tokens.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: ZplaySpacing.s2),
              Text(
                '${playlist.trackCount} tracks',
                style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MusicTrackRow extends StatelessWidget {
  final MusicTrack track;
  final bool isPlaying;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onMoreTap;

  /// The row's position in the list it is drawn in, when that list is a
  /// tracklist. Album, playlist and chart rows are numbered like the prototype's
  /// `.music-track-number`; a flat result list leaves it null and the leading
  /// slot carries the artwork instead.
  final int? index;

  const _MusicTrackRow({
    required this.track,
    required this.isPlaying,
    required this.isCurrent,
    required this.onTap,
    required this.onMoreTap,
    this.index,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final television = FormFactorService.of(context) == FormFactor.television;
    final number = track.trackNumber ?? (index == null ? null : index! + 1);

    return FocusableCard(
      onTap: onTap,
      builder: (context, state) {
        return AnimatedContainer(
          duration: ZplayMotion.fast,
          curve: ZplayMotion.standard,
          constraints: BoxConstraints(minHeight: television ? 56 : 48),
          padding: const EdgeInsets.symmetric(
            horizontal: ZplaySpacing.s12,
            vertical: ZplaySpacing.s4,
          ),
          decoration: BoxDecoration(
            // The prototype's `.music-track-row`: a filled row that lightens
            // under the pointer, a reserved 2 dp border painted only while
            // focused, and no resting edge.
            color: isCurrent
                ? tokens.accentSubtle
                : (state.hovered ? tokens.surfaceRaised : tokens.surface),
            borderRadius: ZplayRadius.xsAll,
            border: Border.all(
              color: state.focused ? tokens.accent : Colors.transparent,
              width: ZplaySpacing.s2,
            ),
          ),
          child: Row(
            children: [
              // Leading slot: the track number in a tracklist, the artwork in a
              // flat result list. While this row is the playing one the slot
              // carries the transport glyph, so the number is never asked to do
              // two jobs.
              SizedBox(
                width: ZplaySpacing.s48,
                height: ZplaySpacing.s48,
                child: number != null
                    ? Center(
                        child: isCurrent
                            ? Icon(
                                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: tokens.accent,
                                size: 22,
                              )
                            : Text(
                                '$number',
                                style: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                              ),
                      )
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: ZplayRadius.smAll,
                            child: CachedNetworkImage(
                                imageUrl: track.coverUrl,
                                cacheManager: AppImageCache.manager,
                                memCacheWidth: 144,
                                width: ZplaySpacing.s48,
                                height: ZplaySpacing.s48,
                                fit: BoxFit.cover),
                          ),
                          if (isCurrent)
                            Container(
                              width: ZplaySpacing.s48,
                              height: ZplaySpacing.s48,
                              decoration: BoxDecoration(
                                color: tokens.bg.withValues(alpha: 0.45),
                                borderRadius: ZplayRadius.smAll,
                              ),
                              child: Icon(
                                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: tokens.accent,
                                size: 28,
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(width: ZplaySpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      style: ZplayType.subtitle.toStyle(
                        color: isCurrent ? tokens.accent : tokens.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      track.artist,
                      style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ZplaySpacing.s8),
              _buildDownloadButton(context),
              const SizedBox(width: ZplaySpacing.s4),
              Text(
                track.formattedDuration,
                style: ZplayType.labelNumeric.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(width: ZplaySpacing.s4),
              IconButton(
                icon: Icon(Icons.more_vert_rounded, color: tokens.textSecondary, size: 20),
                onPressed: onMoreTap,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDownloadButton(BuildContext context) {
    final tokens = context.tokens;
    final isDownloaded = MusicDownloadService.instance.isDownloaded(track.id);
    final task = MusicDownloadService.instance.getTask(track.id);
    final isDownloading = task != null &&
        (task.status == MusicDownloadStatus.extracting || task.status == MusicDownloadStatus.downloading);
    final isQueued = task != null && task.status == MusicDownloadStatus.queued;

    if (isDownloaded) {
      return Tooltip(
        message: 'Downloaded (Offline)',
        child: Container(
          padding: const EdgeInsets.all(ZplaySpacing.s4),
          child: Icon(
            Icons.download_done_rounded,
            color: tokens.info,
            size: 18,
          ),
        ),
      );
    }

    if (isDownloading) {
      return Tooltip(
        message: 'Downloading ${(task.progress * 100).toInt()}%',
        child: Container(
          width: 28,
          height: 28,
          padding: const EdgeInsets.all(ZplaySpacing.s4),
          child: CircularProgressIndicator(
            value: task.progress > 0.05 ? task.progress : null,
            strokeWidth: 2.2,
            color: tokens.info,
          ),
        ),
      );
    }

    if (isQueued) {
      return Tooltip(
        message: 'Queued for download',
        child: Container(
          padding: const EdgeInsets.all(ZplaySpacing.s4),
          child: Icon(
            Icons.hourglass_top_rounded,
            color: tokens.warning,
            size: 18,
          ),
        ),
      );
    }

    return IconButton(
      icon: Icon(Icons.download_rounded, color: tokens.textMuted, size: 18),
      tooltip: 'Download Track',
      onPressed: () {
        MusicDownloadService.instance.queueTrack(track);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${track.title}" to download queue'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }
}

class _MusicCardSizing {
  final double cardWidth;
  final double totalHeight;

  const _MusicCardSizing(this.cardWidth, this.totalHeight);

  factory _MusicCardSizing.fromWidth(double width) {
    if (width >= 1200) return const _MusicCardSizing(170, 240);
    if (width >= 800) return const _MusicCardSizing(150, 215);
    if (width >= 450) return const _MusicCardSizing(140, 200);
    return const _MusicCardSizing(125, 185);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drawers & Modals
// ─────────────────────────────────────────────────────────────────────────────

class _MusicLyricsDrawer extends StatelessWidget {
  final MusicTrack track;
  final MusicPlayerController playerController;
  final VoidCallback onClose;

  const _MusicLyricsDrawer({
    required this.track,
    required this.playerController,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final lyrics = playerController.currentLyrics;
    final activeIndex = playerController.activeLyricIndex;
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final tokens = context.tokens;

    return PerformanceLiquidLens(
      style: PerformanceGlassStyles.sheet,
      child: Container(
        width: isMobile ? MediaQuery.sizeOf(context).width : 360,
        decoration: BoxDecoration(
          color: tokens.surfaceOverlay.withValues(alpha: 0.96),
          borderRadius: isMobile
              ? const BorderRadius.vertical(top: Radius.circular(ZplayRadius.lg))
              : const BorderRadius.only(
                  topLeft: Radius.circular(ZplayRadius.lg),
                  bottomLeft: Radius.circular(ZplayRadius.lg),
                ),
          border: Border.all(color: tokens.borderStrong),
        ),
        padding: const EdgeInsets.all(ZplaySpacing.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.format_quote_rounded,
                  color: tokens.accent,
                  size: 22,
                ),
                const SizedBox(width: ZplaySpacing.s8),
                Text(
                  'Synced Lyrics',
                  style: ZplayType.title.toStyle(color: tokens.textPrimary),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: tokens.textEmphasis, size: 20),
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: ZplaySpacing.s12),
            if (playerController.isLoadingLyrics)
              Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: tokens.accent),
                ),
              )
            else if (!lyrics.isSynced && lyrics.plainLyrics.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    'No lyrics found for this track.',
                    style: ZplayType.label.toStyle(color: tokens.textMuted),
                  ),
                ),
              )
            else if (lyrics.isSynced)
              Expanded(
                child: ListView.builder(
                  itemCount: lyrics.syncedLines.length,
                  itemBuilder: (context, index) {
                    final line = lyrics.syncedLines[index];
                    final isActive = index == activeIndex;
                    return FocusableCard(
                      onTap: () => playerController.seekTo(line.timestamp),
                      builder: (context, _) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s8),
                        child: Text(
                          line.text,
                          style: (isActive ? ZplayType.title : ZplayType.subtitle)
                              .toStyle(
                            color: isActive ? tokens.accent : tokens.textSecondary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    lyrics.plainLyrics,
                    style: ZplayType.body
                        .toStyle(color: tokens.textEmphasis)
                        .copyWith(height: 1.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MusicQueueDrawer extends StatelessWidget {
  final VoidCallback onClose;

  const _MusicQueueDrawer({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final controller = MusicPlayerController.instance;
    final queue = controller.playlist;
    final currentIndex = controller.currentIndex;
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final tokens = context.tokens;

    return PerformanceLiquidLens(
      style: PerformanceGlassStyles.sheet,
      child: Container(
        width: isMobile ? MediaQuery.sizeOf(context).width : 360,
        decoration: BoxDecoration(
          color: tokens.surfaceOverlay.withValues(alpha: 0.96),
          borderRadius: isMobile
              ? const BorderRadius.vertical(top: Radius.circular(ZplayRadius.lg))
              : const BorderRadius.only(
                  topLeft: Radius.circular(ZplayRadius.lg),
                  bottomLeft: Radius.circular(ZplayRadius.lg),
                ),
          border: Border.all(color: tokens.borderStrong),
        ),
        padding: const EdgeInsets.all(ZplaySpacing.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.queue_music_rounded,
                  color: tokens.accent,
                  size: 22,
                ),
                const SizedBox(width: ZplaySpacing.s8),
                Text(
                  'Queue (${queue.length})',
                  style: ZplayType.title.toStyle(color: tokens.textPrimary),
                ),
                const Spacer(),
                if (queue.isNotEmpty)
                  TextButton(
                    onPressed: controller.clearQueue,
                    child: Text(
                      'Clear',
                      style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                    ),
                  ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: tokens.textEmphasis, size: 20),
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: ZplaySpacing.s12),
            if (queue.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    'Queue is empty',
                    style: ZplayType.label.toStyle(color: tokens.textMuted),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: queue.length,
                  separatorBuilder: (_, __) => const SizedBox(height: ZplaySpacing.s8),
                  itemBuilder: (context, index) {
                    final track = queue[index];
                    final isCurrent = index == currentIndex;
                    return ListTile(
                      dense: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: ZplayRadius.smAll,
                      ),
                      tileColor: isCurrent ? tokens.accentSubtle : tokens.surface,
                      leading: ClipRRect(
                        borderRadius: ZplayRadius.smAll,
                        child: CachedNetworkImage(
                          imageUrl: track.coverUrl,
                          cacheManager: AppImageCache.manager,
                          memCacheWidth: 108,
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover),
                      ),
                      title: Text(
                        track.title,
                        style: ZplayType.label.toStyle(
                          color: isCurrent ? tokens.accent : tokens.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        track.artist,
                        style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.close_rounded, color: tokens.textMuted, size: 16),
                        onPressed: () => controller.removeFromQueue(index),
                      ),
                      onTap: () => controller.playTrack(track, playlistQueue: queue),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MusicArtistDetailModal extends StatelessWidget {
  final MusicArtistDetails details;
  final VoidCallback onClose;
  final Function(MusicTrack, List<MusicTrack>) onPlayTrack;
  final Function(MusicTrack) onAddToPlaylist;
  final Function(String) onOpenAlbum;

  const _MusicArtistDetailModal({
    required this.details,
    required this.onClose,
    required this.onPlayTrack,
    required this.onAddToPlaylist,
    required this.onOpenAlbum,
  });

  @override
  Widget build(BuildContext context) {
    final artist = details.artist;
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 700;
    final tokens = context.tokens;

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            width: isMobile ? size.width - 24 : 720,
            height: isMobile ? size.height * 0.85 : 640,
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              borderRadius: ZplayRadius.lgAll,
              border: Border.all(color: tokens.borderStrong),
            ),
            child: Column(
              children: [
                Stack(
                  children: [
                    SizedBox(
                      height: 200,
                      width: double.infinity,
                      child: CachedNetworkImage(
                        imageUrl: artist.pictureUrl,
                        cacheManager: AppImageCache.manager,
                        fit: BoxFit.cover),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              tokens.surfaceOverlay,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: IconButton(
                        icon: Icon(Icons.close_rounded, color: tokens.textPrimary, size: 24),
                        onPressed: onClose,
                      ),
                    ),
                    Positioned(
                      left: 24,
                      bottom: 16,
                      child: Row(
                        children: [
                          Text(
                            artist.name,
                            style: ZplayType.display.toStyle(color: tokens.textPrimary),
                          ),
                          const SizedBox(width: ZplaySpacing.s16),
                          if (details.topTracks.isNotEmpty)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: tokens.accent,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: ZplayRadius.lgAll,
                                ),
                              ),
                              onPressed: () => onPlayTrack(details.topTracks.first, details.topTracks),
                              icon: Icon(Icons.play_arrow_rounded, color: tokens.onAccent),
                              label: Text(
                                'Play All',
                                style: ZplayType.label.toStyle(color: tokens.onAccent),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZplaySpacing.s24,
                      vertical: ZplaySpacing.s12,
                    ),
                    children: [
                      if (details.topTracks.isNotEmpty) ...[
                        Text(
                          'Top Songs',
                          style: ZplayType.title.toStyle(color: tokens.textPrimary),
                        ),
                        const SizedBox(height: ZplaySpacing.s12),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: details.topTracks.length.clamp(0, 10),
                          separatorBuilder: (_, __) => const SizedBox(height: ZplaySpacing.s8),
                          itemBuilder: (context, index) {
                            final track = details.topTracks[index];
                            return _MusicTrackRow(
                              track: track,
                              index: index,
                              isPlaying: false,
                              isCurrent: false,
                              onTap: () => onPlayTrack(track, details.topTracks),
                              onMoreTap: () => onAddToPlaylist(track),
                            );
                          },
                        ),
                        const SizedBox(height: ZplaySpacing.s24),
                      ],
                      if (details.albums.isNotEmpty) ...[
                        Text(
                          'Albums & Discography',
                          style: ZplayType.title.toStyle(color: tokens.textPrimary),
                        ),
                        const SizedBox(height: ZplaySpacing.s12),
                        SizedBox(
                          height: 180,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: details.albums.length,
                            separatorBuilder: (_, __) => const SizedBox(width: ZplaySpacing.s12),
                            itemBuilder: (context, index) {
                              final album = details.albums[index];
                              return _MusicAlbumCard(album: album, onTap: () => onOpenAlbum(album.id));
                            },
                          ),
                        ),
                      ],
                    ],
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

class _MusicAlbumDetailModal extends StatelessWidget {
  final MusicAlbumDetails details;
  final VoidCallback onClose;
  final Function(MusicTrack, List<MusicTrack>) onPlayTrack;
  final Function(MusicTrack) onAddToPlaylist;

  const _MusicAlbumDetailModal({
    required this.details,
    required this.onClose,
    required this.onPlayTrack,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final album = details.album;
    final tracks = details.tracks;
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 700;
    final television = FormFactorService.of(context) == FormFactor.television;
    final tokens = context.tokens;

    // The only truthful Hi-Res claim available: the player's own quality label,
    // and only while this album is the one playing. Nothing in the catalogue
    // carries a bit depth or sample rate.
    final player = MusicPlayerController.instance;
    final playingThisAlbum =
        album.id.isNotEmpty && player.currentTrack?.albumId == album.id;
    final albumOverline = playingThisAlbum
        ? (player.isCurrentTrackLossless
            ? 'HI-RES LOSSLESS · ${player.currentQualityLabel}'
            : player.currentQualityLabel)
        : 'ALBUM';

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            width: isMobile ? size.width - 24 : 720,
            height: isMobile ? size.height * 0.85 : 640,
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              borderRadius: ZplayRadius.lgAll,
              border: Border.all(color: tokens.borderStrong),
            ),
            padding: const EdgeInsets.all(ZplaySpacing.s24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Album hero, in the prototype's `.audiobook-hero-banner`
                // shape: the cover at 88, the details beside it and one row of
                // controls. The overline carries the real quality label while
                // this album is the one playing, and a plain `ALBUM` otherwise -
                // there is no bit-depth or sample-rate field anywhere in the app
                // to print a "24-bit / 96kHz" claim from.
                Container(
                  padding: const EdgeInsets.all(ZplaySpacing.s16),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: ZplayRadius.smAll,
                    border: Border.all(color: tokens.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: ZplayRadius.smAll,
                        child: CachedNetworkImage(
                            imageUrl: album.coverUrl,
                            cacheManager: AppImageCache.manager,
                            width: 88,
                            height: 88,
                            fit: BoxFit.cover),
                      ),
                      const SizedBox(width: ZplaySpacing.s20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              albumOverline,
                              style: ZplayType.overline.toStyle(color: tokens.accent),
                            ),
                            const SizedBox(height: ZplaySpacing.s4),
                            Text(
                              album.title,
                              style: (isMobile ? ZplayType.title : ZplayType.titleLarge)
                                  .toStyle(color: tokens.textPrimary),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: ZplaySpacing.s4),
                            Text(
                              [
                                album.artistName,
                                '${tracks.length} Tracks',
                                if (album.releaseDate.isNotEmpty) album.releaseDate,
                              ].join(' · '),
                              style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: ZplaySpacing.s12),
                            if (tracks.isNotEmpty)
                              Wrap(
                                spacing: ZplaySpacing.s8,
                                runSpacing: ZplaySpacing.s8,
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: tokens.accent,
                                      minimumSize: Size(0, television ? ZplaySpacing.s48 : 40),
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: ZplayRadius.smAll,
                                      ),
                                    ),
                                    onPressed: () => onPlayTrack(tracks.first, tracks),
                                    icon: Icon(Icons.play_arrow_rounded, color: tokens.onAccent),
                                    label: Text(
                                      'Play Album',
                                      style: ZplayType.label.toStyle(color: tokens.onAccent),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: tokens.textPrimary,
                                      minimumSize: Size(0, television ? ZplaySpacing.s48 : 40),
                                      side: BorderSide(color: tokens.borderStrong),
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: ZplayRadius.smAll,
                                      ),
                                    ),
                                    onPressed: () {
                                      MusicDownloadService.instance.queueTracks(tracks, collectionName: album.title);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Added ${tracks.length} tracks from "${album.title}" to download queue'),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.download_rounded, size: 18),
                                    label: const Text('Download Album'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: tokens.textEmphasis),
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ZplaySpacing.s16),
                Divider(color: tokens.borderDefault),
                const SizedBox(height: ZplaySpacing.s8),
                Expanded(
                  child: ListView.separated(
                    itemCount: tracks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: ZplaySpacing.s8),
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      return _MusicTrackRow(
                        track: track,
                        index: index,
                        isPlaying: false,
                        isCurrent: false,
                        onTap: () => onPlayTrack(track, tracks),
                        onMoreTap: () => onAddToPlaylist(track),
                      );
                    },
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

class _MusicCuratedPlaylistDetailModal extends StatelessWidget {
  final MusicPlaylistDetails details;
  final VoidCallback onClose;
  final Function(MusicTrack, List<MusicTrack>) onPlayTrack;
  final Function(MusicTrack) onAddToPlaylist;

  const _MusicCuratedPlaylistDetailModal({
    required this.details,
    required this.onClose,
    required this.onPlayTrack,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final playlist = details.playlist;
    final tracks = details.tracks;
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 700;
    final tokens = context.tokens;

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            width: isMobile ? size.width - 24 : 720,
            height: isMobile ? size.height * 0.85 : 640,
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              borderRadius: ZplayRadius.lgAll,
              border: Border.all(color: tokens.borderStrong),
            ),
            padding: const EdgeInsets.all(ZplaySpacing.s24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: ZplayRadius.mdAll,
                      child: CachedNetworkImage(
                        imageUrl: playlist.coverUrl,
                        cacheManager: AppImageCache.manager,
                        width: isMobile ? 80 : 120,
                        height: isMobile ? 80 : 120,
                        fit: BoxFit.cover),
                    ),
                    const SizedBox(width: ZplaySpacing.s16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            playlist.title,
                            style: (isMobile ? ZplayType.title : ZplayType.titleLarge)
                                .toStyle(color: tokens.textPrimary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: ZplaySpacing.s4),
                          Text(
                            'Curated by ${playlist.creatorName} • ${tracks.length} tracks',
                            style: ZplayType.label.toStyle(color: tokens.textSecondary),
                          ),
                          const SizedBox(height: ZplaySpacing.s12),
                          if (tracks.isNotEmpty)
                            Wrap(
                              spacing: ZplaySpacing.s8,
                              runSpacing: ZplaySpacing.s8,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: tokens.accent,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: ZplayRadius.mdAll,
                                    ),
                                  ),
                                  onPressed: () => onPlayTrack(tracks.first, tracks),
                                  icon: Icon(Icons.play_arrow_rounded, color: tokens.onAccent),
                                  label: Text(
                                    'Play Playlist',
                                    style: ZplayType.label.toStyle(color: tokens.onAccent),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: tokens.textPrimary,
                                    side: BorderSide(color: tokens.borderStrong),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: ZplayRadius.mdAll,
                                    ),
                                  ),
                                  onPressed: () {
                                    MusicDownloadService.instance.queueTracks(tracks, collectionName: playlist.title);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Added ${tracks.length} tracks from "${playlist.title}" to download queue'),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.download_rounded, size: 18),
                                  label: const Text('Download Playlist'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: tokens.textEmphasis),
                      onPressed: onClose,
                    ),
                  ],
                ),
                const SizedBox(height: ZplaySpacing.s16),
                Divider(color: tokens.borderDefault),
                const SizedBox(height: ZplaySpacing.s8),
                Expanded(
                  child: ListView.separated(
                    itemCount: tracks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: ZplaySpacing.s8),
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      return _MusicTrackRow(
                        track: track,
                        index: index,
                        isPlaying: false,
                        isCurrent: false,
                        onTap: () => onPlayTrack(track, tracks),
                        onMoreTap: () => onAddToPlaylist(track),
                      );
                    },
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

class _MusicUserPlaylistDetailModal extends StatelessWidget {
  final UserPlaylist playlist;
  final VoidCallback onClose;
  final Function(MusicTrack, List<MusicTrack>) onPlayTrack;
  final Function(String) onRemoveTrack;

  const _MusicUserPlaylistDetailModal({
    required this.playlist,
    required this.onClose,
    required this.onPlayTrack,
    required this.onRemoveTrack,
  });

  @override
  Widget build(BuildContext context) {
    final tracks = playlist.tracks;
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 700;
    final tokens = context.tokens;

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            width: isMobile ? size.width - 24 : 720,
            height: isMobile ? size.height * 0.85 : 640,
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              borderRadius: ZplayRadius.lgAll,
              border: Border.all(color: tokens.borderStrong),
            ),
            padding: const EdgeInsets.all(ZplaySpacing.s24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: isMobile ? 80 : 120,
                      height: isMobile ? 80 : 120,
                      decoration: BoxDecoration(
                        color: tokens.accentSubtle,
                        borderRadius: ZplayRadius.mdAll,
                      ),
                      child: Icon(
                        Icons.queue_music_rounded,
                        color: tokens.accent,
                        size: isMobile ? 36 : 48,
                      ),
                    ),
                    const SizedBox(width: ZplaySpacing.s16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            playlist.title,
                            style: (isMobile ? ZplayType.titleLarge : ZplayType.display)
                                .toStyle(color: tokens.textPrimary),
                          ),
                          const SizedBox(height: ZplaySpacing.s4),
                          Text(
                            'Custom Playlist • ${tracks.length} tracks',
                            style: ZplayType.label.toStyle(color: tokens.textSecondary),
                          ),
                          const SizedBox(height: ZplaySpacing.s12),
                          if (tracks.isNotEmpty)
                            Wrap(
                              spacing: ZplaySpacing.s8,
                              runSpacing: ZplaySpacing.s8,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: tokens.accent,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: ZplayRadius.mdAll,
                                    ),
                                  ),
                                  onPressed: () => onPlayTrack(tracks.first, tracks),
                                  icon: Icon(Icons.play_arrow_rounded, color: tokens.onAccent),
                                  label: Text(
                                    'Play Playlist',
                                    style: ZplayType.label.toStyle(color: tokens.onAccent),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: tokens.textPrimary,
                                    side: BorderSide(color: tokens.borderStrong),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: ZplayRadius.mdAll,
                                    ),
                                  ),
                                  onPressed: () {
                                    MusicDownloadService.instance.queueTracks(tracks, collectionName: playlist.title);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Added ${tracks.length} tracks from "${playlist.title}" to download queue'),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.download_rounded, size: 18),
                                  label: const Text('Download All'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: tokens.textEmphasis),
                      onPressed: onClose,
                    ),
                  ],
                ),
                const SizedBox(height: ZplaySpacing.s16),
                Divider(color: tokens.borderDefault),
                const SizedBox(height: ZplaySpacing.s8),
                Expanded(
                  child: tracks.isEmpty
                      ? Center(
                          child: Text(
                            'No tracks in this playlist yet',
                            style: ZplayType.body.toStyle(color: tokens.textMuted),
                          ),
                        )
                      : ListView.separated(
                          itemCount: tracks.length,
                          separatorBuilder: (_, __) => const SizedBox(height: ZplaySpacing.s8),
                          itemBuilder: (context, index) {
                            final track = tracks[index];
                            return ListTile(
                              shape: const RoundedRectangleBorder(
                                borderRadius: ZplayRadius.smAll,
                              ),
                              tileColor: tokens.surface,
                              leading: ClipRRect(
                                borderRadius: ZplayRadius.smAll,
                                child: CachedNetworkImage(
                                  imageUrl: track.coverUrl,
                                  cacheManager: AppImageCache.manager,
                                  memCacheWidth: 132,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover),
                              ),
                              title: Text(
                                track.title,
                                style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                              ),
                              subtitle: Text(
                                track.artist,
                                style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.delete_outline_rounded, color: tokens.textMuted),
                                onPressed: () => onRemoveTrack(track.id),
                              ),
                              onTap: () => onPlayTrack(track, tracks),
                            );
                          },
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

class _MusicExpandedPlayer extends StatefulWidget {
  final MusicPlayerController playerController;
  final bool isSaved;
  final VoidCallback onToggleSave;
  final VoidCallback onCollapse;
  final VoidCallback onQueueTap;
  final VoidCallback onAddToPlaylist;

  const _MusicExpandedPlayer({
    required this.playerController,
    required this.isSaved,
    required this.onToggleSave,
    required this.onCollapse,
    required this.onQueueTap,
    required this.onAddToPlaylist,
  });

  @override
  State<_MusicExpandedPlayer> createState() => _MusicExpandedPlayerState();
}

class _MusicExpandedPlayerState extends State<_MusicExpandedPlayer> with SingleTickerProviderStateMixin {
  late AnimationController _discAnimController;

  @override
  void initState() {
    super.initState();
    _discAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    if (widget.playerController.isPlaying) {
      _discAnimController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _MusicExpandedPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playerController.isPlaying && !_discAnimController.isAnimating) {
      _discAnimController.repeat();
    } else if (!widget.playerController.isPlaying && _discAnimController.isAnimating) {
      _discAnimController.stop();
    }
  }

  @override
  void dispose() {
    _discAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.playerController.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final palette = AppThemeService.currentPalette.value;
    final tokens = context.tokens;
    final preset = MusicSettings.selectedFullscreenPreset.value;
    final sourceColor =
        widget.playerController.isCurrentTrackLossless ? tokens.info : tokens.danger;
    final seekStyle = MusicSettings.customSeekbarStyle.value;
    final artStyle = MusicSettings.customArtworkStyle.value;
    final order = MusicSettings.componentOrderFullscreen.value;

    final screenSize = MediaQuery.sizeOf(context);
    final isDesktop = screenSize.width >= 800;
    final artSize = isDesktop
        ? 230.0
        : math.min(screenSize.width * 0.75, screenSize.height * 0.38);

    final playerBody = Column(
      children: [
        // Top Navigation & Actions Bar
        Row(
          children: [
            _MusicHoverable(
              scaleFactor: 1.1,
              child: IconButton(
                icon: Icon(
                  isDesktop ? Icons.close_rounded : Icons.keyboard_arrow_down_rounded,
                  color: tokens.textPrimary,
                  size: isDesktop ? 24 : 32,
                ),
                onPressed: widget.onCollapse,
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: () => _AudioSourceSelectorButton._showAudioSourceDialog(context),
              borderRadius: ZplayRadius.smAll,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZplaySpacing.s8,
                  vertical: ZplaySpacing.s4,
                ),
                decoration: BoxDecoration(
                  color: sourceColor.withValues(alpha: ZplayOpacity.overlayHover),
                  borderRadius: ZplayRadius.smAll,
                  border: Border.all(color: sourceColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.playerController.isCurrentTrackLossless
                          ? Icons.diamond_rounded
                          : Icons.play_circle_fill_rounded,
                      size: 13,
                      color: sourceColor,
                    ),
                    const SizedBox(width: ZplaySpacing.s4),
                    Text(
                      widget.playerController.currentQualityLabel.toUpperCase(),
                      style: ZplayType.overline.toStyle(color: sourceColor),
                    ),
                    const SizedBox(width: ZplaySpacing.s4),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 16,
                      color: sourceColor,
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            _MusicHoverable(
              scaleFactor: 1.1,
              child: IconButton(
                icon: Icon(Icons.more_horiz_rounded, color: tokens.textPrimary),
                onPressed: widget.onAddToPlaylist,
              ),
            ),
          ],
        ),
        if (!isDesktop) const Spacer() else const SizedBox(height: ZplaySpacing.s12),

        // Preset-based or Custom Arranged Body
        if (preset == MusicFullscreenPreset.customStudio)
          ...order.map((key) => _buildCustomComponent(key, track, palette, seekStyle, artStyle, artSize))
        else
          ..._buildPresetBody(preset, track, palette, seekStyle, artSize),

        if (!isDesktop) const Spacer() else const SizedBox(height: ZplaySpacing.s12),
      ],
    );

    if (isDesktop) {
      return Stack(
        alignment: Alignment.center,
        children: [
          // Dismissible Scrim with blur
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onCollapse,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.65),
                ),
              ),
            ),
          ),
          // Floating Modal Card
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 540,
                maxHeight: math.min(740, screenSize.height * 0.88),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: tokens.surfaceOverlay,
                  borderRadius: ZplayRadius.xlAll,
                  border: Border.all(color: tokens.borderStrong, width: 1.2),
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
                  borderRadius: ZplayRadius.xlAll,
                  child: Stack(
                    children: [
                      // Ambient blurred cover backdrop
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0.25,
                          child: CachedNetworkImage(
                            imageUrl: track.coverUrl,
                            cacheManager: AppImageCache.manager,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const SizedBox.shrink()),
                        ),
                      ),
                      Positioned.fill(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                          child: Container(
                            color: tokens.surfaceOverlay.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                      SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s24,
                          vertical: ZplaySpacing.s20,
                        ),
                        child: playerBody,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      color: tokens.bg,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ambient blurred cover backdrop
          Positioned.fill(
            child: Opacity(
              opacity: 0.28,
              child: CachedNetworkImage(
                imageUrl: track.coverUrl,
                cacheManager: AppImageCache.manager,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink()),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(
                color: tokens.bg.withValues(alpha: 0.85),
              ),
            ),
          ),

          // Main Expanded Player Column
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ZplaySpacing.s24,
                vertical: ZplaySpacing.s12,
              ),
              child: playerBody,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPresetBody(
    MusicFullscreenPreset preset,
    MusicTrack track,
    AppThemePalette palette,
    MusicSeekbarStyle seekStyle,
    double artSize,
  ) {
    return [
      // Artwork Section
      if (preset == MusicFullscreenPreset.vinylStudio)
        _buildVinylDiscArtwork(track, artSize)
      else if (preset == MusicFullscreenPreset.cyberWaveform)
        _buildCyberWaveArtwork(track, artSize)
      else if (preset == MusicFullscreenPreset.liquidGlassNeo)
        _buildLiquidGlassArtwork(track, artSize)
      else
        _buildCinematicArtwork(track, artSize),

      const SizedBox(height: ZplaySpacing.s24),

      // Track & Artist Title Row with Like Button
      _buildTitleRow(track),

      const SizedBox(height: ZplaySpacing.s16),

      // Scrubber Canvas
      MusicWaveformSeekbar(
        position: widget.playerController.position,
        duration: widget.playerController.duration,
        isPlaying: widget.playerController.isPlaying,
        style: preset == MusicFullscreenPreset.cyberWaveform
            ? MusicSeekbarStyle.waveformEqualizer
            : (preset == MusicFullscreenPreset.liquidGlassNeo
                ? MusicSeekbarStyle.liquidGlassSlider
                : seekStyle),
        onSeek: (pos) => widget.playerController.seekTo(pos),
      ),

      const SizedBox(height: ZplaySpacing.s16),

      // Main Controls
      _buildPlaybackControlsRow(palette),
    ];
  }

  Widget _buildCustomComponent(
    String key,
    MusicTrack track,
    AppThemePalette palette,
    MusicSeekbarStyle seekStyle,
    MusicArtworkStyle artStyle,
    double artSize,
  ) {
    final tokens = context.tokens;

    switch (key) {
      case 'artwork':
        return Padding(
          padding: const EdgeInsets.only(bottom: ZplaySpacing.s16),
          child: _buildCustomArtworkByStyle(track, artSize, artStyle),
        );
      case 'title':
        return Padding(
          padding: const EdgeInsets.only(bottom: ZplaySpacing.s12),
          child: _buildTitleRow(track),
        );
      case 'qualityBadge':
        return Padding(
          padding: const EdgeInsets.only(bottom: ZplaySpacing.s8),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s8,
              vertical: ZplaySpacing.s2,
            ),
            decoration: BoxDecoration(
              color: tokens.info.withValues(alpha: ZplayOpacity.overlayHover),
              borderRadius: ZplayRadius.xsAll,
              border: Border.all(color: tokens.info.withValues(alpha: 0.4)),
            ),
            child: Text(
              '${widget.playerController.currentQualityLabel.toUpperCase()} • HI-RES LOSSLESS AUDIO',
              style: ZplayType.overline.toStyle(color: tokens.info),
            ),
          ),
        );
      case 'seekbar':
        return Padding(
          padding: const EdgeInsets.only(bottom: ZplaySpacing.s16),
          child: MusicWaveformSeekbar(
            position: widget.playerController.position,
            duration: widget.playerController.duration,
            isPlaying: widget.playerController.isPlaying,
            style: seekStyle,
            onSeek: (pos) => widget.playerController.seekTo(pos),
          ),
        );
      case 'mainControls':
        return Padding(
          padding: const EdgeInsets.only(bottom: ZplaySpacing.s12),
          child: _buildPlaybackControlsRow(palette),
        );
      case 'secondaryControls':
        return Padding(
          padding: const EdgeInsets.only(bottom: ZplaySpacing.s8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.format_quote_rounded, color: tokens.textEmphasis, size: 22),
                onPressed: widget.onCollapse,
              ),
              IconButton(
                icon: Icon(Icons.queue_music_rounded, color: tokens.textEmphasis, size: 22),
                onPressed: widget.onQueueTap,
              ),
            ],
          ),
        );
      case 'extraActions':
        return Padding(
          padding: const EdgeInsets.only(bottom: ZplaySpacing.s4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: widget.onQueueTap,
                icon: Icon(Icons.queue_music_rounded, color: tokens.accent, size: 16),
                label: Text(
                  'Playing Queue',
                  style: ZplayType.bodySmall.toStyle(color: tokens.textPrimary),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: tokens.accent.withValues(alpha: 0.4)),
                  shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                ),
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTitleRow(MusicTrack track) {
    final tokens = context.tokens;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: ZplaySpacing.s4),
              Text(
                track.artist,
                style: ZplayType.subtitle.toStyle(color: tokens.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        MusicInteractivePhysicsButton(
          effect: MusicSettings.customHoverEffect.value,
          glowColor: tokens.danger,
          borderRadius: ZplayRadius.lgAll,
          onTap: widget.onToggleSave,
          child: Padding(
            padding: const EdgeInsets.all(ZplaySpacing.s4),
            child: Icon(
              widget.isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: widget.isSaved ? tokens.danger : tokens.textEmphasis,
              size: 28,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackControlsRow(AppThemePalette palette) {
    final hoverEffect = MusicSettings.customHoverEffect.value;
    final playBtnStyle = MusicSettings.customPlayButtonStyle.value;
    final tokens = context.tokens;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        MusicInteractivePhysicsButton(
          effect: hoverEffect,
          glowColor: tokens.accent,
          borderRadius: ZplayRadius.mdAll,
          onTap: widget.playerController.toggleShuffle,
          child: Padding(
            padding: const EdgeInsets.all(ZplaySpacing.s8),
            child: Icon(
              Icons.shuffle_rounded,
              color: widget.playerController.isShuffle ? tokens.accent : tokens.textMuted,
              size: 24,
            ),
          ),
        ),
        MusicInteractivePhysicsButton(
          effect: hoverEffect,
          glowColor: tokens.accent,
          borderRadius: ZplayRadius.mdAll,
          onTap: widget.playerController.playPrevious,
          child: Padding(
            padding: const EdgeInsets.all(ZplaySpacing.s8),
            child: Icon(Icons.skip_previous_rounded, color: tokens.textPrimary, size: 36),
          ),
        ),
        MusicInteractivePhysicsButton(
          effect: hoverEffect,
          glowColor: tokens.accent,
          borderRadius: ZplayRadius.xlAll,
          onTap: widget.playerController.togglePlayPause,
          child: widget.playerController.isLoading
              ? SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(color: tokens.accent, strokeWidth: 3),
                )
              : _buildExpandedPlayButtonIcon(playBtnStyle, palette),
        ),
        MusicInteractivePhysicsButton(
          effect: hoverEffect,
          glowColor: tokens.accent,
          borderRadius: ZplayRadius.mdAll,
          onTap: widget.playerController.playNext,
          child: Padding(
            padding: const EdgeInsets.all(ZplaySpacing.s8),
            child: Icon(Icons.skip_next_rounded, color: tokens.textPrimary, size: 36),
          ),
        ),
        MusicInteractivePhysicsButton(
          effect: hoverEffect,
          glowColor: tokens.accent,
          borderRadius: ZplayRadius.mdAll,
          onTap: widget.playerController.toggleRepeat,
          child: Padding(
            padding: const EdgeInsets.all(ZplaySpacing.s8),
            child: Icon(
              widget.playerController.repeatMode == MusicRepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              color: widget.playerController.repeatMode != MusicRepeatMode.off ? tokens.accent : tokens.textMuted,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedPlayButtonIcon(MusicPlayButtonStyle style, AppThemePalette palette) {
    final isPlaying = widget.playerController.isPlaying;
    final icon = isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;
    final tokens = context.tokens;

    if (style == MusicPlayButtonStyle.liquidGlassNeo) {
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: tokens.accent.withValues(alpha: 0.3),
          shape: BoxShape.circle,
          border: Border.all(color: tokens.textSecondary, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: tokens.accent.withValues(alpha: 0.5),
              blurRadius: 20,
            ),
          ],
        ),
        child: Icon(icon, color: tokens.onAccent, size: 38),
      );
    }

    if (style == MusicPlayButtonStyle.neonSquare) {
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: ZplayRadius.mdAll,
          gradient: LinearGradient(colors: [tokens.accent, palette.accentColor]),
          boxShadow: [
            BoxShadow(color: tokens.accent.withValues(alpha: 0.6), blurRadius: 20),
          ],
        ),
        child: Icon(icon, color: tokens.onAccent, size: 38),
      );
    }

    // Default: Circle Glow
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [tokens.accent, palette.accentColor]),
        boxShadow: [
          BoxShadow(color: tokens.accent.withValues(alpha: 0.6), blurRadius: 22, spreadRadius: 2),
        ],
      ),
      child: Icon(icon, color: tokens.onAccent, size: 40),
    );
  }

  Widget _buildVinylDiscArtwork(MusicTrack track, double size) {
    final tokens = context.tokens;

    return AnimatedBuilder(
      animation: _discAnimController,
      builder: (context, child) => Transform.rotate(
        angle: widget.playerController.isPlaying ? _discAnimController.value * 2 * math.pi : 0,
        child: child,
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tokens.surface,
          border: Border.all(color: tokens.borderStrong, width: 4),
          boxShadow: [
            BoxShadow(
              color: tokens.accent.withValues(alpha: 0.4),
              blurRadius: 36,
            ),
          ],
        ),
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.22),
            child: CachedNetworkImage(
              imageUrl: track.coverUrl,
              cacheManager: AppImageCache.manager,
              width: size * 0.44,
              height: size * 0.44,
              fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }

  Widget _buildCyberWaveArtwork(MusicTrack track, double size) {
    final tokens = context.tokens;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: ZplayRadius.lgAll,
        border: Border.all(color: tokens.accent, width: 2),
        boxShadow: [
          BoxShadow(
            color: tokens.accent.withValues(alpha: 0.45),
            blurRadius: 30,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: ZplayRadius.lgAll,
        child: CachedNetworkImage(
          imageUrl: track.coverUrl,
          cacheManager: AppImageCache.manager,
          fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildLiquidGlassArtwork(MusicTrack track, double size) {
    final tokens = context.tokens;

    return PerformanceLiquidLens(
      style: PerformanceGlassStyles.sheet,
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(ZplaySpacing.s4),
        decoration: BoxDecoration(
          color: tokens.borderDefault,
          borderRadius: ZplayRadius.xlAll,
          border: Border.all(color: tokens.textDisabled),
          boxShadow: [
            BoxShadow(
              color: tokens.accent.withValues(alpha: 0.35),
              blurRadius: 28,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: ZplayRadius.lgAll,
          child: CachedNetworkImage(
            imageUrl: track.coverUrl,
            cacheManager: AppImageCache.manager,
            fit: BoxFit.cover),
        ),
      ),
    );
  }

  Widget _buildCinematicArtwork(MusicTrack track, double size) {
    return ClipRRect(
      borderRadius: ZplayRadius.lgAll,
      child: CachedNetworkImage(
        imageUrl: track.coverUrl,
        cacheManager: AppImageCache.manager,
        width: size,
        height: size,
        fit: BoxFit.cover),
    );
  }

  Widget _buildCustomArtworkByStyle(MusicTrack track, double size, MusicArtworkStyle style) {
    final tokens = context.tokens;

    if (style == MusicArtworkStyle.vinylSpinningDisc) {
      return _buildVinylDiscArtwork(track, size);
    }
    if (style == MusicArtworkStyle.floatingCard3D) {
      return _buildLiquidGlassArtwork(track, size);
    }
    if (style == MusicArtworkStyle.glowSphere) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: tokens.accent.withValues(alpha: 0.5),
              blurRadius: 36,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: CachedNetworkImage(
            imageUrl: track.coverUrl,
            cacheManager: AppImageCache.manager,
            fit: BoxFit.cover),
        ),
      );
    }
    return _buildCinematicArtwork(track, size);
  }
}

class _MusicShortcutsModal extends StatelessWidget {
  final VoidCallback onClose;

  const _MusicShortcutsModal({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final shortcuts = [
      {'key': 'Space / K', 'desc': 'Toggle Play / Pause'},
      {'key': 'J', 'desc': 'Seek -5 seconds backward'},
      {'key': 'L', 'desc': 'Seek +5 seconds forward'},
      {'key': 'M', 'desc': 'Toggle Mute / Unmute'},
      {'key': 'Q', 'desc': 'Toggle Queue Drawer'},
      {'key': 'F', 'desc': 'Toggle Fullscreen Now Playing'},
      {'key': '? / Shift + /', 'desc': 'Show Shortcuts'},
    ];

    final tokens = context.tokens;

    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      child: Center(
        child: PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(ZplaySpacing.s24),
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              borderRadius: ZplayRadius.lgAll,
              border: Border.all(color: tokens.borderStrong),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.keyboard_rounded, color: tokens.accent, size: 24),
                    const SizedBox(width: ZplaySpacing.s8),
                    Text(
                      'Keyboard Shortcuts',
                      style: ZplayType.title.toStyle(color: tokens.textPrimary),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: tokens.textEmphasis),
                      onPressed: onClose,
                    ),
                  ],
                ),
                const SizedBox(height: ZplaySpacing.s16),
                for (final s in shortcuts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZplaySpacing.s8,
                            vertical: ZplaySpacing.s4,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.surfaceRaised,
                            borderRadius: ZplayRadius.xsAll,
                            border: Border.all(color: tokens.borderStrong),
                          ),
                          child: Text(
                            s['key']!,
                            style: ZplayType.bodySmall.toStyle(color: tokens.accent),
                          ),
                        ),
                        Text(
                          s['desc']!,
                          style: ZplayType.label.toStyle(color: tokens.textEmphasis),
                        ),
                      ],
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

class _MusicDownloadedTracksModal extends StatefulWidget {
  final VoidCallback onClose;
  final Function(MusicTrack, List<MusicTrack>) onPlayTrack;
  final Function(MusicTrack) onAddToPlaylist;

  const _MusicDownloadedTracksModal({
    required this.onClose,
    required this.onPlayTrack,
    required this.onAddToPlaylist,
  });

  @override
  State<_MusicDownloadedTracksModal> createState() => _MusicDownloadedTracksModalState();
}

class _MusicDownloadedTracksModalState extends State<_MusicDownloadedTracksModal> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloadService = MusicDownloadService.instance;
    final allDownloaded = downloadService.downloadedTracks;
    final queue = downloadService.queue;
    final totalBytes = downloadService.totalDownloadedSizeBytes;
    final sizeMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);

    final filtered = _searchQuery.isEmpty
        ? allDownloaded
        : allDownloaded.where((t) =>
            t.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            t.artist.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            t.album.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 700;
    final tokens = context.tokens;

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            width: isMobile ? size.width - 24 : 760,
            height: isMobile ? size.height * 0.88 : 660,
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              borderRadius: ZplayRadius.lgAll,
              border: Border.all(color: tokens.borderStrong),
            ),
            padding: const EdgeInsets.all(ZplaySpacing.s20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: isMobile ? 48 : 56,
                      height: isMobile ? 48 : 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [tokens.info, tokens.accent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: ZplayRadius.mdAll,
                      ),
                      child: Icon(
                        Icons.offline_pin_rounded,
                        color: tokens.onAccent,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: ZplaySpacing.s16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Downloaded Songs',
                            style: (isMobile ? ZplayType.title : ZplayType.titleLarge)
                                .toStyle(color: tokens.textPrimary),
                          ),
                          const SizedBox(height: ZplaySpacing.s2),
                          Text(
                            '${allDownloaded.length} offline tracks • $sizeMb MB storage',
                            style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: tokens.textEmphasis),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),

                const SizedBox(height: ZplaySpacing.s12),

                // Active Download Queue Card
                if (queue.isNotEmpty) ...[
                  _buildQueueBanner(queue, downloadService),
                  const SizedBox(height: ZplaySpacing.s12),
                ],

                // Action Bar: Play All, Shuffle, Search
                Row(
                  children: [
                    if (filtered.isNotEmpty) ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tokens.info,
                          foregroundColor: tokens.onAccent,
                          shape: const RoundedRectangleBorder(
                            borderRadius: ZplayRadius.mdAll,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZplaySpacing.s16,
                            vertical: ZplaySpacing.s8,
                          ),
                        ),
                        onPressed: () {
                          final tracks = filtered.map((d) => d.toMusicTrack()).toList();
                          widget.onPlayTrack(tracks.first, tracks);
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: Text(
                          'Play All',
                          style: ZplayType.label.toStyle(color: tokens.onAccent),
                        ),
                      ),
                      const SizedBox(width: ZplaySpacing.s8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: tokens.textPrimary,
                          side: BorderSide(color: tokens.borderStrong),
                          shape: const RoundedRectangleBorder(
                            borderRadius: ZplayRadius.mdAll,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZplaySpacing.s12,
                            vertical: ZplaySpacing.s8,
                          ),
                        ),
                        onPressed: () {
                          final tracks = filtered.map((d) => d.toMusicTrack()).toList()..shuffle();
                          widget.onPlayTrack(tracks.first, tracks);
                        },
                        icon: const Icon(Icons.shuffle_rounded, size: 18),
                        label: const Text('Shuffle'),
                      ),
                    ],
                    const Spacer(),
                    SizedBox(
                      width: isMobile ? 140 : 200,
                      height: 38,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _searchQuery = v),
                        style: ZplayType.bodySmall.toStyle(color: tokens.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Search offline...',
                          hintStyle: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                          prefixIcon: Icon(Icons.search_rounded, color: tokens.info, size: 16),
                          filled: true,
                          fillColor: tokens.borderSubtle,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: ZplaySpacing.s8,
                            vertical: 0,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: ZplayRadius.smAll,
                            borderSide: BorderSide(color: tokens.borderDefault),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: ZplayRadius.smAll,
                            borderSide: BorderSide(color: tokens.borderDefault),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: ZplaySpacing.s12),
                Divider(color: tokens.borderDefault),
                const SizedBox(height: ZplaySpacing.s4),

                // Downloaded Tracks List
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.cloud_download_rounded,
                                color: tokens.textDisabled,
                                size: 48,
                              ),
                              const SizedBox(height: ZplaySpacing.s12),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No downloaded tracks match "$_searchQuery"'
                                    : 'No offline downloads yet.\nTap the download icon on any song, album, or playlist to listen offline.',
                                textAlign: TextAlign.center,
                                style: ZplayType.label
                                    .toStyle(color: tokens.textSecondary)
                                    .copyWith(height: 1.4),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: ZplaySpacing.s4),
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final track = item.toMusicTrack();
                            final itemSizeMb = (item.fileSizeBytes / (1024 * 1024)).toStringAsFixed(1);
                            final isFlac = item.format.toLowerCase() == 'flac';

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: ZplaySpacing.s8,
                                vertical: ZplaySpacing.s2,
                              ),
                              shape: const RoundedRectangleBorder(
                                borderRadius: ZplayRadius.mdAll,
                              ),
                              tileColor: tokens.surface,
                              leading: ClipRRect(
                                borderRadius: ZplayRadius.smAll,
                                child: item.localCoverPath.isNotEmpty && File(item.localCoverPath).existsSync()
                                    ? Image.file(
                                        File(item.localCoverPath),
                                        width: 46,
                                        height: 46,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _buildFallbackCover(track),
                                      )
                                    : _buildFallbackCover(track),
                              ),
                              title: Text(
                                item.title,
                                style: ZplayType.label.toStyle(color: tokens.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${item.artist} • ${item.album}',
                                      style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: ZplaySpacing.s8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: ZplaySpacing.s4,
                                      vertical: ZplaySpacing.s2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: (isFlac ? tokens.accent : tokens.info)
                                          .withValues(alpha: 0.25),
                                      borderRadius: ZplayRadius.xsAll,
                                    ),
                                    child: Text(
                                      isFlac ? 'FLAC' : item.format.toUpperCase(),
                                      style: ZplayType.overline.toStyle(
                                        color: isFlac ? tokens.accentHover : tokens.info,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: ZplaySpacing.s4),
                                  Text(
                                    '$itemSizeMb MB',
                                    style: ZplayType.caption.toStyle(color: tokens.textMuted),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.delete_outline_rounded, color: tokens.textMuted, size: 20),
                                    tooltip: 'Delete from downloads',
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          backgroundColor: tokens.surfaceOverlay,
                                          title: Text(
                                            'Delete Downloaded Song',
                                            style: ZplayType.title.toStyle(color: tokens.textPrimary),
                                          ),
                                          content: Text(
                                            'Delete "${item.title}" from offline storage?',
                                            style: ZplayType.body.toStyle(color: tokens.textEmphasis),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(c, false),
                                              child: Text(
                                                'Cancel',
                                                style: ZplayType.label
                                                    .toStyle(color: tokens.textSecondary),
                                              ),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: tokens.danger,
                                              ),
                                              onPressed: () => Navigator.pop(c, true),
                                              child: Text(
                                                'Delete',
                                                style: ZplayType.label.toStyle(color: tokens.onAccent),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await downloadService.deleteDownloadedTrack(item.id);
                                        setState(() {});
                                      }
                                    },
                                  ),
                                ],
                              ),
                              onTap: () {
                                final allTracks = filtered.map((d) => d.toMusicTrack()).toList();
                                widget.onPlayTrack(track, allTracks);
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
    );
  }

  Widget _buildFallbackCover(MusicTrack track) {
    final tokens = context.tokens;

    if (track.coverUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: track.coverUrl,
        cacheManager: AppImageCache.manager,
        memCacheWidth: 138,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(
          width: 46,
          height: 46,
          color: tokens.surface,
          child: Icon(Icons.music_note_rounded, color: tokens.textMuted, size: 24),
        ));
    }
    return Container(
      width: 46,
      height: 46,
      color: tokens.surface,
      child: Icon(Icons.music_note_rounded, color: tokens.textMuted, size: 24),
    );
  }

  Widget _buildQueueBanner(List<MusicDownloadTask> queue, MusicDownloadService service) {
    final tokens = context.tokens;
    final activeTask = queue.firstWhere(
      (t) => t.status == MusicDownloadStatus.downloading || t.status == MusicDownloadStatus.extracting,
      orElse: () => queue.first,
    );
    final isExtracting = activeTask.status == MusicDownloadStatus.extracting;
    final progress = activeTask.progress.clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZplaySpacing.s12,
        vertical: ZplaySpacing.s8,
      ),
      decoration: BoxDecoration(
        color: tokens.info.withValues(alpha: ZplayOpacity.overlayHover),
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(color: tokens.info.withValues(alpha: ZplayOpacity.textMuted)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: isExtracting ? null : progress,
                  color: tokens.info,
                ),
              ),
              const SizedBox(width: ZplaySpacing.s8),
              Expanded(
                child: Text(
                  isExtracting
                      ? 'Extracting stream for "${activeTask.track.title}"...'
                      : 'Downloading "${activeTask.track.title}" (${(progress * 100).toInt()}%)',
                  style: ZplayType.caption.toStyle(color: tokens.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: ZplaySpacing.s8),
              Text(
                '${queue.length} in queue',
                style: ZplayType.caption.toStyle(color: tokens.info),
              ),
              const SizedBox(width: ZplaySpacing.s4),
              InkWell(
                onTap: () => service.cancelTask(activeTask.track.id),
                child: Padding(
                  padding: const EdgeInsets.all(ZplaySpacing.s4),
                  child: Icon(Icons.close_rounded, color: tokens.textSecondary, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZplaySpacing.s4),
          ClipRRect(
            borderRadius: ZplayRadius.xsAll,
            child: LinearProgressIndicator(
              value: isExtracting ? null : progress,
              backgroundColor: tokens.borderDefault,
              valueColor: AlwaysStoppedAnimation<Color>(tokens.info),
              minHeight: 3,
            ),
          ),
        ],
      ),
    );
  }
}
