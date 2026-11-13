import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/iptv/iptv_controller.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/iptv/iptv_settings.dart';
import '../../models/iptv/iptv_models.dart';
import '../../pages/iptv/iptv_portal_browser_page.dart';
import '../../pages/iptv/iptv_portals_modal.dart';
import '../../services/storage/app_image_cache.dart';

enum ChannelSheetTab { xtreme, m3u }

/// The channel picker a multi-view cell opens.
///
/// It is a picker, not a second portal manager: adding, editing, selecting,
/// deleting and filtering portals live in `IptvPortalsModal`, which this sheet
/// opens for that work. What stays here is the frame the cell needs - the
/// search field, the portal chooser that hands a stream back through
/// [onChannelSelected], and the copy / favourite / delete controls on each row.
class MultiNutzChannelSheet extends StatefulWidget {
  final int cellIndex;
  final void Function(String streamUrl, String channelName) onChannelSelected;
  final ChannelSheetTab tabType;

  const MultiNutzChannelSheet({
    super.key,
    required this.cellIndex,
    required this.onChannelSelected,
    required this.tabType,
  });

  @override
  State<MultiNutzChannelSheet> createState() => _MultiNutzChannelSheetState();
}

class _MultiNutzChannelSheetState extends State<MultiNutzChannelSheet> {
  final ctrl = IptvController.instance;

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Widget-tree caches — cleared on data change, reused on reopen
  Widget? _cachedXtremeBody;
  Widget? _cachedM3uBody;

  void _clearXtremeCache() {
    _cachedXtremeBody = null;
  }

  void _clearM3uCache() {
    _cachedM3uBody = null;
  }

  List<PortalChannelGroup> get _filteredXtremeGroups {
    if (_searchQuery.isEmpty) return ctrl.xtremeGroups;
    final q = _searchQuery.toLowerCase();
    return ctrl.xtremeGroups
        .map((group) {
          final filteredHits = group.hits
              .where(
                (hit) =>
                    hit.stream.name.toLowerCase().contains(q) ||
                    group.portal.name.toLowerCase().contains(q),
              )
              .toList();
          if (filteredHits.isEmpty) return null;
          return PortalChannelGroup(portal: group.portal, hits: filteredHits);
        })
        .whereType<PortalChannelGroup>()
        .toList();
  }

  List<M3uChannelGroup> get _filteredM3uGroups {
    if (_searchQuery.isEmpty) return ctrl.m3uGroups;
    final q = _searchQuery.toLowerCase();
    return ctrl.m3uGroups
        .map((group) {
          final filtered = group.channels
              .where(
                (ch) =>
                    ch.name.toLowerCase().contains(q) ||
                    group.playlist.name.toLowerCase().contains(q),
              )
              .toList();
          if (filtered.isEmpty) return null;
          return M3uChannelGroup(playlist: group.playlist, channels: filtered);
        })
        .whereType<M3uChannelGroup>()
        .toList();
  }

  @override
  void initState() {
    super.initState();
    if (widget.tabType == ChannelSheetTab.xtreme) {
      ctrl.xtremeGroups;
    } else {
      ctrl.m3uGroups;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Opens the portal manager on the half this sheet was showing.
  ///
  /// The sheet does not listen to [IptvController], so whatever changed in
  /// there - a portal added, removed or renamed, a playlist fetched - is only
  /// picked up on the `setState` below; both body caches are dropped with it
  /// because they were built from the pre-manager state.
  Future<void> _openPortalManager(int tab) async {
    await IptvPortalsModal.show(context, initialTab: tab);
    if (!mounted) return;
    setState(() {
      _clearXtremeCache();
      _clearM3uCache();
    });
  }

  /// The copy / favourite / delete controls a portal row carries.
  ///
  /// `size` is passed per glyph rather than fixed: the copy and delete glyphs
  /// are drawn at 17 and 18 dp against the star's 19, a difference chosen on
  /// screen to keep the wider star from crowding its neighbours. Everything
  /// else - the 5 dp inset and the zero constraints that keep the button from
  /// claiming a 48 dp square inside a 40 dp row - is the same on all of them.
  Widget _cardIconButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onPressed,
    double size = 17,
  }) {
    return IconButton(
      icon: Icon(icon, color: color, size: size),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(5),
      constraints: const BoxConstraints(),
      onPressed: onPressed,
    );
  }

