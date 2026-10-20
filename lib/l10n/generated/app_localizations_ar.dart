// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'ZPlay';

  @override
  String get navHome => 'الرئيسية';

  @override
  String get navBrowse => 'تصفح';

  @override
  String get navSearch => 'بحث';

  @override
  String get navLibrary => 'المكتبة';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get navLiveTv => 'البث المباشر';

  @override
  String get actionCancel => 'إلغاء';

  @override
  String get actionClose => 'إغلاق';

  @override
  String get actionRetry => 'إعادة المحاولة';

  @override
  String get actionTryAgain => 'المحاولة مرة أخرى';

  @override
  String get actionCopy => 'نسخ';

  @override
  String get actionSave => 'حفظ';

  @override
  String get actionCopyReport => 'نسخ التقرير';

  @override
  String get actionSaveReport => 'حفظ التقرير';

  @override
  String get actionCopyDiagnostic => 'نسخ التشخيص';

  @override
  String get shellFullscreen => 'ملء الشاشة';

  @override
  String get shellExitFullscreen => 'الخروج من ملء الشاشة';

  @override
  String get shellFullscreenTooltip => 'ملء الشاشة (F11)';

  @override
  String get shellExitFullscreenTooltip => 'الخروج من ملء الشاشة (F11)';

  @override
  String get errorLoadFailed => 'تعذّر تحميل الأفلام';

  @override
  String get errorUnknown => 'خطأ غير معروف';

  @override
  String get listSeparator => '، ';

  @override
  String get shortcutsTitle => 'اختصارات لوحة المفاتيح';

  @override
  String get shortcutsClose => 'إغلاق اختصارات لوحة المفاتيح';

  @override
  String get shortcutsGroupAnywhere => 'في أي مكان';

  @override
  String get shortcutsGroupMoving => 'التنقل';

  @override
  String get shortcutsGroupPlaying => 'أثناء التشغيل';

  @override
  String get shortcutsGroupReading => 'أثناء القراءة';

  @override
  String get shortcutsShowSheet => 'إظهار هذه القائمة';

  @override
  String get shortcutsShowSheetNote => 'أيضًا Shift + /';

  @override
  String get shortcutsToggleFullscreen => 'تبديل ملء الشاشة';

  @override
  String get shortcutsLeaveFullscreen =>
      'الخروج من ملء الشاشة أو إغلاق ما هو مفتوح';

  @override
  String get shortcutsLeaveFullscreenNote =>
      'لا ينتقل بعيدًا عن الصفحة من تلقاء نفسه';

  @override
  String get shortcutsMyList => 'قائمتي والتنزيلات';

  @override
  String get shortcutsSearchMacNote => 'Cmd + K على macOS';

  @override
  String get shortcutsSettingsMacNote => 'Cmd + , على macOS';

  @override
  String get shortcutsPlayPause => 'تشغيل أو إيقاف مؤقت';

  @override
  String get shortcutsPlayPauseNote => 'المفتاح K يفعل الشيء نفسه';

  @override
  String get shortcutsSeek => 'للخلف أو للأمام ١٠ ثوانٍ';

  @override
  String get shortcutsSeekNote =>
      'تعمل مفاتيح الأسهم بذلك أيضًا عندما يكون الفيديو في التركيز';

  @override
  String get shortcutsMute => 'كتم الصوت أو إعادته';

  @override
  String get shortcutsAspect => 'تغيير طريقة ملء الفيديو للشاشة';

  @override
  String get shortcutsPage => 'الصفحة أو الفصل السابق أو التالي';

  @override
  String get shortcutsLine => 'سطر لأسفل أو لأعلى في وضع التركيز';

  @override
  String nowPlayingSemantics(String title, String subtitle) {
    return 'يُشغَّل الآن $title، $subtitle';
  }

  @override
  String get nowPlayingOpenHint => 'فتح المشغّل الكامل';

  @override
  String get playerPrevious => 'السابق';

  @override
  String get playerNext => 'التالي';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get settingsSectionPlayback => 'التشغيل';

  @override
  String get settingsSectionSources => 'المصادر';

  @override
  String get settingsSectionIntegrations => 'التكاملات';

  @override
  String get settingsSectionAppearance => 'المظهر';

  @override
  String get settingsSectionContent => 'المحتوى';

  @override
  String get settingsSectionApp => 'التطبيق';

  @override
  String get stateEnabled => 'مفعّل';

  @override
  String get stateDisabled => 'معطّل';

  @override
  String get stateActive => 'نشط';

  @override
  String get stateOffline => 'غير متصل';

  @override
  String get stateConnected => 'متصل';

  @override
  String get stateNotSet => 'غير مضبوط';

  @override
  String get stateOn => 'مفعّل';

  @override
  String get stateOff => 'متوقف';

  @override
  String get settingsVideoTitle => 'الفيديو والتحسين';

  @override
  String get settingsVideoSubtitle =>
      'إعدادات Anime4K لتظليل GLSL العصبي ومسار GPU';

  @override
  String get settingsP2pTitle => 'مصدر التورنت P2P المدمج';

  @override
  String get settingsP2pActiveSubtitle =>
      'أسراب تورنت ZPlay (Knaben، TorrentGalaxy) نشطة';

  @override
  String get settingsP2pDisabledSubtitle =>
      'P2P معطّل. يُستخدم البث المباشر عبر HTTP فقط (ZPlayHTTP)';

  @override
  String get settingsP2pActiveValue => 'P2P نشط';

  @override
  String get settingsP2pHttpValue => 'HTTP فقط';

  @override
  String get settingsP2pInfoTooltip => 'تفاصيل تنبيه P2P';

  @override
  String get settingsAddonsTitle => 'الإضافات';

  @override
  String get settingsAddonsSubtitle => 'كتالوجات Stremio ومزوّدو المحتوى';

  @override
  String settingsAddonsInstalled(int count) {
    return '$count مثبّتة';
  }

  @override
  String get settingsBuiltinTitle => 'المزوّدون المدمجون';

  @override
  String get settingsBuiltinSubtitle =>
      'مصادر بث ZPlayHTTP وترتيب الأولوية ومفاتيح التبديل';

  @override
  String get settingsBuiltinCustom => 'مخصّص';

  @override
  String get settingsBuiltinDefault => 'افتراضي';

  @override
  String get settingsDebridTitle => 'Debrid والبث السحابي';

  @override
  String get settingsDebridSubtitle =>
      'Real-Debrid وTorBox وAllDebrid وPremiumize وDebrid-Link';

  @override
  String get settingsTraktTitle => 'مزامنة Trakt.tv';

  @override
  String get settingsTraktSubtitle =>
      'مزامنة قائمة المشاهدة والسجل والتشغيل عبر الأجهزة';

  @override
  String get settingsSimklTitle => 'مزامنة Simkl';

  @override
  String get settingsSimklSubtitle =>
      'مزامنة الأفلام والمسلسلات والأنمي عبر الأجهزة';

  @override
  String get settingsTmdbTitle => 'مفتاح TMDb API';

  @override
  String get settingsTmdbSubtitle =>
      'مفتاحك الخاص لصفوف التسعينيات المرتّبة وبيانات الكاشط';

  @override
  String get settingsTmdbYourKey => 'مفتاحك';

  @override
  String get settingsServiceKeysTitle => 'مفاتيح API للخدمات';

  @override
  String get settingsServiceKeysSubtitle =>
      'مفاتيح الترجمة والكتب الصوتية والكاشط التي توفّرها بنفسك';

  @override
  String settingsServiceKeysCount(int provided, int total) {
    return '$provided من $total مضبوطة';
  }

  @override
  String get settingsDiscordTitle => 'Discord Rich Presence';

  @override
  String get settingsDiscordEnabledSubtitle =>
      'بث الأفلام والمسلسلات والموسيقى والنشاط المباشر إلى Discord';

  @override
  String get settingsDiscordDisabledSubtitle => 'معطّل. النشاط مخفي من Discord';

  @override
  String get settingsAppearanceTitle => 'المظهر والواجهة';

  @override
  String get settingsAppearanceSubtitle =>
      'إعداد Liquid Glass والألوان وواجهة الصفحة الرئيسية';

  @override
  String get settingsGlassOn => 'الزجاج مفعّل';

  @override
  String get settingsCalendarTitle => 'تقويم بث المسلسلات';

  @override
  String get settingsCalendarOnSubtitle =>
      'أزرار التقويم مفعّلة في شريط الرئيسية ورؤوس الأقسام';

  @override
  String get settingsCalendarOffSubtitle => 'التقويم معطّل ومخفي في كل الصفحات';

  @override
  String get settingsAiQuizTitle => 'اختبار التوصيات بالذكاء الاصطناعي';

  @override
  String get settingsAiQuizOnSubtitle =>
      'اختبار الذوق مفعّل في شريط الرئيسية والبحث';

  @override
  String get settingsAiQuizOffSubtitle =>
      'اختبار الذكاء الاصطناعي معطّل ومخفي في كل الصفحات';

  @override
  String get settingsAdultTitle => 'المحتوى للبالغين';

  @override
  String get settingsAdultOnSubtitle =>
      'كتالوجات +18 ونتائج البحث والمصادر مفعّلة';

  @override
  String get settingsAdultOffSubtitle =>
      'مخفي. لا تُجلب كتالوجات أو نتائج بحث أو مصادر +18';

  @override
  String get settingsBackupTitle => 'النسخ الاحتياطي والاستعادة';

  @override
  String get settingsBackupSubtitle =>
      'تصدير أو استيراد الإعدادات والسمة وتقدّم المكتبة (JSON)';

  @override
  String get settingsBackupDialogSubtitle => 'إعداد JSON عبر الأجهزة';

  @override
  String get settingsBackupDescription =>
      'يصدّر إعداداتك وسمتك وقائمتي وتقدّمك. اترك عبارة المرور فارغة لملف شخصي منقّح يُبقي بيانات الاعتماد وبوابات IPTV وعناوين الإضافات على هذا الجهاز. وعبارة المرور تشفّر ملفًا كاملًا يتضمنها.';

  @override
  String get settingsPassphraseOptional => 'عبارة المرور (اختياري)';

  @override
  String get settingsPassphraseHelper =>
      '٨ أحرف على الأقل لملف شخصي كامل مشفّر.';

  @override
  String get settingsExportProfile => 'تصدير الملف الشخصي';

  @override
  String get settingsPassphraseTooShort =>
      'استخدم ٨ أحرف على الأقل لعبارة المرور.';

  @override
  String get settingsRedactedProfileCopied =>
      'نُسخ الملف المنقّح. تبقى بيانات الاعتماد والبوابات والإضافات على هذا الجهاز.';

  @override
  String get settingsEncryptedProfileCopied =>
      'نُسخ الملف الكامل المشفّر. احفظ عبارة المرور بأمان؛ لا يمكن استعادتها.';

  @override
  String get settingsImportJson => 'استيراد JSON';

  @override
  String get settingsPasteJsonTitle => 'لصق إعداد JSON';

  @override
  String get settingsPasteJsonHint => 'الصق JSON النسخة الاحتياطية هنا...';

  @override
  String get settingsPassphraseEncrypted => 'عبارة المرور (الملفات المشفّرة)';

  @override
  String get settingsPassphraseEncryptedHelper =>
      'اتركها فارغة لملف منقّح. الملفات المشفّرة تحتاج عبارة المرور التي صُدّرت بها.';

  @override
  String get settingsPasteFromClipboard => 'لصق من الحافظة';

  @override
  String get settingsFromFile => 'من ملف';

  @override
  String get settingsRestoreNow => 'استعادة الآن';

  @override
  String settingsImportFailed(String error) {
    return 'فشل الاستيراد: $error';
  }

  @override
  String get settingsChooseProfile => 'اختر ملف ZPlay';

  @override
  String get settingsClearCacheTitle => 'مسح ذاكرة التخزين المؤقت';

  @override
  String get settingsClearCacheSubtitle =>
      'حذف الصور والبيانات الوصفية المخزّنة. يبقى تسجيل الدخول والإضافات وقائمتي والسجل';

  @override
  String get settingsClearCacheConfirmTitle => 'مسح ذاكرة التخزين المؤقت؟';

  @override
  String get settingsClearCacheConfirmBody =>
      'يحذف الصور والبيانات الوصفية المخزّنة لتُجلب نسخ جديدة. لا يسجّل خروجك ولا يحذف الإضافات - يبقى ملفك الشخصي وقائمتي وسجل المشاهدة والإعدادات كما هي تمامًا.';

  @override
  String get settingsClear => 'مسح';

  @override
  String settingsCacheArtwork(String error) {
    return 'ذاكرة الصور ($error)';
  }

  @override
  String settingsCacheMetadata(String error) {
    return 'ذاكرة البيانات الوصفية ($error)';
  }

  @override
  String settingsCacheHero(String error) {
    return 'ذاكرة صور الواجهة ($error)';
  }

  @override
  String get settingsCacheCleared => 'تم مسح ذاكرة التخزين المؤقت.';

  @override
  String settingsCacheClearedExcept(String failures) {
    return 'تم المسح باستثناء $failures.';
  }

  @override
  String get settingsCacheClearedSuffix =>
      'ما زلت مسجّل الدخول - الإضافات وقائمتي وسجل المشاهدة والإعدادات دون تغيير.';

  @override
  String get settingsUpdatesTitle => 'تحديثات التطبيق';

  @override
  String get settingsUpdatesSubtitle =>
      'التحقق من أحدث إصدارات البرامج والتصحيحات';

  @override
  String get settingsUpdatesCheck => 'تحقّق';

  @override
  String get settingsDiagnosticsSubtitle =>
      'حالة التطبيق والجهاز والمشغّل (منقّحة) يمكنك نسخها أو حفظها';

  @override
  String get settingsLanguageSubtitle =>
      'الإنجليزية أو العربية أو اتباع الجهاز';

  @override
  String get settingsAboutTitle => 'حول ZPlay';

  @override
  String get settingsAboutSubtitle => 'البنية ومحرّك الفيديو والشكر';

  @override
  String get diagnosticsTitle => 'التشخيص';

  @override
  String get diagnosticsSubtitle =>
      'تقرير محلي عن التطبيق والجهاز والمشغّل (دون إرسال أي بيانات)';

  @override
  String get diagnosticsDescription =>
      'لقطة محلية فقط لهذا التثبيت: تفاصيل التطبيق والجهاز وإعدادات المشغّل وحالة محرّك البث وآثار الأعطال الأخيرة. لا تُضمَّن بيانات الاعتماد أو عناوين الإضافات أو بوابات IPTV أو روابط قوائم التشغيل أبدًا. لا يُرفع أي شيء - لا يوجد التقرير إلا بعد نسخه أو حفظه.';

  @override
  String get diagnosticsSectionDevice => 'الجهاز';

  @override
  String get diagnosticsSectionPlayerEngine => 'المشغّل والمحرّك';

  @override
  String get diagnosticsSectionBreadcrumbs => 'آثار الأعطال الأخيرة';

  @override
  String get diagnosticsSummary => 'الملخص';

  @override
  String get diagnosticsNotAvailable => 'غير متاح';

  @override
  String diagnosticsBreadcrumbCount(int count, int shown) {
    return '$count مسجّل • آخر $shown معروض';
  }

  @override
  String get diagnosticsBreadcrumbs => 'النشاط الأخير';

  @override
  String get diagnosticsEmpty => 'لم يُسجَّل أي نشاط بعد.';

  @override
  String get diagnosticsCopied => 'تم نسخ تقرير التشخيص.';

  @override
  String get diagnosticsCopiedToClipboard => 'تم نسخ تقرير التشخيص إلى الحافظة';

  @override
  String get diagnosticsCopyFailed => 'تعذّر نسخ التقرير';

  @override
  String get diagnosticsSaveFailed => 'تعذّر حفظ التقرير';

  @override
  String diagnosticsSaved(String path) {
    return 'تم حفظ التشخيص في $path';
  }

  @override
  String get searchHintTv => 'ابحث عن فيلم أو مسلسل';

  @override
  String get searchHint => 'ابحث عن أفلام أو مسلسلات أو الصق الروابط';

  @override
  String get searchVoice => 'البحث بالصوت';

  @override
  String get searchVoiceDenied =>
      'إذن الميكروفون مغلق. اسمح به لـ ZPlay للبحث بالصوت.';

  @override
  String get searchAiQuiz => 'اختبار الذوق بالذكاء الاصطناعي';

  @override
  String get searchPaste => 'لصق من الحافظة';

  @override
  String get searchFailureTitle => 'تعذّر على البحث الوصول إلى مصادره';

  @override
  String searchFailureBody(int failed, int total) {
    return '$failed من $total مصادر لم تستجب';
  }

  @override
  String get searchFailureAdvice =>
      'يُعالج أي إضافة معطّلة أو وقت تشغيل مزوّد منتهٍ من صفحة الإضافات.';

  @override
  String searchNoResults(String query) {
    return 'لا توجد نتائج لـ \"$query\"';
  }

  @override
  String get searchingMoreSources => 'جارٍ البحث في مزيد من المصادر...';

  @override
  String searchPartialFailure(String sources) {
    return 'فشل جزئي في المصادر: لم تستجب $sources. أجابت مصادر أخرى بشكل طبيعي، لذا النتائج أدناه حقيقية لكنها غير مكتملة.';
  }

  @override
  String get searchRecent => 'عمليات البحث الأخيرة';

  @override
  String get searchClearAll => 'مسح الكل';

  @override
  String get searchTrending => 'الرائج والمقترح';

  @override
  String get searchNothingToSuggest => 'لا يوجد ما يُقترح بعد';

  @override
  String get searchNothingToSuggestBody =>
      'ابحث عن عنوان في الأعلى، أو اربط إضافة من الإعدادات ليكون لديك ما تبحث فيه.';

  @override
  String get searchPinnedSpine => 'العمود الأساسي';

  @override
  String searchCloudstreamSection(String provider) {
    return 'CloudStream • $provider';
  }

  @override
  String get searchCloudstreamExtension => 'إضافة CloudStream';

  @override
  String get searchTitlesSection => 'العناوين';

  @override
  String get searchImdbSuggestions => 'اقتراحات IMDb';

  @override
  String get searchDirectStream => 'بث مباشر';

  @override
  String get searchSourceTitleLookup => 'البحث بالعنوان';

  @override
  String get playerSeekBack => 'تقديم ١٠ ثوانٍ للخلف';

  @override
  String get playerSeekForward => 'تقديم ١٠ ثوانٍ للأمام';

  @override
  String get playerPlay => 'تشغيل';

  @override
  String get playerPause => 'إيقاف مؤقت';

  @override
  String get playerMute => 'كتم الصوت';

  @override
  String get playerUnmute => 'إعادة الصوت';

  @override
  String get playerPreviousEpisode => 'الحلقة السابقة';

  @override
  String get playerNextEpisode => 'الحلقة التالية';

  @override
  String get playerEpisodes => 'الحلقات';

  @override
  String get playerAspectRatio => 'نسبة العرض (C)';

  @override
  String get playerPlaybackSpeed => 'سرعة التشغيل';

  @override
  String get playerAudioTracks => 'المسارات الصوتية';

  @override
  String get playerSubtitles => 'الترجمة';

  @override
  String get playerSubtitleSync => 'مزامنة الترجمة';

  @override
  String get playerFullscreen => 'ملء الشاشة (F)';

  @override
  String get playerExitFullscreen => 'الخروج من ملء الشاشة (F)';

  @override
  String playerVolume(int percent) {
    return 'مستوى الصوت $percent%';
  }

  @override
  String playerSeekPosition(String position, String duration) {
    return '$position من $duration';
  }

  @override
  String get a11yOpenDetails => 'فتح التفاصيل';

  @override
  String a11yResume(String title, int percent) {
    return 'متابعة $title، شوهد $percent%';
  }

  @override
  String get emptyMyList => 'قائمتك فارغة';

  @override
  String get emptyMyListBody =>
      'احفظ أفلامك ومسلسلاتك المفضلة لمشاهدتها في أي وقت';

  @override
  String get languageTitle => 'اللغة';

  @override
  String get languageSubtitle => 'لغة التطبيق. يتبع خيار «النظام» لغة جهازك.';

  @override
  String get languageSystem => 'النظام';

  @override
  String get languageEnglish => 'الإنجليزية';

  @override
  String get languageArabic => 'العربية';

  @override
  String get a11yResumePlayback => 'متابعة التشغيل';

  @override
  String get playerPlaybackPosition => 'موضع التشغيل';

  @override
  String get playerVolumeLabel => 'مستوى الصوت';
}
