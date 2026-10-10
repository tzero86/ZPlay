import 'package:flutter/material.dart';
import '../../models/iptv/iptv_models.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/iptv/hardcoded_channels.dart';
import '../../services/iptv/iptv_controller.dart';
import '../../utils/navigation/route_transitions.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/pill_button.dart';
import '../../widgets/player/player_glass.dart';
import 'iptv_player_page.dart';

class IptvChannelSheet extends StatefulWidget {
  final HardcodedChannel channel;

  const IptvChannelSheet({super.key, required this.channel});

  static Future<void> show(BuildContext context, HardcodedChannel channel) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => IptvChannelSheet(channel: channel),
    );
  }

  @override
  State<IptvChannelSheet> createState() => _IptvChannelSheetState();
}

class _IptvChannelSheetState extends State<IptvChannelSheet> {
  final _ctrl = IptvController.instance;

  bool _isSelecting = false;
  final Set<String> _selectedUrls = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _ctrl.openHardcodedChannel(widget.channel);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _playHit(ChannelHit hit, [Offset? tapPos]) {
    final results = _ctrl.channelResults;
    if (results.isEmpty) return;
    final index = results.indexOf(hit);
    Navigator.pop(context);
    Navigator.push(
      context,
      LiquidRevealRoute(
        page: IptvPlayerPage(
          channel: widget.channel,
          hits: results,
          initialHitIndex: index >= 0 ? index : 0,
          isLive: true,
        ),
        tapPosition: tapPos,
      ),
    );
  }

  void _toggleSelection(String streamUrl) {
    setState(() {
      if (_selectedUrls.contains(streamUrl)) {
        _selectedUrls.remove(streamUrl);
      } else {
        _selectedUrls.add(streamUrl);
      }
    });
  }

