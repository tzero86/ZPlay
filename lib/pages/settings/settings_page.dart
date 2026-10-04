import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../services/addon/addon_manager.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/common/focusable_card.dart';
import '../../services/debrid/debrid_service.dart';
import '../../services/theme/glass_settings.dart';
import '../../services/trakt/trakt_service.dart';
import '../../services/simkl/simkl_service.dart';
import '../../services/metadata/tmdb_service.dart';
import '../../services/metadata/metadata_service.dart';
import '../../services/hero/hero_media_resolver.dart';
import '../../services/storage/app_image_cache.dart';
import '../../services/config/service_credentials.dart';

import 'appearance_settings_page.dart';
import 'video_settings_page.dart';
import 'debrid_settings_page.dart';
import 'addons_settings_page.dart';
import 'builtin_providers_settings_page.dart';
import 'trakt_settings_page.dart';
import 'simkl_settings_page.dart';
import 'tmdb_settings_page.dart';
import 'service_keys_settings_page.dart';
import 'updates_settings_page.dart';
import 'about_settings_page.dart';
import '../../services/player/player_settings.dart';
import '../../services/p2p/p2p_settings_service.dart';
import '../../services/scraper/builtin_providers_settings_service.dart';
import '../../widgets/p2p/p2p_warning_dialog.dart';
import '../../services/discord/discord_rpc_service.dart';
import '../../services/backup/backup_restore_service.dart';
import '../../services/home/home_page_settings.dart';
import '../../services/content/content_settings.dart';

import '../../widgets/common/animated_ambient_background.dart';

/// Third-party brand hues. These identify an external service, so they stay
/// outside the palette-derived token layer.
const Color _traktBrand = Color(0xFFED1C24);
const Color _simklBrand = Color(0xFF00ADFF);
const Color _discordBrand = Color(0xFF5865F2);

