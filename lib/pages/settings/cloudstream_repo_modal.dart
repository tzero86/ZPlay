import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/cloudstream/cloudstream_source.dart';
import '../../services/cloudstream/cloudstream_manager.dart';
import '../../services/theme/design_tokens.dart';

class CloudStreamRepoModal extends StatefulWidget {
  const CloudStreamRepoModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CloudStreamRepoModal(),
    );
  }

  @override
  State<CloudStreamRepoModal> createState() => _CloudStreamRepoModalState();
}

class _CloudStreamRepoModalState extends State<CloudStreamRepoModal> {
  final _manager = CloudStreamManager.instance;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _installingIds = {};

  bool _isLoading = true;
  List<CloudStreamSource> _plugins = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadAvailable();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailable() async {
    setState(() => _isLoading = true);
    try {
      final list = await _manager.fetchAvailableExtensions();
      if (mounted) {
        setState(() {
          _plugins = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<CloudStreamSource> get _filteredPlugins {
    if (_searchQuery.trim().isEmpty) return _plugins;
    final q = _searchQuery.trim().toLowerCase();
    return _plugins.where((p) {
      final nameMatch = p.name.toLowerCase().contains(q);
      final langMatch = (p.lang ?? '').toLowerCase().contains(q);
      return nameMatch || langMatch;
    }).toList();
  }

  bool _isInstalled(CloudStreamSource plugin) {
    return _manager.installedExtensions.any(
      (e) => e.name.toLowerCase() == plugin.name.toLowerCase() ||
             (plugin.internalName != null && e.internalName == plugin.internalName),
    );
  }

  Future<void> _install(CloudStreamSource plugin) async {
    final tokens = context.tokens;
    final id = plugin.internalName ?? plugin.name;
    setState(() => _installingIds.add(id));

    try {
      await _manager.installExtension(plugin);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${plugin.name} installed successfully!'),
          backgroundColor: tokens.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
        setState(() => _installingIds.remove(id));
      }
    }
  }

  Future<void> _uninstall(CloudStreamSource plugin) async {
    final tokens = context.tokens;
    final id = plugin.internalName ?? plugin.name;
    setState(() => _installingIds.add(id));

    try {
      await _manager.uninstallExtension(plugin);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${plugin.name} uninstalled.'),
          backgroundColor: tokens.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
        setState(() => _installingIds.remove(id));
      }
    }
  }

  Future<void> _installAll() async {
    final tokens = context.tokens;
    final uninstalled = _filteredPlugins.where((p) => !_isInstalled(p)).toList();
    if (uninstalled.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All matching plugins are already installed!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final count = await _manager.installExtensions(uninstalled);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully installed $count plugins!'),
          backgroundColor: tokens.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {});
    } catch (e) {
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

  Future<void> _confirmUninstallAllInRepo() async {
    final tokens = context.tokens;
    final installedList = _filteredPlugins.where((p) => _isInstalled(p)).toList();
    if (installedList.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.surfaceOverlay,
        shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.mdAll),
        title: Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: tokens.danger, size: 22),
            const SizedBox(width: 8),
            Text('Remove ${installedList.length} Plugin${installedList.length > 1 ? 's' : ''}?'),
          ],
        ),
        content: Text(
          'Are you sure you want to uninstall all ${installedList.length} installed plugins from this list? Their downloaded files will be removed.',
          style: ZplayType.body.toStyle(color: tokens.textEmphasis),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: ZplayType.label.toStyle(color: tokens.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: tokens.danger,
              foregroundColor: tokens.onAccent,
              shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
            ),
            child: Text('Remove All (${installedList.length})', style: ZplayType.label.toStyle()),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    await _manager.uninstallExtensions(installedList);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Successfully uninstalled ${installedList.length} plugins.'),
        backgroundColor: tokens.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final filtered = _filteredPlugins;
    final uninstalledCount = filtered.where((p) => !_isInstalled(p)).length;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: tokens.surfaceOverlay,
            borderRadius: ZplayRadius.sheetTop,
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 30,
                offset: Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: ZplayOpacity.overlayHover),
                    borderRadius: ZplayRadius.xsAll,
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 600;
                    final installedCount = filtered.where((p) => _isInstalled(p)).length;

                    Widget removeAllBtn(bool fullWidth) => ValueListenableBuilder<bool>(
                          valueListenable: _manager.isBusy,
                          builder: (context, busy, _) {
                            return OutlinedButton.icon(
                              onPressed: busy ? null : _confirmUninstallAllInRepo,
                              icon: Icon(
                                Icons.delete_sweep_rounded,
                                size: 14,
                                color: tokens.danger,
                              ),
                              label: Text(
                                'Remove All ($installedCount)',
                                style: ZplayType.caption.toStyle(color: tokens.danger),
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: tokens.danger.withValues(
                                    alpha: ZplayOpacity.textSecondary,
                                  ),
                                ),
                                backgroundColor: tokens.danger.withValues(
                                  alpha: ZplayOpacity.borderDefault,
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                                visualDensity: VisualDensity.compact,
                              ),
                            );
                          },
                        );

                    Widget installAllBtn(bool fullWidth) => ValueListenableBuilder<bool>(
                          valueListenable: _manager.isBusy,
                          builder: (context, busy, _) {
                            return ElevatedButton.icon(
                              onPressed: busy ? null : _installAll,
                              icon: const Icon(Icons.download_rounded, size: 14),
                              label: Text(
                                'Install All ($uninstalledCount)',
                                style: ZplayType.caption.toStyle(),
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: tokens.accent,
                                foregroundColor: tokens.onAccent,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                                visualDensity: VisualDensity.compact,
                              ),
                            );
                          },
                        );

                    if (isMobile) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Available Plugins',
                                  style: ZplayType.title.toStyle(color: tokens.textPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.close_rounded, color: tokens.textEmphasis),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                          if (installedCount > 0 || uninstalledCount > 0) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                if (installedCount > 0)
                                  Expanded(child: removeAllBtn(true)),
                                if (installedCount > 0 && uninstalledCount > 0)
                                  const SizedBox(width: 8),
                                if (uninstalledCount > 0)
                                  Expanded(child: installAllBtn(true)),
                              ],
                            ),
                          ],
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Text(
                          'Available CloudStream Plugins',
                          style: ZplayType.title.toStyle(color: tokens.textPrimary),
                        ),
                        const Spacer(),
                        if (installedCount > 0) ...[
                          removeAllBtn(false),
                          const SizedBox(width: 8),
                        ],
                        if (uninstalledCount > 0) ...[
                          installAllBtn(false),
                          const SizedBox(width: 8),
                        ],
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: tokens.textEmphasis),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // Progress bar if busy
              ValueListenableBuilder<bool>(
                valueListenable: _manager.isBusy,
                builder: (context, busy, _) {
                  if (!busy) return const SizedBox.shrink();
                  return ValueListenableBuilder<String>(
                    valueListenable: _manager.busyMessage,
                    builder: (context, msg, _) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: tokens.accentSubtle,
                          borderRadius: ZplayRadius.smAll,
                          border: Border.all(
                            color: tokens.accent.withValues(
                              alpha: ZplayOpacity.borderStrong,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: tokens.accent),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                msg,
                                style: ZplayType.bodySmall.toStyle(color: tokens.accent),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),

              // Search box
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: TextField(
                  controller: _searchController,
                  style: ZplayType.body.toStyle(color: tokens.textPrimary),
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search plugins (e.g. Sflix, SuperStream)...',
                    hintStyle: ZplayType.label.toStyle(color: tokens.textDisabled),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: tokens.textSecondary,
                    ),
                    filled: true,
                    fillColor: tokens.surfaceRaised,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: const OutlineInputBorder(
                      borderRadius: ZplayRadius.smAll,
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // Plugins list
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: tokens.accent))
                    : filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Text(
                                _searchQuery.isEmpty
                                    ? 'No plugins found in added repositories.\nPlease add a CloudStream repository URL first.'
                                    : 'No plugins matching "$_searchQuery"',
                                textAlign: TextAlign.center,
                                style: ZplayType.body.toStyle(color: tokens.textMuted),
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, idx) {
                              final plugin = filtered[idx];
                              final installed = _isInstalled(plugin);
                              final id = plugin.internalName ?? plugin.name;
                              final isProcessing = _installingIds.contains(id);

                              return Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    // Plugin logo
                                    ClipRRect(
                                      borderRadius: ZplayRadius.smAll,
                                      child: SizedBox(
                                        width: 40,
                                        height: 40,
                                        child: plugin.iconUrl != null && plugin.iconUrl!.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: plugin.iconUrl!,
                                                fit: BoxFit.cover,
                                                errorWidget: (_, __, ___) => Icon(
                                                  Icons.extension_rounded,
                                                  color: tokens.textSecondary,
                                                ),
                                              )
                                            : Icon(
                                                Icons.extension_rounded,
                                                color: tokens.textSecondary,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),

                                    // Info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  plugin.name,
                                                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (plugin.isNsfw) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                  decoration: BoxDecoration(
                                                    color: tokens.danger.withValues(
                                                      alpha: ZplayOpacity.borderStrong,
                                                    ),
                                                    borderRadius: ZplayRadius.xsAll,
                                                  ),
                                                  child: Text(
                                                    '18+',
                                                    style: ZplayType.caption.toStyle(color: tokens.danger),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: tokens.accent.withValues(
                                                    alpha: ZplayOpacity.borderStrong,
                                                  ),
                                                  borderRadius: ZplayRadius.xsAll,
                                                ),
                                                child: Text(
                                                  plugin.effectiveLanguage.toUpperCase(),
                                                  style: ZplayType.caption.toStyle(color: tokens.accent),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'v${plugin.version ?? "1.0.0"}',
                                                style: ZplayType.caption.toStyle(color: tokens.textMuted),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Install / Installed button
                                    if (isProcessing)
                                      SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: tokens.accent),
                                      )
                                    else if (installed)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: tokens.success.withValues(
                                                alpha: ZplayOpacity.borderStrong,
                                              ),
                                              borderRadius: ZplayRadius.smAll,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.check_rounded,
                                                  size: 13,
                                                  color: tokens.success,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Installed',
                                                  style: ZplayType.caption.toStyle(
                                                    color: tokens.success,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 2),
                                          IconButton(
                                            icon: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 18,
                                              color: tokens.danger,
                                            ),
                                            onPressed: () => _uninstall(plugin),
                                            tooltip: 'Uninstall',
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.all(6),
                                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          ),
                                        ],
                                      )
                                    else
                                      ElevatedButton(
                                        onPressed: () => _install(plugin),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: tokens.accent,
                                          foregroundColor: tokens.onAccent,
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                          shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        child: Text(
                                          'Install',
                                          style: ZplayType.label.toStyle(),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}