  /// The one manager entry left here: adding, editing, selecting, deleting and
  /// filtering all live in `IptvPortalsModal`, so this is the way to it rather
  /// than a second copy of it.
  Widget _manageButton({required int tab, required String label}) {
    final tokens = context.tokens;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.textPrimary,
        side: BorderSide(color: tokens.borderStrong),
        shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: ZplaySpacing.s8,
        ),
        minimumSize: const Size(0, 36),
      ),
      icon: const Icon(Icons.settings_input_antenna_rounded, size: 16),
      label: Text(
        label,
        style: ZplayType.bodySmall.copyWith(weight: FontWeight.w700).toStyle(),
      ),
      onPressed: () => _openPortalManager(tab),
    );
  }

  /// Both tabs search the same controller, so they draw the same field.
  Widget _searchField(AppThemePalette palette) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZplaySpacing.s16,
        ZplaySpacing.s16,
        ZplaySpacing.s16,
        ZplaySpacing.s8,
      ),
      child: TextField(
        controller: _searchController,
        style: ZplayType.label.toStyle(color: tokens.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search channels...',
          hintStyle: ZplayType.body.toStyle(color: tokens.textDisabled),
          prefixIcon: Icon(Icons.search_rounded, color: tokens.textDisabled),
          border: OutlineInputBorder(
            borderRadius: ZplayRadius.smAll,
            borderSide: tokens.hairlineStrong,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: ZplayRadius.smAll,
            borderSide: tokens.hairlineStrong,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: ZplayRadius.smAll,
            borderSide: BorderSide(color: palette.primaryColor),
          ),
          filled: true,
          fillColor: tokens.textPrimary.withValues(
            alpha: ZplayOpacity.borderFaint,
          ),
          isDense: true,
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      color: tokens.bg,
      child: widget.tabType == ChannelSheetTab.xtreme
          ? _buildXtremeTab()
          : _buildM3uTab(),
    );
  }

  Widget _buildXtremeTab() {
    final palette = AppThemeService.currentPalette.value;
    final tokens = context.tokens;
    final groups = _filteredXtremeGroups;
    final portals = ctrl.verified;

    // Return cached body when not searching — avoids rebuilding all ExpansionTiles
    if (_searchQuery.isEmpty && _cachedXtremeBody != null) {
      return _cachedXtremeBody!;
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _searchField(palette),

        // Portals are managed in the dialog, not here.
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZplaySpacing.s16,
            vertical: ZplaySpacing.s8,
          ),
          child: _manageButton(tab: 0, label: 'Portals'),
        ),

        const SizedBox(height: ZplaySpacing.s8),

        // Portal List
        ...[
          if (portals.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tv_off_rounded,
                      size: 48,
                      color: tokens.textDisabled,
                    ),
                    const SizedBox(height: ZplaySpacing.s16),
                    Text(
                      _searchQuery.isEmpty
                          ? 'No Xtream portals loaded'
                          : 'No matching channels',
                      style: ZplayType.body.toStyle(color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
            )
          else if (_searchQuery.isEmpty)
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZplaySpacing.s16,
                  vertical: ZplaySpacing.s8,
                ),
                itemCount: portals.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: ZplaySpacing.s8),
                itemBuilder: (context, index) {
                  final p = portals[index];
                  return _buildXtremePortalCard(p, palette);
                },
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZplaySpacing.s16,
                  vertical: ZplaySpacing.s8,
                ),
                itemCount: groups.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: ZplaySpacing.s8),
                itemBuilder: (context, index) {
                  final group = groups[index];
                  return _buildPortalChannelGroup(group, palette);
                },
              ),
            ),
        ],
      ],
    );
    if (_searchQuery.isEmpty) _cachedXtremeBody = body;
    return body;
  }

  Widget _buildXtremePortalCard(VerifiedPortal p, AppThemePalette palette) {
    final tokens = context.tokens;
    final showExp = IptvSettings.showPortalExpiry.value && p.expiry.isNotEmpty;
    final showConn =
        IptvSettings.showPortalConnections.value && p.maxConnections.isNotEmpty;
    final isFav = ctrl.isFavoritePortal(p.key);
    final hasBadges = showExp || showConn || p.portal.source.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: ZplayRadius.smAll,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => IptvPortalBrowserPage(
                portal: p,
                returning: true,
                onStreamSelected: widget.onChannelSelected,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: ZplaySpacing.s12,
          ),
          decoration: BoxDecoration(
            color: tokens.textPrimary.withValues(
              alpha: ZplayOpacity.borderFaint,
            ),
            borderRadius: ZplayRadius.smAll,
            border: Border.all(color: tokens.borderDefault),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      p.name.isNotEmpty ? p.name : p.portal.url,
                      style: ZplayType.label
                          .copyWith(weight: FontWeight.w700)
                          .toStyle(color: tokens.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: ZplaySpacing.s4),
                  _cardIconButton(
                    icon: Icons.copy_rounded,
                    tooltip: 'Copy Login (url:user:pass)',
                    color: tokens.textEmphasis,
                    onPressed: () {
                      final text =
                          '${p.portal.url}:${p.portal.username}:${p.portal.password}';
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied: $text'),
                          duration: const Duration(seconds: 2),
                          backgroundColor: context.tokens.surfaceOverlay,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: ZplaySpacing.s2),
                  _cardIconButton(
                    icon: isFav
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    tooltip: isFav ? 'Remove Favorite' : 'Add to Favorites',
                    color: isFav ? tokens.warning : tokens.textMuted,
                    size: 19,
                    onPressed: () => ctrl.toggleFavoritePortal(p.key),
                  ),
                  const SizedBox(width: ZplaySpacing.s2),
                  _cardIconButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Remove Portal',
                    color: tokens.danger,
                    size: 18,
                    onPressed: () => ctrl.deletePortalsByKeys({p.key}),
                  ),
                  const SizedBox(width: ZplaySpacing.s2),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: tokens.textMuted,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: ZplaySpacing.s4),
              Row(
                children: [
                  Icon(Icons.link_rounded, size: 13, color: tokens.textMuted),
                  const SizedBox(width: ZplaySpacing.s4),
                  Expanded(
                    child: Text(
                      p.portal.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZplayType.caption.toStyle(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              if (hasBadges) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (showExp)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: palette.primaryColor.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: ZplayRadius.xsAll,
                              ),
                              child: Text(
                                'Exp: ${p.expiry}',
                                style: ZplayType.overline
                                    .copyWith(weight: FontWeight.w700)
                                    .toStyle(color: palette.primaryColor),
                              ),
                            ),
                          if (showConn)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.borderDefault,
                                borderRadius: ZplayRadius.xsAll,
                              ),
                              child: Text(
                                'Conn: ${p.activeConnections}/${p.maxConnections}',
                                style: ZplayType.overline.toStyle(
                                  color: tokens.textEmphasis,
                                ),
                              ),
                            ),
                          if (p.portal.source.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    p.portal.source.toLowerCase().contains(
                                          'cloud',
                                        ) ||
                                        p.portal.source.toLowerCase().contains(
                                          'vault',
                                        )
                                    ? tokens.info.withValues(alpha: 0.15)
                                    : (p.portal.source.toLowerCase().contains(
                                            'reddit',
                                          )
                                          ? tokens.danger.withValues(
                                              alpha: 0.15,
                                            )
                                          : tokens.borderDefault),
                                borderRadius: ZplayRadius.xsAll,
                              ),
                              child: Text(
                                p.portal.source,
                                style: ZplayType.overline
                                    .copyWith(weight: FontWeight.w700)
                                    .toStyle(
                                      color:
                                          p.portal.source
                                                  .toLowerCase()
                                                  .contains('cloud') ||
                                              p.portal.source
                                                  .toLowerCase()
                                                  .contains('vault')
                                          ? tokens.info
                                          : (p.portal.source
                                                    .toLowerCase()
                                                    .contains('reddit')
                                                ? tokens.danger
                                                : tokens.textEmphasis),
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPortalChannelGroup(
    PortalChannelGroup group,
    AppThemePalette palette,
  ) {
    final tokens = context.tokens;
    final isRich = IptvSettings.portalCardStyle.value == PortalCardStyle.rich;
    final showExp =
        IptvSettings.showPortalExpiry.value && group.portal.expiry.isNotEmpty;
    final showConn =
        IptvSettings.showPortalConnections.value &&
        group.portal.maxConnections.isNotEmpty;
    final isFav = ctrl.isFavoritePortal(group.portal.key);

    Widget buildBadgesWrap() {
      return Wrap(
        spacing: 5,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (showExp)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: palette.primaryColor.withValues(alpha: 0.15),
                borderRadius: ZplayRadius.xsAll,
              ),
              child: Text(
                'Exp: ${group.portal.expiry}',
                style: ZplayType.overline
                    .copyWith(weight: FontWeight.w700)
                    .toStyle(color: palette.primaryColor),
              ),
            ),
          if (showConn)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: tokens.borderDefault,
                borderRadius: ZplayRadius.xsAll,
              ),
              child: Text(
                'Conn: ${group.portal.activeConnections}/${group.portal.maxConnections}',
                style: ZplayType.overline.toStyle(color: tokens.textEmphasis),
              ),
            ),
          if (group.portal.portal.source.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color:
                    group.portal.portal.source.toLowerCase().contains(
                          'cloud',
                        ) ||
                        group.portal.portal.source.toLowerCase().contains(
                          'vault',
                        )
                    ? tokens.info.withValues(alpha: 0.15)
                    : (group.portal.portal.source.toLowerCase().contains(
                            'reddit',
                          )
                          ? tokens.danger.withValues(alpha: 0.15)
                          : tokens.borderDefault),
                borderRadius: ZplayRadius.xsAll,
              ),
              child: Text(
                group.portal.portal.source,
                style: ZplayType.overline
                    .copyWith(weight: FontWeight.w700)
                    .toStyle(
                      color:
                          group.portal.portal.source.toLowerCase().contains(
                                'cloud',
                              ) ||
                              group.portal.portal.source.toLowerCase().contains(
                                'vault',
                              )
                          ? tokens.info
                          : (group.portal.portal.source.toLowerCase().contains(
                                  'reddit',
                                )
                                ? tokens.danger
                                : tokens.textEmphasis),
                    ),
              ),
            ),
        ],
      );
    }

    return ExpansionTile(
      collapsedShape: const RoundedRectangleBorder(),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: tokens.textPrimary.withValues(
            alpha: ZplayOpacity.borderMedium,
          ),
        ),
      ),
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      title: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: tokens.success,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.portal.name.isNotEmpty
                            ? group.portal.name
                            : group.portal.portal.url,
                        style: ZplayType.label
                            .copyWith(weight: FontWeight.w700)
                            .toStyle(color: tokens.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: ZplaySpacing.s4),
                    _cardIconButton(
                      icon: Icons.copy_rounded,
                      tooltip: 'Copy Login (url:user:pass)',
                      color: tokens.textEmphasis,
                      onPressed: () {
                        final text =
                            '${group.portal.portal.url}:${group.portal.portal.username}:${group.portal.portal.password}';
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Copied: $text'),
                            duration: const Duration(seconds: 2),
                            backgroundColor: context.tokens.surfaceOverlay,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: ZplaySpacing.s2),
                    _cardIconButton(
                      icon: isFav
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      tooltip: isFav ? 'Remove Favorite' : 'Add to Favorites',
                      color: isFav ? tokens.warning : tokens.textMuted,
                      size: 19,
                      onPressed: () =>
                          ctrl.toggleFavoritePortal(group.portal.key),
                    ),
                    const SizedBox(width: ZplaySpacing.s2),
                    _cardIconButton(
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Remove Portal',
                      color: tokens.danger,
                      size: 18,
                      onPressed: () =>
                          ctrl.deletePortalsByKeys({group.portal.key}),
                    ),
                  ],
                ),
                const SizedBox(height: ZplaySpacing.s2),
                Text(
                  group.portal.portal.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                ),
                if ((showExp ||
                        showConn ||
                        group.portal.portal.source.isNotEmpty) &&
                    isRich) ...[
                  const SizedBox(height: ZplaySpacing.s4),
                  buildBadgesWrap(),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, color: tokens.textMuted, size: 18),
        ],
      ),
      children: group.hits.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.all(ZplaySpacing.s16),
                child: Center(
                  child: Text(
                    'No live channels available for this portal',
                    style: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                  ),
                ),
              ),
            ]
          : [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZplaySpacing.s16,
                  vertical: ZplaySpacing.s4,
                ),
                child: Text(
                  '${group.hits.length} live channels',
                  style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: false,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZplaySpacing.s16,
                    vertical: ZplaySpacing.s4,
                  ),
                  itemCount: group.hits.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: ZplaySpacing.s4),
                  itemBuilder: (context, hitIndex) {
                    final hit = group.hits[hitIndex];
                    return _buildChannelHitItem(hit, hitIndex);
                  },
                ),
              ),
            ],
    );
  }

  Widget _buildChannelHitItem(ChannelHit hit, int hitIndex) {
    final tokens = context.tokens;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: hit.stream.icon.isNotEmpty
            ? ClipRRect(
                borderRadius: ZplayRadius.xsAll,
                child: CachedNetworkImage(
                  imageUrl: hit.stream.icon,
                  cacheManager: AppImageCache.manager,
                  memCacheWidth: 96,
                  width: 24,
                  height: 24,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      Icon(Icons.tv, color: tokens.textDisabled),
                ),
              )
            : Icon(Icons.tv, color: tokens.textDisabled, size: 24),
        title: Text(
          hit.stream.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ZplayType.label.toStyle(color: tokens.textPrimary),
        ),
        subtitle: Text(
          hit.stream.containerExt.toUpperCase(),
          style: ZplayType.overline.toStyle(color: tokens.textMuted),
        ),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: ZplaySpacing.s4,
        ),
        shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
        tileColor: tokens.textPrimary.withValues(
          alpha: ZplayOpacity.borderFaint,
        ),
        hoverColor: tokens.borderDefault,
        onTap: () {
          Navigator.pop(context);
          widget.onChannelSelected(hit.streamUrl, hit.stream.name);
        },
      ),
    );
  }

  Widget _buildM3uTab() {
    final palette = AppThemeService.currentPalette.value;
    final tokens = context.tokens;
    final groups = _filteredM3uGroups;

    // Return cached body when not searching — avoids rebuilding all ExpansionTiles
    if (_searchQuery.isEmpty && _cachedM3uBody != null) {
      return _cachedM3uBody!;
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _searchField(palette),

        // Playlists are managed in the dialog, not here.
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZplaySpacing.s16,
            vertical: ZplaySpacing.s8,
          ),
          child: _manageButton(tab: 1, label: 'Playlists'),
        ),

        const SizedBox(height: ZplaySpacing.s8),

        // Channel Groups List
        if (groups.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.playlist_play_rounded,
                    size: 48,
                    color: tokens.textDisabled,
                  ),
                  const SizedBox(height: ZplaySpacing.s16),
                  Text(
                    _searchQuery.isEmpty
                        ? 'No M3U playlists loaded'
                        : 'No matching channels',
                    style: ZplayType.body.toStyle(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: ZplaySpacing.s16,
                vertical: ZplaySpacing.s8,
              ),
              itemCount: groups.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: ZplaySpacing.s8),
              itemBuilder: (context, index) {
                final group = groups[index];
                return _buildM3uChannelGroup(group, palette);
              },
            ),
          ),
      ],
    );
    if (_searchQuery.isEmpty) _cachedM3uBody = body;
    return body;
  }

  Widget _buildM3uChannelGroup(M3uChannelGroup group, AppThemePalette palette) {
    final tokens = context.tokens;

    return ExpansionTile(
      collapsedShape: const RoundedRectangleBorder(),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: tokens.textPrimary.withValues(
            alpha: ZplayOpacity.borderMedium,
          ),
        ),
      ),
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      title: Row(
        children: [
          Container(
            margin: const EdgeInsets.only(right: 10),
            child: Icon(
              Icons.queue_music_rounded,
              color: palette.primaryColor,
              size: 19,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.playlist.name,
                  style: ZplayType.label
                      .copyWith(weight: FontWeight.w700)
                      .toStyle(color: tokens.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: ZplaySpacing.s2),
                Text(
                  '${group.channels.length} channels${group.playlist.sourceUrl != null ? ' · ${group.playlist.sourceUrl!}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZplayType.caption.toStyle(color: tokens.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _cardIconButton(
            icon: Icons.copy_rounded,
            tooltip: 'Copy Playlist URL',
            color: tokens.textEmphasis,
            onPressed: () {
              final text = group.playlist.sourceUrl ?? '';
              if (text.isNotEmpty) {
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Copied: $text'),
                    duration: const Duration(seconds: 2),
                    backgroundColor: context.tokens.surfaceOverlay,
                  ),
                );
              }
            },
          ),
          const SizedBox(width: ZplaySpacing.s2),
          _cardIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Remove Playlist',
            color: tokens.danger,
            size: 18,
            onPressed: () => ctrl.deleteM3uPlaylist(group.playlist.id),
          ),
          const SizedBox(width: ZplaySpacing.s2),
          Icon(Icons.chevron_right_rounded, color: tokens.textMuted, size: 18),
        ],
      ),
      children: group.channels.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.all(ZplaySpacing.s16),
                child: Center(
                  child: Text(
                    'No channels in this playlist',
                    style: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                  ),
                ),
              ),
            ]
          : [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZplaySpacing.s16,
                  vertical: ZplaySpacing.s4,
                ),
                child: Text(
                  '${group.channels.length} channels',
                  style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: false,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZplaySpacing.s16,
                    vertical: ZplaySpacing.s4,
                  ),
                  itemCount: group.channels.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: ZplaySpacing.s4),
                  itemBuilder: (context, chIndex) {
                    final ch = group.channels[chIndex];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: ZplayRadius.smAll,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onChannelSelected(ch.url, ch.name);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: ZplaySpacing.s8,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.textPrimary.withValues(
                              alpha: ZplayOpacity.borderFaint,
                            ),
                            borderRadius: ZplayRadius.smAll,
                            border: Border.all(color: tokens.borderSubtle),
                          ),
                          child: Row(
                            children: [
                              if (ch.logo.isNotEmpty)
                                ClipRRect(
                                  borderRadius: ZplayRadius.xsAll,
                                  child: CachedNetworkImage(
                                    imageUrl: ch.logo,
                                    cacheManager: AppImageCache.manager,
                                    memCacheWidth: 96,
                                    width: 24,
                                    height: 24,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Icon(
                                      Icons.tv,
                                      color: tokens.textDisabled,
                                    ),
                                  ),
                                )
                              else
                                Icon(
                                  Icons.tv,
                                  color: tokens.textDisabled,
                                  size: 24,
                                ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ch.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: ZplayType.label.toStyle(
                                        color: tokens.textPrimary,
                                      ),
                                    ),
                                    if (ch.group.isNotEmpty)
                                      Text(
                                        ch.group,
                                        style: ZplayType.overline.toStyle(
                                          color: tokens.textMuted,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.play_arrow_rounded,
                                color: tokens.success,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
    );
  }
}
