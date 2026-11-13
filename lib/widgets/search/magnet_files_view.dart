import 'package:flutter/material.dart';
import '../../models/stream/stream_model.dart';
import '../../pages/player/player_screen.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/debrid/debrid_service.dart';
import '../../services/stream/torrent_stream_service.dart';
import '../common/focusable_card.dart';

class MagnetFileItem {
  final int id;
  final String name;
  final int size;
  final String? downloadUrl;
  final bool isVideo;

  const MagnetFileItem({
    required this.id,
    required this.name,
    required this.size,
    this.downloadUrl,
    required this.isVideo,
  });

  String get cleanFilename {
    if (name.contains('/')) return name.split('/').last;
    if (name.contains(r'\')) return name.split(r'\').last;
    return name;
  }

  String get extension {
    final clean = cleanFilename;
    final dotIdx = clean.lastIndexOf('.');
    if (dotIdx != -1 && dotIdx < clean.length - 1) {
      return clean.substring(dotIdx + 1).toUpperCase();
    }
    return '';
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(i == 0 ? 0 : 2)} ${suffixes[i]}';
  }
}

class MagnetFilesView extends StatefulWidget {
  final String magnet;

  const MagnetFilesView({super.key, required this.magnet});

  @override
  State<MagnetFilesView> createState() => _MagnetFilesViewState();
}

class _MagnetFilesViewState extends State<MagnetFilesView> {
  bool _isLoading = true;
  String? _errorMessage;
  String _torrentTitle = '';
  String? _infoHash;
  bool _isDebrid = false;
  String _providerName = 'Torrent Engine';
  int _totalSize = 0;
  List<MagnetFileItem> _files = [];

  String _searchFilter = '';
  String _activeCategory = 'all'; // 'all', 'video', 'other'

  @override
  void initState() {
    super.initState();
    _loadMagnetFiles();
  }

  @override
  void didUpdateWidget(covariant MagnetFilesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.magnet != widget.magnet) {
      _loadMagnetFiles();
    }
  }

