import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/cloudstream/cloudstream_manager.dart';
import '../../services/cloudstream/marketplace/cloudstream_marketplace_service.dart';
import 'cloudstream_repo_modal.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/zplay_sheet.dart';

class CloudStreamMarketplaceModal extends StatefulWidget {
  const CloudStreamMarketplaceModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CloudStreamMarketplaceModal(),
    );
  }

  @override
  State<CloudStreamMarketplaceModal> createState() => _CloudStreamMarketplaceModalState();
}

class _CloudStreamMarketplaceModalState extends State<CloudStreamMarketplaceModal> {
  final _manager = CloudStreamManager.instance;
  final _service = CloudStreamMarketplaceService.instance;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _categoryScrollController = ScrollController();

  List<CloudStreamMarketplaceRepo> _repos = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String _selectedCategory = 'All';
  String _searchQuery = '';
  final Set<String> _expandedRepos = {};
  final Set<String> _addingRepoUrls = {};

  @override
  void initState() {
    super.initState();
    _loadRepos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _categoryScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadRepos({bool forceRefresh = false}) async {
    setState(() {
      if (forceRefresh) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
      }
    });

    try {
      final list = await _service.getRepos(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _repos = list;
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  List<CloudStreamMarketplaceRepo> get _filteredRepos {
    var list = _repos;
    if (_selectedCategory != 'All') {
      list = list.where((r) => r.category == _selectedCategory).toList();
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return list;

    return list.where((r) {
      final nameMatch = r.name.toLowerCase().contains(query);
      final catMatch = r.category.toLowerCase().contains(query);
      final pluginMatch = r.plugins.any((p) => p.toLowerCase().contains(query));
      return nameMatch || catMatch || pluginMatch;
    }).toList();
  }

  String _getCategoryEmoji(String category) {
    switch (category) {
      case 'Turkish':
        return '🇹🇷';
      case 'Arabic':
        return '🇸🇦';
      case 'Hindi / Asian':
        return '🇮🇳';
      case 'French':
        return '🇫🇷';
      case 'Italian':
        return '🇮🇹';
      case 'German':
        return '🇩🇪';
      case 'Portuguese / Spanish':
        return '🇵🇹';
      case 'Vietnamese':
        return '🇻🇳';
      case 'Ukrainian':
        return '🇺🇦';
      case 'Anime / Cartoons':
        return '🎌';
      case 'Multi / English':
        return '🌐';
      default:
        return '📦';
    }
  }

  /// Categorical hues: each language group keeps its own colour so the chip
  /// legends stay readable at a glance. These encode category identity the way a
  /// per-format badge does, so they stay outside the palette layer.
  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Turkish':
        return const Color(0xFFEF4444);
      case 'Arabic':
        return const Color(0xFF10B981);
      case 'Hindi / Asian':
        return const Color(0xFFF59E0B);
      case 'French':
        return const Color(0xFF3B82F6);
      case 'Italian':
        return const Color(0xFF06B6D4);
      case 'German':
        return const Color(0xFFEAB308);
      case 'Portuguese / Spanish':
        return const Color(0xFF8B5CF6);
      case 'Vietnamese':
        return const Color(0xFFEC4899);
      case 'Ukrainian':
        return const Color(0xFF0EA5E9);
      case 'Anime / Cartoons':
        return const Color(0xFFA855F7);
      default:
        return context.tokens.accent;
    }
  }

  Future<void> _addRepo(CloudStreamMarketplaceRepo repo) async {
    final tokens = context.tokens;
    setState(() => _addingRepoUrls.add(repo.url));

    try {
      await _manager.addRepo(repo.url);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: tokens.onAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('${repo.name} added successfully!')),
            ],
          ),
          backgroundColor: tokens.success,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Offer to install plugins immediately
      final shouldInstallAll = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: tokens.surfaceOverlay,
          shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.mdAll),
          title: Text('Install ${repo.name} Plugins?'),
          content: Text(
            repo.plugins.isNotEmpty
                ? 'This repository includes ${repo.plugins.length} plugins (${repo.plugins.take(3).join(', ')}...). Install all plugins now so their stream sources appear immediately?'
                : 'Would you like to install plugins from this repository now?',
            style: ZplayType.body.toStyle(color: tokens.textEmphasis),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Later',
                style: ZplayType.label.toStyle(color: tokens.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.onAccent,
                shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
              ),
              child: Text(
                'Install All Now',
                style: ZplayType.label.toStyle(),
              ),
            ),
          ],
        ),
      );

      if (shouldInstallAll == true && mounted) {
        await _installAllPlugins(repo.url);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: tokens.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _addingRepoUrls.remove(repo.url));
      }
    }
  }

  Future<void> _installAllPlugins(String repoUrl) async {
    final tokens = context.tokens;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: tokens.surfaceOverlay,
          shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.mdAll),
          title: Text(
            'Installing Repository Plugins',
            style: ZplayType.title.toStyle(color: tokens.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              CircularProgressIndicator(color: tokens.accent),
              const SizedBox(height: 16),
              ValueListenableBuilder<String>(
                valueListenable: _manager.busyMessage,
                builder: (context, msg, _) => Text(
                  msg.isEmpty ? 'Installing extensions...' : msg,
                  style: ZplayType.label.toStyle(color: tokens.textEmphasis),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      },
    );

    try {
      final count = await _manager.installAllFromRepo(repoUrl);
      if (mounted) Navigator.pop(context);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count plugins installed and ready!'),
          backgroundColor: tokens.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {});
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Installation error: $e'),
          backgroundColor: tokens.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return ZplaySheet(
      heightFactor: 0.88,
      // The header mark stays, as a flat accent tile: the two-stop indigo gradient
      // that used to fill it was a hand-written colour, and the "N Repos" pill is
      // gone too, its count moved into the subtitle (which removed the second
      // hand-written colour, 0xFF9D84FF) along with one container for the eye.
      // The tile's accent glow went with them: the design language carries
      // structure with spacing and type weight, not with a halo.
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: tokens.accentSubtle,
          borderRadius: ZplayRadius.smAll,
        ),
        child: Icon(Icons.hub_rounded, color: tokens.accent, size: 20),
      ),
      title: 'Marketplace',
      subtitle:
          '${_repos.length} repos · Direct install links & verified providers',
      status: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Refresh list from web',
            icon: _isRefreshing
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.accent,
                    ),
                  )
                : Icon(
                    Icons.refresh_rounded,
                    color: tokens.textSecondary,
                  ),
            onPressed:
                _isRefreshing ? null : () => _loadRepos(forceRefresh: true),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: tokens.textEmphasis),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      child: Column(
        children: [
          // Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: tokens.surfaceOverlay,
                borderRadius: ZplayRadius.smAll,
                border: Border.all(color: tokens.borderDefault),
              ),
              child: TextField(
                controller: _searchController,
                style: ZplayType.body.toStyle(color: tokens.textPrimary),
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search repository or plugin (e.g. Turkish, 3rabi, DiziBox, Shahid)...',
                  hintStyle: ZplayType.bodySmall.toStyle(color: tokens.textDisabled),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: tokens.textMuted,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: tokens.textSecondary,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Category Chips Bar with desktop horizontal scroll arrows
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: ZplayRadius.lgAll,
                    onTap: () {
                      if (_categoryScrollController.hasClients) {
                        final target = (_categoryScrollController.offset - 180).clamp(
                          0.0,
                          _categoryScrollController.position.maxScrollExtent,
                        );
                        _categoryScrollController.animateTo(
                          target,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: tokens.surfaceOverlay,
                        shape: BoxShape.circle,
                        border: Border.all(color: tokens.borderDefault),
                      ),
                      child: Icon(
                        Icons.chevron_left_rounded,
                        size: 18,
                        color: tokens.textEmphasis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: ListView.builder(
                      controller: _categoryScrollController,
                      scrollDirection: Axis.horizontal,
                      itemCount: CloudStreamMarketplaceService.categories.length,
                      itemBuilder: (context, idx) {
                        final cat = CloudStreamMarketplaceService.categories[idx];
                        final isSelected = _selectedCategory == cat;
                        final count = cat == 'All' ? _repos.length : _repos.where((r) => r.category == cat).length;
                        final emoji = _getCategoryEmoji(cat);

                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FocusableCard(
                            onTap: () => setState(() => _selectedCategory = cat),
                            builder: (_, state) => AnimatedContainer(
                              duration: ZplayMotion.base,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? tokens.accentSubtle : tokens.surfaceOverlay,
                                borderRadius: ZplayRadius.smAll,
                                border: Border.all(
                                  color: isSelected
                                      ? tokens.accent
                                      : tokens.borderDefault,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(emoji, style: ZplayType.bodySmall.toStyle()),
                                  const SizedBox(width: 6),
                                  Text(
                                    cat,
                                    style: ZplayType.bodySmall
                                        .toStyle(
                                          color: isSelected
                                              ? tokens.textPrimary
                                              : tokens.textSecondary,
                                        )
                                        .copyWith(
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: isSelected
                                            ? ZplayOpacity.overlayHover
                                            : ZplayOpacity.borderDefault,
                                      ),
                                      borderRadius: ZplayRadius.xsAll,
                                    ),
                                    child: Text(
                                      '$count',
                                      style: ZplayType.caption.toStyle(
                                        color: isSelected
                                            ? tokens.textPrimary
                                            : tokens.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: ZplayRadius.lgAll,
                    onTap: () {
                      if (_categoryScrollController.hasClients) {
                        final target = (_categoryScrollController.offset + 180).clamp(
                          0.0,
                          _categoryScrollController.position.maxScrollExtent,
                        );
                        _categoryScrollController.animateTo(
                          target,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: tokens.surfaceOverlay,
                        shape: BoxShape.circle,
                        border: Border.all(color: tokens.borderDefault),
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: tokens.textEmphasis,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Repositories List
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: tokens.accent),
                  )
                : _filteredRepos.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 48,
                              color: tokens.textDisabled,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No repositories found for "$_searchQuery"',
                              style: ZplayType.body.toStyle(color: tokens.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        physics: const BouncingScrollPhysics(),
                        itemCount: _filteredRepos.length,
                        itemBuilder: (context, index) {
                          final repo = _filteredRepos[index];
                          final isInstalled = _manager.isRepoInstalled(repo.url);
                          final isAdding = _addingRepoUrls.contains(repo.url);
                          final isExpanded = _expandedRepos.contains(repo.url);
                          final catColor = _getCategoryColor(repo.category);

                          // Search highlight check
                          final query = _searchQuery.trim().toLowerCase();
                          final matchingPlugins = query.isNotEmpty
                              ? repo.plugins.where((p) => p.toLowerCase().contains(query)).toList()
                              : <String>[];

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Top row: Title + Category badge
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              repo.name,
                                              style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 4,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                                  decoration: BoxDecoration(
                                                    color: catColor.withValues(
                                                      alpha: ZplayOpacity.overlayHover,
                                                    ),
                                                    borderRadius: ZplayRadius.xsAll,
                                                    border: Border.all(
                                                      color: catColor.withValues(
                                                        alpha: ZplayOpacity.textDisabled,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        _getCategoryEmoji(repo.category),
                                                        style: ZplayType.caption.toStyle(),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        repo.category,
                                                        style: ZplayType.caption.toStyle(color: catColor),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (repo.plugins.isNotEmpty)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                                    decoration: BoxDecoration(
                                                      color: tokens.borderDefault,
                                                      borderRadius: ZplayRadius.xsAll,
                                                    ),
                                                    child: Text(
                                                      '${repo.plugins.length} Plugins',
                                                      style: ZplayType.caption.toStyle(
                                                        color: tokens.textEmphasis,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Added status indicator
                                      if (isInstalled)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: tokens.success.withValues(
                                              alpha: ZplayOpacity.borderStrong,
                                            ),
                                            borderRadius: ZplayRadius.smAll,
                                            border: Border.all(
                                              color: tokens.success.withValues(
                                                alpha: ZplayOpacity.textDisabled,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.check_circle_rounded,
                                                color: tokens.success,
                                                size: 14,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Added',
                                                style: ZplayType.caption.toStyle(
                                                  color: tokens.success,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),

                                  const SizedBox(height: 12),

                                  // Direct Install Link Box
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: tokens.bg,
                                      borderRadius: ZplayRadius.smAll,
                                      border: Border.all(color: tokens.borderSubtle),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.link_rounded, size: 14, color: tokens.textMuted),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            repo.url,
                                            style: ZplayType.caption
                                              .toStyle(color: tokens.textSecondary)
                                              .copyWith(fontFamily: 'monospace'),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        FocusableCard(
                                          onTap: () {
                                            Clipboard.setData(ClipboardData(text: repo.url));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Copied link: ${repo.url}'),
                                                duration: const Duration(seconds: 2),
                                                behavior: SnackBarBehavior.floating,
                                              ),
                                            );
                                          },
                                          builder: (_, state) => Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: tokens.borderDefault,
                                              borderRadius: ZplayRadius.xsAll,
                                            ),
                                            child: Icon(
                                              Icons.copy_rounded,
                                              size: 12,
                                              color: tokens.textEmphasis,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Matching search banner
                                  if (matchingPlugins.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: tokens.accentSubtle,
                                        borderRadius: ZplayRadius.xsAll,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.auto_awesome_rounded, size: 12, color: tokens.accent),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Contains: ${matchingPlugins.join(', ')}',
                                              style: ZplayType.caption.toStyle(color: tokens.accent),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],

                                  // Plugins expandable list
                                  if (repo.plugins.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          if (isExpanded) {
                                            _expandedRepos.remove(repo.url);
                                          } else {
                                            _expandedRepos.add(repo.url);
                                          }
                                        });
                                      },
                                      borderRadius: ZplayRadius.xsAll,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 3),
                                        child: Row(
                                          children: [
                                            Text(
                                              isExpanded ? 'Hide plugins' : 'View all ${repo.plugins.length} plugins',
                                              style: ZplayType.caption.toStyle(
                                                color: tokens.accent,
                                                opacity: ZplayOpacity.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(
                                              isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                              size: 16,
                                              color: tokens.accent,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (isExpanded) ...[
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: repo.plugins.map((plugin) {
                                          final isMatched = query.isNotEmpty && plugin.toLowerCase().contains(query);
                                          return Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: isMatched
                                                  ? tokens.accent.withValues(
                                                      alpha: ZplayOpacity.textDisabled,
                                                    )
                                                  : tokens.borderSubtle,
                                              borderRadius: ZplayRadius.xsAll,
                                              border: Border.all(
                                                color: isMatched
                                                    ? tokens.accent
                                                    : tokens.borderDefault,
                                              ),
                                            ),
                                            child: Text(
                                              plugin,
                                              style: ZplayType.caption
                                                  .toStyle(
                                                    color: isMatched
                                                        ? tokens.textPrimary
                                                        : tokens.textEmphasis,
                                                  )
                                                  .copyWith(
                                                    fontWeight: isMatched
                                                        ? FontWeight.w700
                                                        : FontWeight.w400,
                                                  ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ],

                                  const SizedBox(height: 14),

                                  // Actions row
                                  Row(
                                    children: [
                                      if (!isInstalled)
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: isAdding ? null : () => _addRepo(repo),
                                            icon: isAdding
                                                ? SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: tokens.onAccent,
                                                    ),
                                                  )
                                                : const Icon(Icons.add_circle_outline_rounded, size: 16),
                                            label: Text(
                                              isAdding ? 'Adding Repository...' : 'Install Repository',
                                              style: ZplayType.label.toStyle(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: tokens.accent,
                                              foregroundColor: tokens.onAccent,
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                              shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                                            ),
                                          ),
                                        )
                                      else ...[
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () => _installAllPlugins(repo.url),
                                            icon: const Icon(Icons.download_for_offline_rounded, size: 16),
                                            label: Text(
                                              'Install All Plugins',
                                              style: ZplayType.label.toStyle(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: tokens.accent,
                                              foregroundColor: tokens.onAccent,
                                              padding: const EdgeInsets.symmetric(vertical: 9),
                                              shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            CloudStreamRepoModal.show(context);
                                          },
                                          icon: const Icon(Icons.manage_search_rounded, size: 16),
                                          label: Text(
                                            'Browse',
                                            style: ZplayType.bodySmall.toStyle(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: tokens.textEmphasis,
                                            side: BorderSide(color: tokens.borderStrong),
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                            shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
