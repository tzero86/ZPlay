import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../widgets/common/zplay_logo.dart';
import '../../models/addon/addon.dart';
import '../../models/cloudstream/cloudstream_repo.dart';
import '../../models/cloudstream/cloudstream_source.dart';
import '../../services/addon/addon_manager.dart';
import '../../services/addon/debrid_addon_catalog.dart';
import '../../services/debrid/debrid_service.dart';
import '../../services/storage/app_image_cache.dart';
import '../../services/cloudstream/cloudstream_manager.dart';
import '../../services/cloudstream/runtime/cloudstream_downloader.dart';
import 'cloudstream_marketplace_modal.dart';
import 'cloudstream_repo_modal.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/common/focusable_card.dart';

class AddonsSettingsPage extends StatefulWidget {
  const AddonsSettingsPage({super.key});

  @override
  State<AddonsSettingsPage> createState() => _AddonsSettingsPageState();
}

class _AddonsSettingsPageState extends State<AddonsSettingsPage> {
  final _manager = AddonManager.instance;
  final _csManager = CloudStreamManager.instance;
  final _csDownloader = CloudStreamDownloader.instance;

  int _selectedTabIndex = 0; // 0: Stremio Addons, 1: CloudStream Extensions
  bool _isAdding = false;
  bool _isAddingCsRepo = false;
  bool _csRuntimeReady = false;
  final Set<String> _selectedCsExtensionKeys = {};

  /// Debrid provider picked in Settings, or 'None' when nothing is set up yet.
  String _selectedDebridService = 'None';

  /// Template id whose Connect or Disconnect call is in flight.
  String? _debridAddonBusyId;

  @override
  void initState() {
    super.initState();
    _loadSelectedDebridService();
    _manager.initialize().then((_) {
      if (mounted) setState(() {});
    });
    _csManager.initialize().then((_) {
      if (mounted) setState(() {});
    });
    _checkCsRuntime();
    _csDownloader.isReady.addListener(_onDownloaderChanged);
    _csDownloader.isDownloading.addListener(_onDownloaderChanged);
    _csDownloader.status.addListener(_onDownloaderChanged);
    _csDownloader.progress.addListener(_onDownloaderChanged);
  }

  @override
  void dispose() {
    _csDownloader.isReady.removeListener(_onDownloaderChanged);
    _csDownloader.isDownloading.removeListener(_onDownloaderChanged);
    _csDownloader.status.removeListener(_onDownloaderChanged);
    _csDownloader.progress.removeListener(_onDownloaderChanged);
    super.dispose();
  }

  void _onDownloaderChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkCsRuntime() async {
    final ready = await _csDownloader.checkIsReady();
    if (mounted) {
      setState(() => _csRuntimeReady = ready);
    }
  }

  // ── Debrid addons ──────────────────────────────────────────────────────────

  Future<void> _loadSelectedDebridService() async {
    final service = await DebridService().getSelectedService();
    if (mounted) setState(() => _selectedDebridService = service);
  }

