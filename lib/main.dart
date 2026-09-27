import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:media_kit/media_kit.dart';

import 'package:window_manager/window_manager.dart';

import './shell/app_shell.dart';
import './services/addon/addon_manager.dart';
import './services/cloudstream/cloudstream_manager.dart';
import './services/theme/app_theme_service.dart';
import './services/updater/app_updater_service.dart';
import './services/books/continue_reading_service.dart';
import './services/books/reader_settings.dart';
import './services/continue_watching/continue_watching_service.dart';
import './services/theme/custom_background_service.dart';
import './services/theme/glass_settings.dart';
import './services/audiobook/audiobook_settings.dart';
import './services/home/home_page_settings.dart';
import './services/layout/device_profile.dart';
import './services/layout/focus_debug.dart';
import './services/iptv/iptv_controller.dart';
import './services/iptv/iptv_settings.dart';
import './services/manga/manga_settings.dart';
import './services/music/music_download_service.dart';
import './services/music/music_settings.dart';
import './services/music/qobuz_music_service.dart';
import './services/metadata/tmdb_service.dart';
import './services/my_list/my_list_service.dart';
import './services/debrid/debrid_rejection_store.dart';
import './services/debrid/debrid_service.dart';
import './services/stream/torrent_stream_service.dart';
import './services/player/player_settings.dart';
import './services/playback/music_now_playing_bridge.dart';
import './services/collections/collections_service.dart';
import './services/content/content_settings.dart';
import './services/download/download_service.dart';
import './services/config/env_service.dart';
import './services/config/service_credentials.dart';
import './services/window/window_service.dart';
import './services/profiles/windows_state_migration.dart';
import './services/p2p/p2p_settings_service.dart';
import './services/discord/discord_rpc_service.dart';
import './services/diagnostics/crash_breadcrumbs.dart';
import 'package:flutter/foundation.dart';
import './services/diagnostics/perf_monitor.dart';
import './services/diagnostics/renderer_backend.dart';
import './widgets/debug/perf_hud.dart';
import './services/scraper/builtin_providers_settings_service.dart';
import './widgets/updater/update_dialog.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await WindowService.instance.initialize();
  }

  // Before runApp, not after: the first frame's shell builds its chrome, sizes
  // the rail's targets and makes the TV autofocus decision, so a late answer
  // would leave the pointer-device layout on a television with no rebuild to
  // correct it. One round trip, and only on Android.
  if (kDebugMode) FocusDebug.install();
  await DeviceProfile.resolve();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Only what the first frame reads synchronously is awaited here: the theme
  // decides the MaterialApp palette at build time, and EnvService supplies the
  // API keys the home feed requests stamp on their very first request.
  // Everything else below is read through listenables/futures that already
  // tolerate an empty first value, so gating runApp on it only adds startup
  // latency (the pre-split version blocked on ~22 services including a torrent
  // engine boot).
  try {
    // Must run before the first path_provider / shared_preferences read: the
    // Windows plugins derive their storage root from Runner.rc's CompanyName /
    // ProductName, and the rebrand moved that root. Whoever reads first creates
    // the new empty profile, which the migration then refuses to touch.
    await migrateLegacyWindowsState();
  } catch (e) {
    debugPrint('[Startup] Windows state migration failed: $e');
  }
  await EnvService.initialize();
  await PlayerSettings.initialize();
  await Future.wait([
    AppThemeService.initialize(),
    // The first frame mounts the shell, which mounts HomePage, and HomePage
    // listens to these.
    HomePageSettings.initialize(),
    MyListService.initialize(),
    ContinueWatchingService.initialize(),
    CustomBackgroundService.initialize(),
    GlassSettings.initialize(),
    ContentSettings.initialize(),
    // The Home rails' visibility switch is read on the first frame.
    CollectionsService.initialize(),
    RendererBackendSettings.initialize(),
  ]);
  runApp(const ZPlayApp());
  if (kDebugMode) PerfMonitor.start();
  unawaited(CrashBreadcrumbs.initialize());
  CrashBreadcrumbs.lifecycle('start');
  unawaited(_initializeDeferredServices().then((_) => CrashBreadcrumbs.memory('startup.warm')));
}

