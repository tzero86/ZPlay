import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'ZPlay'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get navBrowse;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navLiveTv.
  ///
  /// In en, this message translates to:
  /// **'Live TV'**
  String get navLiveTv;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @actionTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionTryAgain;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionCopyReport.
  ///
  /// In en, this message translates to:
  /// **'Copy report'**
  String get actionCopyReport;

  /// No description provided for @actionSaveReport.
  ///
  /// In en, this message translates to:
  /// **'Save report'**
  String get actionSaveReport;

  /// No description provided for @actionCopyDiagnostic.
  ///
  /// In en, this message translates to:
  /// **'Copy diagnostic'**
  String get actionCopyDiagnostic;

  /// No description provided for @shellFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get shellFullscreen;

  /// No description provided for @shellExitFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Exit Fullscreen'**
  String get shellExitFullscreen;

  /// No description provided for @shellFullscreenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen (F11)'**
  String get shellFullscreenTooltip;

  /// No description provided for @shellExitFullscreenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Exit Fullscreen (F11)'**
  String get shellExitFullscreenTooltip;

  /// No description provided for @errorLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load movies'**
  String get errorLoadFailed;

  /// No description provided for @errorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get errorUnknown;

  /// No description provided for @listSeparator.
  ///
  /// In en, this message translates to:
  /// **', '**
  String get listSeparator;

  /// No description provided for @shortcutsTitle.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get shortcutsTitle;

  /// No description provided for @shortcutsClose.
  ///
  /// In en, this message translates to:
  /// **'Close keyboard shortcuts'**
  String get shortcutsClose;

  /// No description provided for @shortcutsGroupAnywhere.
  ///
  /// In en, this message translates to:
  /// **'Anywhere'**
  String get shortcutsGroupAnywhere;

  /// No description provided for @shortcutsGroupMoving.
  ///
  /// In en, this message translates to:
  /// **'Moving around'**
  String get shortcutsGroupMoving;

  /// No description provided for @shortcutsGroupPlaying.
  ///
  /// In en, this message translates to:
  /// **'While playing'**
  String get shortcutsGroupPlaying;

  /// No description provided for @shortcutsGroupReading.
  ///
  /// In en, this message translates to:
  /// **'While reading'**
  String get shortcutsGroupReading;

  /// No description provided for @shortcutsShowSheet.
  ///
  /// In en, this message translates to:
  /// **'Show this sheet'**
  String get shortcutsShowSheet;

  /// No description provided for @shortcutsShowSheetNote.
  ///
  /// In en, this message translates to:
  /// **'Also Shift + /'**
  String get shortcutsShowSheetNote;

  /// No description provided for @shortcutsToggleFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Toggle fullscreen'**
  String get shortcutsToggleFullscreen;

  /// No description provided for @shortcutsLeaveFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Leave fullscreen, or close what is open'**
  String get shortcutsLeaveFullscreen;

  /// No description provided for @shortcutsLeaveFullscreenNote.
  ///
  /// In en, this message translates to:
  /// **'Never navigates away from a page by itself'**
  String get shortcutsLeaveFullscreenNote;

  /// No description provided for @shortcutsMyList.
  ///
  /// In en, this message translates to:
  /// **'My List and Downloads'**
  String get shortcutsMyList;

  /// No description provided for @shortcutsSearchMacNote.
  ///
  /// In en, this message translates to:
  /// **'Cmd + K on macOS'**
  String get shortcutsSearchMacNote;

  /// No description provided for @shortcutsSettingsMacNote.
  ///
  /// In en, this message translates to:
  /// **'Cmd + , on macOS'**
  String get shortcutsSettingsMacNote;

  /// No description provided for @shortcutsPlayPause.
  ///
  /// In en, this message translates to:
  /// **'Play or pause'**
  String get shortcutsPlayPause;

  /// No description provided for @shortcutsPlayPauseNote.
  ///
  /// In en, this message translates to:
  /// **'K does the same'**
  String get shortcutsPlayPauseNote;

  /// No description provided for @shortcutsSeek.
  ///
  /// In en, this message translates to:
  /// **'Back or forward 10 seconds'**
  String get shortcutsSeek;

  /// No description provided for @shortcutsSeekNote.
  ///
  /// In en, this message translates to:
  /// **'The arrow keys do this too, when the video has focus'**
  String get shortcutsSeekNote;

  /// No description provided for @shortcutsMute.
  ///
  /// In en, this message translates to:
  /// **'Mute or unmute'**
  String get shortcutsMute;

  /// No description provided for @shortcutsAspect.
  ///
  /// In en, this message translates to:
  /// **'Change how the video fills the screen'**
  String get shortcutsAspect;

  /// No description provided for @shortcutsPage.
  ///
  /// In en, this message translates to:
  /// **'Previous or next page or chapter'**
  String get shortcutsPage;

  /// No description provided for @shortcutsLine.
  ///
  /// In en, this message translates to:
  /// **'Down or up a line, in focus mode'**
  String get shortcutsLine;

  /// No description provided for @nowPlayingSemantics.
  ///
  /// In en, this message translates to:
  /// **'Now playing, {title}, {subtitle}'**
  String nowPlayingSemantics(String title, String subtitle);

  /// No description provided for @nowPlayingOpenHint.
  ///
  /// In en, this message translates to:
  /// **'Open the full player'**
  String get nowPlayingOpenHint;

  /// No description provided for @playerPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get playerPrevious;

  /// No description provided for @playerNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get playerNext;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSectionPlayback.
  ///
  /// In en, this message translates to:
  /// **'PLAYBACK'**
  String get settingsSectionPlayback;

  /// No description provided for @settingsSectionSources.
  ///
  /// In en, this message translates to:
  /// **'SOURCES'**
  String get settingsSectionSources;

  /// No description provided for @settingsSectionIntegrations.
  ///
  /// In en, this message translates to:
  /// **'INTEGRATIONS'**
  String get settingsSectionIntegrations;

  /// No description provided for @settingsSectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'APPEARANCE'**
  String get settingsSectionAppearance;

  /// No description provided for @settingsSectionContent.
  ///
  /// In en, this message translates to:
  /// **'CONTENT'**
  String get settingsSectionContent;

  /// No description provided for @settingsSectionApp.
  ///
  /// In en, this message translates to:
  /// **'APP'**
  String get settingsSectionApp;

  /// No description provided for @stateEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get stateEnabled;

  /// No description provided for @stateDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get stateDisabled;

  /// No description provided for @stateActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get stateActive;

  /// No description provided for @stateOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get stateOffline;

  /// No description provided for @stateConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get stateConnected;

  /// No description provided for @stateNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get stateNotSet;

  /// No description provided for @stateOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get stateOn;

  /// No description provided for @stateOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get stateOff;

  /// No description provided for @settingsVideoTitle.
  ///
  /// In en, this message translates to:
  /// **'Video & Upscaling'**
  String get settingsVideoTitle;

  /// No description provided for @settingsVideoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Anime4K neural GLSL shader presets and GPU pipeline'**
  String get settingsVideoSubtitle;

  /// No description provided for @settingsP2pTitle.
  ///
  /// In en, this message translates to:
  /// **'Built-in P2P Torrent Source'**
  String get settingsP2pTitle;

  /// No description provided for @settingsP2pActiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'ZPlay torrent swarms (Knaben, TorrentGalaxy) active'**
  String get settingsP2pActiveSubtitle;

  /// No description provided for @settingsP2pDisabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'P2P disabled. Using only direct HTTP streaming (ZPlayHTTP)'**
  String get settingsP2pDisabledSubtitle;

  /// No description provided for @settingsP2pActiveValue.
  ///
  /// In en, this message translates to:
  /// **'P2P Active'**
  String get settingsP2pActiveValue;

  /// No description provided for @settingsP2pHttpValue.
  ///
  /// In en, this message translates to:
  /// **'HTTP Only'**
  String get settingsP2pHttpValue;

  /// No description provided for @settingsP2pInfoTooltip.
  ///
  /// In en, this message translates to:
  /// **'P2P Advisory Details'**
  String get settingsP2pInfoTooltip;

  /// No description provided for @settingsAddonsTitle.
  ///
  /// In en, this message translates to:
  /// **'Addons'**
  String get settingsAddonsTitle;

  /// No description provided for @settingsAddonsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stremio catalogs and content providers'**
  String get settingsAddonsSubtitle;

  /// No description provided for @settingsAddonsInstalled.
  ///
  /// In en, this message translates to:
  /// **'{count} Installed'**
  String settingsAddonsInstalled(int count);

  /// No description provided for @settingsBuiltinTitle.
  ///
  /// In en, this message translates to:
  /// **'Built-in Providers'**
  String get settingsBuiltinTitle;

  /// No description provided for @settingsBuiltinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'ZPlayHTTP streaming sources, priority order & toggles'**
  String get settingsBuiltinSubtitle;

  /// No description provided for @settingsBuiltinCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get settingsBuiltinCustom;

  /// No description provided for @settingsBuiltinDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get settingsBuiltinDefault;

  /// No description provided for @settingsDebridTitle.
  ///
  /// In en, this message translates to:
  /// **'Debrid & Cloud Streaming'**
  String get settingsDebridTitle;

  /// No description provided for @settingsDebridSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Real-Debrid, TorBox, AllDebrid, Premiumize & Debrid-Link'**
  String get settingsDebridSubtitle;

  /// No description provided for @settingsTraktTitle.
  ///
  /// In en, this message translates to:
  /// **'Trakt.tv Sync'**
  String get settingsTraktTitle;

  /// No description provided for @settingsTraktSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Cross-device watchlist, history & playback synchronization'**
  String get settingsTraktSubtitle;

  /// No description provided for @settingsSimklTitle.
  ///
  /// In en, this message translates to:
  /// **'Simkl Sync'**
  String get settingsSimklTitle;

  /// No description provided for @settingsSimklSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Cross-device Movies, TV & Anime synchronization'**
  String get settingsSimklSubtitle;

  /// No description provided for @settingsTmdbTitle.
  ///
  /// In en, this message translates to:
  /// **'TMDb API Key'**
  String get settingsTmdbTitle;

  /// No description provided for @settingsTmdbSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your own key for the ranked 1990s rails and scraper metadata'**
  String get settingsTmdbSubtitle;

  /// No description provided for @settingsTmdbYourKey.
  ///
  /// In en, this message translates to:
  /// **'Your key'**
  String get settingsTmdbYourKey;

  /// No description provided for @settingsServiceKeysTitle.
  ///
  /// In en, this message translates to:
  /// **'Service API Keys'**
  String get settingsServiceKeysTitle;

  /// No description provided for @settingsServiceKeysSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitles, audiobooks and scraper keys you supply yourself'**
  String get settingsServiceKeysSubtitle;

  /// No description provided for @settingsServiceKeysCount.
  ///
  /// In en, this message translates to:
  /// **'{provided} of {total} set'**
  String settingsServiceKeysCount(int provided, int total);

  /// No description provided for @settingsDiscordTitle.
  ///
  /// In en, this message translates to:
  /// **'Discord Rich Presence'**
  String get settingsDiscordTitle;

  /// No description provided for @settingsDiscordEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Broadcasting movies, shows, music & live activity to Discord'**
  String get settingsDiscordEnabledSubtitle;

  /// No description provided for @settingsDiscordDisabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Disabled. Activity is hidden from Discord'**
  String get settingsDiscordDisabledSubtitle;

  /// No description provided for @settingsAppearanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance & Interface'**
  String get settingsAppearanceTitle;

  /// No description provided for @settingsAppearanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Liquid Glass setup, color themes, and Home Page UI'**
  String get settingsAppearanceSubtitle;

  /// No description provided for @settingsGlassOn.
  ///
  /// In en, this message translates to:
  /// **'Glass ON'**
  String get settingsGlassOn;

  /// No description provided for @settingsCalendarTitle.
  ///
  /// In en, this message translates to:
  /// **'TV Airing Calendar'**
  String get settingsCalendarTitle;

  /// No description provided for @settingsCalendarOnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Calendar buttons active on Home top bar and section headers'**
  String get settingsCalendarOnSubtitle;

  /// No description provided for @settingsCalendarOffSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Calendar disabled and hidden across all pages'**
  String get settingsCalendarOffSubtitle;

  /// No description provided for @settingsAiQuizTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Recommendation Quiz'**
  String get settingsAiQuizTitle;

  /// No description provided for @settingsAiQuizOnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'AI Taste Profile Quiz active on Home and Search bars'**
  String get settingsAiQuizOnSubtitle;

  /// No description provided for @settingsAiQuizOffSubtitle.
  ///
  /// In en, this message translates to:
  /// **'AI quiz disabled and hidden across all pages'**
  String get settingsAiQuizOffSubtitle;

  /// No description provided for @settingsAdultTitle.
  ///
  /// In en, this message translates to:
  /// **'Adult Content'**
  String get settingsAdultTitle;

  /// No description provided for @settingsAdultOnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'18+ catalogs, search results and sources are enabled'**
  String get settingsAdultOnSubtitle;

  /// No description provided for @settingsAdultOffSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hidden. No 18+ catalogs, search results or sources are fetched'**
  String get settingsAdultOffSubtitle;

  /// No description provided for @settingsBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore'**
  String get settingsBackupTitle;

  /// No description provided for @settingsBackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Export or import settings, theme and library progress (JSON)'**
  String get settingsBackupSubtitle;

  /// No description provided for @settingsBackupDialogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Cross-device JSON configuration'**
  String get settingsBackupDialogSubtitle;

  /// No description provided for @settingsBackupDescription.
  ///
  /// In en, this message translates to:
  /// **'Exports your settings, theme, My List and progress. Leave the passphrase blank for a redacted profile that keeps credentials, IPTV portals and addon URLs on this device. A passphrase encrypts a full profile with them included.'**
  String get settingsBackupDescription;

  /// No description provided for @settingsPassphraseOptional.
  ///
  /// In en, this message translates to:
  /// **'Passphrase (optional)'**
  String get settingsPassphraseOptional;

  /// No description provided for @settingsPassphraseHelper.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters for an encrypted full profile.'**
  String get settingsPassphraseHelper;

  /// No description provided for @settingsExportProfile.
  ///
  /// In en, this message translates to:
  /// **'Export Profile'**
  String get settingsExportProfile;

  /// No description provided for @settingsPassphraseTooShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least 8 characters for the passphrase.'**
  String get settingsPassphraseTooShort;

  /// No description provided for @settingsRedactedProfileCopied.
  ///
  /// In en, this message translates to:
  /// **'Redacted profile copied. Credentials, portals and addons stay on this device.'**
  String get settingsRedactedProfileCopied;

  /// No description provided for @settingsEncryptedProfileCopied.
  ///
  /// In en, this message translates to:
  /// **'Encrypted full profile copied. Keep the passphrase safe; it cannot be recovered.'**
  String get settingsEncryptedProfileCopied;

  /// No description provided for @settingsImportJson.
  ///
  /// In en, this message translates to:
  /// **'Import JSON'**
  String get settingsImportJson;

  /// No description provided for @settingsPasteJsonTitle.
  ///
  /// In en, this message translates to:
  /// **'Paste Configuration JSON'**
  String get settingsPasteJsonTitle;

  /// No description provided for @settingsPasteJsonHint.
  ///
  /// In en, this message translates to:
  /// **'Paste backup JSON here...'**
  String get settingsPasteJsonHint;

  /// No description provided for @settingsPassphraseEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Passphrase (encrypted profiles)'**
  String get settingsPassphraseEncrypted;

  /// No description provided for @settingsPassphraseEncryptedHelper.
  ///
  /// In en, this message translates to:
  /// **'Leave blank for a redacted profile. Encrypted profiles need the passphrase they were exported with.'**
  String get settingsPassphraseEncryptedHelper;

  /// No description provided for @settingsPasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from Clipboard'**
  String get settingsPasteFromClipboard;

  /// No description provided for @settingsFromFile.
  ///
  /// In en, this message translates to:
  /// **'From File'**
  String get settingsFromFile;

  /// No description provided for @settingsRestoreNow.
  ///
  /// In en, this message translates to:
  /// **'Restore Now'**
  String get settingsRestoreNow;

  /// No description provided for @settingsImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String settingsImportFailed(String error);

  /// No description provided for @settingsChooseProfile.
  ///
  /// In en, this message translates to:
  /// **'Choose a ZPlay profile'**
  String get settingsChooseProfile;

  /// No description provided for @settingsClearCacheTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear cache'**
  String get settingsClearCacheTitle;

  /// No description provided for @settingsClearCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Drop cached artwork & metadata. Sign-in, addons, My List & history stay'**
  String get settingsClearCacheSubtitle;

  /// No description provided for @settingsClearCacheConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear cache?'**
  String get settingsClearCacheConfirmTitle;

  /// No description provided for @settingsClearCacheConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Removes cached artwork and metadata so fresh copies are fetched. This does not sign you out or remove addons - your profile, My List, watch history and settings stay exactly as they are.'**
  String get settingsClearCacheConfirmBody;

  /// No description provided for @settingsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get settingsClear;

  /// No description provided for @settingsCacheArtwork.
  ///
  /// In en, this message translates to:
  /// **'artwork cache ({error})'**
  String settingsCacheArtwork(String error);

  /// No description provided for @settingsCacheMetadata.
  ///
  /// In en, this message translates to:
  /// **'metadata cache ({error})'**
  String settingsCacheMetadata(String error);

  /// No description provided for @settingsCacheHero.
  ///
  /// In en, this message translates to:
  /// **'hero artwork cache ({error})'**
  String settingsCacheHero(String error);

  /// No description provided for @settingsCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared.'**
  String get settingsCacheCleared;

  /// No description provided for @settingsCacheClearedExcept.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared except the {failures}.'**
  String settingsCacheClearedExcept(String failures);

  /// No description provided for @settingsCacheClearedSuffix.
  ///
  /// In en, this message translates to:
  /// **'You are still signed in - addons, My List, watch history and settings are untouched.'**
  String get settingsCacheClearedSuffix;

  /// No description provided for @settingsUpdatesTitle.
  ///
  /// In en, this message translates to:
  /// **'App Updates'**
  String get settingsUpdatesTitle;

  /// No description provided for @settingsUpdatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Check for latest software versions and patches'**
  String get settingsUpdatesSubtitle;

  /// No description provided for @settingsUpdatesCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get settingsUpdatesCheck;

  /// No description provided for @settingsDiagnosticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'App, device and player state (redacted) you can copy or save'**
  String get settingsDiagnosticsSubtitle;

  /// No description provided for @settingsLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'English, Arabic, or follow the device'**
  String get settingsLanguageSubtitle;

  /// No description provided for @settingsAboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About ZPlay'**
  String get settingsAboutTitle;

  /// No description provided for @settingsAboutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Architecture, video engine, and credits'**
  String get settingsAboutSubtitle;

  /// No description provided for @diagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsTitle;

  /// No description provided for @diagnosticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Local app, device and player report (no telemetry)'**
  String get diagnosticsSubtitle;

  /// No description provided for @diagnosticsDescription.
  ///
  /// In en, this message translates to:
  /// **'A local-only snapshot of this install: app and device details, player settings, the stream engine state and the recent crash breadcrumbs. Credentials, addon URLs, IPTV portals and playlist links are never included. Nothing is uploaded - the report only exists once you copy or save it.'**
  String get diagnosticsDescription;

  /// No description provided for @diagnosticsSectionDevice.
  ///
  /// In en, this message translates to:
  /// **'DEVICE'**
  String get diagnosticsSectionDevice;

  /// No description provided for @diagnosticsSectionPlayerEngine.
  ///
  /// In en, this message translates to:
  /// **'PLAYER & ENGINE'**
  String get diagnosticsSectionPlayerEngine;

  /// No description provided for @diagnosticsSectionBreadcrumbs.
  ///
  /// In en, this message translates to:
  /// **'CRASH BREADCRUMBS'**
  String get diagnosticsSectionBreadcrumbs;

  /// No description provided for @diagnosticsSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get diagnosticsSummary;

  /// No description provided for @diagnosticsNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get diagnosticsNotAvailable;

  /// No description provided for @diagnosticsBreadcrumbCount.
  ///
  /// In en, this message translates to:
  /// **'{count} recorded • last {shown} shown'**
  String diagnosticsBreadcrumbCount(int count, int shown);

  /// No description provided for @diagnosticsBreadcrumbs.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get diagnosticsBreadcrumbs;

  /// No description provided for @diagnosticsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No breadcrumbs recorded yet.'**
  String get diagnosticsEmpty;

  /// No description provided for @diagnosticsCopied.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics report copied.'**
  String get diagnosticsCopied;

  /// No description provided for @diagnosticsCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic report copied to clipboard'**
  String get diagnosticsCopiedToClipboard;

  /// No description provided for @diagnosticsCopyFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not copy the report'**
  String get diagnosticsCopyFailed;

  /// No description provided for @diagnosticsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the report'**
  String get diagnosticsSaveFailed;

  /// No description provided for @diagnosticsSaved.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics saved to {path}'**
  String diagnosticsSaved(String path);

  /// No description provided for @searchHintTv.
  ///
  /// In en, this message translates to:
  /// **'Search for a movie or series'**
  String get searchHintTv;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search movies, series, or paste links'**
  String get searchHint;

  /// No description provided for @searchVoice.
  ///
  /// In en, this message translates to:
  /// **'Search by voice'**
  String get searchVoice;

  /// No description provided for @searchVoiceDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone access is off. Allow it for ZPlay to search by voice.'**
  String get searchVoiceDenied;

  /// No description provided for @searchAiQuiz.
  ///
  /// In en, this message translates to:
  /// **'AI Taste Quiz'**
  String get searchAiQuiz;

  /// No description provided for @searchPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste from clipboard'**
  String get searchPaste;

  /// No description provided for @searchFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Search could not reach its sources'**
  String get searchFailureTitle;

  /// No description provided for @searchFailureBody.
  ///
  /// In en, this message translates to:
  /// **'{failed} of {total} sources did not respond'**
  String searchFailureBody(int failed, int total);

  /// No description provided for @searchFailureAdvice.
  ///
  /// In en, this message translates to:
  /// **'A dead addon or an expired provider runtime is fixed in Addons.'**
  String get searchFailureAdvice;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results for \"{query}\"'**
  String searchNoResults(String query);

  /// No description provided for @searchingMoreSources.
  ///
  /// In en, this message translates to:
  /// **'Searching more sources...'**
  String get searchingMoreSources;

  /// No description provided for @searchPartialFailure.
  ///
  /// In en, this message translates to:
  /// **'Partial Source Failure: {sources} did not respond. Other sources answered normally, so the results below are real but incomplete.'**
  String searchPartialFailure(String sources);

  /// No description provided for @searchRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent Searches'**
  String get searchRecent;

  /// No description provided for @searchClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get searchClearAll;

  /// No description provided for @searchTrending.
  ///
  /// In en, this message translates to:
  /// **'Trending & Suggested'**
  String get searchTrending;

  /// No description provided for @searchNothingToSuggest.
  ///
  /// In en, this message translates to:
  /// **'Nothing to suggest yet'**
  String get searchNothingToSuggest;

  /// No description provided for @searchNothingToSuggestBody.
  ///
  /// In en, this message translates to:
  /// **'Search for a title above, or connect an addon in Settings to have something to search.'**
  String get searchNothingToSuggestBody;

  /// No description provided for @searchPinnedSpine.
  ///
  /// In en, this message translates to:
  /// **'PINNED SPINE'**
  String get searchPinnedSpine;

  /// No description provided for @searchCloudstreamSection.
  ///
  /// In en, this message translates to:
  /// **'CloudStream • {provider}'**
  String searchCloudstreamSection(String provider);

  /// No description provided for @searchCloudstreamExtension.
  ///
  /// In en, this message translates to:
  /// **'CloudStream Extension'**
  String get searchCloudstreamExtension;

  /// No description provided for @searchTitlesSection.
  ///
  /// In en, this message translates to:
  /// **'Titles'**
  String get searchTitlesSection;

  /// No description provided for @searchImdbSuggestions.
  ///
  /// In en, this message translates to:
  /// **'IMDb suggestions'**
  String get searchImdbSuggestions;

  /// No description provided for @searchDirectStream.
  ///
  /// In en, this message translates to:
  /// **'Direct Stream'**
  String get searchDirectStream;

  /// No description provided for @searchSourceTitleLookup.
  ///
  /// In en, this message translates to:
  /// **'Title lookup'**
  String get searchSourceTitleLookup;

  /// No description provided for @playerSeekBack.
  ///
  /// In en, this message translates to:
  /// **'Seek -10s'**
  String get playerSeekBack;

  /// No description provided for @playerSeekForward.
  ///
  /// In en, this message translates to:
  /// **'Seek +10s'**
  String get playerSeekForward;

  /// No description provided for @playerPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get playerPlay;

  /// No description provided for @playerPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get playerPause;

  /// No description provided for @playerMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get playerMute;

  /// No description provided for @playerUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get playerUnmute;

  /// No description provided for @playerPreviousEpisode.
  ///
  /// In en, this message translates to:
  /// **'Previous Episode'**
  String get playerPreviousEpisode;

  /// No description provided for @playerNextEpisode.
  ///
  /// In en, this message translates to:
  /// **'Next Episode'**
  String get playerNextEpisode;

  /// No description provided for @playerEpisodes.
  ///
  /// In en, this message translates to:
  /// **'Episodes'**
  String get playerEpisodes;

  /// No description provided for @playerAspectRatio.
  ///
  /// In en, this message translates to:
  /// **'Aspect Ratio (C)'**
  String get playerAspectRatio;

  /// No description provided for @playerPlaybackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Playback Speed'**
  String get playerPlaybackSpeed;

  /// No description provided for @playerAudioTracks.
  ///
  /// In en, this message translates to:
  /// **'Audio Tracks'**
  String get playerAudioTracks;

  /// No description provided for @playerSubtitles.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get playerSubtitles;

  /// No description provided for @playerSubtitleSync.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Sync'**
  String get playerSubtitleSync;

  /// No description provided for @playerFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen (F)'**
  String get playerFullscreen;

  /// No description provided for @playerExitFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Exit Fullscreen (F)'**
  String get playerExitFullscreen;

  /// No description provided for @playerVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume {percent}%'**
  String playerVolume(int percent);

  /// No description provided for @playerSeekPosition.
  ///
  /// In en, this message translates to:
  /// **'{position} of {duration}'**
  String playerSeekPosition(String position, String duration);

  /// No description provided for @a11yOpenDetails.
  ///
  /// In en, this message translates to:
  /// **'Open details'**
  String get a11yOpenDetails;

  /// No description provided for @a11yResume.
  ///
  /// In en, this message translates to:
  /// **'Resume {title}, {percent}% watched'**
  String a11yResume(String title, int percent);

  /// No description provided for @emptyMyList.
  ///
  /// In en, this message translates to:
  /// **'Your list is empty'**
  String get emptyMyList;

  /// No description provided for @emptyMyListBody.
  ///
  /// In en, this message translates to:
  /// **'Save your favorite movies and TV shows to watch anytime'**
  String get emptyMyListBody;

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// No description provided for @languageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'App language. System follows your device.'**
  String get languageSubtitle;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get languageArabic;

  /// No description provided for @a11yResumePlayback.
  ///
  /// In en, this message translates to:
  /// **'Resume playback'**
  String get a11yResumePlayback;

  /// No description provided for @playerPlaybackPosition.
  ///
  /// In en, this message translates to:
  /// **'Playback position'**
  String get playerPlaybackPosition;

  /// No description provided for @playerVolumeLabel.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get playerVolumeLabel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