  /// A trailing slash and `/manifest.json` are both cosmetic here, and the
  /// manager strips them when it stores a base URL.
  String _normalizeAddonUrl(String url) {
    var value = url.trim();
    if (value.endsWith('/manifest.json')) {
      value = value.substring(0, value.length - '/manifest.json'.length);
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// The installed entry for [template], matched by base URL because the same
  /// manifest id is reported for every Debrid variant of the addon.
  InstalledAddon? _installedFor(DebridAddonTemplate template) {
    final prefix = _normalizeAddonUrl(template.plainUrl);
    for (final addon in _manager.addons) {
      final baseUrl = _normalizeAddonUrl(addon.baseUrl);
      if (baseUrl == prefix || baseUrl.startsWith('$prefix/')) return addon;
    }
    return null;
  }

  bool _isConnected(DebridAddonTemplate template, InstalledAddon? installed) {
    if (installed == null) return false;
    final url = template.baseUrlFor(_selectedDebridService);
    if (url == null) return false;
    return _normalizeAddonUrl(installed.baseUrl) == _normalizeAddonUrl(url);
  }

  Future<void> _connectDebridAddon(DebridAddonTemplate template, String url) async {
    final installed = _installedFor(template);
    setState(() => _debridAddonBusyId = template.id);

    try {
      final addon = await _manager.replaceAddonUrl(
        installed?.manifest.id ?? template.id,
        url,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${addon.manifest.name} connected to $_selectedDebridService'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.tokens.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.tokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _debridAddonBusyId = null);
    }
  }

  Future<void> _disconnectDebridAddon(
    DebridAddonTemplate template,
    InstalledAddon installed,
  ) async {
    setState(() => _debridAddonBusyId = template.id);

    try {
      await _manager.replaceAddonUrl(installed.manifest.id, template.plainUrl);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.tokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _debridAddonBusyId = null);
    }
  }

  Future<void> _addAddon() async {
    final url = await _showAddDialog();
    if (url == null || url.trim().isEmpty) return;

    setState(() => _isAdding = true);

    try {
      final addon = await _manager.addAddon(url);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${addon.manifest.name} installed successfully!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.tokens.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.tokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<String?> _showAddDialog() {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) {
        final tokens = context.tokens;
        return AlertDialog(
          backgroundColor: tokens.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: ZplayRadius.lgAll,
            side: tokens.hairlineStrong,
          ),
          title: Text(
            'Add Stremio Addon',
            style: ZplayType.title.toStyle(color: tokens.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paste the Stremio addon manifest.json URL to install catalogs, metadata, streams, or subtitles.',
                style: ZplayType.body.toStyle(color: tokens.textSecondary),
              ),
              const SizedBox(height: ZplaySpacing.s16),
              TextField(
                controller: controller,
                autofocus: true,
                style: ZplayType.bodySmall.toStyle(color: tokens.textPrimary),
                decoration: InputDecoration(
                  hintText: 'https://opensubtitles-v3.strem.io/manifest.json',
                  hintStyle: ZplayType.bodySmall.toStyle(
                    color: tokens.textDisabled,
                  ),
                  filled: true,
                  fillColor: tokens.surface,
                  border: OutlineInputBorder(
                    borderRadius: ZplayRadius.smAll,
                    borderSide: BorderSide(color: tokens.borderDefault),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: ZplayRadius.smAll,
                    borderSide: BorderSide(color: tokens.borderDefault),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: ZplayRadius.smAll,
                    borderSide: BorderSide(color: tokens.accent),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                onSubmitted: (value) => Navigator.pop(context, value),
              ),
            ],
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
              onPressed: () => Navigator.pop(context, controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.onAccent,
                shape: const RoundedRectangleBorder(
                  borderRadius: ZplayRadius.smAll,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: Text(
                'Install',
                style: ZplayType.label.toStyle(),
              ),
            ),
          ],
        );
      },
    );
  }

  void _confirmRemove(InstalledAddon addon) {
    if (addon.baseUrl.startsWith('builtin:') ||
        addon.manifest.id == 'builtin.zplay' ||
        addon.manifest.id == 'builtin.zplayhttp') {
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        final tokens = context.tokens;
        return AlertDialog(
          backgroundColor: tokens.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: ZplayRadius.lgAll,
            side: tokens.hairlineStrong,
          ),
          title: Text('Remove ${addon.manifest.name}?'),
          content: Text(
            'Its catalogs and metadata will be removed from your home page.',
            style: ZplayType.body.toStyle(color: tokens.textSecondary),
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
              onPressed: () async {
                Navigator.pop(context);
                await _manager.removeAddon(addon.manifest.id);
                setState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.danger,
                shape: const RoundedRectangleBorder(
                  borderRadius: ZplayRadius.smAll,
                ),
              ),
              child: Text(
                'Remove',
                style: ZplayType.label.toStyle(color: tokens.textPrimary),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addCsRepo() async {
    final url = await _showAddCsRepoDialog();
    if (url == null || url.trim().isEmpty) return;

    setState(() => _isAddingCsRepo = true);
    try {
      await _csManager.addRepo(url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Repository added successfully!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.tokens.success,
        ),
      );

      final shouldInstall = await showDialog<bool>(
        context: context,
        builder: (context) {
          final tokens = context.tokens;
          return AlertDialog(
            backgroundColor: tokens.surfaceOverlay,
            shape: RoundedRectangleBorder(
              borderRadius: ZplayRadius.lgAll,
              side: tokens.hairlineStrong,
            ),
            title: const Text('Install Repository Plugins?'),
            content: Text(
              'Would you like to install all plugins from this repository now so their streaming sources become available immediately on the watch screen?',
              style: ZplayType.body.toStyle(color: tokens.textEmphasis),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Browse Later', style: ZplayType.label.toStyle(color: tokens.textSecondary)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: tokens.onAccent,
                  shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                ),
                child: Text('Install All Now', style: ZplayType.label.toStyle()),
              ),
            ],
          );
        },
      );

      if (shouldInstall == true) {
        await _installAllFromRepo(url);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.tokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isAddingCsRepo = false);
    }
  }

  Future<void> _installAllFromRepo(String repoUrl) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final tokens = context.tokens;
        return AlertDialog(
          backgroundColor: tokens.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: ZplayRadius.lgAll,
            side: tokens.hairlineStrong,
          ),
          title: Text(
            'Installing Plugins',
            style: ZplayType.title.toStyle(color: tokens.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: ZplaySpacing.s8),
              CircularProgressIndicator(color: tokens.accent),
              const SizedBox(height: ZplaySpacing.s16),
              ValueListenableBuilder<String>(
                valueListenable: _csManager.busyMessage,
                builder: (context, msg, _) => Text(
                  msg.isEmpty ? 'Preparing runtime...' : msg,
                  style: ZplayType.body.toStyle(color: tokens.textEmphasis),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      },
    );

    try {
      final count = await _csManager.installAllFromRepo(repoUrl);
      if (mounted) Navigator.pop(context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully installed $count plugins from repository!'),
          backgroundColor: context.tokens.success,
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
          backgroundColor: context.tokens.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<String?> _showAddCsRepoDialog() {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) {
        final tokens = context.tokens;
        return AlertDialog(
          backgroundColor: tokens.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: ZplayRadius.lgAll,
            side: tokens.hairlineStrong,
          ),
          title: Text(
            'Add CloudStream Repository',
            style: ZplayType.title.toStyle(color: tokens.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paste the repository URL (supports cloudstreamrepo://, repo.json, or plugins.json).',
                style: ZplayType.body.toStyle(color: tokens.textSecondary),
              ),
              const SizedBox(height: ZplaySpacing.s16),
              TextField(
                controller: controller,
                autofocus: true,
                style: ZplayType.bodySmall.toStyle(color: tokens.textPrimary),
                decoration: InputDecoration(
                  hintText: 'cloudstreamrepo://.../repo.json or plugins.json',
                  hintStyle: ZplayType.bodySmall.toStyle(
                    color: tokens.textDisabled,
                  ),
                  filled: true,
                  fillColor: tokens.surface,
                  border: OutlineInputBorder(
                    borderRadius: ZplayRadius.smAll,
                    borderSide: BorderSide(color: tokens.borderDefault),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: ZplayRadius.smAll,
                    borderSide: BorderSide(color: tokens.borderDefault),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: ZplayRadius.smAll,
                    borderSide: BorderSide(color: tokens.accent),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                onSubmitted: (value) => Navigator.pop(context, value),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                CloudStreamMarketplaceModal.show(context);
              },
              icon: Icon(Icons.hub_rounded, size: 16, color: tokens.accent),
              label: Text('Browse Marketplace', style: ZplayType.label.toStyle(color: tokens.accent)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: ZplayType.label.toStyle(color: tokens.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.onAccent,
                shape: const RoundedRectangleBorder(
                  borderRadius: ZplayRadius.smAll,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: Text(
                'Add Repository',
                style: ZplayType.label.toStyle(),
              ),
            ),
          ],
        );
      },
    );
  }

  void _confirmRemoveCsExtension(CloudStreamSource ext) {
    showDialog(
      context: context,
      builder: (context) {
        final tokens = context.tokens;
        return AlertDialog(
          backgroundColor: tokens.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: ZplayRadius.lgAll,
            side: tokens.hairlineStrong,
          ),
          title: Text('Remove ${ext.name}?'),
          content: Text(
            'This CloudStream extension will be uninstalled.',
            style: ZplayType.body.toStyle(color: tokens.textSecondary),
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
              onPressed: () async {
                Navigator.pop(context);
                await _csManager.uninstallExtension(ext);
                if (mounted) setState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.danger,
                shape: const RoundedRectangleBorder(
                  borderRadius: ZplayRadius.smAll,
                ),
              ),
              child: Text(
                'Remove',
                style: ZplayType.label.toStyle(color: tokens.textPrimary),
              ),
            ),
          ],
        );
      },
    );
  }

  void _confirmRemoveSelectedCsExtensions(List<CloudStreamSource> installed) {
    final toRemove = installed.where((e) => _selectedCsExtensionKeys.contains(e.internalName ?? e.name)).toList();
    if (toRemove.isEmpty) return;

    final count = toRemove.length;
    showDialog(
      context: context,
      builder: (dialogCtx) {
        final tokens = context.tokens;
        return AlertDialog(
          backgroundColor: tokens.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: ZplayRadius.lgAll,
            side: tokens.hairlineStrong,
          ),
          title: Row(
            children: [
              Icon(Icons.delete_sweep_rounded, color: tokens.danger, size: 22),
              const SizedBox(width: 10),
              Text('Remove $count Plugin${count > 1 ? 's' : ''}?'),
            ],
          ),
          content: Text(
            count == installed.length
                ? 'Are you sure you want to remove all $count installed CloudStream plugins? All downloaded plugin files (.jar/.cs3) will be deleted.'
                : 'Are you sure you want to remove the $count selected CloudStream plugins? Their downloaded files will be deleted from your device.',
            style: ZplayType.body.toStyle(color: tokens.textEmphasis),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                'Cancel',
                style: ZplayType.label.toStyle(color: tokens.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogCtx);
                await _csManager.uninstallExtensions(toRemove);
                if (!mounted) return;
                setState(() {
                  _selectedCsExtensionKeys.clear();
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: tokens.textPrimary, size: 18),
                        const SizedBox(width: ZplaySpacing.s8),
                        Text('Successfully removed $count plugin${count > 1 ? 's' : ''}.'),
                      ],
                    ),
                    backgroundColor: tokens.danger,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.danger,
                foregroundColor: tokens.textPrimary,
                shape: const RoundedRectangleBorder(
                  borderRadius: ZplayRadius.smAll,
                ),
              ),
              child: Text(
                'Remove ($count)',
                style: ZplayType.label.toStyle(),
              ),
            ),
          ],
        );
      },
    );
  }

  void _confirmRemoveCsRepo(CloudStreamRepo repo) {
    showDialog(
      context: context,
      builder: (context) {
        final tokens = context.tokens;
        return AlertDialog(
          backgroundColor: tokens.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: ZplayRadius.lgAll,
            side: tokens.hairlineStrong,
          ),
          title: Text('Remove ${repo.name}?'),
          content: Text(
            'Plugins from this repository will not be deleted, but repository updates will no longer be fetched.',
            style: ZplayType.body.toStyle(color: tokens.textSecondary),
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
              onPressed: () async {
                Navigator.pop(context);
                await _csManager.removeRepo(repo.url);
                if (mounted) setState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.danger,
                shape: const RoundedRectangleBorder(
                  borderRadius: ZplayRadius.smAll,
                ),
              ),
              child: Text(
                'Remove',
                style: ZplayType.label.toStyle(color: tokens.textPrimary),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final addons = _manager.addons;
    final csExtensions = _csManager.installedExtensions;
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        surfaceTintColor: Colors.transparent,
        // Opaque palette band with a bottom hairline, matching the rest of the
        // settings family, instead of a translucent wash over the page.
        shape: Border(bottom: tokens.hairline),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Addons & Extensions',
          style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s16,
              vertical: ZplaySpacing.s20,
            ),
            children: [
              // Segmented Tab Selector
              Container(
                margin: const EdgeInsets.only(bottom: ZplaySpacing.s20),
                padding: const EdgeInsets.all(ZplaySpacing.s4),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: ZplayRadius.mdAll,
                  border: Border.all(color: tokens.borderDefault),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _TabButton(
                        title: 'Stremio Addons',
                        icon: Icons.extension_rounded,
                        count: addons.length,
                        isSelected: _selectedTabIndex == 0,
                        onTap: () => setState(() => _selectedTabIndex = 0),
                      ),
                    ),
                    Expanded(
                      child: _TabButton(
                        title: 'CloudStream',
                        icon: Icons.cloud_download_rounded,
                        count: csExtensions.length,
                        isSelected: _selectedTabIndex == 1,
                        onTap: () => setState(() => _selectedTabIndex = 1),
                      ),
                    ),
                  ],
                ),
              ),

              if (_selectedTabIndex == 0)
                _buildStremioTab(addons)
              else
                _buildCloudStreamTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStremioTab(List<InstalledAddon> addons) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Description
        Padding(
          padding: const EdgeInsets.only(bottom: ZplaySpacing.s20),
          child: Text(
            'Addons provide metadata, catalogs, and streaming sources. Hold and drag to reorder priority. Providers higher up load and appear first in watch sources.',
            style: ZplayType.body.toStyle(color: tokens.textSecondary),
          ),
        ),

        // Add Addon Button
        _AddAddonButton(isLoading: _isAdding, onTap: _addAddon),
        const SizedBox(height: ZplaySpacing.s24),

        // Debrid addons
        _buildDebridAddonsSection(),
        const SizedBox(height: ZplaySpacing.s24),

        // Section Header
        Row(
          children: [
            Expanded(
              child: Text(
                'INSTALLED PROVIDERS & ADDONS',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: ZplaySpacing.s8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ZplaySpacing.s8,
                vertical: ZplaySpacing.s2,
              ),
              decoration: BoxDecoration(
                color: tokens.accentSubtle,
                borderRadius: ZplayRadius.xsAll,
              ),
              child: Text(
                '${addons.length} Total',
                style: ZplayType.caption.toStyle(color: tokens.accent),
              ),
            ),
          ],
        ),
        const SizedBox(height: ZplaySpacing.s12),

        // Addons List or Empty State
        if (addons.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: ZplayRadius.mdAll,
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Column(
              children: [
                Icon(Icons.extension_off_rounded, size: 40, color: tokens.textDisabled),
                const SizedBox(height: ZplaySpacing.s12),
                Text(
                  'No Addons Installed',
                  style: ZplayType.title.toStyle(color: tokens.textEmphasis),
                ),
                const SizedBox(height: 6),
                Text(
                  'Click "Add Addon" above to install a Stremio manifest URL.',
                  textAlign: TextAlign.center,
                  style: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                ),
              ],
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: addons.length,
            onReorder: (oldIdx, newIdx) async {
              await _manager.reorderAddons(oldIdx, newIdx);
              setState(() {});
            },
            itemBuilder: (context, index) {
              final addon = addons[index];
              return Padding(
                key: ValueKey(addon.manifest.id),
                padding: const EdgeInsets.only(bottom: ZplaySpacing.s12),
                child: _AddonCard(
                  index: index,
                  totalCount: addons.length,
                  addon: addon,
                  onMoveUp: index > 0
                      ? () async {
                          await _manager.moveAddonUp(index);
                          setState(() {});
                        }
                      : null,
                  onMoveDown: index < addons.length - 1
                      ? () async {
                          await _manager.moveAddonDown(index);
                          setState(() {});
                        }
                      : null,
                  onToggle: (enabled) async {
                    await _manager.toggleAddon(addon.manifest.id, enabled);
                    setState(() {});
                  },
                  onRatingChanged: (rating) async {
                    await _manager.setAddonAdultRating(
                      addon.manifest.id,
                      rating,
                    );
                    setState(() {});
                  },
                  onUpdateFeature: ({
                    enableCatalogs,
                    enableSearch,
                    enableSubtitles,
                    enableStreams,
                  }) async {
                    await _manager.updateAddonFeature(
                      addonId: addon.manifest.id,
                      enableCatalogs: enableCatalogs,
                      enableSearch: enableSearch,
                      enableSubtitles: enableSubtitles,
                      enableStreams: enableStreams,
                    );
                    setState(() {});
                  },
                  onRemove: () => _confirmRemove(addon),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildDebridAddonsSection() {
    final tokens = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DEBRID ADDONS',
          style: ZplayType.overline.toStyle(color: tokens.textMuted),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: ZplaySpacing.s4),
        Text(
          'Installs the addon for the Debrid provider selected in Settings and fills your saved key in at request time, so the key is never stored twice.',
          style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
        ),
        const SizedBox(height: ZplaySpacing.s12),

        for (final template in DebridAddonCatalog.templates)
          Padding(
            padding: const EdgeInsets.only(bottom: ZplaySpacing.s12),
            child: _debridAddonCard(template),
          ),

        Text(
          'Addons that take the key as a plain URL parameter accept a {realdebrid} style placeholder. Addons that hide it inside a base64 config blob have to be pasted fully configured instead.',
          style: ZplayType.caption.toStyle(color: tokens.textMuted),
        ),
      ],
    );
  }

  Widget _debridAddonCard(DebridAddonTemplate template) {
    final installed = _installedFor(template);
    final url = template.baseUrlFor(_selectedDebridService);

    return _DebridAddonCard(
      template: template,
      selectedService: _selectedDebridService,
      isServiceReady: url != null,
      isConnected: _isConnected(template, installed),
      isBusy: _debridAddonBusyId == template.id,
      onConnect: url == null ? null : () => _connectDebridAddon(template, url),
      onDisconnect: installed == null
          ? null
          : () => _disconnectDebridAddon(template, installed),
    );
  }

  Widget _buildCloudStreamTab() {
    final installed = _csManager.installedExtensions;
    final repos = _csManager.repos;
    final isReady = _csRuntimeReady || _csDownloader.isReady.value;
    final isDownloading = _csDownloader.isDownloading.value;
    final tokens = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Description
        Padding(
          padding: const EdgeInsets.only(bottom: ZplaySpacing.s16),
          child: Text(
            'CloudStream (.cs3) extensions provide stream providers directly from popular media sites. Extensions run locally in a sandboxed sidecar or native ART engine.',
            style: ZplayType.body.toStyle(color: tokens.textSecondary),
          ),
        ),

        // Runtime Status Card
        Container(
          padding: const EdgeInsets.all(ZplaySpacing.s16),
          margin: const EdgeInsets.only(bottom: ZplaySpacing.s20),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: ZplayRadius.mdAll,
            border: Border.all(
              color: (isReady ? tokens.success : tokens.warning).withValues(
                alpha: ZplayOpacity.textMuted,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 500;
                  final statusContent = Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(ZplaySpacing.s8),
                        decoration: BoxDecoration(
                          color: (isReady ? tokens.success : tokens.warning)
                              .withValues(alpha: ZplayOpacity.overlayHover),
                          borderRadius: ZplayRadius.smAll,
                        ),
                        child: Icon(
                          isReady ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                          color: isReady ? tokens.success : tokens.warning,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: ZplaySpacing.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isReady ? 'CloudStream Engine Ready' : 'Runtime Setup Required',
                              style: ZplayType.subtitle.toStyle(
                                color: tokens.textPrimary,
                              ),
                            ),
                            const SizedBox(height: ZplaySpacing.s2),
                            Text(
                              isReady
                                  ? 'Native engine active and listening for queries.'
                                  : (isDownloading
                                      ? (_csDownloader.status.value.isNotEmpty
                                          ? _csDownloader.status.value
                                          : 'Downloading runtime components...')
                                      : (Platform.isAndroid
                                          ? 'Requires runtime host to execute .cs3 bytecode.'
                                          : 'Requires sidecar runtime to execute .cs3 bytecode.')),
                              style: ZplayType.bodySmall.toStyle(
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isReady && !isDownloading && !isCompact) ...[
                        const SizedBox(width: ZplaySpacing.s12),
                        _buildSetupEngineButton(),
                      ],
                    ],
                  );

                  if (isCompact && !isReady && !isDownloading) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        statusContent,
                        const SizedBox(height: ZplaySpacing.s12),
                        _buildSetupEngineButton(),
                      ],
                    );
                  }
                  return statusContent;
                },
              ),
              if (isDownloading) ...[
                const SizedBox(height: ZplaySpacing.s12),
                ClipRRect(
                  borderRadius: ZplayRadius.xsAll,
                  child: LinearProgressIndicator(
                    value: _csDownloader.progress.value > 0 ? _csDownloader.progress.value : null,
                    backgroundColor: tokens.borderDefault,
                    color: tokens.accent,
                    minHeight: 6,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Repository Marketplace Banner Card
        FocusableCard(
          onTap: () async {
            await CloudStreamMarketplaceModal.show(context);
            if (mounted) setState(() {});
          },
          builder: (_, state) => Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(ZplaySpacing.s16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  tokens.accent.withValues(alpha: ZplayOpacity.overlayHover),
                  tokens.info.withValues(alpha: ZplayOpacity.borderStrong),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: ZplayRadius.mdAll,
              border: Border.all(
                color: tokens.accent.withValues(alpha: ZplayOpacity.textMuted),
              ),
              boxShadow: [
                BoxShadow(
                  color: tokens.accent.withValues(alpha: ZplayOpacity.borderMedium),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(ZplaySpacing.s12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [tokens.accent, tokens.accentHover],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: ZplayRadius.mdAll,
                    boxShadow: [
                      BoxShadow(
                        color: tokens.accent.withValues(alpha: ZplayOpacity.textMuted),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(Icons.hub_rounded, color: tokens.onAccent, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Repository Marketplace',
                            style: ZplayType.subtitle.toStyle(
                              color: tokens.textPrimary,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: tokens.success.withValues(alpha: ZplayOpacity.overlayHover),
                              borderRadius: ZplayRadius.xsAll,
                              border: Border.all(
                                color: tokens.success.withValues(alpha: ZplayOpacity.textMuted),
                              ),
                            ),
                            child: Text(
                              '45+ Repos',
                              style: ZplayType.caption.toStyle(color: tokens.success),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: ZplaySpacing.s4),
                      Text(
                        'Browse curated Turkish, 3rabi, English, Hindi & global repos with direct install links.',
                        style: ZplayType.bodySmall.toStyle(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: ZplaySpacing.s8),
                Container(
                  padding: const EdgeInsets.all(ZplaySpacing.s8),
                  decoration: BoxDecoration(
                    color: tokens.borderDefault,
                    borderRadius: ZplayRadius.smAll,
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: tokens.textEmphasis,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Action Buttons (Responsive Row / Column)
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 520;

            final browseBtn = FocusableCard(
              onTap: () async {
                await CloudStreamRepoModal.show(context);
                if (mounted) setState(() {});
              },
              builder: (_, state) => Container(
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: ZplayRadius.mdAll,
                  gradient: LinearGradient(
                    colors: [tokens.accent, tokens.accentHover],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: tokens.accent.withValues(alpha: ZplayOpacity.textDisabled),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.storefront_rounded, color: tokens.onAccent, size: 20),
                    const SizedBox(width: ZplaySpacing.s8),
                    Flexible(
                      child: Text(
                        'Browse Available Plugins',
                        style: ZplayType.label.toStyle(color: tokens.onAccent),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );

            final addRepoBtn = FocusableCard(
              onTap: _addCsRepo,
              enabled: !_isAddingCsRepo,
              builder: (_, state) => Container(
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: ZplayRadius.mdAll,
                  border: Border.all(
                    color: tokens.accent.withValues(alpha: ZplayOpacity.textDisabled),
                  ),
                  color: tokens.accent.withValues(alpha: ZplayOpacity.borderSubtle),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isAddingCsRepo)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: tokens.accent),
                      )
                    else
                      Icon(Icons.add_link_rounded, color: tokens.accent, size: 20),
                    const SizedBox(width: ZplaySpacing.s8),
                    Flexible(
                      child: Text(
                        'Add Repository',
                        style: ZplayType.label.toStyle(color: tokens.accent),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );

            if (isNarrow) {
              return Column(
                children: [
                  browseBtn,
                  const SizedBox(height: 10),
                  addRepoBtn,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: browseBtn),
                const SizedBox(width: ZplaySpacing.s12),
                Expanded(child: addRepoBtn),
              ],
            );
          },
        ),
        const SizedBox(height: ZplaySpacing.s24),

        // Section: Installed Extensions (Responsive Header)
        LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 560;

            Widget selectAllBtn() {
              final allKeys = installed.map((e) => e.internalName ?? e.name).toSet();
              final allSelected = allKeys.isNotEmpty && allKeys.every(_selectedCsExtensionKeys.contains);
              final anySelected = _selectedCsExtensionKeys.isNotEmpty;

              return TextButton.icon(
                onPressed: () {
                  setState(() {
                    if (allSelected || anySelected) {
                      _selectedCsExtensionKeys.clear();
                    } else {
                      _selectedCsExtensionKeys.addAll(allKeys);
                    }
                  });
                },
                icon: Icon(
                  allSelected
                      ? Icons.check_box_rounded
                      : (anySelected
                          ? Icons.indeterminate_check_box_rounded
                          : Icons.check_box_outline_blank_rounded),
                  size: 16,
                  color: anySelected ? tokens.accent : tokens.textSecondary,
                ),
                label: Text(
                  allSelected ? 'Deselect All' : (anySelected ? 'Deselect All' : 'Select All'),
                  style: ZplayType.caption.toStyle(
                    color: anySelected ? tokens.accent : tokens.textEmphasis,
                  ),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: anySelected
                      ? tokens.accent.withValues(alpha: ZplayOpacity.borderStrong)
                      : tokens.borderSubtle,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }

            Widget removeSelectedBtn() {
              return ElevatedButton.icon(
                onPressed: () => _confirmRemoveSelectedCsExtensions(installed),
                icon: const Icon(Icons.delete_sweep_rounded, size: 14),
                label: Text(
                  'Remove (${_selectedCsExtensionKeys.length})',
                  style: ZplayType.caption.toStyle(),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.danger,
                  foregroundColor: tokens.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                  visualDensity: VisualDensity.compact,
                  elevation: 0,
                ),
              );
            }

            final totalBadge = Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ZplaySpacing.s8,
                vertical: ZplaySpacing.s2,
              ),
              decoration: BoxDecoration(
                color: tokens.accentSubtle,
                borderRadius: ZplayRadius.xsAll,
              ),
              child: Text(
                '${installed.length} Total',
                style: ZplayType.caption.toStyle(color: tokens.accent),
              ),
            );

            if (isMobile) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'INSTALLED EXTENSIONS',
                          style: ZplayType.overline.toStyle(color: tokens.textMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: ZplaySpacing.s8),
                      totalBadge,
                    ],
                  ),
                  if (installed.isNotEmpty) ...[
                    const SizedBox(height: ZplaySpacing.s8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        selectAllBtn(),
                        if (_selectedCsExtensionKeys.isNotEmpty) removeSelectedBtn(),
                      ],
                    ),
                  ],
                ],
              );
            }

            return Row(
              children: [
                Text(
                  'INSTALLED CLOUDSTREAM EXTENSIONS',
                  style: ZplayType.overline.toStyle(color: tokens.textMuted),
                ),
                const Spacer(),
                if (installed.isNotEmpty) ...[
                  selectAllBtn(),
                  const SizedBox(width: ZplaySpacing.s8),
                  if (_selectedCsExtensionKeys.isNotEmpty) ...[
                    removeSelectedBtn(),
                    const SizedBox(width: ZplaySpacing.s8),
                  ],
                ],
                totalBadge,
              ],
            );
          },
        ),
        const SizedBox(height: ZplaySpacing.s12),

        if (installed.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: ZplayRadius.mdAll,
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Column(
              children: [
                Icon(Icons.extension_off_rounded, size: 40, color: tokens.textDisabled),
                const SizedBox(height: ZplaySpacing.s12),
                Text(
                  'No Extensions Installed',
                  style: ZplayType.title.toStyle(color: tokens.textEmphasis),
                ),
                const SizedBox(height: 6),
                Text(
                  'Click "Browse Available Plugins" to find and install extensions.',
                  textAlign: TextAlign.center,
                  style: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: installed.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final ext = installed[index];
              final key = ext.internalName ?? ext.name;
              final isSelected = _selectedCsExtensionKeys.contains(key);
              return _CloudStreamCard(
                source: ext,
                isSelected: isSelected,
                onSelectToggle: () {
                  setState(() {
                    if (isSelected) {
                      _selectedCsExtensionKeys.remove(key);
                    } else {
                      _selectedCsExtensionKeys.add(key);
                    }
                  });
                },
                onToggle: (val) async {
                  await _csManager.toggleExtension(ext.internalName ?? ext.name, val);
                  setState(() {});
                },
                onRemove: () => _confirmRemoveCsExtension(ext),
              );
            },
          ),

        const SizedBox(height: 28),

        // Section: Added Repositories
        Row(
          children: [
            Text(
              'REPOSITORIES',
              style: ZplayType.overline.toStyle(color: tokens.textMuted),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ZplaySpacing.s8,
                vertical: ZplaySpacing.s2,
              ),
              decoration: BoxDecoration(
                color: tokens.borderSubtle,
                borderRadius: ZplayRadius.xsAll,
              ),
              child: Text(
                '${repos.length} Repos',
                style: ZplayType.caption.toStyle(color: tokens.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: ZplaySpacing.s12),

        if (repos.isEmpty)
          Container(
            padding: const EdgeInsets.all(ZplaySpacing.s20),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: ZplayRadius.mdAll,
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Row(
              children: [
                Icon(Icons.link_off_rounded, color: tokens.textDisabled, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'No custom repositories added. Click "Add Repository" to subscribe to a CloudStream repository.',
                    style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                  ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: repos.length,
            separatorBuilder: (_, __) => const SizedBox(height: ZplaySpacing.s8),
            itemBuilder: (context, index) {
              final repo = repos[index];
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZplaySpacing.s16,
                  vertical: ZplaySpacing.s12,
                ),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: ZplayRadius.smAll,
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: Row(
                  children: [
                    Icon(Icons.folder_copy_rounded, color: tokens.accent, size: 20),
                    const SizedBox(width: ZplaySpacing.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            repo.name,
                            style: ZplayType.subtitle.toStyle(
                              color: tokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: ZplaySpacing.s2),
                          Text(
                            repo.url,
                            style: ZplayType.caption.toStyle(
                              color: tokens.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.download_rounded, size: 20),
                      color: tokens.accent,
                      splashRadius: 18,
                      tooltip: 'Install all plugins from this repository',
                      onPressed: () => _installAllFromRepo(repo.url),
                    ),
                    IconButton(
                      icon: const Icon(Icons.storefront_rounded, size: 19),
                      color: tokens.textEmphasis,
                      splashRadius: 18,
                      tooltip: 'Browse repository plugins',
                      onPressed: () async {
                        await CloudStreamRepoModal.show(context);
                        if (mounted) setState(() {});
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      color: tokens.textMuted,
                      splashRadius: 18,
                      tooltip: 'Remove repository',
                      onPressed: () => _confirmRemoveCsRepo(repo),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildSetupEngineButton() {
    final tokens = context.tokens;
    return ElevatedButton.icon(
      onPressed: () async {
        try {
          await _csDownloader.setupRuntime();
          await _checkCsRuntime();
          await _csManager.seedDefaultRepoIfEligible();
          if (mounted) setState(() {});
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Runtime setup error: $e'),
              backgroundColor: tokens.danger,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      icon: const Icon(Icons.download_rounded, size: 16),
      label: Text('Setup Engine', style: ZplayType.label.toStyle()),
      style: ElevatedButton.styleFrom(
        backgroundColor: tokens.accent,
        foregroundColor: tokens.onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: const RoundedRectangleBorder(
          borderRadius: ZplayRadius.smAll,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Addon Card
// ─────────────────────────────────────────────────────────────────────────────

class _AddonCard extends StatelessWidget {
  final int index;
  final int totalCount;
  final InstalledAddon addon;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final ValueChanged<bool> onToggle;
  final ValueChanged<AddonAdultRating> onRatingChanged;
  final void Function({
    bool? enableCatalogs,
    bool? enableSearch,
    bool? enableSubtitles,
    bool? enableStreams,
  }) onUpdateFeature;
  final VoidCallback onRemove;

  const _AddonCard({
    required this.index,
    required this.totalCount,
    required this.addon,
    this.onMoveUp,
    this.onMoveDown,
    required this.onToggle,
    required this.onRatingChanged,
    required this.onUpdateFeature,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final m = addon.manifest;
    final isP2p = addon.manifest.id == 'builtin.zplay' || addon.baseUrl == 'builtin:zplay';
    final isHttp = addon.manifest.id == 'builtin.zplayhttp' || addon.baseUrl == 'builtin:zplayhttp';
    final isBuiltIn = isP2p || isHttp || addon.baseUrl.startsWith('builtin:');

    final hasCatalogs = m.supportsCatalog || m.catalogs.isNotEmpty;
    final hasSearch = m.catalogs.any((c) => c.supportsSearch) || m.supportsCatalog;
    final hasStreams = m.supportsStream;
    final hasSubtitles = m.supportsSubtitles;
    final hasAnyFeature = hasCatalogs || hasSearch || hasStreams || hasSubtitles;

    final providerColor = isHttp ? tokens.success : tokens.accent;

    final subtitleText = isP2p
        ? 'Built-in TorrServer P2P streaming engine'
        : (isHttp
            ? 'Built-in multi-source fast HTTP scrapers'
            : (m.supportsSubtitles && m.catalogs.isEmpty
                ? 'v${m.version}  ·  Subtitles Provider'
                : 'v${m.version}  ·  ${m.catalogs.length} catalog${m.catalogs.length == 1 ? '' : 's'}${m.supportsSubtitles ? '  ·  Subtitles' : ''}'));

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 560;

        Widget dragHandle() => ReorderableDragStartListener(
              index: index,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: tokens.borderSubtle,
                    borderRadius: ZplayRadius.smAll,
                  ),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: tokens.textMuted,
                    size: 19,
                  ),
                ),
              ),
            );

        Widget priorityBadge() => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
              margin: const EdgeInsets.only(right: ZplaySpacing.s8),
              decoration: BoxDecoration(
                color: providerColor.withValues(alpha: ZplayOpacity.overlayHover),
                borderRadius: ZplayRadius.xsAll,
                border: Border.all(
                  color: providerColor.withValues(alpha: ZplayOpacity.textDisabled),
                ),
              ),
              child: Text(
                '#${index + 1}',
                style: ZplayType.caption.toStyle(color: providerColor),
              ),
            );

        Widget addonIcon() => Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(3.5),
              decoration: BoxDecoration(
                borderRadius: ZplayRadius.smAll,
                color: providerColor.withValues(alpha: ZplayOpacity.overlayHover),
              ),
              child: isBuiltIn
                  ? const ZplayLogo(size: 26)
                  : (m.logo != null && m.logo!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: ZplayRadius.xsAll,
                          child: CachedNetworkImage(
                            imageUrl: m.logo!,
                            cacheManager: AppImageCache.manager,
                            memCacheWidth: 96,
                            width: 26,
                            height: 26,
                            fit: BoxFit.contain,
                            errorWidget: (_, __, ___) => Icon(
                              Icons.extension_rounded,
                              color: providerColor,
                              size: 19,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.extension_rounded,
                          color: providerColor,
                          size: 19,
                        )),
            );

        Widget upDownButtons() => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
                  color: onMoveUp != null ? tokens.textEmphasis : tokens.textDisabled,
                  onPressed: onMoveUp,
                  tooltip: 'Move up in priority',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                  color: onMoveDown != null ? tokens.textEmphasis : tokens.textDisabled,
                  onPressed: onMoveDown,
                  tooltip: 'Move down in priority',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            );

        Widget switchWidget() => Switch.adaptive(
              value: addon.enabled,
              onChanged: onToggle,
              activeColor: providerColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            );

        Widget builtInTag() => Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: providerColor.withValues(alpha: ZplayOpacity.overlayHover),
                borderRadius: ZplayRadius.xsAll,
              ),
              child: Text(
                isP2p ? 'BUILT-IN TORRENT' : 'BUILT-IN HTTP',
                style: ZplayType.overline.toStyle(color: providerColor),
              ),
            );

        Widget removeButton() => IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 19),
              color: tokens.danger.withValues(alpha: ZplayOpacity.textSecondary),
              onPressed: onRemove,
              tooltip: 'Remove addon',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              visualDensity: VisualDensity.compact,
            );

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: ZplayRadius.mdAll,
            border: Border.all(
              color: addon.enabled
                  ? providerColor.withValues(alpha: ZplayOpacity.textDisabled)
                  : tokens.borderSubtle,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile) ...[
                // Mobile Top Row: Drag + Priority + Icon + Title/Badge + Switch
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    dragHandle(),
                    priorityBadge(),
                    addonIcon(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            m.name,
                            style: ZplayType.subtitle.toStyle(
                              color: tokens.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isBuiltIn) ...[
                            const SizedBox(height: 3),
                            builtInTag(),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: ZplaySpacing.s8),
                    switchWidget(),
                  ],
                ),
                // Mobile Subtitle: Full width of the card, never squished
                Padding(
                  padding: const EdgeInsets.only(top: ZplaySpacing.s8, bottom: ZplaySpacing.s2),
                  child: Text(
                    subtitleText,
                    style: ZplayType.bodySmall.toStyle(
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
              ] else ...[
                // Desktop Header Row: Everything inline
                Row(
                  children: [
                    dragHandle(),
                    priorityBadge(),
                    addonIcon(),
                    const SizedBox(width: ZplaySpacing.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  m.name,
                                  style: ZplayType.subtitle.toStyle(
                                    color: tokens.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isBuiltIn) ...[
                                const SizedBox(width: 6),
                                builtInTag(),
                              ],
                            ],
                          ),
                          const SizedBox(height: ZplaySpacing.s2),
                          Text(
                            subtitleText,
                            style: ZplayType.bodySmall.toStyle(
                              color: tokens.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    upDownButtons(),
                    const SizedBox(width: ZplaySpacing.s4),
                    switchWidget(),
                  ],
                ),
              ],

              // Description
              if (m.description != null && m.description!.isNotEmpty) ...[
                const SizedBox(height: ZplaySpacing.s8),
                Text(
                  m.description!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: ZplayType.bodySmall.toStyle(
                    color: tokens.textSecondary,
                  ),

                ),
              ],

              // Feature Toggles Section
              if (addon.enabled && hasAnyFeature) ...[
                const SizedBox(height: ZplaySpacing.s12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12, vertical: 10),
                  decoration: BoxDecoration(
                    color: tokens.bg.withValues(alpha: ZplayOpacity.textDisabled),
                    borderRadius: ZplayRadius.smAll,
                    border: Border.all(
                      color: tokens.borderSubtle,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 13,
                            color: tokens.textSecondary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'FUNCTIONS',
                            style: ZplayType.overline.toStyle(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: ZplaySpacing.s8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (hasCatalogs)
                            _FeatureToggleChip(
                              icon: Icons.grid_view_rounded,
                              label: 'Catalogs',
                              count: m.catalogs.isNotEmpty ? m.catalogs.length : null,
                              isEnabled: addon.enableCatalogs,
                              onTap: () => onUpdateFeature(
                                enableCatalogs: !addon.enableCatalogs,
                              ),
                            ),
                          if (hasSearch)
                            _FeatureToggleChip(
                              icon: Icons.search_rounded,
                              label: 'Search',
                              isEnabled: addon.enableSearch,
                              onTap: () => onUpdateFeature(
                                enableSearch: !addon.enableSearch,
                              ),
                            ),
                          if (hasStreams)
                            _FeatureToggleChip(
                              icon: Icons.play_circle_outline_rounded,
                              label: 'Sources',
                              isEnabled: addon.enableStreams,
                              onTap: () => onUpdateFeature(
                                enableStreams: !addon.enableStreams,
                              ),
                            ),
                          if (hasSubtitles)
                            _FeatureToggleChip(
                              icon: Icons.subtitles_rounded,
                              label: 'Subtitles',
                              isEnabled: addon.enableSubtitles,
                              onTap: () => onUpdateFeature(
                                enableSubtitles: !addon.enableSubtitles,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              // Adult rating (gates this addon behind the global Adult Content switch)
              if (!isBuiltIn) ...[
                const SizedBox(height: ZplaySpacing.s12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final rating in AddonAdultRating.values)
                      _ratingChip(tokens, rating),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  m.isAdult
                      ? 'This addon declares itself 18+ in its manifest, so it is '
                            'treated as 18+ only whatever is selected above'
                      : switch (addon.adultRating) {
                          AddonAdultRating.sfw => 'No adult content from this addon',
                          AddonAdultRating.hybrid =>
                            'Shows with Adult Content off; its catalogs appear under 18+ in Discover',
                          AddonAdultRating.nsfw =>
                            'Hidden unless Adult Content is on',
                        },
                  style: ZplayType.caption.toStyle(color: tokens.textMuted),
                ),
              ],

              const SizedBox(height: ZplaySpacing.s12),

              // Bottom Row: Type badges + (on mobile: Quick Move) + Remove
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: m.types.map(
                        (type) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZplaySpacing.s8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.borderSubtle,
                            borderRadius: ZplayRadius.xsAll,
                          ),
                          child: Text(
                            type,
                            style: ZplayType.caption.toStyle(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ),
                      ).toList(),
                    ),
                  ),
                  if (isMobile) ...[
                    const SizedBox(width: ZplaySpacing.s8),
                    upDownButtons(),
                  ],
                  if (!isBuiltIn) ...[
                    const SizedBox(width: 6),
                    removeButton(),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// One selectable adult rating. The selected state is the enabled one; tapping
  /// it again is a no-op, so the rating can never end up unset.
  Widget _ratingChip(ZplayTokens tokens, AddonAdultRating rating) {
    final selected = addon.adultRating == rating;
    final (label, icon, color) = switch (rating) {
      AddonAdultRating.sfw => (
        'SFW only',
        Icons.shield_outlined,
        tokens.success,
      ),
      AddonAdultRating.hybrid => (
        'Hybrid',
        Icons.balance_rounded,
        tokens.warning,
      ),
      AddonAdultRating.nsfw => (
        '18+ only',
        Icons.eighteen_up_rating_rounded,
        tokens.danger,
      ),
    };

    return _FeatureToggleChip(
      icon: icon,
      label: label,
      isEnabled: selected,
      showStateIcon: selected,
      activeColor: color,
      onTap: () {
        if (selected) return;
        onRatingChanged(rating);
      },
    );
  }
}

class _FeatureToggleChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final bool isEnabled;
  final Color? activeColor;
  final bool showStateIcon;
  final VoidCallback onTap;

  const _FeatureToggleChip({
    required this.icon,
    required this.label,
    this.count,
    required this.isEnabled,
    this.activeColor,
    this.showStateIcon = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // A default parameter value has to be a compile-time constant, so the
    // palette accent cannot be one; it is resolved here instead.
    final accent = activeColor ?? tokens.accent;

    return FocusableCard(
      onTap: onTap,
      builder: (_, state) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isEnabled
                ? (state.highlighted
                    ? accent.withValues(alpha: ZplayOpacity.textDisabled)
                    : accent.withValues(alpha: ZplayOpacity.overlayHover))
                : (state.highlighted
                    ? tokens.borderDefault
                    : tokens.borderSubtle),
            borderRadius: ZplayRadius.smAll,
            border: Border.all(
              color: isEnabled
                  ? accent.withValues(alpha: ZplayOpacity.textSecondary)
                  : tokens.borderDefault,
              width: 1,
            ),
            boxShadow: isEnabled && state.highlighted
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: ZplayOpacity.textDisabled),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isEnabled ? accent : tokens.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                count != null
                    ? '$label ($count)'
                    : label,
                style: ZplayType.bodySmall.toStyle(
                  color: isEnabled ? tokens.textPrimary : tokens.textSecondary,
                ),
              ),
              if (showStateIcon) ...[
                const SizedBox(width: 6),
                Icon(
                  isEnabled
                      ? Icons.check_circle_rounded
                      : Icons.cancel_outlined,
                  size: 13,
                  color: isEnabled ? tokens.success : tokens.textDisabled,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Addon Button
// ─────────────────────────────────────────────────────────────────────────────

class _AddAddonButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _AddAddonButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return FocusableCard(
      onTap: onTap,
      enabled: !isLoading,
      builder: (_, state) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s20),
        decoration: BoxDecoration(
          borderRadius: ZplayRadius.mdAll,
          border: Border.all(
            color: tokens.accent.withValues(alpha: ZplayOpacity.textDisabled),
          ),
          color: tokens.accent.withValues(alpha: ZplayOpacity.borderFaint),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.accent,
                ),
              )
            else
              Icon(Icons.add_rounded, color: tokens.accent, size: 22),
            const SizedBox(width: 10),
            Text(
              isLoading ? 'Installing...' : 'Add Addon',
              style: ZplayType.subtitle.toStyle(color: tokens.accent),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Debrid Addon Card
// ─────────────────────────────────────────────────────────────────────────────

class _DebridAddonCard extends StatelessWidget {
  final DebridAddonTemplate template;
  final String selectedService;
  final bool isServiceReady;
  final bool isConnected;
  final bool isBusy;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;

  const _DebridAddonCard({
    required this.template,
    required this.selectedService,
    required this.isServiceReady,
    required this.isConnected,
    required this.isBusy,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    Widget connectButton() => FocusableCard(
          onTap: onConnect,
          enabled: isServiceReady && !isBusy,
          builder: (_, state) => AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: !isServiceReady
                  ? tokens.borderSubtle
                  : (state.highlighted
                      ? tokens.accent.withValues(alpha: ZplayOpacity.overlayHover)
                      : tokens.accent.withValues(alpha: ZplayOpacity.borderFaint)),
              borderRadius: ZplayRadius.smAll,
              border: Border.all(
                color: isServiceReady
                    ? tokens.accent.withValues(alpha: ZplayOpacity.textDisabled)
                    : tokens.borderDefault,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isBusy)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.accent,
                    ),
                  )
                else
                  Icon(
                    Icons.link_rounded,
                    size: 15,
                    color: isServiceReady ? tokens.accent : tokens.textDisabled,
                  ),
                const SizedBox(width: 6),
                Text(
                  isBusy ? 'Connecting...' : 'Connect',
                  style: ZplayType.bodySmall.toStyle(
                    color: isServiceReady ? tokens.accent : tokens.textDisabled,
                  ),
                ),
              ],
            ),
          ),
        );

    Widget disconnectButton() => FocusableCard(
          onTap: onDisconnect,
          enabled: !isBusy,
          builder: (_, state) => AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: state.highlighted
                  ? tokens.danger.withValues(alpha: ZplayOpacity.overlayHover)
                  : tokens.surface,
              borderRadius: ZplayRadius.smAll,
              border: Border.all(
                color: tokens.danger.withValues(alpha: ZplayOpacity.textDisabled),
              ),
            ),
            child: Text(
              'Disconnect',
              style: ZplayType.bodySmall.toStyle(color: tokens.danger),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(
          color: isConnected
              ? tokens.accent.withValues(alpha: ZplayOpacity.textDisabled)
              : tokens.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: ZplayRadius.smAll,
                  color: tokens.accent.withValues(alpha: ZplayOpacity.overlayHover),
                ),
                child: Icon(
                  Icons.hub_rounded,
                  color: tokens.accent,
                  size: 19,
                ),
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
                            template.name,
                            style: ZplayType.subtitle.toStyle(
                              color: tokens.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isConnected) ...[
                          const SizedBox(width: ZplaySpacing.s8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.accentSubtle,
                              borderRadius: ZplayRadius.xsAll,
                            ),
                            child: Text(
                              'Connected',
                              style: ZplayType.caption.toStyle(color: tokens.accent),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      template.description,
                      style: ZplayType.bodySmall.toStyle(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ZplaySpacing.s12),
          Row(
            children: [
              Expanded(
                child: Text(
                  isServiceReady
                      ? 'Uses your $selectedService key'
                      : 'No Debrid provider is set up yet',
                  style: ZplayType.caption.toStyle(
                    color: isServiceReady ? tokens.textMuted : tokens.textDisabled,
                  ),
                ),
              ),
              const SizedBox(width: ZplaySpacing.s8),
              if (isConnected) disconnectButton() else connectButton(),
            ],
          ),
          if (!isServiceReady) ...[
            const SizedBox(height: ZplaySpacing.s4),
            Text(
              'Set up a Debrid provider in Settings first, then come back to connect it.',
              style: ZplayType.caption.toStyle(color: tokens.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Segmented Tab Button
// ─────────────────────────────────────────────────────────────────────────────

class _TabButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabButton({
    required this.title,
    required this.icon,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return FocusableCard(
      onTap: onTap,
      builder: (_, state) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s12),
        decoration: BoxDecoration(
          color: isSelected ? tokens.accentSubtle : Colors.transparent,
          borderRadius: ZplayRadius.smAll,
          border: Border.all(
            color: isSelected
                ? tokens.accent.withValues(alpha: ZplayOpacity.textMuted)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? tokens.accent : tokens.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                style: ZplayType.label.toStyle(
                  color: isSelected ? tokens.textPrimary : tokens.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? tokens.accent : tokens.borderDefault,
                borderRadius: ZplayRadius.smAll,
              ),
              child: Text(
                '$count',
                style: ZplayType.caption.toStyle(
                  color: isSelected ? tokens.onAccent : tokens.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CloudStream Extension Card
// ─────────────────────────────────────────────────────────────────────────────

class _CloudStreamCard extends StatelessWidget {
  final CloudStreamSource source;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;
  final bool isSelected;
  final VoidCallback onSelectToggle;

  const _CloudStreamCard({
    required this.source,
    required this.onToggle,
    required this.onRemove,
    required this.isSelected,
    required this.onSelectToggle,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasIcon = source.iconUrl != null && source.iconUrl!.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: isSelected
            ? tokens.accent.withValues(alpha: ZplayOpacity.borderDefault)
            : tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(
          color: isSelected
              ? tokens.accent.withValues(alpha: ZplayOpacity.textSecondary)
              : (source.enabled
                  ? tokens.accent.withValues(alpha: ZplayOpacity.textDisabled)
                  : tokens.borderSubtle),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          // Checkmark Selection Button
          FocusableCard(
            onTap: onSelectToggle,
            builder: (_, state) => Padding(
              padding: const EdgeInsets.only(right: ZplaySpacing.s12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? tokens.accent : tokens.borderSubtle,
                  borderRadius: ZplayRadius.xsAll,
                  border: Border.all(
                    color: isSelected
                        ? tokens.accent
                        : tokens.textDisabled,
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? Icon(
                        Icons.check_rounded,
                        size: 17,
                        color: tokens.onAccent,
                      )
                    : null,
              ),
            ),
          ),

          // Icon
          ClipRRect(
            borderRadius: ZplayRadius.smAll,
            child: Container(
              width: 42,
              height: 42,
              color: tokens.accent.withValues(alpha: ZplayOpacity.borderStrong),
              child: hasIcon
                  ? CachedNetworkImage(
                      imageUrl: source.iconUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Icon(
                        Icons.cloud_rounded,
                        color: tokens.accent,
                        size: 22,
                      ),
                    )
                  : Icon(
                      Icons.cloud_rounded,
                      color: tokens.accent,
                      size: 22,
                    ),
            ),
          ),
          const SizedBox(width: 14),

          // Details (Tap details area also toggles selection!)
          Expanded(
            child: FocusableCard(
              onTap: onSelectToggle,
              builder: (_, state) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          source.name,
                          style: ZplayType.subtitle.toStyle(
                            color: isSelected ? tokens.accent : tokens.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (source.lang != null && source.lang!.isNotEmpty) ...[
                        const SizedBox(width: ZplaySpacing.s8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: tokens.borderDefault,
                            borderRadius: ZplayRadius.xsAll,
                          ),
                          child: Text(
                            source.lang!.toUpperCase(),
                            style: ZplayType.overline.toStyle(
                              color: tokens.textEmphasis,
                            ),
                          ),
                        ),
                      ],
                      if (source.version != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          'v${source.version}',
                          style: ZplayType.caption.toStyle(
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    source.description ?? 'CloudStream scraping & streaming provider',
                    style: ZplayType.bodySmall.toStyle(
                      color: tokens.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: ZplaySpacing.s8),

          // Switch
          Switch(
            value: source.enabled,
            activeColor: tokens.accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: onToggle,
          ),

          // Delete
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            color: tokens.textMuted,
            splashRadius: 18,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