/// Service warm-up that the UI can render without: catalogs, downloads, the
/// torrent engine and integrations the user has to navigate to first. Failures
/// are logged and swallowed — a broken optional integration must not stop the
/// app from launching.
Future<void> _initializeDeferredServices() async {
  Future<void> guard(String label, Future<void> Function() init) async {
    try {
      await init();
    } catch (e) {
      debugPrint('[Startup] $label failed to initialize: $e');
    }
  }

  await Future.wait([
    guard('AddonManager', AddonManager.instance.initialize),
    guard('CloudStreamManager', CloudStreamManager.instance.initialize),
    guard(
      'BuiltinProvidersSettingsService',
      BuiltinProvidersSettingsService.instance.init,
    ),
    guard('AudiobookSettings', AudiobookSettings.initialize),
    guard('ContinueReadingService', ContinueReadingService.initialize),
    guard('ReaderSettings', ReaderSettings.initialize),
    guard('IptvController', IptvController.instance.init),
    guard('IptvSettings', IptvSettings.initialize),
    guard('MangaSettings', MangaSettings.initialize),
    guard('MusicSettings', MusicSettings.initialize),
    // Music constructs its player only when the user opens the tab, but the
    // shell's bar needs an owner from the first track it publishes, so the
    // bridge registers itself here rather than on first Music visit.
    guard('MusicNowPlayingBridge', () async => MusicNowPlayingBridge.initialize()),
    guard('MusicDownloadService', MusicDownloadService.instance.init),
    guard('QobuzMusicService', QobuzMusicService.instance.initialize),
    guard('P2pSettingsService', P2pSettingsService.initialize),
    guard('DebridService', DebridService.refreshDebridReady),
    guard('DebridRejectionStore', DebridRejectionStore.instance.initialize),
    guard('TmdbService', TmdbService.initialize),
    guard('ServiceCredentials', ServiceCredentials.initialize),
    guard('DownloadService', DownloadService.instance.initialize),
    guard('TorrentStreamService', TorrentStreamService().start),
    guard('DiscordRpcService', DiscordRpcService.instance.initialize),
  ]);
}

class ZPlayApp extends StatefulWidget {
  const ZPlayApp({super.key});

  @override
  State<ZPlayApp> createState() => _ZPlayAppState();
}

class _ZPlayAppState extends State<ZPlayApp>
    with WidgetsBindingObserver {
  static bool _hasCheckedInitialUpdate = false;
  static bool _isShowingUpdateDialog = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasCheckedInitialUpdate) {
        _hasCheckedInitialUpdate = true;
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) _checkForUpdates();
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    CrashBreadcrumbs.lifecycle(state.name);
    if (state == AppLifecycleState.detached) {
      CrashBreadcrumbs.memory('app.detached');
    }
  }

  @override
  void didHaveMemoryPressure() {
    CrashBreadcrumbs.memory('os.memoryPressure');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    if (_isShowingUpdateDialog) return;
    try {
      final updater = AppUpdaterService();
      final updateInfo = await updater.checkForUpdates();
      if (updateInfo == null) return;

      BuildContext? context = navigatorKey.currentContext;
      for (int i = 0; i < 6 && (context == null || !context.mounted); i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        context = navigatorKey.currentContext;
      }

      if (context != null && context.mounted && !_isShowingUpdateDialog) {
        _isShowingUpdateDialog = true;
        await showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => UpdateDialog(updateInfo: updateInfo),
        );
        _isShowingUpdateDialog = false;
      }
    } catch (e) {
      _isShowingUpdateDialog = false;
      debugPrint('Error checking for app updates: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemePalette>(
      valueListenable: AppThemeService.currentPalette,
      builder: (context, palette, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [BreadcrumbObserver()],
          title: 'ZPlay',
          debugShowCheckedModeBanner: false,
          theme: AppThemeService.createThemeData(palette),
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            overscroll: false,
          ),
          home: const AppShell(),
          builder: (context, child) {
            if (!kDebugMode) return child ?? const SizedBox.shrink();
            return Stack(
              children: [if (child != null) child, const PerfHud()],
            );
          },
        );
      },
    );
  }
}

