import 'package:flutter/material.dart';
import '../../services/scraper/builtin_providers_settings_service.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/settings/settings_app_bar.dart';

class BuiltinProvidersSettingsPage extends StatefulWidget {
  const BuiltinProvidersSettingsPage({super.key});

  @override
  State<BuiltinProvidersSettingsPage> createState() => _BuiltinProvidersSettingsPageState();
}

class _BuiltinProvidersSettingsPageState extends State<BuiltinProvidersSettingsPage> {
  final _service = BuiltinProvidersSettingsService.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _service.init();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 500;
    final isUltraCompact = screenWidth < 380;
    final isTabletOrDesktop = screenWidth >= 800;
    final horizontalPadding = isCompact ? 12.0 : (isTabletOrDesktop ? 24.0 : 16.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      // The body's own `AnimatedAmbientBackground` is this page's canvas, so the
      // transparent header is made to float on that same canvas instead of on a
      // second, phase-mismatched one: the body runs behind the bar and the list
      // clears it with its own top padding (below).
      extendBodyBehindAppBar: true,
      appBar: SettingsAppBar(
        title: 'Built-in Providers',
        actions: [
          ListenableBuilder(
            listenable: _service,
            builder: (context, _) {
              if (!_service.isCustom) return const SizedBox.shrink();
              return TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: tokens.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: Text('Reset', style: ZplayType.label.toStyle()),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) {
                      final tokens = ctx.tokens;
                      return AlertDialog(
                        backgroundColor: tokens.surfaceOverlay,
                        shape: const RoundedRectangleBorder(
                          borderRadius: ZplayRadius.lgAll,
                        ),
                        title: Text(
                          'Reset Providers Order?',
                          style: ZplayType.title.toStyle(
                            color: tokens.textPrimary,
                          ),
                        ),
                        content: Text(
                          'This will restore all 45 ZPlayHTTP providers to their default order and re-enable any disabled providers.',
                          style: ZplayType.body.toStyle(
                            color: tokens.textEmphasis,
                          ),
                        ),
                        actions: [
                          TextButton(
                            child: Text(
                              'Cancel',
                              style: ZplayType.label.toStyle(
                                color: tokens.textSecondary,
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx, false),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: tokens.accent,
                              foregroundColor: tokens.onAccent,
                            ),
                            child: const Text('Reset'),
                            onPressed: () => Navigator.pop(ctx, true),
                          ),
                        ],
                      );
                    },
                  );
                  if (confirm == true) {
                    await _service.resetToDefault();
                  }
                },
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedAmbientBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListenableBuilder(
              listenable: _service,
              builder: (context, _) {
                final isCustom = _service.isCustom;
                final allOrdered = _service.getOrderedProviders();
                final filtered = _searchQuery.isEmpty
                    ? allOrdered
                    : allOrdered
                        .where((p) =>
                            p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                            p.id.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                            p.description.toLowerCase().contains(_searchQuery.toLowerCase()))
                        .toList();

                final activeCount = allOrdered.where((p) => _service.isProviderEnabled(p.id)).length;
                final totalCount = allOrdered.length;

                return ListView(
                  // The body runs behind the transparent header
                  // (`extendBodyBehindAppBar`), so the list pays the bar's
                  // height once here: exactly what the old opaque band charged
                  // the layout for.
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    kToolbarHeight + MediaQuery.paddingOf(context).top + 16,
                    horizontalPadding,
                    32 + bottomInset,
                  ),
                  children: [
                    // Mode Selector Header (Responsive)
                    _buildModeSelector(isCustom, isCompact),

                    const SizedBox(height: 18),

                    if (!isCustom) ...[
                      // Default mode info banner
                      _buildDefaultModeCard(totalCount, isCompact),
                    ] else ...[
                      // Custom mode explanation & priority banner
                      _buildPriorityNoticeBanner(isCompact),

                      const SizedBox(height: 16),

                      // Search & Quick Action Toolbar (Responsive)
                      _buildToolbar(activeCount, totalCount, isCompact),

                      const SizedBox(height: 14),

                      // Reorderable list or filtered list
                      if (filtered.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                          alignment: Alignment.center,
                          child: Column(
                            children: [
                              Icon(Icons.search_off_rounded, size: 44, color: tokens.textDisabled),
                              const SizedBox(height: 12),
                              Text(
                                'No providers found matching "$_searchQuery"',
                                textAlign: TextAlign.center,
                                style: ZplayType.body.toStyle(color: tokens.textSecondary),
                              ),
                            ],
                          ),
                        )
                      else if (_searchQuery.isNotEmpty)
                        // Static list when filtered by search query
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final provider = filtered[index];
                            final rank = _service.getProviderRank(provider.id);
                            return _buildProviderTile(
                              provider,
                              rank,
                              isFiltered: true,
                              isCompact: isCompact,
                              isUltraCompact: isUltraCompact,
                            );
                          },
                        )
                      else
                        // Reorderable List
                        Theme(
                          data: Theme.of(context).copyWith(
                            canvasColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                          ),
                          child: ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: allOrdered.length,
                            onReorder: (oldIndex, newIndex) {
                              _service.reorder(oldIndex, newIndex);
                            },
                            itemBuilder: (context, index) {
                              final provider = allOrdered[index];
                              return KeyedSubtree(
                                key: ValueKey('provider_${provider.id}'),
                                child: _buildProviderTile(
                                  provider,
                                  index,
                                  isFiltered: false,
                                  isCompact: isCompact,
                                  isUltraCompact: isUltraCompact,
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector(bool isCustom, bool isCompact) {
    final tokens = context.tokens;
    if (isCompact) {
      return Padding(
        padding: const EdgeInsets.all(5),
        child: Column(
          children: [
            _buildModeTabItem(
              isSelected: !isCustom,
              icon: Icons.auto_awesome_rounded,
              iconColor: tokens.accent,
              title: 'Default Mode',
              subtitle: 'Standard auto-sorting across all 45 providers',
              activeColor: tokens.accent,
              onTap: () => _service.setMode(BuiltinProvidersMode.defaultMode),
            ),
            const SizedBox(height: 4),
            _buildModeTabItem(
              isSelected: isCustom,
              icon: Icons.tune_rounded,
              iconColor: tokens.accent,
              title: 'Custom Mode',
              subtitle: 'Manual provider order, toggles & priority scraping',
              activeColor: tokens.accent,
              onTap: () => _service.setMode(BuiltinProvidersMode.customMode),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          Expanded(
            child: _buildModeTabItem(
              isSelected: !isCustom,
              icon: Icons.auto_awesome_rounded,
              iconColor: tokens.accent,
              title: 'Default',
              subtitle: 'Standard auto-sorting',
              activeColor: tokens.accent,
              onTap: () => _service.setMode(BuiltinProvidersMode.defaultMode),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildModeTabItem(
              isSelected: isCustom,
              icon: Icons.tune_rounded,
              iconColor: tokens.accent,
              title: 'Custom',
              subtitle: 'Manual order & toggles',
              activeColor: tokens.accent,
              onTap: () => _service.setMode(BuiltinProvidersMode.customMode),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTabItem({
    required bool isSelected,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: ZplayRadius.smAll,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? tokens.accentSubtle : Colors.transparent,
          borderRadius: ZplayRadius.smAll,
          border: Border.all(
            color: isSelected
                ? activeColor.withValues(alpha: ZplayOpacity.borderStrong)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? activeColor : tokens.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: ZplayType.subtitle.toStyle(
                      color: isSelected ? tokens.textPrimary : tokens.textEmphasis,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZplayType.caption.toStyle(
                      color: isSelected
                          ? activeColor.withValues(alpha: ZplayOpacity.textPrimary)
                          : tokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, size: 16, color: activeColor),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultModeCard(int totalCount, bool isCompact) {
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.all(isCompact ? 16 : 22),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(
          color: tokens.success.withValues(alpha: ZplayOpacity.borderStrong),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tokens.success.withValues(alpha: ZplayOpacity.borderStrong),
                  borderRadius: ZplayRadius.smAll,
                ),
                child: Icon(Icons.check_circle_rounded, color: tokens.success, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Default Mode Active',
                      style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'All $totalCount ZPlayHTTP providers are active and scraped concurrently.',
                      style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: tokens.borderStrong, height: 1),
          const SizedBox(height: 14),
          Text(
            'In Default mode, ZPlay uses its native multi-source streaming engine. All providers run simultaneously, and results are smartly sorted by video resolution (4K, 1080p, 720p) and file size.',
            style: ZplayType.bodySmall.toStyle(color: tokens.textEmphasis),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: isCompact ? double.infinity : null,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.accent,
                side: BorderSide(
                  color: tokens.accent.withValues(alpha: ZplayOpacity.borderStrong),
                ),
                shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              icon: const Icon(Icons.tune_rounded, size: 17),
              label: Text('Switch to Custom Mode', style: ZplayType.label.toStyle()),
              onPressed: () => _service.setMode(BuiltinProvidersMode.customMode),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityNoticeBanner(bool isCompact) {
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tokens.accent.withValues(alpha: ZplayOpacity.overlayHover),
            tokens.accent.withValues(alpha: ZplayOpacity.borderFaint),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(
          color: tokens.accent.withValues(alpha: ZplayOpacity.borderStrong),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: tokens.accent.withValues(alpha: ZplayOpacity.borderStrong),
              borderRadius: ZplayRadius.smAll,
            ),
            child: Icon(Icons.arrow_upward_rounded, color: tokens.accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Priority Scrape & Result Sorting',
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  'Providers at the top scrape first, and their results strictly display at the top of stream results, no matter the file size or quality.',
                  style: ZplayType.bodySmall.toStyle(color: tokens.textEmphasis),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(int activeCount, int totalCount, bool isCompact) {
    final tokens = context.tokens;
    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search input
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: ZplayRadius.smAll,
              border: Border.fromBorderSide(tokens.hairline),
            ),
            child: TextField(
              controller: _searchController,
              style: ZplayType.body.toStyle(color: tokens.textPrimary),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              decoration: InputDecoration(
                hintText: 'Search providers (e.g. CineSrc)...',
                hintStyle: ZplayType.bodySmall.toStyle(color: tokens.textDisabled),
                prefixIcon: Icon(Icons.search_rounded, size: 18, color: tokens.textMuted),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded, size: 16, color: tokens.textMuted),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Actions and active count row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: ZplayRadius.smAll,
                  border: Border.fromBorderSide(tokens.hairline),
                ),
                child: Text(
                  '$activeCount / $totalCount Active',
                  style: ZplayType.caption.toStyle(
                    color: activeCount > 0 ? tokens.success : tokens.danger,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.select_all_rounded, size: 15),
                    label: Text('Enable All', style: ZplayType.label.toStyle()),
                    onPressed: () => _service.enableAll(),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.deselect_rounded, size: 15),
                    label: Text('Disable All', style: ZplayType.label.toStyle()),
                    onPressed: () => _service.disableAll(),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    }

    // Tablet & Desktop layout
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: ZplayRadius.smAll,
                  border: Border.fromBorderSide(tokens.hairline),
                ),
                child: TextField(
                  controller: _searchController,
                  style: ZplayType.body.toStyle(color: tokens.textPrimary),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search providers (e.g. CineSrc, Dulo)...',
                    hintStyle: ZplayType.bodySmall.toStyle(color: tokens.textDisabled),
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: tokens.textMuted),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded, size: 16, color: tokens.textMuted),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: ZplayRadius.smAll,
                border: Border.fromBorderSide(tokens.hairline),
              ),
              child: Text(
                '$activeCount / $totalCount Active',
                style: ZplayType.caption.toStyle(
                  color: activeCount > 0 ? tokens.success : tokens.danger,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: tokens.accent,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              icon: const Icon(Icons.select_all_rounded, size: 16),
              label: Text('Enable All', style: ZplayType.label.toStyle()),
              onPressed: () => _service.enableAll(),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: tokens.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              icon: const Icon(Icons.deselect_rounded, size: 16),
              label: Text('Disable All', style: ZplayType.label.toStyle()),
              onPressed: () => _service.disableAll(),
            ),
            const Spacer(),
            if (_searchQuery.isNotEmpty)
              Text(
                'Clear search to drag & reorder',
                style: ZplayType.caption.toStyle(color: tokens.textMuted),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildProviderTile(
    BuiltinProviderMeta provider,
    int index, {
    required bool isFiltered,
    required bool isCompact,
    required bool isUltraCompact,
  }) {
    final isEnabled = _service.isProviderEnabled(provider.id);
    final rank = index + 1;
    final isTop3 = rank <= 3;
    final tokens = context.tokens;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: tokens.surface.withValues(
          alpha: isEnabled ? ZplayOpacity.textEmphasis : ZplayOpacity.textMuted,
        ),
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(
          color: isEnabled
              ? (isTop3
                  ? tokens.accent.withValues(alpha: ZplayOpacity.borderStrong)
                  : tokens.borderDefault)
              : tokens.borderSubtle,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 8 : 12,
          vertical: isCompact ? 8 : 10,
        ),
        child: Row(
          children: [
            // Drag Handle (only when not searching)
            if (!isFiltered)
              ReorderableDragStartListener(
                index: index,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 3 : 6,
                    vertical: 8,
                  ),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: isCompact ? 18 : 20,
                    color: isEnabled ? tokens.textMuted : tokens.textDisabled,
                  ),
                ),
              ),

            // Rank Badge
            Container(
              width: isCompact ? 28 : 34,
              height: isCompact ? 28 : 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isTop3 && isEnabled
                    ? tokens.accentSubtle
                    : tokens.borderSubtle,
                borderRadius: ZplayRadius.smAll,
                border: Border.all(
                  color: isTop3 && isEnabled
                      ? tokens.accent.withValues(alpha: ZplayOpacity.borderStrong)
                      : Colors.transparent,
                ),
              ),
              child: Text(
                '#$rank',
                style: ZplayType.caption.toStyle(
                  color: isTop3 && isEnabled
                      ? tokens.accent
                      : (isEnabled ? tokens.textEmphasis : tokens.textDisabled),
                ),
              ),
            ),

            SizedBox(width: isCompact ? 8 : 12),

            // Name & Description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          provider.name,
                          overflow: TextOverflow.ellipsis,
                          style: ZplayType.subtitle.toStyle(
                            color: isEnabled ? tokens.textPrimary : tokens.textMuted,
                          ),
                        ),
                      ),
                      if (!isEnabled) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: tokens.borderSubtle,
                            borderRadius: ZplayRadius.xsAll,
                          ),
                          child: Text(
                            'Off',
                            style: ZplayType.caption.toStyle(color: tokens.textMuted),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    provider.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZplayType.caption.toStyle(
                      color: isEnabled ? tokens.textSecondary : tokens.textDisabled,
                    ),
                  ),
                ],
              ),
            ),

            // Move Up / Move Down Arrow Buttons (compact sizing)
            if (!isUltraCompact) ...[
              IconButton(
                icon: const Icon(Icons.arrow_upward_rounded),
                iconSize: isCompact ? 16 : 18,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                  width: isCompact ? 28 : 34,
                  height: isCompact ? 28 : 34,
                ),
                color: isEnabled && index > 0 ? tokens.textEmphasis : tokens.textDisabled,
                tooltip: 'Move Up',
                onPressed: isEnabled && index > 0
                    ? () => _service.moveProvider(provider.id, -1)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward_rounded),
                iconSize: isCompact ? 16 : 18,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                  width: isCompact ? 28 : 34,
                  height: isCompact ? 28 : 34,
                ),
                color: isEnabled ? tokens.textEmphasis : tokens.textDisabled,
                tooltip: 'Move Down',
                onPressed: isEnabled
                    ? () => _service.moveProvider(provider.id, 1)
                    : null,
              ),
            ],

            SizedBox(width: isCompact ? 4 : 8),

            // Enable / Disable Switch (compact)
            Transform.scale(
              scale: isCompact ? 0.82 : 0.95,
              child: Switch.adaptive(
                value: isEnabled,
                activeColor: tokens.accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (val) => _service.toggleProvider(provider.id, val),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
