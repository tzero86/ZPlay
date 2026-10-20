// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'ZPlay';

  @override
  String get navHome => 'Home';

  @override
  String get navBrowse => 'Browse';

  @override
  String get navSearch => 'Search';

  @override
  String get navLibrary => 'Library';

  @override
  String get navSettings => 'Settings';

  @override
  String get navLiveTv => 'Live TV';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionClose => 'Close';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionTryAgain => 'Try again';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionSave => 'Save';

  @override
  String get actionCopyReport => 'Copy report';

  @override
  String get actionSaveReport => 'Save report';

  @override
  String get actionCopyDiagnostic => 'Copy diagnostic';

  @override
  String get shellFullscreen => 'Fullscreen';

  @override
  String get shellExitFullscreen => 'Exit Fullscreen';

  @override
  String get shellFullscreenTooltip => 'Fullscreen (F11)';

  @override
  String get shellExitFullscreenTooltip => 'Exit Fullscreen (F11)';

  @override
  String get errorLoadFailed => 'Could not load movies';

  @override
  String get errorUnknown => 'Unknown error';

  @override
  String get listSeparator => ', ';

  @override
  String get shortcutsTitle => 'Keyboard shortcuts';

  @override
  String get shortcutsClose => 'Close keyboard shortcuts';

  @override
  String get shortcutsGroupAnywhere => 'Anywhere';

  @override
  String get shortcutsGroupMoving => 'Moving around';

  @override
  String get shortcutsGroupPlaying => 'While playing';

  @override
  String get shortcutsGroupReading => 'While reading';

  @override
  String get shortcutsShowSheet => 'Show this sheet';

  @override
  String get shortcutsShowSheetNote => 'Also Shift + /';

  @override
  String get shortcutsToggleFullscreen => 'Toggle fullscreen';

  @override
  String get shortcutsLeaveFullscreen =>
      'Leave fullscreen, or close what is open';

  @override
  String get shortcutsLeaveFullscreenNote =>
      'Never navigates away from a page by itself';

  @override
  String get shortcutsMyList => 'My List and Downloads';

  @override
  String get shortcutsSearchMacNote => 'Cmd + K on macOS';

  @override
  String get shortcutsSettingsMacNote => 'Cmd + , on macOS';

  @override
  String get shortcutsPlayPause => 'Play or pause';

  @override
  String get shortcutsPlayPauseNote => 'K does the same';

  @override
  String get shortcutsSeek => 'Back or forward 10 seconds';

  @override
  String get shortcutsSeekNote =>
      'The arrow keys do this too, when the video has focus';

  @override
  String get shortcutsMute => 'Mute or unmute';

  @override
  String get shortcutsAspect => 'Change how the video fills the screen';

  @override
  String get shortcutsPage => 'Previous or next page or chapter';

  @override
  String get shortcutsLine => 'Down or up a line, in focus mode';

  @override
  String nowPlayingSemantics(String title, String subtitle) {
    return 'Now playing, $title, $subtitle';
  }

  @override
  String get nowPlayingOpenHint => 'Open the full player';

  @override
  String get playerPrevious => 'Previous';

  @override
  String get playerNext => 'Next';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionPlayback => 'PLAYBACK';

  @override
  String get settingsSectionSources => 'SOURCES';

  @override
  String get settingsSectionIntegrations => 'INTEGRATIONS';

  @override
  String get settingsSectionAppearance => 'APPEARANCE';

  @override
  String get settingsSectionContent => 'CONTENT';

  @override
  String get settingsSectionApp => 'APP';

  @override
  String get stateEnabled => 'Enabled';

  @override
  String get stateDisabled => 'Disabled';

  @override
  String get stateActive => 'Active';

  @override
  String get stateOffline => 'Offline';

  @override
  String get stateConnected => 'Connected';

  @override
  String get stateNotSet => 'Not set';

  @override
  String get stateOn => 'On';

  @override
  String get stateOff => 'Off';

  @override
  String get settingsVideoTitle => 'Video & Upscaling';

  @override
  String get settingsVideoSubtitle =>
      'Anime4K neural GLSL shader presets and GPU pipeline';

  @override
  String get settingsP2pTitle => 'Built-in P2P Torrent Source';

  @override
  String get settingsP2pActiveSubtitle =>
      'ZPlay torrent swarms (Knaben, TorrentGalaxy) active';

  @override
  String get settingsP2pDisabledSubtitle =>
      'P2P disabled. Using only direct HTTP streaming (ZPlayHTTP)';

  @override
  String get settingsP2pActiveValue => 'P2P Active';

  @override
  String get settingsP2pHttpValue => 'HTTP Only';

  @override
  String get settingsP2pInfoTooltip => 'P2P Advisory Details';

  @override
  String get settingsAddonsTitle => 'Addons';

  @override
  String get settingsAddonsSubtitle => 'Stremio catalogs and content providers';

  @override
  String settingsAddonsInstalled(int count) {
    return '$count Installed';
  }

  @override
  String get settingsBuiltinTitle => 'Built-in Providers';

  @override
  String get settingsBuiltinSubtitle =>
      'ZPlayHTTP streaming sources, priority order & toggles';

  @override
  String get settingsBuiltinCustom => 'Custom';

  @override
  String get settingsBuiltinDefault => 'Default';

  @override
  String get settingsDebridTitle => 'Debrid & Cloud Streaming';

  @override
  String get settingsDebridSubtitle =>
      'Real-Debrid, TorBox, AllDebrid, Premiumize & Debrid-Link';

  @override
  String get settingsTraktTitle => 'Trakt.tv Sync';

  @override
  String get settingsTraktSubtitle =>
      'Cross-device watchlist, history & playback synchronization';

  @override
  String get settingsSimklTitle => 'Simkl Sync';

  @override
  String get settingsSimklSubtitle =>
      'Cross-device Movies, TV & Anime synchronization';

  @override
  String get settingsTmdbTitle => 'TMDb API Key';

  @override
  String get settingsTmdbSubtitle =>
      'Your own key for the ranked 1990s rails and scraper metadata';

  @override
  String get settingsTmdbYourKey => 'Your key';

  @override
  String get settingsServiceKeysTitle => 'Service API Keys';

  @override
  String get settingsServiceKeysSubtitle =>
      'Subtitles, audiobooks and scraper keys you supply yourself';

  @override
  String settingsServiceKeysCount(int provided, int total) {
    return '$provided of $total set';
  }

  @override
  String get settingsDiscordTitle => 'Discord Rich Presence';

  @override
  String get settingsDiscordEnabledSubtitle =>
      'Broadcasting movies, shows, music & live activity to Discord';

  @override
  String get settingsDiscordDisabledSubtitle =>
      'Disabled. Activity is hidden from Discord';

  @override
  String get settingsAppearanceTitle => 'Appearance & Interface';

  @override
  String get settingsAppearanceSubtitle =>
      'Liquid Glass setup, color themes, and Home Page UI';

  @override
  String get settingsGlassOn => 'Glass ON';

  @override
  String get settingsCalendarTitle => 'TV Airing Calendar';

  @override
  String get settingsCalendarOnSubtitle =>
      'Calendar buttons active on Home top bar and section headers';

  @override
  String get settingsCalendarOffSubtitle =>
      'Calendar disabled and hidden across all pages';

  @override
  String get settingsAiQuizTitle => 'AI Recommendation Quiz';

  @override
  String get settingsAiQuizOnSubtitle =>
      'AI Taste Profile Quiz active on Home and Search bars';

  @override
  String get settingsAiQuizOffSubtitle =>
      'AI quiz disabled and hidden across all pages';

  @override
  String get settingsAdultTitle => 'Adult Content';

  @override
  String get settingsAdultOnSubtitle =>
      '18+ catalogs, search results and sources are enabled';

  @override
  String get settingsAdultOffSubtitle =>
      'Hidden. No 18+ catalogs, search results or sources are fetched';

  @override
  String get settingsBackupTitle => 'Backup & Restore';

  @override
  String get settingsBackupSubtitle =>
      'Export or import settings, theme and library progress (JSON)';

  @override
  String get settingsBackupDialogSubtitle => 'Cross-device JSON configuration';

  @override
  String get settingsBackupDescription =>
      'Exports your settings, theme, My List and progress. Leave the passphrase blank for a redacted profile that keeps credentials, IPTV portals and addon URLs on this device. A passphrase encrypts a full profile with them included.';

  @override
  String get settingsPassphraseOptional => 'Passphrase (optional)';

  @override
  String get settingsPassphraseHelper =>
      'At least 8 characters for an encrypted full profile.';

  @override
  String get settingsExportProfile => 'Export Profile';

  @override
  String get settingsPassphraseTooShort =>
      'Use at least 8 characters for the passphrase.';

  @override
  String get settingsRedactedProfileCopied =>
      'Redacted profile copied. Credentials, portals and addons stay on this device.';

  @override
  String get settingsEncryptedProfileCopied =>
      'Encrypted full profile copied. Keep the passphrase safe; it cannot be recovered.';

  @override
  String get settingsImportJson => 'Import JSON';

  @override
  String get settingsPasteJsonTitle => 'Paste Configuration JSON';

  @override
  String get settingsPasteJsonHint => 'Paste backup JSON here...';

  @override
  String get settingsPassphraseEncrypted => 'Passphrase (encrypted profiles)';

  @override
  String get settingsPassphraseEncryptedHelper =>
      'Leave blank for a redacted profile. Encrypted profiles need the passphrase they were exported with.';

  @override
  String get settingsPasteFromClipboard => 'Paste from Clipboard';

  @override
  String get settingsFromFile => 'From File';

  @override
  String get settingsRestoreNow => 'Restore Now';

  @override
  String settingsImportFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get settingsChooseProfile => 'Choose a ZPlay profile';

  @override
  String get settingsClearCacheTitle => 'Clear cache';

  @override
  String get settingsClearCacheSubtitle =>
      'Drop cached artwork & metadata. Sign-in, addons, My List & history stay';

  @override
  String get settingsClearCacheConfirmTitle => 'Clear cache?';

  @override
  String get settingsClearCacheConfirmBody =>
      'Removes cached artwork and metadata so fresh copies are fetched. This does not sign you out or remove addons - your profile, My List, watch history and settings stay exactly as they are.';

  @override
  String get settingsClear => 'Clear';

  @override
  String settingsCacheArtwork(String error) {
    return 'artwork cache ($error)';
  }

  @override
  String settingsCacheMetadata(String error) {
    return 'metadata cache ($error)';
  }

  @override
  String settingsCacheHero(String error) {
    return 'hero artwork cache ($error)';
  }

  @override
  String get settingsCacheCleared => 'Cache cleared.';

  @override
  String settingsCacheClearedExcept(String failures) {
    return 'Cache cleared except the $failures.';
  }

  @override
  String get settingsCacheClearedSuffix =>
      'You are still signed in - addons, My List, watch history and settings are untouched.';

  @override
  String get settingsUpdatesTitle => 'App Updates';

  @override
  String get settingsUpdatesSubtitle =>
      'Check for latest software versions and patches';

  @override
  String get settingsUpdatesCheck => 'Check';

  @override
  String get settingsDiagnosticsSubtitle =>
      'App, device and player state (redacted) you can copy or save';

  @override
  String get settingsLanguageSubtitle =>
      'English, Arabic, or follow the device';

  @override
  String get settingsAboutTitle => 'About ZPlay';

  @override
  String get settingsAboutSubtitle => 'Architecture, video engine, and credits';

  @override
  String get diagnosticsTitle => 'Diagnostics';

  @override
  String get diagnosticsSubtitle =>
      'Local app, device and player report (no telemetry)';

  @override
  String get diagnosticsDescription =>
      'A local-only snapshot of this install: app and device details, player settings, the stream engine state and the recent crash breadcrumbs. Credentials, addon URLs, IPTV portals and playlist links are never included. Nothing is uploaded - the report only exists once you copy or save it.';

  @override
  String get diagnosticsSectionDevice => 'DEVICE';

  @override
  String get diagnosticsSectionPlayerEngine => 'PLAYER & ENGINE';

  @override
  String get diagnosticsSectionBreadcrumbs => 'CRASH BREADCRUMBS';

  @override
  String get diagnosticsSummary => 'Summary';

  @override
  String get diagnosticsNotAvailable => 'Not available';

  @override
  String diagnosticsBreadcrumbCount(int count, int shown) {
    return '$count recorded • last $shown shown';
  }

  @override
  String get diagnosticsBreadcrumbs => 'Recent activity';

  @override
  String get diagnosticsEmpty => 'No breadcrumbs recorded yet.';

  @override
  String get diagnosticsCopied => 'Diagnostics report copied.';

  @override
  String get diagnosticsCopiedToClipboard =>
      'Diagnostic report copied to clipboard';

  @override
  String get diagnosticsCopyFailed => 'Could not copy the report';

  @override
  String get diagnosticsSaveFailed => 'Could not save the report';

  @override
  String diagnosticsSaved(String path) {
    return 'Diagnostics saved to $path';
  }

  @override
  String get searchHintTv => 'Search for a movie or series';

  @override
  String get searchHint => 'Search movies, series, or paste links';

  @override
  String get searchVoice => 'Search by voice';

  @override
  String get searchVoiceDenied =>
      'Microphone access is off. Allow it for ZPlay to search by voice.';

  @override
  String get searchAiQuiz => 'AI Taste Quiz';

  @override
  String get searchPaste => 'Paste from clipboard';

  @override
  String get searchFailureTitle => 'Search could not reach its sources';

  @override
  String searchFailureBody(int failed, int total) {
    return '$failed of $total sources did not respond';
  }

  @override
  String get searchFailureAdvice =>
      'A dead addon or an expired provider runtime is fixed in Addons.';

  @override
  String searchNoResults(String query) {
    return 'No results for \"$query\"';
  }

  @override
  String get searchingMoreSources => 'Searching more sources...';

  @override
  String searchPartialFailure(String sources) {
    return 'Partial Source Failure: $sources did not respond. Other sources answered normally, so the results below are real but incomplete.';
  }

  @override
  String get searchRecent => 'Recent Searches';

  @override
  String get searchClearAll => 'Clear All';

  @override
  String get searchTrending => 'Trending & Suggested';

  @override
  String get searchNothingToSuggest => 'Nothing to suggest yet';

  @override
  String get searchNothingToSuggestBody =>
      'Search for a title above, or connect an addon in Settings to have something to search.';

  @override
  String get searchPinnedSpine => 'PINNED SPINE';

  @override
  String searchCloudstreamSection(String provider) {
    return 'CloudStream • $provider';
  }

  @override
  String get searchCloudstreamExtension => 'CloudStream Extension';

  @override
  String get searchTitlesSection => 'Titles';

  @override
  String get searchImdbSuggestions => 'IMDb suggestions';

  @override
  String get searchDirectStream => 'Direct Stream';

  @override
  String get searchSourceTitleLookup => 'Title lookup';

  @override
  String get playerSeekBack => 'Seek -10s';

  @override
  String get playerSeekForward => 'Seek +10s';

  @override
  String get playerPlay => 'Play';

  @override
  String get playerPause => 'Pause';

  @override
  String get playerMute => 'Mute';

  @override
  String get playerUnmute => 'Unmute';

  @override
  String get playerPreviousEpisode => 'Previous Episode';

  @override
  String get playerNextEpisode => 'Next Episode';

  @override
  String get playerEpisodes => 'Episodes';

  @override
  String get playerAspectRatio => 'Aspect Ratio (C)';

  @override
  String get playerPlaybackSpeed => 'Playback Speed';

  @override
  String get playerAudioTracks => 'Audio Tracks';

  @override
  String get playerSubtitles => 'Subtitles';

  @override
  String get playerSubtitleSync => 'Subtitle Sync';

  @override
  String get playerFullscreen => 'Fullscreen (F)';

  @override
  String get playerExitFullscreen => 'Exit Fullscreen (F)';

  @override
  String playerVolume(int percent) {
    return 'Volume $percent%';
  }

  @override
  String playerSeekPosition(String position, String duration) {
    return '$position of $duration';
  }

  @override
  String get a11yOpenDetails => 'Open details';

  @override
  String a11yResume(String title, int percent) {
    return 'Resume $title, $percent% watched';
  }

  @override
  String get emptyMyList => 'Your list is empty';

  @override
  String get emptyMyListBody =>
      'Save your favorite movies and TV shows to watch anytime';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSubtitle => 'App language. System follows your device.';

  @override
  String get languageSystem => 'System';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'Arabic';

  @override
  String get a11yResumePlayback => 'Resume playback';

  @override
  String get playerPlaybackPosition => 'Playback position';

  @override
  String get playerVolumeLabel => 'Volume';
}