  static bool _checkIsVideo(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.flv') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.wmv') ||
        lower.endsWith('.3gp');
  }

  static String? _extractHash(String magnetOrHash) {
    final match = RegExp(r'[0-9a-fA-F]{40}').firstMatch(magnetOrHash);
    return match?.group(0)?.toLowerCase();
  }

  static String _extractDisplayName(String magnet) {
    try {
      final match = RegExp(r'[?&]dn=([^&]+)').firstMatch(magnet);
      if (match != null && match.group(1) != null) {
        return Uri.decodeComponent(match.group(1)!.replaceAll('+', ' '));
      }
    } catch (_) {}
    return '';
  }

  Future<void> _loadMagnetFiles() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _files = [];
      _totalSize = 0;
    });

    final rawMagnet = widget.magnet.trim();
    final rawHash = _extractHash(rawMagnet);
    _infoHash = rawHash;

    String normalizedMagnet = rawMagnet;
    if (!rawMagnet.toLowerCase().startsWith('magnet:')) {
      if (rawHash != null) {
        normalizedMagnet = 'magnet:?xt=urn:btih:$rawHash';
      }
    }

    final dn = _extractDisplayName(normalizedMagnet);
    _torrentTitle = dn.isNotEmpty ? dn : (rawHash ?? 'Magnet Torrent');

    try {
      final useDebrid = await DebridService().isDebridActiveForStreams();
      _isDebrid = useDebrid;

      if (useDebrid) {
        final activeService = await DebridService().getSelectedService();
        _providerName = activeService;

        final debridFiles = await DebridService().resolveMagnet(
          magnet: normalizedMagnet,
        );
        if (debridFiles.isEmpty) {
          throw Exception('$activeService returned no files for this magnet.');
        }

        final items = <MagnetFileItem>[];
        int sumBytes = 0;
        for (int i = 0; i < debridFiles.length; i++) {
          final df = debridFiles[i];
          final isVid = _checkIsVideo(df.filename);
          sumBytes += df.filesize;
          items.add(
            MagnetFileItem(
              id: i,
              name: df.filename,
              size: df.filesize,
              downloadUrl: df.downloadUrl,
              isVideo: isVid,
            ),
          );
        }

        if (mounted) {
          setState(() {
            _files = items;
            _totalSize = sumBytes;
            _isLoading = false;
          });
        }
      } else {
        _providerName = 'Torrent Engine';
        final tss = TorrentStreamService();
        final info = await tss.getTorrentMetadata(normalizedMagnet);

        if (info == null || info.fileStats.isEmpty) {
          throw Exception(
            'Could not retrieve torrent metadata from swarm. Check peer connectivity.',
          );
        }

        final items = <MagnetFileItem>[];
        int sumBytes = 0;
        for (final stat in info.fileStats) {
          final isVid = _checkIsVideo(stat.path);
          sumBytes += stat.length;
          items.add(
            MagnetFileItem(
              id: stat.id,
              name: stat.path,
              size: stat.length,
              isVideo: isVid,
            ),
          );
        }

        if (info.title.isNotEmpty && _torrentTitle == (rawHash ?? '')) {
          _torrentTitle = info.title;
        }

        if (mounted) {
          setState(() {
            _files = items;
            _totalSize = sumBytes > 0 ? sumBytes : info.torrentSize;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _playFile(MagnetFileItem file) {
    final streamTitle = file.cleanFilename;

    StreamSource source;
    if (_isDebrid) {
      source = StreamSource(
        name: _providerName,
        title: streamTitle,
        url: file.downloadUrl,
        addonName: _providerName,
      );
    } else {
      source = StreamSource(
        name: 'Torrent Engine',
        title: streamTitle,
        infoHash: _infoHash,
        fileIdx: file.id,
        addonName: 'Torrent Engine',
      );
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(source: source, title: streamTitle),
      ),
    );
  }

  List<MagnetFileItem> get _filteredFiles {
    return _files.where((f) {
      if (_activeCategory == 'video' && !f.isVideo) return false;
      if (_activeCategory == 'other' && f.isVideo) return false;
      if (_searchFilter.isNotEmpty) {
        return f.name.toLowerCase().contains(_searchFilter.toLowerCase());
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemePalette>(
      valueListenable: AppThemeService.currentPalette,
      builder: (context, palette, _) {
        if (_isLoading) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.primaryColor.withValues(alpha: 0.12),
                      border: Border.all(
                        color: palette.primaryColor.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: palette.primaryColor.withValues(alpha: 0.25),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: CircularProgressIndicator(
                        color: palette.primaryColor,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _isDebrid
                        ? 'Using $_providerName for files...'
                        : 'Connecting to swarm peers...',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gathering file list & stream metadata',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (_errorMessage != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.redAccent.withValues(alpha: 0.12),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.redAccent,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Failed to Read Magnet',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.6),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _loadMagnetFiles,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(
                      'Try Again',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final filtered = _filteredFiles;
        final videoCount = _files.where((f) => f.isVideo).length;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.paddingOf(context).top + kToolbarHeight + 20,
            16,
            40 + MediaQuery.paddingOf(context).bottom,
          ),
          physics: const BouncingScrollPhysics(),
          children: [
            // Header Info Card
            _buildTorrentHeaderCard(palette, videoCount),

            const SizedBox(height: 18),

            // Search & Filter Toolbar
            _buildFilterToolbar(palette, videoCount),

            const SizedBox(height: 14),

            // Files List
            if (filtered.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    'No files match filter',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 14,
                    ),
                  ),
                ),
              )
            else
              ...filtered.map((file) => _buildFileTile(file, palette)),
          ],
        );
      },
    );
  }

  Widget _buildTorrentHeaderCard(AppThemePalette palette, int videoCount) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF131722).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: palette.primaryColor.withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: palette.primaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.link_rounded,
                  color: palette.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _torrentTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_infoHash != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        _infoHash!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.4),
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Provider Badge
              _buildBadge(
                icon: _isDebrid ? Icons.cloud_done_rounded : Icons.hub_rounded,
                label: _isDebrid ? '$_providerName Cloud' : 'P2P Swarm',
                color: _isDebrid ? Colors.cyanAccent : palette.primaryColor,
              ),
              // Size Badge
              _buildBadge(
                icon: Icons.storage_rounded,
                label: MagnetFileItem.formatBytes(_totalSize),
                color: Colors.white70,
              ),
              // Total Files Badge
              _buildBadge(
                icon: Icons.folder_rounded,
                label:
                    '${_files.length} ${_files.length == 1 ? "file" : "files"}',
                color: Colors.white70,
              ),
              // Video Files Badge
              if (videoCount > 0)
                _buildBadge(
                  icon: Icons.movie_rounded,
                  label: '$videoCount ${videoCount == 1 ? "video" : "videos"}',
                  color: palette.primaryColor,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterToolbar(AppThemePalette palette, int videoCount) {
    return Column(
      children: [
        // Search Filter Input
        Container(
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: TextField(
            style: const TextStyle(color: Colors.white, fontSize: 13),
            onChanged: (val) => setState(() => _searchFilter = val),
            decoration: InputDecoration(
              hintText: 'Filter files by name...',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 13,
              ),
              prefixIcon: Icon(
                Icons.filter_list_rounded,
                size: 16,
                color: Colors.white.withValues(alpha: 0.4),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Filter Chips
        Row(
          children: [
            _buildCategoryChip('all', 'All (${_files.length})', palette),
            const SizedBox(width: 8),
            _buildCategoryChip('video', 'Videos ($videoCount)', palette),
            const SizedBox(width: 8),
            _buildCategoryChip(
              'other',
              'Other (${_files.length - videoCount})',
              palette,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryChip(
    String category,
    String label,
    AppThemePalette palette,
  ) {
    final isSelected = _activeCategory == category;
    return FocusableCard(
      onTap: () => setState(() => _activeCategory = category),
      builder: (context, state) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? palette.primaryColor.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? palette.primaryColor
                : Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.white60,
          ),
        ),
      ),
    );
  }

  Widget _buildFileTile(MagnetFileItem file, AppThemePalette palette) {
    final ext = file.extension;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: file.isVideo
            ? const Color(0xFF161B26).withValues(alpha: 0.75)
            : const Color(0xFF10141C).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: file.isVideo
              ? palette.primaryColor.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          width: 0.9,
        ),
      ),
      child: Row(
        children: [
          // File Type Icon
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: file.isVideo
                  ? palette.primaryColor.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              file.isVideo
                  ? Icons.movie_rounded
                  : (ext == 'MP3' || ext == 'FLAC' || ext == 'M4A'
                        ? Icons.audiotrack_rounded
                        : Icons.insert_drive_file_rounded),
              color: file.isVideo ? palette.primaryColor : Colors.white54,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          // Filename & Size
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.cleanFilename,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: file.isVideo
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: file.isVideo ? Colors.white : Colors.white70,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (ext.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          ext,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      MagnetFileItem.formatBytes(file.size),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // Action Button
          if (file.isVideo)
            ElevatedButton.icon(
              onPressed: () => _playFile(file),
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text(
                'Play',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
            )
          else
            Text(
              'Non-video',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.25),
              ),
            ),
        ],
      ),
    );
  }
}
