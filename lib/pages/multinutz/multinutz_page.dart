import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../services/theme/design_tokens.dart';
import '../../services/theme/glass_settings.dart';
import '../../services/iptv/iptv_controller.dart';
import '../../models/iptv/iptv_models.dart';
import '../../services/iptv/iptv_storage.dart';
import '../../services/player/player_settings.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/pill_button.dart';
import '../../widgets/iptv/multinutz_channel_sheet.dart';
import '../../services/iptv/hardcoded_channels.dart';
import '../../services/storage/app_image_cache.dart';

class MultiStreamCell {
  int index;
  final Player player;
  final VideoController controller;
  String? channelName;
  String? streamUrl;
  List<ChannelHit>? availableHits;
  int? currentHitIndex;
  bool isMuted;
  double volume;
  bool isScanning;
  bool isPlaying;
  String? statusText;

  MultiStreamCell({
    required this.index,
    required this.player,
    required this.controller,
    this.channelName,
    this.streamUrl,
    this.availableHits,
    this.currentHitIndex,
    this.isMuted = true,
    this.volume = 0.5,
    this.isScanning = false,
    this.isPlaying = false,
    this.statusText,
  });
}

enum MultiNutzLayout {
  single('Single'),
  vertical2('Vertical 2'),
  vertical3('Vertical 3'),
  vertical4('Vertical 4'),
  vertical5('Vertical 5'),
  vertical6('Vertical 6'),
  grid2x2('Grid 2x2'),
  grid2x3('Grid 2x3');

  final String label;
  const MultiNutzLayout(this.label);
}

class MultiNutzPage extends StatefulWidget {
  const MultiNutzPage({super.key});

  @override
  State<MultiNutzPage> createState() => _MultiNutzPageState();
}