  Future<void> _deleteSelectedStreams() async {
    if (_selectedUrls.isEmpty) return;
    final count = _selectedUrls.length;
    final toDelete = Set<String>.from(_selectedUrls);
    setState(() {
      _selectedUrls.clear();
      _isSelecting = false;
    });
    await _ctrl.removeChannelHits(widget.channel.id, toDelete);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed $count stream feed${count == 1 ? "" : "s"}'),
          duration: const Duration(seconds: 2),
          backgroundColor: context.tokens.surfaceOverlay,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final ch = widget.channel;
    final primaryColor = ch.gradient.isNotEmpty ? ch.gradient.first : tokens.accent;
    // Second stop of a channel's data-driven gradient; falls back to the info hue.
    final secondaryColor = ch.gradient.length > 1 ? ch.gradient.last : tokens.info;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final results = _ctrl.channelResults;
        final isScanning = _ctrl.channelIsRunning;
        final status = _ctrl.channelStatus;
        final filteredResults = _searchQuery.trim().isEmpty
            ? results
            : results.where((hit) {
                final q = _searchQuery.trim().toLowerCase();
                final nameMatches = hit.stream.name.toLowerCase().contains(q);
                final portalMatches = hit.portal.name.toLowerCase().contains(q) ||
                    hit.portal.portal.username.toLowerCase().contains(q);
                final formatMatches = hit.stream.containerExt.toLowerCase().contains(q);
                return nameMatches || portalMatches || formatMatches;
              }).toList();
        final allSelected = results.isNotEmpty && _selectedUrls.length == results.length;

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          // A sheet is already separated from the page by its modal barrier, so
          // it needs neither an edge nor a lift: both were chrome the content
          // had to compete with.
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: ZplayRadius.sheetTop,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(
                    top: ZplaySpacing.s12,
                    bottom: ZplaySpacing.s8,
                  ),
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: tokens.textPrimary.withValues(alpha: ZplayOpacity.overlayHover),
                    borderRadius: ZplayRadius.xsAll,
                  ),
                ),
              ),

              // Header Banner
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 16, 10),
                child: Row(
                  children: [
                    // Channel Short / Icon Badge
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: ZplayRadius.mdAll,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [primaryColor, secondaryColor],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          ch.short,
                          style: ZplayType.title.toStyle(color: tokens.textPrimary),
                        ),
                      ),
                    ),

                    const SizedBox(width: 14),

                    // Title & Category
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: tokens.danger,
                                  borderRadius: ZplayRadius.xsAll,
                                ),
                                child: Text(
                                  'LIVE',
                                  style: ZplayType.overline.toStyle(color: tokens.textPrimary),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                ch.category,
                                style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            ch.name,
                            style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
                          ),
                        ],
                      ),
                    ),

                    // Pen / Edit Button
                    if (results.isNotEmpty)
                      Tooltip(
                        message: _isSelecting ? 'Cancel Selection' : 'Manage / Delete Channels',
                        child: FocusableInkWell(
                          borderRadius: ZplayRadius.smAll,
                          onTap: () {
                            setState(() {
                              _isSelecting = !_isSelecting;
                              if (!_isSelecting) _selectedUrls.clear();
                            });
                          },
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              _isSelecting ? Icons.edit_off_rounded : Icons.edit_rounded,
                              color: _isSelecting ? tokens.info : tokens.textEmphasis,
                              size: 22,
                            ),
                          ),
                        ),
                      ),

                    // Close Button
                    FocusableInkWell(
                      borderRadius: ZplayRadius.smAll,
                      onTap: () => Navigator.pop(context),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.close_rounded, color: tokens.textMuted),
                      ),
                    ),
                  ],
                ),
              ),

              // Search Input Field
              if (results.isNotEmpty || _searchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                  child: Container(
                    height: 42,
                    // The fill is the field's whole shape: a resting hairline
                    // drew a second box on a surface that already reads as one.
                    decoration: BoxDecoration(
                      color: tokens.borderSubtle,
                      borderRadius: ZplayRadius.smAll,
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: ZplayType.label.toStyle(color: tokens.textPrimary),
                      cursorColor: tokens.accent,
                      decoration: InputDecoration(
                        hintText: 'Search ${results.length} channels (e.g. 1080p, 4K, feed name)...',
                        hintStyle: ZplayType.label.toStyle(color: tokens.textMuted),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: _searchQuery.isNotEmpty ? tokens.accent : tokens.textMuted,
                          size: 20,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? FocusableInkWell(
                                borderRadius: ZplayRadius.fullAll,
                                onTap: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                child: SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Icon(Icons.close_rounded, color: tokens.textEmphasis, size: 18),
                                ),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onChanged: (val) {
                        setState(() => _searchQuery = val);
                      },
                    ),
                  ),
                ),

              // Selection Toolbar (when in edit mode)
              if (_isSelecting)
                Container(
                  margin: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  // One accent wash says "edit mode" for the whole bar; the
                  // hairline that used to sit on top of it was a second edge.
                  decoration: BoxDecoration(
                    color: tokens.accentSubtle,
                    borderRadius: ZplayRadius.smAll,
                  ),
                  child: Row(
                    children: [
                      // Select All / Deselect All
                      FocusableInkWell(
                        borderRadius: ZplayRadius.smAll,
                        onTap: () {
                          setState(() {
                            if (allSelected) {
                              _selectedUrls.clear();
                            } else {
                              _selectedUrls.clear();
                              _selectedUrls.addAll(results.map((h) => h.streamUrl));
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                                size: 18,
                                color: tokens.info,
                              ),
                              const SizedBox(width: ZplaySpacing.s8),
                              Text(
                                allSelected ? 'Deselect All' : 'Select All',
                                style: ZplayType.label.toStyle(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${_selectedUrls.length}/${results.length})',
                        style: ZplayType.caption.toStyle(color: tokens.textEmphasis),
                      ),
                      const Spacer(),
                      // Delete Selected
                      FocusableInkWell(
                        borderRadius: ZplayRadius.smAll,
                        enabled: _selectedUrls.isNotEmpty,
                        onTap: _selectedUrls.isEmpty ? null : _deleteSelectedStreams,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12, vertical: 7),
                          decoration: BoxDecoration(
                            color: _selectedUrls.isEmpty ? tokens.borderStrong : tokens.danger,
                            borderRadius: ZplayRadius.smAll,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.delete_rounded,
                                size: 15,
                                color: _selectedUrls.isEmpty ? tokens.textMuted : tokens.onAccent,
                              ),
                              const SizedBox(width: ZplaySpacing.s8),
                              Text(
                                'Delete (${_selectedUrls.length})',
                                style: ZplayType.caption.toStyle(
                                  color: _selectedUrls.isEmpty ? tokens.textMuted : tokens.onAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Status Bar / Progress
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderFaint),
                    borderRadius: ZplayRadius.smAll,
                  ),
                  child: Row(
                    children: [
                      if (isScanning)
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tokens.accent,
                          ),
                        )
                      else
                        Icon(Icons.check_circle_outline_rounded, color: tokens.success, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          status.isNotEmpty
                              ? status
                              : (_searchQuery.trim().isNotEmpty
                                  ? 'Found ${filteredResults.length} of ${results.length} feeds'
                                  : '${results.length} live stream feeds available'),
                          style: ZplayType.label.toStyle(color: tokens.textEmphasis),
                        ),
                      ),
                      if (isScanning)
                        FocusableCard(
                          onTap: _ctrl.stopChannelSearch,
                          builder: (context, state) => CardFocusRing(
                            focused: state.focused,
                            radius: ZplayRadius.xsAll,
                            // Padded to a real D-pad target: the bare label was
                            // a four-letter-wide stop.
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: ZplaySpacing.s12,
                                vertical: ZplaySpacing.s8,
                              ),
                              child: Text(
                                'Stop',
                                style: ZplayType.caption.toStyle(color: tokens.danger),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Discovered Stream Hits List
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isScanning) ...[
                                CircularProgressIndicator(color: tokens.accent),
                                const SizedBox(height: ZplaySpacing.s16),
                                Text(
                                  'Scanning all verified portals in parallel…',
                                  style: ZplayType.body.toStyle(color: tokens.textEmphasis),
                                ),
                              ] else ...[
                                Icon(Icons.tv_off_rounded, color: tokens.textMuted, size: 48),
                                const SizedBox(height: ZplaySpacing.s12),
                                Text(
                                  'No alive streams discovered yet.',
                                  style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Tap "Scan More Portals" to discover fresh feeds.',
                                  style: ZplayType.label.toStyle(color: tokens.textMuted),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : (filteredResults.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search_off_rounded, color: tokens.textMuted, size: 48),
                                  const SizedBox(height: ZplaySpacing.s12),
                                  Text(
                                    'No feeds match "$_searchQuery"',
                                    style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
                                  ),
                                  const SizedBox(height: ZplaySpacing.s8),
                                  FocusableInkWell(
                                    borderRadius: ZplayRadius.smAll,
                                    onTap: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: ZplaySpacing.s12,
                                        vertical: ZplaySpacing.s8,
                                      ),
                                      child: Text(
                                        'Clear Search',
                                        style: ZplayType.label.toStyle(color: tokens.accent),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
                            physics: const BouncingScrollPhysics(),
                            itemCount: filteredResults.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final hit = filteredResults[index];
                              final isFav = _ctrl.isFavoriteHit(ch.id, hit);
                              final isSelected = _selectedUrls.contains(hit.streamUrl);

                              return FocusableCard(
                                onTap: () => _isSelecting
                                    ? _toggleSelection(hit.streamUrl)
                                    : _playHit(hit),
                                builder: (context, state) => CardFocusRing(
                                  focused: state.focused,
                                  radius: ZplayRadius.mdAll,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: ZplaySpacing.s16,
                                      vertical: ZplaySpacing.s12,
                                    ),
                                    decoration: BoxDecoration(
                                      // Selected is one accent wash; favourite
                                      // is the filled star alone. The row is a
                                      // card on a sheet, so it carries no edge
                                      // and no resting fill of its own.
                                      color: isSelected
                                          ? tokens.accentSubtle
                                          : (state.highlighted ? tokens.borderDefault : Colors.transparent),
                                      borderRadius: ZplayRadius.mdAll,
                                    ),
                                    child: Row(
                                      children: [
                                        // Selection checkbox or Play icon
                                        if (_isSelecting)
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? tokens.accent
                                                  : tokens.borderStrong,
                                              shape: BoxShape.circle,
                                            ),
                                            child: isSelected
                                                ? Icon(Icons.check_rounded, color: tokens.onAccent, size: 18)
                                                : null,
                                          )
                                        else
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: tokens.accent.withValues(alpha: 0.2),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.play_arrow_rounded,
                                              color: tokens.accent,
                                              size: 22,
                                            ),
                                          ),

                                        const SizedBox(width: 14),

                                        // Stream Info
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    width: 7,
                                                    height: 7,
                                                    decoration: BoxDecoration(
                                                      color: tokens.success,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      hit.stream.name,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Padding(
                                                padding: const EdgeInsets.only(left: 13),
                                                child: Text(
                                                  hit.portal.portal.username.isNotEmpty
                                                      ? hit.portal.portal.username
                                                      : (hit.portal.name.isNotEmpty
                                                          ? hit.portal.name
                                                          : 'Server ${index + 1}'),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Format Tag
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderMedium),
                                            borderRadius: ZplayRadius.xsAll,
                                          ),
                                          child: Text(
                                            hit.stream.containerExt.toUpperCase(),
                                            style: ZplayType.overline.toStyle(color: tokens.textEmphasis),
                                          ),
                                        ),

                                        const SizedBox(width: 8),

                                        // Favorite Pin
                                        FocusableInkWell(
                                          borderRadius: ZplayRadius.fullAll,
                                          onTap: () => _ctrl.toggleFavoriteHit(hit),
                                          child: SizedBox(
                                            width: 44,
                                            height: 44,
                                            child: Icon(
                                              isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                                              color: isFav ? tokens.warning : tokens.textMuted,
                                              size: 22,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          )),
              ),

              // Bottom Action Bar
              Container(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
                child: Row(
                  children: [
                    // Quick Play Best
                    if (results.isNotEmpty)
                      Expanded(
                        child: PillButton(
                          label: 'Watch Live',
                          icon: Icons.play_arrow_rounded,
                          expand: true,
                          onPressed: filteredResults.isNotEmpty
                              ? () => _playHit(filteredResults.first)
                              : () => _playHit(results.first),
                        ),
                      ),

                    if (results.isNotEmpty) const SizedBox(width: 12),

                    // Scan More: a secondary action, so it stays a quiet
                    // text-only control - the primary pill above is the only
                    // filled button in the bar.
                    FocusableInkWell(
                      borderRadius: ZplayRadius.mdAll,
                      enabled: !isScanning,
                      onTap: isScanning ? null : () => _ctrl.getMoreChannels(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s16,
                          vertical: 14,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              size: 18,
                              color: isScanning ? tokens.textMuted : tokens.textPrimary,
                            ),
                            const SizedBox(width: ZplaySpacing.s8),
                            Text(
                              'Scan More',
                              style: ZplayType.label.toStyle(
                                color: isScanning ? tokens.textMuted : tokens.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
