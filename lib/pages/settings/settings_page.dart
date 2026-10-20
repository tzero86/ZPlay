import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n.dart';
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
import '../../services/metadata/trailer_resolver.dart';
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
import 'diagnostics_page.dart';
import 'language_settings_page.dart';
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
    final passphraseController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        final tokens = ctx.tokens;
        final l10n = l10nOf(ctx);
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
                              l10n.settingsBackupTitle,
                              style: ZplayType.title.toStyle(
                                color: tokens.textPrimary,
                              ),
                            ),
                            Text(
                              l10n.settingsBackupDialogSubtitle,
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
                    l10n.settingsBackupDescription,
                    style: ZplayType.body.toStyle(color: tokens.textEmphasis),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passphraseController,
                    obscureText: true,
                    style: ZplayType.bodySmall.toStyle(
                      color: tokens.textPrimary,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n.settingsPassphraseOptional,
                      helperText: l10n.settingsPassphraseHelper,
                      helperStyle: ZplayType.bodySmall.toStyle(
                        color: tokens.textSecondary,
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
                            l10n.settingsExportProfile,
                            style: ZplayType.label.toStyle(),
                          ),
                          onPressed: () async {
                            final passphrase = passphraseController.text;
                            if (passphrase.isNotEmpty &&
                                passphrase.length < 8) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    l10n.settingsPassphraseTooShort,
                                  ),
                                ),
                              );
                              return;
                            }
                            final jsonStr =
                                await BackupRestoreService.exportSettingsJson(
                                  passphrase: passphrase.isEmpty
                                      ? null
                                      : passphrase,
                                );
                            await Clipboard.setData(
                              ClipboardData(text: jsonStr),
                            );
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    passphrase.isEmpty
                                        ? l10n.settingsRedactedProfileCopied
                                        : l10n.settingsEncryptedProfileCopied,
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
                            l10n.settingsImportJson,
                            style: ZplayType.label.toStyle(),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showImportJsonInputDialog(
                              initialPassphrase: passphraseController.text,
                            );
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

  void _showImportJsonInputDialog({String initialPassphrase = ''}) {
    final textController = TextEditingController();
    final passphraseController = TextEditingController(text: initialPassphrase);
    showDialog(
      context: context,
      builder: (ctx) {
        final tokens = ctx.tokens;
        final l10n = l10nOf(ctx);
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
                        l10n.settingsPasteJsonTitle,
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
                      hintText: l10n.settingsPasteJsonHint,
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
                  TextField(
                    controller: passphraseController,
                    obscureText: true,
                    style: ZplayType.bodySmall.toStyle(
                      color: tokens.textPrimary,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n.settingsPassphraseEncrypted,
                      helperText: l10n.settingsPassphraseEncryptedHelper,
                      helperStyle: ZplayType.bodySmall.toStyle(
                        color: tokens.textSecondary,
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
                          l10n.settingsPasteFromClipboard,
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
                          l10n.settingsFromFile,
                          style: ZplayType.label.toStyle(color: tokens.accent),
                        ),
                        onPressed: () => _importFromFile(
                          passphrase: passphraseController.text,
                        ),
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
                          l10n.settingsRestoreNow,
                          style: ZplayType.label.toStyle(),
                        ),
                        onPressed: () async {
                          final txt = textController.text.trim();
                          if (txt.isEmpty) return;
                          try {
                            final msg =
                                await BackupRestoreService.importSettingsJson(
                                  txt,
                                  passphrase: passphraseController.text.isEmpty
                                      ? null
                                      : passphraseController.text,
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
                                content: Text(l10n.settingsImportFailed('$e')),
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
  Future<void> _importFromFile({String? passphrase}) async {
    FilePickerResult? picked;
    try {
      // `withData` asks Android for the bytes of the document the picker
      // granted. The SAF URI behind it is not a path this process may open.
      picked = await FilePicker.platform.pickFiles(
        // Not restricted to `.json`: a provider that reports a profile as
        // `text/plain` would otherwise hide it from the picker.
        type: FileType.any,
        withData: true,
        dialogTitle: l10nOf(context).settingsChooseProfile,
      );
    } catch (_) {
      // A television with no document picker installed. Fall back to the
      // locations the app can read on its own rather than a dead button.
      await _importFromSearchPaths(passphrase: passphrase);
      return;
    }
    if (picked == null || picked.files.isEmpty) return; // cancelled
    final file = picked.files.first;
    await _reportImport(
      () => BackupRestoreService.importPickedProfile(
        bytes: file.bytes,
        path: file.path,
        name: file.name,
        passphrase: passphrase,
      ),
    );
  }

  /// Imports the profile pushed to one of the locations the app can read.
  ///
  /// This is what [autoImportFromFile] drives, so a build without a remote in
  /// front of it exercises exactly the import a person gets.
  Future<void> _importFromSearchPaths({String? passphrase}) => _reportImport(
    () async => BackupRestoreService.importSettingsFromFile(
      await BackupRestoreService.importSearchPaths(),
      passphrase: passphrase,
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
                : l10nOf(context).settingsImportFailed('$e'),
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
        final l10n = l10nOf(ctx);
        return AlertDialog(
          backgroundColor: tokens.surfaceOverlay,
          shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.lgAll),
          title: Text(
            l10n.settingsClearCacheConfirmTitle,
            style: ZplayType.title.toStyle(color: tokens.textPrimary),
          ),
          content: Text(
            l10n.settingsClearCacheConfirmBody,
            style: ZplayType.body.toStyle(color: tokens.textEmphasis),
          ),
          actions: [
            TextButton(
              child: Text(
                l10n.actionCancel,
                style: ZplayType.label.toStyle(color: tokens.textSecondary),
              ),
              onPressed: () => Navigator.pop(ctx, false),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.onAccent,
              ),
              child: Text(l10n.settingsClear),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final tokens = context.tokens;
    final l10n = l10nOf(context);
    final messenger = ScaffoldMessenger.of(context);

    // One label per step, so the report names the store that failed instead of
    // a generic "something went wrong".
    final failures = <String>[];
    try {
      await AppImageCache.emptyCache();
    } catch (e) {
      failures.add(
        l10n.settingsCacheArtwork(e.toString().replaceFirst('Exception: ', '')),
      );
    }
    try {
      MetadataService.clearCache();
    } catch (e) {
      failures.add(
        l10n.settingsCacheMetadata(
          e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
    try {
      HeroMediaResolver.clearCache();
    } catch (e) {
      failures.add(
        l10n.settingsCacheHero(e.toString().replaceFirst('Exception: ', '')),
      );
    }
    try {
      TrailerResolver.clearCache();
    } catch (e) {
      failures.add(
        l10n.settingsCacheHero(e.toString().replaceFirst('Exception: ', '')),
      );
    }

    final cleared = failures.isEmpty
        ? l10n.settingsCacheCleared
        : l10n.settingsCacheClearedExcept(failures.join(l10n.listSeparator));
    messenger.showSnackBar(
      SnackBar(
        content: Text('$cleared ${l10n.settingsCacheClearedSuffix}'),
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
  ///
  /// These are stable ids, not copy: they key [_sectionKeys] and [_activeSection]
  /// across rebuilds, so translating them in place would move every anchor the
  /// moment the language changed. [_sectionLabel] maps an id to the words the
  /// user sees.
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

  /// One labelled section: an overline heading over a group of rows that rest
  /// on the page canvas, split by hairline dividers instead of one card per row.
  Widget _buildSection(
    BuildContext context,
    String label, {
    required List<Widget> rows,
    bool first = false,
  }) {
    final tokens = context.tokens;
    final title = _sectionLabel(l10nOf(context), label);
    return Column(
      key: _sectionKeys[label],
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!first) const SizedBox(height: ZplaySpacing.s24),
        Text(title, style: ZplayType.overline.toStyle(color: tokens.textMuted)),
        const SizedBox(height: ZplaySpacing.s12),
        Column(children: _dividerSeparated(rows, tokens.borderSubtle)),
      ],
    );
  }

  /// Returns [rows] with a hairline divider between each pair, so a section's
  /// rows still read as one group without a surface around them.
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
  PreferredSizeWidget _appBar(BuildContext context, ZplayTokens tokens) {
    final bar = AppBar(
      // Transparent, no hairline: Settings is a shell slot, and the shell's nav
      // blends over every slot now. An opaque palette band pinned across the
      // strip the nav rests on is the seam that blend exists to remove - the
      // canvas below is the band, and the nav sits on it directly.
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      // No explicit leading: the framework already gates the back button on canPop,
      // so it vanishes in the shell and returns if this page is pushed.
      title: Text(
        l10nOf(context).settingsTitle,
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

    // The canvas wraps the `Scaffold`, not its `body`, so it paints behind the
    // (now transparent) header too: the nav bar rests on it and the title sits
    // on the same surface as the rows instead of on a strip of its own.
    return AnimatedAmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _appBar(context, tokens),
        body: LayoutBuilder(
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
                                title: l10nOf(context).settingsVideoTitle,
                                subtitle: l10nOf(context).settingsVideoSubtitle,
                                valueText: anime4kPreset == Anime4KPreset.off
                                    ? l10nOf(context).stateOff
                                    : anime4kPreset.label
                                          .split('(')
                                          .first
                                          .trim(),
                                onTap: () =>
                                    _navigateTo(const VideoSettingsPage()),
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
                                title: l10nOf(context).settingsP2pTitle,
                                subtitle: isP2p
                                    ? l10nOf(context).settingsP2pActiveSubtitle
                                    : l10nOf(
                                        context,
                                      ).settingsP2pDisabledSubtitle,
                                valueText: isP2p
                                    ? l10nOf(context).settingsP2pActiveValue
                                    : l10nOf(context).settingsP2pHttpValue,
                                value: isP2p,
                                onChanged: (val) async {
                                  await P2pSettingsService.setP2pEnabled(val);
                                },
                                onInfoTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) =>
                                        const P2pWarningDialog(),
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
                            title: l10nOf(context).settingsAddonsTitle,
                            subtitle: l10nOf(context).settingsAddonsSubtitle,
                            valueText: l10nOf(
                              context,
                            ).settingsAddonsInstalled(addonCount),
                            onTap: () =>
                                _navigateTo(const AddonsSettingsPage()),
                          ),
                          // Built-in Providers (ZPlayHTTP)
                          ListenableBuilder(
                            listenable:
                                BuiltinProvidersSettingsService.instance,
                            builder: (context, _) {
                              final isCustom = BuiltinProvidersSettingsService
                                  .instance
                                  .isCustom;
                              return _SettingsNavRow(
                                icon: Icons.dns_rounded,
                                iconColor: isCustom
                                    ? tokens.accent
                                    : tokens.success,
                                title: l10nOf(context).settingsBuiltinTitle,
                                subtitle: l10nOf(
                                  context,
                                ).settingsBuiltinSubtitle,
                                valueText: isCustom
                                    ? l10nOf(context).settingsBuiltinCustom
                                    : l10nOf(context).settingsBuiltinDefault,
                                onTap: () => _navigateTo(
                                  const BuiltinProvidersSettingsPage(),
                                ),
                              );
                            },
                          ),
                          // Debrid & Cloud Streaming
                          _SettingsNavRow(
                            icon: Icons.cloud_download_rounded,
                            iconColor: tokens.accent,
                            title: l10nOf(context).settingsDebridTitle,
                            subtitle: l10nOf(context).settingsDebridSubtitle,
                            valueText: _useDebrid
                                ? (_debridProvider != 'None'
                                      ? _debridProvider
                                      : l10nOf(context).stateActive)
                                : l10nOf(context).stateDisabled,
                            onTap: () =>
                                _navigateTo(const DebridSettingsPage()),
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
                            title: l10nOf(context).settingsTraktTitle,
                            subtitle: l10nOf(context).settingsTraktSubtitle,
                            valueText: _traktConnected
                                ? l10nOf(context).stateConnected
                                : l10nOf(context).stateOffline,
                            onTap: () => _navigateTo(const TraktSettingsPage()),
                          ),
                          // Simkl Sync
                          _SettingsNavRow(
                            icon: Icons.tv_rounded,
                            iconColor: _simklBrand,
                            title: l10nOf(context).settingsSimklTitle,
                            subtitle: l10nOf(context).settingsSimklSubtitle,
                            valueText: _simklConnected
                                ? l10nOf(context).stateConnected
                                : l10nOf(context).stateOffline,
                            onTap: () => _navigateTo(const SimklSettingsPage()),
                          ),
                          // TMDb API Key (bring your own)
                          ListenableBuilder(
                            listenable: TmdbService.apiKey,
                            builder: (context, _) => _SettingsNavRow(
                              icon: Icons.theaters_rounded,
                              iconColor: tokens.accent,
                              title: l10nOf(context).settingsTmdbTitle,
                              subtitle: l10nOf(context).settingsTmdbSubtitle,
                              valueText: TmdbService.isConfigured
                                  ? l10nOf(context).settingsTmdbYourKey
                                  : l10nOf(context).stateNotSet,
                              onTap: () =>
                                  _navigateTo(const TmdbSettingsPage()),
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
                                title: l10nOf(context).settingsServiceKeysTitle,
                                subtitle: l10nOf(
                                  context,
                                ).settingsServiceKeysSubtitle,
                                valueText: l10nOf(context)
                                    .settingsServiceKeysCount(
                                      provided,
                                      ServiceCredential.values.length,
                                    ),
                                onTap: () => _navigateTo(
                                  const ServiceKeysSettingsPage(),
                                ),
                              );
                            },
                          ),
                          // Discord Rich Presence (Desktop Only)
                          if (Platform.isWindows ||
                              Platform.isLinux ||
                              Platform.isMacOS)
                            ValueListenableBuilder<bool>(
                              valueListenable:
                                  DiscordRpcService.instance.isEnabled,
                              builder: (context, isDiscordEnabled, _) {
                                return _SettingsSwitchRow(
                                  icon: Icons.sports_esports_rounded,
                                  iconColor: isDiscordEnabled
                                      ? _discordBrand
                                      : tokens.textSecondary,
                                  title: l10nOf(context).settingsDiscordTitle,
                                  subtitle: isDiscordEnabled
                                      ? l10nOf(
                                          context,
                                        ).settingsDiscordEnabledSubtitle
                                      : l10nOf(
                                          context,
                                        ).settingsDiscordDisabledSubtitle,
                                  valueText: isDiscordEnabled
                                      ? l10nOf(context).stateActive
                                      : l10nOf(context).stateDisabled,
                                  value: isDiscordEnabled,
                                  onChanged: (val) async {
                                    await DiscordRpcService.instance.setEnabled(
                                      val,
                                    );
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
                                    title: l10nOf(
                                      context,
                                    ).settingsAppearanceTitle,
                                    subtitle: l10nOf(
                                      context,
                                    ).settingsAppearanceSubtitle,
                                    valueText: glassEnabled
                                        ? '${currentPalette.name} · ${l10nOf(context).settingsGlassOn}'
                                        : currentPalette.name,
                                    onTap: () => _navigateTo(
                                      const AppearanceSettingsPage(),
                                    ),
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
                                title: l10nOf(context).settingsCalendarTitle,
                                subtitle: isCalEnabled
                                    ? l10nOf(context).settingsCalendarOnSubtitle
                                    : l10nOf(
                                        context,
                                      ).settingsCalendarOffSubtitle,
                                valueText: isCalEnabled
                                    ? l10nOf(context).stateEnabled
                                    : l10nOf(context).stateDisabled,
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
                                title: l10nOf(context).settingsAiQuizTitle,
                                subtitle: isAiEnabled
                                    ? l10nOf(context).settingsAiQuizOnSubtitle
                                    : l10nOf(context).settingsAiQuizOffSubtitle,
                                valueText: isAiEnabled
                                    ? l10nOf(context).stateEnabled
                                    : l10nOf(context).stateDisabled,
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
                                title: l10nOf(context).settingsAdultTitle,
                                subtitle: isAdultOn
                                    ? l10nOf(context).settingsAdultOnSubtitle
                                    : l10nOf(context).settingsAdultOffSubtitle,
                                valueText: isAdultOn
                                    ? l10nOf(context).stateOn
                                    : l10nOf(context).stateOff,
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
                            title: l10nOf(context).settingsBackupTitle,
                            subtitle: l10nOf(context).settingsBackupSubtitle,
                            valueText: 'JSON',
                            onTap: _showBackupRestoreDialog,
                          ),
                          // Cache cleanup (artwork + metadata, never user state)
                          _SettingsNavRow(
                            icon: Icons.cleaning_services_rounded,
                            iconColor: tokens.accent,
                            title: l10nOf(context).settingsClearCacheTitle,
                            subtitle: l10nOf(
                              context,
                            ).settingsClearCacheSubtitle,
                            onTap: _confirmAndClearCache,
                          ),
                          // App Updates & System
                          _SettingsNavRow(
                            icon: Icons.system_update_rounded,
                            iconColor: tokens.accent,
                            title: l10nOf(context).settingsUpdatesTitle,
                            subtitle: l10nOf(context).settingsUpdatesSubtitle,
                            valueText: _appVersion != null
                                ? 'v$_appVersion'
                                : l10nOf(context).settingsUpdatesCheck,
                            onTap: () =>
                                _navigateTo(const UpdatesSettingsPage()),
                          ),
                          // Diagnostics (local-only report)
                          _SettingsNavRow(
                            icon: Icons.monitor_heart_outlined,
                            iconColor: tokens.accent,
                            title: l10nOf(context).diagnosticsTitle,
                            subtitle: l10nOf(
                              context,
                            ).settingsDiagnosticsSubtitle,
                            onTap: () => _navigateTo(const DiagnosticsPage()),
                          ),
                          // Language (English / Arabic / system)
                          _SettingsNavRow(
                            icon: Icons.translate_rounded,
                            iconColor: tokens.accent,
                            title: l10nOf(context).languageTitle,
                            subtitle: l10nOf(context).settingsLanguageSubtitle,
                            onTap: () =>
                                _navigateTo(const LanguageSettingsPage()),
                          ),
                          // About ZPlay
                          _SettingsNavRow(
                            icon: Icons.info_outline_rounded,
                            iconColor: tokens.accent,
                            title: l10nOf(context).settingsAboutTitle,
                            subtitle: l10nOf(context).settingsAboutSubtitle,
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
                  sections: [
                    for (final id in _sectionLabels)
                      (id: id, label: _sectionLabel(l10nOf(context), id)),
                  ],
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

/// A navigating settings row inside a grouped section: bare 20 px leading icon,
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
    //
    // **The ring is the row's own rect, not the content inside its padding.**
    //
    // A device sweep measured the first content row's ring at 671 x 62 dp and
    // read it as "the widest focus rect in the app, and a different control from
    // every other focus target". The rectangles differ because the targets do,
    // and this target is a full-width list row: a ring drawn around the row's
    // *text* would mark a region a press does not have to land in, because the
    // whole row activates - its 16 dp gutter included. On a television the ring
    // is the only thing that says what a press does, so it draws the edge of
    // what a press hits. Every full-width row surface in the app answers the
    // same way, and says so: `_buildActiveCard` in `downloads_page.dart` - "the
    // row is spacing over the page surface, and the only edge it ever draws is
    // the focus ring" - and the sidebar beside this page, which wraps its own
    // `Padding` in the ring rather than insetting it. So does every settings row,
    // nav or switch.
    //
    // The layout is identical either way: the `Padding` stays inside the ring, so
    // the row's box, its content and the ring's radius all sit where they sat.
    // This is a decision about the mark, not about the box.
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

/// A toggle settings row inside a grouped section. Same anatomy as
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
    // remote's centre key and a pointer change the setting identically. The ring
    // is the whole row, for the reason [_SettingsNavRow] writes down.
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
                        tooltip: l10nOf(context).settingsP2pInfoTooltip,
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

/// What a settings section id is called in the active language.
///
/// The id stays English because it is the anchor key; only this mapping is
/// copy. An unknown id falls through unchanged, which keeps a section added by
/// a future change visible (in its own words) instead of blank.
String _sectionLabel(AppLocalizations l10n, String id) => switch (id) {
  'PLAYBACK' => l10n.settingsSectionPlayback,
  'SOURCES' => l10n.settingsSectionSources,
  'INTEGRATIONS' => l10n.settingsSectionIntegrations,
  'APPEARANCE' => l10n.settingsSectionAppearance,
  'CONTENT' => l10n.settingsSectionContent,
  'APP' => l10n.settingsSectionApp,
  _ => id,
};

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
    required this.sections,
    required this.active,
    required this.onSelected,
  });

  /// Section id plus the words to draw for it. The id is what selection and
  /// scrolling travel on, so changing language never moves the active anchor.
  final List<({String id, String label})> sections;
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
          for (final section in sections)
            _SettingsSidebarItem(
              label: section.label,
              selected: section.id == active,
              onTap: () => onSelected(section.id),
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
                  .copyWith(
                    weight: selected ? FontWeight.w700 : FontWeight.w500,
                  )
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