class _MultiNutzPageState extends State<MultiNutzPage>
    with WidgetsBindingObserver {
  final List<MultiStreamCell> _cells = [];
  final List<StreamSubscription> _playingSubs = [];
  MultiNutzLayout _currentLayout = MultiNutzLayout.vertical3; // Default to 3 vertical
  int _activeCells = 3;
  int? _fullscreenIndex;
  bool _isRearrangeMode = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    WidgetsBinding.instance.addObserver(this);

    // Allow all orientations (portrait + landscape)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _initPlayers();
    _restoreSession();
  }

  void _initPlayers() {
    for (int i = 0; i < 6; i++) {
      final player = Player(
        configuration: PlayerSettings.getMediaKitPlayerConfiguration(),
      );
      final controller = VideoController(
        player,
        configuration: PlayerSettings.getVideoControllerConfiguration(),
      );

      // Apply initial muted setting (all muted initially to prevent audio chaos)
      player.setVolume(0.0);

      final cell = MultiStreamCell(
        index: i,
        player: player,
        controller: controller,
        isMuted: true,
        volume: 0.5,
      );

      _cells.add(cell);

      // Setup listening states
      _playingSubs.add(player.stream.playing.listen((playing) {
        if (mounted) {
          setState(() {
            cell.isPlaying = playing;
          });
        }
      }));
    }
  }

  Future<void> _restoreSession() async {
    final saved = await MultiNutzSessionStore.load();
    if (saved.isEmpty) return;
    for (final state in saved) {
      if (state.index >= _cells.length) continue;
      final cell = _cells[state.index];
      cell.channelName = state.channelName;
      cell.streamUrl = state.streamUrl;
      cell.volume = state.volume;
      cell.isMuted = state.isMuted;
      cell.isPlaying = state.wasPlaying;
      cell.isScanning = true;
      cell.statusText = 'Restoring...';
      try {
        await cell.player.open(Media(state.streamUrl!));
        cell.player.setVolume(state.isMuted ? 0.0 : state.volume * 100.0);
        if (state.wasPlaying) {
          cell.player.play();
        }
        cell.isScanning = false;
        cell.statusText = null;
      } catch (_) {
        cell.isScanning = false;
        cell.statusText = 'Playback error';
      }
    }
if (mounted) {
        setState(() {});
      }
    }

  Future<void> _saveSession() async {
    final states = <MultiNutzCellState>[];
    for (final cell in _cells) {
      if (cell.streamUrl != null && cell.streamUrl!.isNotEmpty) {
        states.add(MultiNutzCellState(
          index: cell.index,
          channelName: cell.channelName,
          streamUrl: cell.streamUrl,
          volume: cell.volume,
          isMuted: cell.isMuted,
          wasPlaying: cell.isPlaying,
        ));
      }
    }
    await MultiNutzSessionStore.save(states);
  }

  void _pauseAllPlayers() {
    for (final cell in _cells) {
      if (cell.streamUrl != null && cell.isPlaying) {
        cell.player.pause();
      }
    }
  }

  void _resumeAllPlayers() {
    for (final cell in _cells) {
      if (cell.streamUrl != null && !cell.isPlaying) {
        cell.player.play();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        _pauseAllPlayers();
        _saveSession();
        break;
      case AppLifecycleState.resumed:
        _resumeAllPlayers();
        break;
      case AppLifecycleState.detached:
        _pauseAllPlayers();
        _saveSession();
        break;
    }
  }

  void _setLayout(MultiNutzLayout layout) {
    setState(() {
      _currentLayout = layout;
      
      // Set active cells based on layout
      switch (layout) {
        case MultiNutzLayout.single:
          _activeCells = 1;
          break;
        case MultiNutzLayout.vertical2:
          _activeCells = 2;
          break;
        case MultiNutzLayout.vertical3:
          _activeCells = 3;
          break;
        case MultiNutzLayout.vertical4:
          _activeCells = 4;
          break;
        case MultiNutzLayout.vertical5:
          _activeCells = 5;
          break;
        case MultiNutzLayout.vertical6:
        case MultiNutzLayout.grid2x2:
          _activeCells = 6;
          break;
        case MultiNutzLayout.grid2x3:
          _activeCells = 6;
          break;
      }
    });
  }

  void _navigateLayoutBackward() {
    const layouts = MultiNutzLayout.values;
    final currentIndex = layouts.indexOf(_currentLayout);
    if (currentIndex > 0) {
      _setLayout(layouts[currentIndex - 1]);
    }
  }

  void _navigateLayoutForward() {
    const layouts = MultiNutzLayout.values;
    final currentIndex = layouts.indexOf(_currentLayout);
    if (currentIndex < layouts.length - 1) {
      _setLayout(layouts[currentIndex + 1]);
    }
  }

  Future<void> _switchStreamInCell(int index, int hitIndex) async {
    if (index >= _cells.length) return;
    final cell = _cells[index];
    final hits = cell.availableHits;
    if (hits == null || hitIndex < 0 || hitIndex >= hits.length) return;
    final hit = hits[hitIndex];

    setState(() {
      cell.currentHitIndex = hitIndex;
      cell.streamUrl = hit.streamUrl;
      cell.statusText = 'Switching feed...';
    });

    try {
      await cell.player.open(Media(hit.streamUrl));
      if (mounted) {
        setState(() {
          cell.statusText = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          cell.statusText = 'Switch failed';
        });
      }
    }
  }

  void _showStreamPicker(int index) {
    final cell = _cells[index];
    final hits = cell.availableHits;
    if (hits == null || hits.isEmpty) return;

    final tokens = context.tokens;
    showModalBottomSheet(
      context: context,
      backgroundColor: tokens.surfaceOverlay,
      shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.sheetTop),
      builder: (context) {
        return ListView.builder(
          padding: const EdgeInsets.all(ZplaySpacing.s16),
          itemCount: hits.length,
          itemBuilder: (context, i) {
            final hit = hits[i];
            final isSelected = cell.currentHitIndex == i;
            return Container(
              margin: const EdgeInsets.only(bottom: ZplaySpacing.s8),
              decoration: BoxDecoration(
                color: isSelected ? tokens.accentSubtle : tokens.borderSubtle,
                borderRadius: ZplayRadius.smAll,
                border: Border.all(
                  color: isSelected ? tokens.accent : tokens.borderDefault,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: ListTile(
                leading: Icon(Icons.live_tv_rounded, color: tokens.textEmphasis, size: 20),
                title: Text(
                  hit.portal.name,
                  style: ZplayType.label
                      .copyWith(weight: FontWeight.w700)
                      .toStyle(color: tokens.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  hit.stream.name,
                  style: ZplayType.caption.toStyle(
                    color: tokens.accent.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isSelected
                    ? Icon(Icons.check_circle_rounded, color: tokens.accent, size: 18)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _switchStreamInCell(index, i);
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadCustomUrlInCell(int index, String name, String url) async {
    if (index >= _cells.length) return;
    final cell = _cells[index];
    setState(() {
      cell.channelName = name.isNotEmpty ? name : 'Custom Stream';
      cell.isScanning = true;
      cell.statusText = 'Connecting...';
      cell.streamUrl = url;
    });

    try {
      await cell.player.open(Media(url));
      if (mounted) {
        setState(() {
          cell.isScanning = false;
          cell.statusText = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          cell.isScanning = false;
          cell.statusText = 'Playback error';
        });
      }
    }
  }

  void _onCellVolumeToggle(int index) {
    if (index >= _cells.length) return;
    final cell = _cells[index];
    setState(() {
      cell.isMuted = !cell.isMuted;
      cell.player.setVolume(cell.isMuted ? 0.0 : cell.volume * 100.0);
    });
  }

  void _onCellVolumeChanged(int index, double value) {
    if (index >= _cells.length) return;
    final cell = _cells[index];
    setState(() {
      cell.volume = value;
      cell.isMuted = value <= 0.01;
      cell.player.setVolume(value * 100.0);
    });
  }

  void _onCellPauseToggle(int index) {
    if (index >= _cells.length) return;
    final cell = _cells[index];
    if (cell.streamUrl == null) return;
    cell.player.playOrPause();
  }

  void _onCellRemove(int index) {
    if (index >= _cells.length) return;
    final cell = _cells[index];
    cell.player.stop();
    setState(() {
      cell.channelName = null;
      cell.streamUrl = null;
      cell.isScanning = false;
      cell.isPlaying = false;
      cell.statusText = null;
    });
  }

  void _showChannelPicker(int index) {
    if (index >= _cells.length) return;
    final tokens = context.tokens;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return DefaultTabController(
          length: 4,
          initialIndex: 2,
          child: SafeArea(
            child: Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: tokens.surfaceOverlay,
                borderRadius: ZplayRadius.sheetTop,
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: ZplaySpacing.s12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.borderStrong,
                      borderRadius: ZplayRadius.xsAll,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZplaySpacing.s16,
                      vertical: ZplaySpacing.s12,
                    ),
                    child: Text(
                      'Select Channel',
                      style: ZplayType.title.toStyle(color: tokens.textPrimary),
                    ),
                  ),
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s8),
                    child: TabBar(
                      labelColor: tokens.accent,
                      unselectedLabelColor: tokens.textSecondary,
                      indicatorColor: tokens.accent,
                      tabs: const [
                        Tab(text: 'Xtreme'),
                        Tab(text: 'M3U'),
                        Tab(text: 'IPTV'),
                        Tab(text: 'Custom URL'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Xtreme Playlist Tab
                        MultiNutzChannelSheet(
                          cellIndex: index,
                          onChannelSelected: (url, name) => _loadXtremeM3uInCell(index, url, name),
                          tabType: ChannelSheetTab.xtreme,
                        ),
                        // M3U Playlist Tab
                        MultiNutzChannelSheet(
                          cellIndex: index,
                          onChannelSelected: (url, name) => _loadXtremeM3uInCell(index, url, name),
                          tabType: ChannelSheetTab.m3u,
                        ),
                        // Hardcoded IPTV Channels Tab
                        _buildHardcodedChannelsTab(index),
                        // Custom URL Tab
                        _buildCustomUrlTab(index),
                      ],
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

  Widget _buildHardcodedChannelsTab(int index) {
    final tokens = context.tokens;
    const channels = HardcodedChannels.all;
    return FutureBuilder<List<QuickChannel>>(
      future: IptvQuickChannelStore.load(),
      builder: (context, snapshot) {
        final quickChannels = snapshot.data ?? const <QuickChannel>[];
        return ListView.builder(
          padding: const EdgeInsets.all(ZplaySpacing.s16),
          itemCount: channels.length + quickChannels.length,
          itemBuilder: (context, i) {
if (i < quickChannels.length) {
              final qc = quickChannels[i];
              final ch = HardcodedChannel(
                id: 'qc_${qc.id}',
                name: qc.name,
                short: qc.short,
                category: qc.category,
                keywords: qc.keywords,
                gradient: qc.gradient,
                iconUrl: qc.iconUrl,
              );
              return Container(
                margin: const EdgeInsets.only(bottom: ZplaySpacing.s8),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.06),
                  borderRadius: ZplayRadius.smAll,
                  border: Border.all(color: tokens.accent.withValues(alpha: 0.2)),
                ),
                child: ListTile(
                  leading: qc.iconUrl != null
                      ? CachedNetworkImage(imageUrl: qc.iconUrl!, cacheManager: AppImageCache.manager,
 memCacheWidth: 96, width: 32, height: 32, errorWidget: (_, __, ___) => Icon(Icons.tv, color: tokens.textEmphasis))
                      : Icon(Icons.tv, color: tokens.textEmphasis),
                  title: Text(qc.name, style: ZplayType.label.copyWith(weight: FontWeight.w700).toStyle(color: tokens.textPrimary)),
                  subtitle: Text(qc.category, style: ZplayType.caption.toStyle(color: tokens.accent.withValues(alpha: 0.6))),
                  trailing: Icon(Icons.add_rounded, color: tokens.textSecondary),
                  onTap: () {
                    Navigator.pop(context);
                    _loadStreamInCell(index, ch);
                  },
                ),
              );
            }
            final ch = channels[i - quickChannels.length];
            return Container(
              margin: const EdgeInsets.only(bottom: ZplaySpacing.s8),
              decoration: BoxDecoration(
                color: tokens.borderSubtle,
                borderRadius: ZplayRadius.smAll,
              ),
              child: ListTile(
                leading: ch.iconUrl != null
                    ? CachedNetworkImage(imageUrl: ch.iconUrl!, cacheManager: AppImageCache.manager,
 memCacheWidth: 96, width: 32, height: 32, errorWidget: (_, __, ___) => Icon(Icons.tv, color: tokens.textEmphasis))
                    : Icon(Icons.tv, color: tokens.textEmphasis),
                title: Text(ch.name, style: ZplayType.label.copyWith(weight: FontWeight.w700).toStyle(color: tokens.textPrimary)),
                subtitle: Text(ch.category, style: ZplayType.caption.toStyle(color: tokens.accent.withValues(alpha: 0.6))),
                trailing: Icon(Icons.add_rounded, color: tokens.textSecondary),
                onTap: () {
                  Navigator.pop(context);
                  _loadStreamInCell(index, ch);
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCustomUrlTab(int index) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.all(ZplaySpacing.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Stream Details',
            style: ZplayType.subtitle
                .copyWith(weight: FontWeight.w700)
                .toStyle(color: tokens.textPrimary),
          ),
          const SizedBox(height: ZplaySpacing.s16),
          TextField(
            style: ZplayType.body.toStyle(color: tokens.textPrimary),
            decoration: InputDecoration(
              labelText: 'Stream Name',
              labelStyle: ZplayType.body.toStyle(color: tokens.textSecondary),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: tokens.borderStrong),
                borderRadius: ZplayRadius.smAll,
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: tokens.accent),
                borderRadius: ZplayRadius.smAll,
              ),
            ),
            onSubmitted: (nameVal) {
              _promptForUrl(index, nameVal);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _loadXtremeM3uInCell(int index, String url, String name) async {
    if (index >= _cells.length) return;
    final cell = _cells[index];
    setState(() {
      cell.channelName = name.isNotEmpty ? name : 'Live Stream';
      cell.isScanning = true;
      cell.statusText = 'Connecting...';
      cell.streamUrl = url;
    });

    try {
      await cell.player.open(Media(url));
      if (mounted) {
        setState(() {
          cell.isScanning = false;
          cell.statusText = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          cell.isScanning = false;
          cell.statusText = 'Playback error';
        });
      }
    }
  }

  Future<void> _loadStreamInCell(int index, HardcodedChannel channel) async {
    if (index >= _cells.length) return;
    final cell = _cells[index];
    
    setState(() {
      cell.channelName = channel.name;
      cell.isScanning = true;
      cell.statusText = 'Discovering stream...';
      cell.isPlaying = false;
      cell.streamUrl = null;
    });

    try {
      final ctrl = IptvController.instance;
      await ctrl.openHardcodedChannel(channel);

      List<ChannelHit> hits = ctrl.channelResults;
      if (hits.isEmpty) {
        await ctrl.runChannelScan(channel);
        hits = ctrl.channelResults;
      }

      if (hits.isEmpty) {
        if (mounted) {
          setState(() {
            cell.isScanning = false;
            cell.statusText = 'No active feeds found';
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          cell.availableHits = hits;
          cell.currentHitIndex = 0;
          cell.streamUrl = hits.first.streamUrl;
          cell.statusText = 'Connecting to feed...';
        });
      }

      await cell.player.open(Media(hits.first.streamUrl));
      if (mounted) {
        setState(() {
          cell.isScanning = false;
          cell.statusText = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          cell.isScanning = false;
          cell.statusText = 'Failed to load feed';
        });
      }
    }
  }

  void _promptForUrl(int index, String name) {
    if (index >= _cells.length) return;
    Navigator.pop(context);
    final tokens = context.tokens;
    
    showDialog(
      context: context,
      builder: (context) {
        final ctrl = TextEditingController();
        return AlertDialog(
          backgroundColor: tokens.surfaceOverlay,
          title: Text(
            'Stream URL for $name',
            style: ZplayType.title.toStyle(color: tokens.textPrimary),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: ZplayType.body.toStyle(color: tokens.textPrimary),
            decoration: InputDecoration(
              hintText: 'http://example.com/stream.m3u8',
              hintStyle: ZplayType.body.toStyle(color: tokens.textDisabled),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: tokens.accent.withValues(alpha: 0.5)),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: tokens.accent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: ZplayType.label.toStyle(color: tokens.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final url = ctrl.text.trim();
                Navigator.pop(context);
                if (url.isNotEmpty) {
                  _loadCustomUrlInCell(index, name, url);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.onAccent,
              ),
              child: Text('Add', style: ZplayType.label.toStyle(color: tokens.onAccent)),
            ),
          ],
        );
      },
    );
  }

  void _reorderCells(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    if (oldIndex >= _cells.length || newIndex >= _cells.length) return;
    setState(() {
      final oldCell = _cells[oldIndex];
      final newCell = _cells[newIndex];
      // Swap full cell objects so players/controllers travel with their content
      _cells[oldIndex] = newCell;
      _cells[newIndex] = oldCell;
      oldCell.index = newIndex;
      newCell.index = oldIndex;
      if (_fullscreenIndex == oldIndex) {
        _fullscreenIndex = newIndex;
      } else if (_fullscreenIndex == newIndex) {
        _fullscreenIndex = oldIndex;
      }
    });
    _saveSession();
}

  Widget _buildRearrangeGrid(int crossAxisCount, double childAspectRatio, double topPadding) {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: ZplaySpacing.s16, vertical: topPadding + 88),
      physics: const ClampingScrollPhysics(),
      itemCount: _activeCells,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: ZplaySpacing.s8),
          child: DragTarget<int>(
            builder: (context, accepted, rejected) {
              return Draggable<int>(
                data: index,
                feedback: Material(
                  color: Colors.transparent,
                  child: Opacity(opacity: 0.8, child: _buildPlayerCell(_cells[index], false, isRearrangeMode: true)),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.3,
                  child: _buildPlayerCell(_cells[index], false, isRearrangeMode: true),
                ),
                onDragEnd: (details) {
                  // No-op; handled by DragTarget's onWillAccept/onAccept
                },
                child: _buildPlayerCell(_cells[index], false, isRearrangeMode: true),
              );
            },
            onWillAccept: (fromIndex) => fromIndex != null && fromIndex != index,
            onAccept: (fromIndex) {
              _reorderCells(fromIndex, index);
            },
          ),
        );
      },
    );
  }

  void _muteAll() {
    setState(() {
      for (final cell in _cells) {
        cell.isMuted = true;
        cell.player.setVolume(0.0);
      }
    });
  }

  void _closeAll() {
    setState(() {
      for (int i = 0; i < _cells.length; i++) {
        _onCellRemove(i);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _saveSession();
    for (final s in _playingSubs) {
      s.cancel();
    }
    for (final cell in _cells) {
      // No VideoController.dispose in pinned media_kit_video (video_controller.dart:56-172); Player.dispose owns the texture.
      cell.player.dispose();
    }

    // Restore orientation
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final tokens = context.tokens;
    // Determine grid rows & columns based on layout
    int crossAxisCount;
    double childAspectRatio;
    
    switch (_currentLayout) {
      case MultiNutzLayout.single:
        crossAxisCount = 1;
        childAspectRatio = 16 / 9;
        break;
      case MultiNutzLayout.vertical2:
        crossAxisCount = 1;
        childAspectRatio = 16 / 12;
        break;
      case MultiNutzLayout.vertical3:
        crossAxisCount = 1;
        childAspectRatio = 16 / 14;
        break;
      case MultiNutzLayout.vertical4:
        crossAxisCount = 1;
        childAspectRatio = 16 / 16;
        break;
      case MultiNutzLayout.vertical5:
        crossAxisCount = 1;
        childAspectRatio = 16 / 18;
        break;
      case MultiNutzLayout.vertical6:
        crossAxisCount = 1;
        childAspectRatio = 16 / 20;
        break;
      case MultiNutzLayout.grid2x2:
        crossAxisCount = 2;
        childAspectRatio = 16 / 9;
        break;
      case MultiNutzLayout.grid2x3:
        crossAxisCount = 3;
        childAspectRatio = 16 / 9;
        break;
    }

final gridContent = _fullscreenIndex != null
        ? _buildPlayerCell(_cells[_fullscreenIndex!], true)
        : (_isRearrangeMode
            ? _buildRearrangeGrid(crossAxisCount, childAspectRatio, topPadding)
            : GridView.builder(
                // The 96 px bottom was dock clearance; the shell reserves its own space now.
                padding: EdgeInsets.fromLTRB(
                  ZplaySpacing.s16,
                  topPadding + 88,
                  ZplaySpacing.s16,
                  ZplaySpacing.s24 + MediaQuery.paddingOf(context).bottom,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: ZplaySpacing.s12,
                  mainAxisSpacing: ZplaySpacing.s12,
                  childAspectRatio: childAspectRatio,
                ),
                itemCount: _activeCells,
                itemBuilder: (context, index) => _buildPlayerCell(_cells[index], false, isRearrangeMode: false),
              ));

    final backgroundContent = AnimatedAmbientBackground(
      child: gridContent,
    );

    final overlayChildren = <Widget>[
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: _buildSlidingMenuBars(topPadding: topPadding),
      ),
    ];

    return PopScope(
      canPop: _fullscreenIndex == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _fullscreenIndex != null) {
          setState(() {
            _fullscreenIndex = null;
          });
        }
      },
      child: Scaffold(
        backgroundColor: tokens.bg,
        body: ValueListenableBuilder<bool>(
          valueListenable: GlassSettings.enabled,
          builder: (context, enabled, _) {
            final overlays = Stack(children: overlayChildren);
            if (enabled) {
              return LiquidGlassView(
                realTimeCapture: true,
                useSync: true,
                pixelRatio: 1.0,
                refreshRate: LiquidGlassRefreshRate.deviceRefreshRate,
                regionCapture: true,
                backgroundWidget: backgroundContent,
                child: overlays,
              );
            }
            return Container(
              color: tokens.bg,
              child: Stack(
                children: [
                  RepaintBoundary(child: backgroundContent),
                  ...overlayChildren,
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlayerCell(MultiStreamCell cell, bool isFullscreen, {bool isRearrangeMode = false}) {
    final tokens = context.tokens;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(
          color: cell.channelName != null
              ? (cell.isMuted ? tokens.borderStrong : tokens.accent)
              : tokens.borderDefault,
          width: cell.channelName != null && !cell.isMuted ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Video player engine
          if (cell.streamUrl != null)
            Positioned.fill(
              child: Center(
                child: Video(
                  controller: cell.controller,
                  fit: BoxFit.contain,
                ),
              ),
            ),

          // Loading/Scanning Indicator
          if (cell.isScanning)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.7),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
                      ),
                      if (cell.statusText != null) ...[
                        const SizedBox(height: ZplaySpacing.s12),
                        Text(
                          cell.statusText!,
                          style: ZplayType.caption
                              .copyWith(weight: FontWeight.w700)
                              .toStyle(color: tokens.textEmphasis),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // Empty state click to add stream
          if (cell.streamUrl == null && !cell.isScanning && !isRearrangeMode)
            Positioned.fill(
              child: FocusableCard(
                onTap: () => _showChannelPicker(cell.index),
                builder: (context, state) => CardFocusRing(
                  focused: state.focused,
                  radius: ZplayRadius.mdAll,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_rounded,
                        color: state.highlighted
                            ? tokens.textPrimary
                            : tokens.textSecondary,
                        size: 28,
                      ),
                      const SizedBox(height: ZplaySpacing.s8),
                      Text(
                        'Add Live Stream Feed',
                        style: ZplayType.bodySmall
                            .copyWith(weight: FontWeight.w700)
                            .toStyle(color: tokens.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Controls HUD overlay (Mute, Pause, Remove, Fullscreen, Stream Picker)
          if (cell.streamUrl != null && !cell.isScanning && !isRearrangeMode)
            Positioned(
              top: 12,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: ZplaySpacing.s8,
                        vertical: ZplaySpacing.s4,
                      ),
                      decoration: BoxDecoration(
                        // HUD chip over live video: the black scrim stays.
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: ZplayRadius.xsAll,
                      ),
                      child: Text(
                        cell.channelName ?? 'Live Stream',
                        style: ZplayType.overline.toStyle(color: tokens.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Cell overlay control bar
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildMiniHudButton(
                        icon: cell.isMuted ? Icons.volume_off_rounded : (cell.volume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                        color: cell.isMuted ? tokens.textEmphasis : tokens.accent,
                        onTap: () => _onCellVolumeToggle(cell.index),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 64,
                        height: 32,
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                            activeTrackColor: tokens.accent,
                            inactiveTrackColor: tokens.borderStrong,
                            thumbColor: tokens.accent,
                            overlayColor: tokens.accent.withValues(alpha: 0.2),
                          ),
                          child: Slider(
                            value: cell.volume,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (v) => _onCellVolumeChanged(cell.index, v),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  _buildMiniHudButton(
                    icon: cell.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    onTap: () => _onCellPauseToggle(cell.index),
                  ),
                  const SizedBox(width: 6),
                  _buildMiniHudButton(
                    icon: isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                    onTap: () {
                      setState(() {
                        if (isFullscreen) {
                          _fullscreenIndex = null;
                        } else {
                          _fullscreenIndex = cell.index;
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 6),
                  _buildMiniHudButton(
                    icon: (cell.availableHits?.length ?? 0) > 1
                        ? Icons.swap_horiz_rounded
                        : Icons.swap_horiz_outlined,
                    color: (cell.availableHits?.length ?? 0) > 1
                        ? tokens.accent
                        : tokens.textEmphasis,
                    onTap: (cell.availableHits?.length ?? 0) > 1
                        ? () => _showStreamPicker(cell.index)
                        : null,
                  ),
                  const SizedBox(width: 6),
                  _buildMiniHudButton(
                    icon: Icons.close_rounded,
                    color: tokens.danger,
                    onTap: () => _onCellRemove(cell.index),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniHudButton({required IconData icon, Color? color, VoidCallback? onTap}) {
    final tokens = context.tokens;
    return FocusableCard(
      onTap: onTap,
      cursor: SystemMouseCursors.click,
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.smAll,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            // HUD button over live video: the black scrim stays. No border -
            // the focus ring is the only indicator this control carries.
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: ZplayRadius.smAll,
          ),
          child: Icon(icon, color: color ?? tokens.textEmphasis, size: 20),
        ),
      ),
    );
  }

  Widget _buildSlidingMenuBars({required double topPadding}) {
    final tokens = context.tokens;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The system's own top strip, left completely bare: the page runs edge
        // to edge under it and the ambient canvas (or the live video) is the
        // only thing that should show there. The scrim below starts *after* it,
        // at zero alpha, so there is no edge where the two meet.
        SizedBox(height: topPadding),
        // Top bar - layout controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: BoxDecoration(
            // HUD scrim over live video: no hairline, no opaque band - a soft
            // gradient that fades in behind the controls and out below them, so
            // the grid meets it without a seam.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                tokens.bg.withValues(alpha: 0.80),
                tokens.bg.withValues(alpha: 0.47),
                Colors.transparent,
              ],
              stops: const [0.0, 0.35, 0.7, 1.0],
            ),
          ),
          child: Row(
            children: [
              // Left: title + layout label
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (Navigator.canPop(context)) ...[
                  _buildGlassButton(
                    icon: Icons.arrow_back_rounded,
                    isSelected: false,
                    tooltip: 'Back to Live TV',
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: tokens.accent,
                    borderRadius: ZplayRadius.smAll,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.dashboard_rounded, color: tokens.onAccent, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'MULTI STREAMS',
                        style: ZplayType.label.toStyle(color: tokens.onAccent),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _currentLayout.label.toUpperCase(),
                  style: ZplayType.overline.toStyle(color: tokens.textEmphasis),
                ),
              ]),

              // Right: scrollable controls
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    shrinkWrap: true,
                    children: [
                      if (_fullscreenIndex == null) ...[
                        _buildGlassButton(
                          icon: Icons.chevron_left_rounded,
                          isSelected: false,
                          tooltip: 'Previous Layout',
                          onTap: _navigateLayoutBackward,
                        ),
                        const SizedBox(width: 8),
                        _buildGlassButton(
                          icon: Icons.chevron_right_rounded,
                          isSelected: false,
                          tooltip: 'Next Layout',
                          onTap: _navigateLayoutForward,
                        ),
                        const SizedBox(width: ZplaySpacing.s12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.view_comfy_rounded, color: tokens.accent, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '$_activeCells Stream${_activeCells > 1 ? "s" : ""}',
                              style: ZplayType.bodySmall
                                  .copyWith(weight: FontWeight.w700)
                                  .toStyle(color: tokens.textEmphasis),
                            ),
                          ],
                        ),
                        const SizedBox(width: ZplaySpacing.s24),
                      ],
                      const SizedBox(width: ZplaySpacing.s16),
                      _buildGlassButton(
                        icon: _isRearrangeMode ? Icons.check_rounded : Icons.swap_vert_rounded,
                        isSelected: _isRearrangeMode,
                        tooltip: _isRearrangeMode ? 'Done Rearranging' : 'Rearrange Streams',
                        onTap: () {
                          setState(() {
                            _isRearrangeMode = !_isRearrangeMode;
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildGlassButton(
                        icon: Icons.volume_off_rounded,
                        isSelected: false,
                        tooltip: 'Mute All',
                        onTap: _muteAll,
                      ),
                      const SizedBox(width: 8),
                      _buildGlassButton(
                        icon: Icons.delete_sweep_rounded,
                        isSelected: false,
                        tooltip: 'Clear All Windows',
                        onTap: _closeAll,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGlassButton({required IconData icon, required bool isSelected, required String tooltip, VoidCallback? onTap}) {
    final tokens = context.tokens;

    return Tooltip(
      message: tooltip,
      child: FocusableCard(
        onTap: onTap,
        builder: (context, state) => CardFocusRing(
          focused: state.focused,
          radius: ZplayRadius.smAll,
          child: AnimatedContainer(
            duration: ZplayMotion.fast,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              // Over live video, so the control keeps a scrim to stay visible;
              // selection is the accent and nothing else. No border, no glow -
              // the ring is the only focus marker.
              color: isSelected ? tokens.accent : PillButton.scrim(tokens),
              borderRadius: ZplayRadius.smAll,
            ),
            child: Icon(
              icon,
              color: isSelected ? tokens.onAccent : tokens.textEmphasis,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}