/// Import the profile pushed to the device, without navigating to it.
///
/// A compile-time constant, so a normal build carries the string and never the
/// value. It exists because reaching this dialog on a television is a dozen
/// D-pad presses, and a test that has to drive the remote cannot confirm which
/// row it pressed - only the screen it ended up on, which was the same problem
/// nine separate defects were diagnosed through.
const bool autoImportFromFile = bool.fromEnvironment('ZPLAY_AUTO_IMPORT');

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// One subscription for the hub row's set count; the notifiers are static
  /// finals, so the merge is built once instead of on every rebuild.
  static final Listenable _serviceCredentials = Listenable.merge([
    for (final credential in ServiceCredential.values)
      ServiceCredentials.notifier(credential),
  ]);

  final _debrid = DebridService();
  bool _useDebrid = false;
  String _debridProvider = 'None';
  String? _appVersion;
  bool _traktConnected = false;
  bool _simklConnected = false;

  void _showBackupRestoreDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final tokens = ctx.tokens;
        return Dialog(
          backgroundColor: tokens.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: ZplayRadius.lgAll,
            side: tokens.hairlineStrong,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(ZplaySpacing.s24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: tokens.success.withValues(
                            alpha: ZplayOpacity.overlayHover,
                          ),
                          borderRadius: ZplayRadius.smAll,
                        ),
                        child: Icon(
                          Icons.backup_rounded,
                          color: tokens.success,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Backup & Restore',
                              style: ZplayType.title.toStyle(
                                color: tokens.textPrimary,
                              ),
                            ),
                            Text(
                              'Cross-device JSON configuration',
                              style: ZplayType.bodySmall.toStyle(
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: tokens.textSecondary,
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        style: _iconButtonFocusStyle(tokens),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Export your configuration (addons, IPTV portals, Debrid keys & themes) to JSON or import on another device.',
                    style: ZplayType.body.toStyle(color: tokens.textEmphasis),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: tokens.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: const RoundedRectangleBorder(
                              borderRadius: ZplayRadius.smAll,
                            ),
                          ),
                          icon: const Icon(
                            Icons.file_upload_outlined,
                            size: 18,
                          ),
                          label: Text(
                            'Export JSON',
                            style: ZplayType.label.toStyle(),
                          ),
                          onPressed: () async {
                            final jsonStr =
                                await BackupRestoreService.exportSettingsJson();
                            await Clipboard.setData(
                              ClipboardData(text: jsonStr),
                            );
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Configuration JSON copied to clipboard! Save or paste it on any device.',
                                  ),
                                  backgroundColor: tokens.success,
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: tokens.textPrimary,
                            side: BorderSide(color: tokens.borderStrong),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: const RoundedRectangleBorder(
                              borderRadius: ZplayRadius.smAll,
                            ),
                          ),
                          icon: const Icon(
                            Icons.file_download_outlined,
                            size: 18,
                          ),
                          label: Text(
                            'Import JSON',
                            style: ZplayType.label.toStyle(),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showImportJsonInputDialog();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showImportJsonInputDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        final tokens = ctx.tokens;
        return Dialog(
          backgroundColor: tokens.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: ZplayRadius.lgAll,
            side: tokens.hairlineStrong,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(ZplaySpacing.s24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.file_download_outlined,
                        color: tokens.accent,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Paste Configuration JSON',
                        style: ZplayType.title.toStyle(
                          color: tokens.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: tokens.textSecondary,
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        style: _iconButtonFocusStyle(tokens),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    maxLines: 8,
                    style: ZplayType.bodySmall
                        .toStyle(color: tokens.textPrimary)
                        .copyWith(fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: 'Paste backup JSON here...',
                      hintStyle: ZplayType.bodySmall.toStyle(
                        color: tokens.textDisabled,
                      ),
                      filled: true,
                      fillColor: tokens.surface,
                      border: OutlineInputBorder(
                        borderRadius: ZplayRadius.smAll,
                        borderSide: BorderSide(color: tokens.borderDefault),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      TextButton.icon(
                        icon: Icon(
                          Icons.paste_rounded,
                          size: 16,
                          color: tokens.accent,
                        ),
                        label: Text(
                          'Paste from Clipboard',
                          style: ZplayType.label.toStyle(color: tokens.accent),
                        ),
                        onPressed: () async {
                          final data = await Clipboard.getData(
                            Clipboard.kTextPlain,
                          );
                          if (data?.text != null) {
                            textController.text = data!.text!;
                          }
                        },
                      ),
                      const Spacer(),
                      // A whole profile is ~200 KB of JSON. Typing that into a
                      // text field with a remote is not a task anyone should
                      // attempt, so a file already on the device is a first
                      // class way in rather than something a user has to work
                      // around.
                      TextButton.icon(
                        icon: Icon(
                          Icons.folder_open_rounded,
                          size: 16,
                          color: tokens.accent,
                        ),
                        label: Text(
                          'From File',
                          style: ZplayType.label.toStyle(color: tokens.accent),
                        ),
                        onPressed: _importFromFile,
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tokens.accent,
                          foregroundColor: tokens.onAccent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          shape: const RoundedRectangleBorder(
                            borderRadius: ZplayRadius.smAll,
                          ),
                        ),
                        child: Text(
                          'Restore Now',
                          style: ZplayType.label.toStyle(),
                        ),
                        onPressed: () async {
                          final txt = textController.text.trim();
                          if (txt.isEmpty) return;
                          try {
                            final msg =
                                await BackupRestoreService.importSettingsJson(
                                  txt,
                                );
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            if (mounted) {
                              _loadOverviewState();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(msg),
                                  backgroundColor: tokens.success,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          } catch (e) {
                            if (!ctx.mounted) return;
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text('Import Failed: $e'),
                                backgroundColor: tokens.danger,
                              ),
                            );
                          }
                        },
                      ),
                    ],
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
  void initState() {
    super.initState();
    BuiltinProvidersSettingsService.instance.init();
    _loadOverviewState();
    if (autoImportFromFile) {
      // After the first frame, so the dialog has a size to be laid out against
      // and the page behind it is already on screen. This is the scripted
      // route, so it searches the readable locations rather than putting a
      // file picker in front of a build that is meant to run unattended.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _importFromSearchPaths();
      });
    }
  }

  Future<void> _loadOverviewState() async {
    final useDebrid = await _debrid.getUseDebridForStreams();
    final provider = await _debrid.getSelectedService();
    final traktAuth = await TraktService.instance.isAuthenticated();
    final simklAuth = await SimklService.instance.isAuthenticated();
    final pkg = await PackageInfo.fromPlatform().catchError(
      (_) => PackageInfo(
        appName: 'ZPlay',
        packageName: 'io.github.tzero86.zplay',
        version: '1.1.6',
        buildNumber: '2019',
      ),
    );

    if (mounted) {
      setState(() {
        _useDebrid = useDebrid;
        _debridProvider = provider;
        _appVersion = pkg.version;
        _traktConnected = traktAuth;
        _simklConnected = simklAuth;
      });
    }
  }

  /// Imports a profile from a file already on the device.
  ///
  /// "From File" opens the system picker, so the person chooses the file and
  /// the picker grants the app access to it. Under Android 14 scoped storage
  /// that grant is the only way to read a file in Downloads, which is why the
  /// button cannot just open a fixed path: the path is what was denied.
  /// [autoImportFromFile] takes the other route below, which searches the
  /// locations the app can read without anyone choosing anything.
  Future<void> _importFromFile() async {
    FilePickerResult? picked;
    try {
      // `withData` asks Android for the bytes of the document the picker
      // granted. The SAF URI behind it is not a path this process may open.
      picked = await FilePicker.platform.pickFiles(
        // Not restricted to `.json`: a provider that reports a profile as
        // `text/plain` would otherwise hide it from the picker.
        type: FileType.any,
        withData: true,
        dialogTitle: 'Choose a ZPlay profile',
      );
    } catch (_) {
      // A television with no document picker installed. Fall back to the
      // locations the app can read on its own rather than a dead button.
      await _importFromSearchPaths();
      return;
    }
    if (picked == null || picked.files.isEmpty) return; // cancelled
    final file = picked.files.first;
    await _reportImport(
      () => BackupRestoreService.importPickedProfile(
        bytes: file.bytes,
        path: file.path,
        name: file.name,
      ),
    );
  }

  /// Imports the profile pushed to one of the locations the app can read.
  ///
  /// This is what [autoImportFromFile] drives, so a build without a remote in
  /// front of it exercises exactly the import a person gets.
  Future<void> _importFromSearchPaths() => _reportImport(
        () async => BackupRestoreService.importSettingsFromFile(
          await BackupRestoreService.importSearchPaths(),
        ),
      );

  /// Runs an import and reports the outcome, shared by both ways in.
  Future<void> _reportImport(Future<String> Function() import) async {
    final tokens = context.tokens;
    final navigator = Navigator.of(context);
    // "Restore Now" and "From File" run from the import dialog and need it
    // closed afterwards, but the startup import ([autoImportFromFile]) runs
    // from this page's own post-frame callback with nothing on top of it -
    // and this page is a slot in the shell's [IndexedStack], not a pushed
    // route, so the shell is the only route in the navigator. Popping there
    // took the shell off the stack: the app stayed alive with nothing left to
    // paint, a uniform black screen with no way back, which is what a readable
    // profile at startup used to do. Close what is open, never the app.
    final hasDialogToClose = navigator.canPop();
    try {
      final msg = await import();
      if (!mounted) return;
      if (hasDialogToClose) navigator.pop();
      _loadOverviewState();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: tokens.success,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      // The service names the locations it tried and says the app can only
      // read its own directory, which is more use than the exception's type.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is FileSystemException && e.message.isNotEmpty
                ? e.message
                : 'Import failed: $e',
            style: ZplayType.bodySmall.toStyle(color: tokens.textPrimary),
          ),
          backgroundColor: tokens.danger,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  /// The "Clear cache" control: empties every cache the app holds in memory or
  /// on disk - the artwork store, the metadata lookups and the hero media
  /// table - and touches nothing else. Profile, addons, My List, watch history
  /// and the P2P preference all survive, which is the whole point: the
  /// grievance this answers is a stale artwork response sticking with no way
  /// out short of a reinstall, and a reinstall wipes exactly the state this
  /// deliberately leaves alone.
  ///
  /// Each step runs in its own guard. A step that fails is named in the report
  /// instead of being swallowed, and the steps after it still run - one broken
  /// store must not spare the caches behind it.
  Future<void> _confirmAndClearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final tokens = ctx.tokens;
        return AlertDialog(
          backgroundColor: tokens.surfaceOverlay,
          shape: const RoundedRectangleBorder(
            borderRadius: ZplayRadius.lgAll,
          ),
          title: Text(
            'Clear cache?',
            style: ZplayType.title.toStyle(color: tokens.textPrimary),
          ),
          content: Text(
            'Removes cached artwork and metadata so fresh copies are fetched. '
            'This does not sign you out or remove addons - your profile, My '
            'List, watch history and settings stay exactly as they are.',
            style: ZplayType.body.toStyle(color: tokens.textEmphasis),
          ),
          actions: [
            TextButton(
              child: Text(
                'Cancel',
                style: ZplayType.label.toStyle(color: tokens.textSecondary),
              ),
              onPressed: () => Navigator.pop(ctx, false),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.onAccent,
              ),
              child: const Text('Clear'),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final tokens = context.tokens;
    final messenger = ScaffoldMessenger.of(context);

    // One label per step, so the report names the store that failed instead of
    // a generic "something went wrong".
    final failures = <String>[];
    try {
      await AppImageCache.emptyCache();
    } catch (e) {
      failures.add('artwork cache (${e.toString().replaceFirst('Exception: ', '')})');
    }
    try {
      MetadataService.clearCache();
    } catch (e) {
      failures.add('metadata cache (${e.toString().replaceFirst('Exception: ', '')})');
    }
    try {
      HeroMediaResolver.clearCache();
    } catch (e) {
      failures.add('hero artwork cache (${e.toString().replaceFirst('Exception: ', '')})');
    }

    final cleared = failures.isEmpty
        ? 'Cache cleared.'
        : 'Cache cleared except the ${failures.join(' and the ')}.';
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '$cleared You are still signed in - addons, My List, watch history '
          'and settings are untouched.',
        ),
        backgroundColor: failures.isEmpty ? tokens.success : tokens.danger,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _navigateTo(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
    // Refresh badges when returning
    _loadOverviewState();
  }

  /// The hub's sections, in order. The split pane's sidebar lists these, and
  /// [_buildSection] anchors each one with the matching key.
  static const List<String> _sectionLabels = [
    'PLAYBACK',
    'SOURCES',
    'INTEGRATIONS',
    'APPEARANCE',
    'CONTENT',
    'APP',
  ];

  /// One anchor per section, created once so a sidebar tap can scroll the
  /// content pane to its group.
  final Map<String, GlobalKey> _sectionKeys = {
    for (final label in _sectionLabels) label: GlobalKey(),
  };

  String _activeSection = _sectionLabels.first;

  /// Scrolls the content pane to [label]'s group and marks it current.
  ///
  /// The prototype's sidebar swaps the pane; here every section is one
  /// continuously scrolling hub - the structure the page already had - so the
  /// sidebar indexes it instead of replacing it. That keeps every row mounted
  /// (and so every `_navigateTo` destination where it was) while still giving a
  /// television a single press to reach a group instead of a dozen.
  void _jumpToSection(String label) {
    if (label == _activeSection) {
      _scrollToSection(label);
      return;
    }
    setState(() => _activeSection = label);
    _scrollToSection(label);
  }

  void _scrollToSection(String label) {
    final sectionContext = _sectionKeys[label]?.currentContext;
    if (sectionContext == null) return;
    Scrollable.ensureVisible(
      sectionContext,
      duration: ZplayMotion.base,
      curve: ZplayMotion.standard,
      alignment: 0,
    );
  }

  /// One labelled section: a group of rows inside a single bordered surface,
  /// split by hairline dividers instead of one card per row.
  Widget _buildSection(
    BuildContext context,
    String label, {
    required List<Widget> rows,
    bool first = false,
  }) {
    final tokens = context.tokens;
    return Column(
      key: _sectionKeys[label],
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!first) const SizedBox(height: ZplaySpacing.s24),
        Text(label, style: ZplayType.overline.toStyle(color: tokens.textMuted)),
        const SizedBox(height: ZplaySpacing.s12),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: ZplayRadius.mdAll,
            border: Border.all(color: tokens.borderDefault),
          ),
          child: Column(children: _dividerSeparated(rows, tokens.borderSubtle)),
        ),
      ],
    );
  }

  /// Returns [rows] with a hairline divider between each pair, for the inside of
  /// a grouped surface.
  static List<Widget> _dividerSeparated(List<Widget> rows, Color dividerColor) {
    final children = <Widget>[];
    for (final row in rows) {
      if (children.isNotEmpty) {
        children.add(Divider(color: dividerColor, height: 1));
      }
      children.add(row);
    }
    return children;
  }

  /// The page header, carrying the page's icon-button focus state.
  ///
  /// The header's leading control is the framework's own - a `BackButton`, or a
  /// `CloseButton` on a fullscreen-dialog route - so there is no `leading` here
  /// to style, and `AppBar` has no style parameter for it. `IconButtonTheme`
  /// above the bar reaches whatever the framework puts there.
  ///
  /// `PreferredSize` because the scaffold's `appBar` slot takes a
  /// `PreferredSizeWidget` and `IconButtonTheme` is not one; it only restates
  /// the height `AppBar` reports itself.
  PreferredSizeWidget _appBar(ZplayTokens tokens) {
    final bar = AppBar(
      backgroundColor: tokens.bg,
      surfaceTintColor: Colors.transparent,
      // The shell family draws this header as an opaque palette band with a
      // bottom hairline rather than a translucent wash over the page.
      shape: Border(bottom: tokens.hairline),
      // No explicit leading: the framework already gates the back button on canPop,
      // so it vanishes in the shell and returns if this page is pushed.
      title: Text(
        'Settings',
        style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
      ),
    );

    return PreferredSize(
      preferredSize: bar.preferredSize,
      child: IconButtonTheme(
        data: IconButtonThemeData(style: _iconButtonFocusStyle(tokens)),
        child: bar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final addonCount = AddonManager.instance.addons.length;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _appBar(tokens),
      body: AnimatedAmbientBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 240 dp of sidebar beside a readable pane is what the prototype's
            // split pane needs. Below that the two do not both fit, so the hub
            // stacks as the single column it was.
            final split = constraints.maxWidth >= 720;
            final content = Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                // `SingleChildScrollView` + `Column`, not a `ListView`.
                //
                // A `ListView` builds only what is near the viewport, so on a
                // 540 dp television the sections below the fold have no element
                // and no `currentContext` - and the sidebar's `ensureVisible`
                // would silently do nothing for every section but the first few.
                // A settings hub is a dozen rows, so building them all costs
                // nothing and makes every anchor real.
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    split ? ZplaySpacing.s24 : ZplaySpacing.s16,
                    ZplaySpacing.s20,
                    split ? ZplaySpacing.s24 : ZplaySpacing.s16,
                    ZplaySpacing.s32 + bottomInset,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSection(
                        context,
                        'PLAYBACK',
                        first: true,
                        rows: [
                          // Video & Anime4K Upscaling
                          ValueListenableBuilder<Anime4KPreset>(
                            valueListenable: PlayerSettings.anime4kPreset,
                            builder: (context, anime4kPreset, _) {
                              return _SettingsNavRow(
                                icon: Icons.auto_awesome_rounded,
                                iconColor: tokens.accent,
                                title: 'Video & Upscaling',
                                subtitle:
                                    'Anime4K neural GLSL shader presets and GPU pipeline',
                                valueText: anime4kPreset == Anime4KPreset.off
                                    ? 'Off'
                                    : anime4kPreset.label.split('(').first.trim(),
                                onTap: () => _navigateTo(const VideoSettingsPage()),
                              );
                            },
                          ),
                          // Built-in P2P Torrent Source Toggle (ZPlay)
                          ValueListenableBuilder<bool>(
                            valueListenable: P2pSettingsService.isP2pEnabled,
                            builder: (context, isP2p, _) {
                              return _SettingsSwitchRow(
                                icon: Icons.hub_rounded,
                                iconColor: isP2p
                                    ? tokens.warning
                                    : tokens.textSecondary,
                                title: 'Built-in P2P Torrent Source',
                                subtitle: isP2p
                                    ? 'ZPlay torrent swarms (Knaben, TorrentGalaxy) active'
                                    : 'P2P disabled. Using only direct HTTP streaming (ZPlayHTTP)',
                                valueText: isP2p ? 'P2P Active' : 'HTTP Only',
                                value: isP2p,
                                onChanged: (val) async {
                                  await P2pSettingsService.setP2pEnabled(val);
                                },
                                onInfoTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => const P2pWarningDialog(),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),

                      _buildSection(
                        context,
                        'SOURCES',
                        rows: [
                          // Metadata & Catalogs (Addons)
                          _SettingsNavRow(
                            icon: Icons.extension_rounded,
                            iconColor: tokens.accent,
                            title: 'Addons',
                            subtitle: 'Stremio catalogs and content providers',
                            valueText: '$addonCount Installed',
                            onTap: () => _navigateTo(const AddonsSettingsPage()),
                          ),
                          // Built-in Providers (ZPlayHTTP)
                          ListenableBuilder(
                            listenable: BuiltinProvidersSettingsService.instance,
                            builder: (context, _) {
                              final isCustom =
                                  BuiltinProvidersSettingsService.instance.isCustom;
                              return _SettingsNavRow(
                                icon: Icons.dns_rounded,
                                iconColor: isCustom ? tokens.accent : tokens.success,
                                title: 'Built-in Providers',
                                subtitle:
                                    'ZPlayHTTP streaming sources, priority order & toggles',
                                valueText: isCustom ? 'Custom' : 'Default',
                                onTap: () =>
                                    _navigateTo(const BuiltinProvidersSettingsPage()),
                              );
                            },
                          ),
                          // Debrid & Cloud Streaming
                          _SettingsNavRow(
                            icon: Icons.cloud_download_rounded,
                            iconColor: tokens.accent,
                            title: 'Debrid & Cloud Streaming',
                            subtitle:
                                'Real-Debrid, TorBox, AllDebrid, Premiumize & Debrid-Link',
                            valueText: _useDebrid
                                ? (_debridProvider != 'None'
                                      ? _debridProvider
                                      : 'Active')
                                : 'Disabled',
                            onTap: () => _navigateTo(const DebridSettingsPage()),
                          ),
                        ],
                      ),

                      _buildSection(
                        context,
                        'INTEGRATIONS',
                        rows: [
                          // Trakt Sync
                          _SettingsNavRow(
                            icon: Icons.movie_filter_rounded,
                            iconColor: _traktBrand,
                            title: 'Trakt.tv Sync',
                            subtitle:
                                'Cross-device watchlist, history & playback synchronization',
                            valueText: _traktConnected ? 'Connected' : 'Offline',
                            onTap: () => _navigateTo(const TraktSettingsPage()),
                          ),
                          // Simkl Sync
                          _SettingsNavRow(
                            icon: Icons.tv_rounded,
                            iconColor: _simklBrand,
                            title: 'Simkl Sync',
                            subtitle:
                                'Cross-device Movies, TV & Anime synchronization',
                            valueText: _simklConnected ? 'Connected' : 'Offline',
                            onTap: () => _navigateTo(const SimklSettingsPage()),
                          ),
                          // TMDb API Key (bring your own)
                          ListenableBuilder(
                            listenable: TmdbService.apiKey,
                            builder: (context, _) => _SettingsNavRow(
                              icon: Icons.theaters_rounded,
                              iconColor: tokens.accent,
                              title: 'TMDb API Key',
                              subtitle:
                                  'Your own key for the ranked 1990s rails and scraper metadata',
                              valueText: TmdbService.isConfigured
                                  ? 'Your key'
                                  : 'Not set',
                              onTap: () => _navigateTo(const TmdbSettingsPage()),
                            ),
                          ),
                          // Service API Keys (bring your own)
                          ListenableBuilder(
                            listenable: _serviceCredentials,
                            builder: (context, _) {
                              final provided = ServiceCredential.values
                                  .where(ServiceCredentials.isUserProvided)
                                  .length;
                              return _SettingsNavRow(
                                icon: Icons.key_rounded,
                                iconColor: tokens.accent,
                                title: 'Service API Keys',
                                subtitle:
                                    'Subtitles, audiobooks and scraper keys you supply yourself',
                                valueText:
                                    '$provided of ${ServiceCredential.values.length} set',
                                onTap: () =>
                                    _navigateTo(const ServiceKeysSettingsPage()),
                              );
                            },
                          ),
                          // Discord Rich Presence (Desktop Only)
                          if (Platform.isWindows ||
                              Platform.isLinux ||
                              Platform.isMacOS)
                            ValueListenableBuilder<bool>(
                              valueListenable: DiscordRpcService.instance.isEnabled,
                              builder: (context, isDiscordEnabled, _) {
                                return _SettingsSwitchRow(
                                  icon: Icons.sports_esports_rounded,
                                  iconColor: isDiscordEnabled
                                      ? _discordBrand
                                      : tokens.textSecondary,
                                  title: 'Discord Rich Presence',
                                  subtitle: isDiscordEnabled
                                      ? 'Broadcasting movies, shows, music & live activity to Discord'
                                      : 'Disabled. Activity is hidden from Discord',
                                  valueText: isDiscordEnabled ? 'Active' : 'Disabled',
                                  value: isDiscordEnabled,
                                  onChanged: (val) async {
                                    await DiscordRpcService.instance.setEnabled(val);
                                  },
                                );
                              },
                            ),
                        ],
                      ),

                      _buildSection(
                        context,
                        'APPEARANCE',
                        rows: [
                          // Appearance & Interface
                          ValueListenableBuilder<bool>(
                            valueListenable: GlassSettings.enabled,
                            builder: (context, glassEnabled, _) {
                              return ValueListenableBuilder<AppThemePalette>(
                                valueListenable: AppThemeService.currentPalette,
                                builder: (context, currentPalette, _) {
                                  return _SettingsNavRow(
                                    icon: Icons.palette_rounded,
                                    iconColor: tokens.accent,
                                    title: 'Appearance & Interface',
                                    subtitle:
                                        'Liquid Glass setup, color themes, and Home Page UI',
                                    valueText: glassEnabled
                                        ? '${currentPalette.name} · Glass ON'
                                        : currentPalette.name,
                                    onTap: () =>
                                        _navigateTo(const AppearanceSettingsPage()),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),

                      _buildSection(
                        context,
                        'CONTENT',
                        rows: [
                          // TV Airing Calendar Toggle
                          ValueListenableBuilder<bool>(
                            valueListenable: HomePageSettings.enableCalendar,
                            builder: (context, isCalEnabled, _) {
                              return _SettingsSwitchRow(
                                icon: Icons.calendar_month_rounded,
                                iconColor: isCalEnabled
                                    ? tokens.info
                                    : tokens.textSecondary,
                                title: 'TV Airing Calendar',
                                subtitle: isCalEnabled
                                    ? 'Calendar buttons active on Home top bar and section headers'
                                    : 'Calendar disabled and hidden across all pages',
                                valueText: isCalEnabled ? 'Enabled' : 'Disabled',
                                value: isCalEnabled,
                                onChanged: (val) async {
                                  await HomePageSettings.setEnableCalendar(val);
                                },
                              );
                            },
                          ),
                          // AI Recommendation Quiz Toggle
                          ValueListenableBuilder<bool>(
                            valueListenable: HomePageSettings.enableAiQuiz,
                            builder: (context, isAiEnabled, _) {
                              return _SettingsSwitchRow(
                                icon: Icons.auto_awesome_rounded,
                                iconColor: isAiEnabled
                                    ? tokens.accent
                                    : tokens.textSecondary,
                                title: 'AI Recommendation Quiz',
                                subtitle: isAiEnabled
                                    ? 'AI Taste Profile Quiz active on Home and Search bars'
                                    : 'AI quiz disabled and hidden across all pages',
                                valueText: isAiEnabled ? 'Enabled' : 'Disabled',
                                value: isAiEnabled,
                                onChanged: (val) async {
                                  await HomePageSettings.setEnableAiQuiz(val);
                                },
                              );
                            },
                          ),
                          // Adult Content (18+) Global Switch
                          ValueListenableBuilder<bool>(
                            valueListenable: ContentSettings.adultEnabled,
                            builder: (context, isAdultOn, _) {
                              return _SettingsSwitchRow(
                                icon: Icons.eighteen_up_rating_rounded,
                                iconColor: isAdultOn
                                    ? tokens.danger
                                    : tokens.textSecondary,
                                title: 'Adult Content',
                                subtitle: isAdultOn
                                    ? '18+ catalogs, search results and sources are enabled'
                                    : 'Hidden. No 18+ catalogs, search results or sources are fetched',
                                valueText: isAdultOn ? 'On' : 'Off',
                                value: isAdultOn,
                                onChanged: (val) async {
                                  await ContentSettings.setAdultEnabled(val);
                                },
                              );
                            },
                          ),
                        ],
                      ),

                      _buildSection(
                        context,
                        'APP',
                        rows: [
                          // Backup & Restore (JSON)
                          _SettingsNavRow(
                            icon: Icons.backup_rounded,
                            iconColor: tokens.accent,
                            title: 'Backup & Restore',
                            subtitle:
                                'Export or import your settings, addons & IPTV portals (JSON)',
                            valueText: 'JSON',
                            onTap: _showBackupRestoreDialog,
                          ),
                          // Cache cleanup (artwork + metadata, never user state)
                          _SettingsNavRow(
                            icon: Icons.cleaning_services_rounded,
                            iconColor: tokens.accent,
                            title: 'Clear cache',
                            subtitle:
                                'Drop cached artwork & metadata. Sign-in, addons, My List & history stay',
                            onTap: _confirmAndClearCache,
                          ),
                          // App Updates & System
                          _SettingsNavRow(
                            icon: Icons.system_update_rounded,
                            iconColor: tokens.accent,
                            title: 'App Updates',
                            subtitle:
                                'Check for latest software versions and patches',
                            valueText: _appVersion != null
                                ? 'v$_appVersion'
                                : 'Check',
                            onTap: () => _navigateTo(const UpdatesSettingsPage()),
                          ),
                          // About ZPlay
                          _SettingsNavRow(
                            icon: Icons.info_outline_rounded,
                            iconColor: tokens.accent,
                            title: 'About ZPlay',
                            subtitle: 'Architecture, video engine, and credits',
                            onTap: () => _navigateTo(const AboutSettingsPage()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );

            if (!split) return content;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsSidebar(
                  labels: _sectionLabels,
                  active: _activeSection,
                  onSelected: _jumpToSection,
                ),
                Expanded(child: content),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings Row
// ─────────────────────────────────────────────────────────────────────────────

/// A navigating settings row inside a grouped surface: bare 20 px leading icon,
/// title and subtitle, with the row's value right-aligned ahead of the chevron.
class _SettingsNavRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? valueText;
  final VoidCallback onTap;

  const _SettingsNavRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.valueText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // `FocusableCard`, not a bare `InkWell`.
    //
    // An `InkWell` is pointer-only: it is not a `Focus` widget, so no key, remote
    // or D-pad event can reach it and it draws no focus indicator. Every other
    // surface in the app was converted to `FocusableCard` for exactly this, and
    // Settings was missed - which is why a television could open the page and
    // then not be able to enter anything. The focus tree showed the nodes
    // existing 40-odd in the shell scope while nothing on the page was
    // reachable, because the rows that looked like controls were not focus
    // nodes at all.
    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: CardFocusRing(
            focused: state.focused,
            radius: ZplayRadius.smAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ZplaySpacing.s16,
                vertical: ZplaySpacing.s12,
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: iconColor),
                  const SizedBox(width: ZplaySpacing.s16),

                  // Title and Subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: ZplayType.subtitle.toStyle(
                            color: tokens.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: ZplaySpacing.s2),
                        Text(
                          subtitle,
                          style: ZplayType.bodySmall.toStyle(
                            color: tokens.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  if (valueText != null) ...[
                    const SizedBox(width: ZplaySpacing.s12),
                    Text(
                      valueText!,
                      style: ZplayType.caption.toStyle(color: tokens.textMuted),
                      maxLines: 1,
                    ),
                  ],

                  const SizedBox(width: ZplaySpacing.s8),

                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: tokens.textDisabled,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings Switch Row
// ─────────────────────────────────────────────────────────────────────────────

/// A toggle settings row inside a grouped surface. Same anatomy as
/// [_SettingsNavRow], with the switch at the trailing edge instead of a chevron.
class _SettingsSwitchRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? valueText;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onInfoTap;

  const _SettingsSwitchRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.valueText,
    required this.value,
    required this.onChanged,
    this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    // `FocusableCard`, for the same reason [_SettingsNavRow] uses it, and for
    // the defect that conversion left behind on this row.
    //
    // The switch used to be the only focus node here, so a remote landed on a
    // 40 px thumb at the far edge of the surface, `CardFocusRing` never drew,
    // and this - the row a person reaches specifically to ask "is adult content
    // on?" - was the one row focus could not mark. Activation is the row's, via
    // `ActivateIntent`, and runs the same [onChanged] the switch runs, so the
    // remote's centre key and a pointer change the setting identically.
    return FocusableCard(
      onTap: () => onChanged(!value),
      builder: (context, state) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!value),
          child: CardFocusRing(
            focused: state.focused,
            radius: ZplayRadius.smAll,
            child: _row(context, highlighted: state.highlighted),
          ),
        ),
      ),
    );
  }

  /// The row's anatomy: leading icon, title and subtitle, the value the setting
  /// currently holds, then the switch.
  ///
  /// [highlighted] brightens that value. On a television the ring says where
  /// focus is; the value has to be legible in the same glance, and it was
  /// `textMuted` whether or not the row was the target - which is why "Adult
  /// Content" could be focused and still not say On or Off.
  Widget _row(BuildContext context, {required bool highlighted}) {
    final tokens = context.tokens;
    final valueColor = highlighted ? tokens.textPrimary : tokens.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZplaySpacing.s16,
        vertical: ZplaySpacing.s12,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: ZplaySpacing.s16),

          // Title and Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: ZplayType.subtitle.toStyle(
                          color: tokens.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onInfoTap != null) ...[
                      const SizedBox(width: ZplaySpacing.s4),
                      IconButton(
                        icon: Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: tokens.textSecondary,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'P2P Advisory Details',
                        onPressed: onInfoTap,
                        style: _iconButtonFocusStyle(tokens),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: ZplaySpacing.s2),
                Text(
                  subtitle,
                  style: ZplayType.bodySmall.toStyle(
                    color: tokens.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          if (valueText != null) ...[
            const SizedBox(width: ZplaySpacing.s12),
            Text(
              valueText!,
              style: ZplayType.caption.toStyle(color: valueColor),
              maxLines: 1,
            ),
          ],

          const SizedBox(width: ZplaySpacing.s8),

          // `ExcludeFocus`, because the row is the focus target.
          //
          // Material's `Switch` is focusable in its own right, and it was the
          // only focus node in this row: a remote landed on the thumb, the row
          // stayed unmarked, and the framework's 12% tint under a 36 px
          // control is not a focus state anyone reads at ten feet. The row
          // above runs the same [onChanged], so nothing becomes unreachable -
          // and a pointer still lands on the switch itself, which is the whole
          // reason it is drawn there.
          ExcludeFocus(
            child: Transform.scale(
              scale: 0.9,
              child: Switch.adaptive(
                value: value,
                activeColor: tokens.accent,
                activeTrackColor: tokens.accent.withValues(
                  alpha: ZplayOpacity.textMuted,
                ),
                inactiveThumbColor: tokens.textSecondary,
                inactiveTrackColor: Colors.white.withValues(
                  alpha: ZplayOpacity.borderMedium,
                ),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What a focused `IconButton` looks like on this page.
///
/// The theme gives every Material button a visible focus state - a
/// full-strength accent overlay and a 2 px accent border - but `IconButton`
/// does not read `elevatedButtonTheme`, `outlinedButtonTheme` or
/// `textButtonTheme`; it falls back to the framework's 12% tint, which is the
/// same invisible-at-ten-feet default the settings rows were left in.
///
/// It matters on a television here: the P2P row's advisory button and the two
/// dialog close buttons are `IconButton`s, and a remote lands on each of them
/// in the middle of the settings flow. Same answer the theme gives `TextButton`,
/// so the indicator is one convention rather than two.
ButtonStyle _iconButtonFocusStyle(ZplayTokens tokens) {
  return ButtonStyle(
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) return tokens.accent;
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.pressed)) {
        return tokens.accentSubtle;
      }
      return null;
    }),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings Split Pane
// ─────────────────────────────────────────────────────────────────────────────

/// The hub's section index, down the left of the split pane.
///
/// The prototype's settings screen is a split pane, and this is the part of it
/// that fits a hub whose subpages are pushed routes rather than swapped panels:
/// the sidebar names the groups, the pane keeps every group, and selecting a
/// name scrolls to it. Nothing that was reachable before is now behind a
/// selection, which is what a panel-swapping sidebar would have done to the
/// rows of five sections at a time.
class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({
    required this.labels,
    required this.active,
    required this.onSelected,
  });

  final List<String> labels;
  final String active;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(right: tokens.hairline),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s16),
        children: [
          for (final label in labels)
            _SettingsSidebarItem(
              label: label,
              selected: label == active,
              onTap: () => onSelected(label),
            ),
        ],
      ),
    );
  }
}

/// One section name in [_SettingsSidebar].
///
/// `FocusableCard`, like every other control on the page: a sidebar a remote
/// cannot enter would leave the index visible and unusable, which is the
/// pointer-only defect this file has been fixing since the rows were `InkWell`s.
/// The 16 dp vertical padding keeps the target above the 48 dp ten-foot floor.
class _SettingsSidebarItem extends StatelessWidget {
  const _SettingsSidebarItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => Container(
        decoration: BoxDecoration(
          color: selected ? tokens.surfaceRaised : Colors.transparent,
          // The prototype marks the current item with an accent edge rather
          // than a fill, so the fill can stay the hover/selection surface.
          border: Border(
            left: BorderSide(
              color: selected ? tokens.accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: CardFocusRing(
          focused: state.focused,
          radius: ZplayRadius.xsAll,
          child: Padding(
            // 20, not 16: `ZplayType.label` is 15.6 dp of line box, so 16 dp of
            // padding is a 47.6 dp target - a tenth of a dp under the ten-foot
            // floor, which is exactly the kind of miss a remote exposes.
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s16,
              vertical: ZplaySpacing.s20,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ZplayType.label
                  .copyWith(weight: selected ? FontWeight.w700 : FontWeight.w500)
                  .toStyle(
                    color: selected ? tokens.textPrimary : tokens.textSecondary,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
