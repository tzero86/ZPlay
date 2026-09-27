import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Subtitle styling preset for rapid 1-tap appearance selection.
enum SubtitleStylePreset {
  classicWhite('Classic White', 'Crisp white text with black outline', '#FFFFFFFF', '#00000000', '#FF000000', 2.0, 0.0, '#00000000', false, false),
  cinemaYellow('Cinema Yellow', 'Warm yellow text with subtle shadow and border', '#FFFFEB3B', '#00000000', '#FF000000', 2.5, 1.5, '#80000000', false, false),
  streamingBox('Streaming Box', 'White text inside a 50% translucent black box', '#FFFFFFFF', '#80000000', '#00000000', 0.0, 0.0, '#00000000', false, false),
  highContrast('High Contrast', 'Bold yellow text with solid opaque black box', '#FFFFD600', '#FF000000', '#FF000000', 0.0, 0.0, '#00000000', true, false),
  animeClean('Anime Clean', 'Bold white text with deep outline & shadow', '#FFFFFFFF', '#00000000', '#FF000000', 3.5, 2.0, '#BF000000', true, false),
  cyberpunkCyan('Cyberpunk Cyan', 'Vibrant cyan text with dark border', '#00E5FF', '#00000000', '#FF0D111A', 2.5, 1.0, '#6600E5FF', false, false),
  nightModeSoft('Night Mode Warm', 'Soft cream text with 40% translucent background', '#FFF8E1', '#66000000', '#00000000', 0.0, 0.0, '#00000000', false, false),
  custom('Custom', 'User configured custom subtitle styles', '#FFFFFFFF', '#00000000', '#FF000000', 2.0, 0.0, '#00000000', false, false);

  final String label;
  final String description;
  final String textColor;
  final String backColor;
  final String borderColor;
  final double borderSize;
  final double shadowOffset;
  final String shadowColor;
  final bool bold;
  final bool italic;

  const SubtitleStylePreset(
    this.label,
    this.description,
    this.textColor,
    this.backColor,
    this.borderColor,
    this.borderSize,
    this.shadowOffset,
    this.shadowColor,
    this.bold,
    this.italic,
  );
}

/// Anime4K GLSL shader upscaling presets for libmpv / media_kit.
enum Anime4KPreset {
  off(
    'Off',
    'Standard video playback without neural upscaling shaders',
    [],
  ),
  modeAFast(
    'Mode A (Fast / Balanced)',
    'Restores line art and upscales cleanly. Balanced GPU load, ideal for 1080p anime and mobile/integrated GPUs.',
    [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_M.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_AutoDownscalePre_x4.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
    ],
  ),
  modeAHQ(
    'Mode A (High Quality / HQ)',
    'Ultra-crisp perceptual line reconstruction and upscale using Very Large CNNs. Best for discrete desktop GPUs.',
    [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_VL.glsl',
      'Anime4K_Upscale_CNN_x2_VL.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_AutoDownscalePre_x4.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
    ],
  ),
  modeB(
    'Mode B (Soft / Denoise)',
    'Soft line reconstruction and artifact reduction. Best for blurry, compressed, or older anime.',
    [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_Soft_M.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_AutoDownscalePre_x4.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
    ],
  ),
  modeC(
    'Mode C (Deblur / Upscale)',
    'Aggressive deblurring and scaling. Best for 720p / 480p low-resolution anime streams.',
    [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_AutoDownscalePre_x4.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
    ],
  ),

  /// AMD FidelityFX Super Resolution 1.0, the edge-adaptive spatial pass only.
  ///
  /// FSR 1 is a single-frame spatial upscaler, which is why it works at all
  /// here: a libmpv GLSL shader has no motion vectors and no depth buffer, so
  /// the temporal FSR 2/3 and DLSS paths are not reachable from a player. This
  /// is the portable option — it runs on every GPU the app runs on, unlike
  /// NVIDIA's RTX Video Super Resolution.
  fsrEasu(
    'FSR 1.0 (Smooth)',
    'Edge-adaptive upscaling for live action and older sources. Upscales rather '
        'than sharpens, so it is the safer of the two FSR modes. Not useful on '
        'a source already at display resolution.',
    [
      'FSR_EASU.glsl',
    ],
  ),

  /// FSR 1.0 with the RCAS sharpening pass.
  ///
  /// The sharper of the two, and the one that can make things worse: on an
  /// already-sharp source RCAS amplifies compression ringing instead of
  /// adding detail. That is why it is a separate choice rather than always-on.
  fsrEasuRcas(
    'FSR 1.0 (Sharp)',
    'FSR with contrast-adaptive sharpening. Adds bite to soft or low-bitrate '
        'sources. On a 2K or 4K source this can look worse than no upscaling, '
        'so use it deliberately.',
    [
      'FSR_EASU.glsl',
      'FSR_RCAS.glsl',
    ],
  );

  final String label;
  final String description;
  final List<String> shaderFiles;

  const Anime4KPreset(
    this.label,
    this.description,
    this.shaderFiles,
  );

  /// True for the FSR modes, which are aimed at live action and film rather
  /// than at drawn line art. Used to decide whether the source-resolution
  /// warning applies, since sharpening an already-high-resolution source is
  /// the case worth warning about and Anime4K has its own trade-offs.
  bool get isFsr => this == fsrEasu || this == fsrEasuRcas;

  /// True for the Anime4K presets, which are the only ones that should be
  /// described as neural line-art reconstruction.
  bool get isAnime4k =>
      this != off && this != fsrEasu && this != fsrEasuRcas;
}

/// Hardware acceleration mode for video decoding in media_kit / libmpv.
enum HardwareAccelerationMode {
  autoSafe(
    'Auto-Safe (Hardware Accelerated)',
    'auto-safe',
    'GPU hardware decoding with safe driver fallbacks (recommended)',
  ),
  software(
    'Software Decoding (Crash-Proof)',
    'no',
    'Pure CPU decoding using FFmpeg libavcodec. Guarantees frame rendering and eliminates black screens.',
  ),
  forceHardware(
    'Direct Hardware',
    'auto',
    'Direct GPU hardware decoding (Direct3D 11 / MediaCodec / VAAPI).',
  );

  final String label;
  final String mpvValue;
  final String description;

  const HardwareAccelerationMode(
    this.label,
    this.mpvValue,
    this.description,
  );
}

/// What a source resolution means for the selected upscaling mode.
///
/// Upscalers help when the source is smaller than the panel and hurt when it
/// is not: sharpening a 4K transfer on a 4K panel amplifies compression
/// ringing rather than adding detail, and that is not something a user can be
/// expected to discover by looking at the result.
enum UpscaleAdvisory {
  /// No upscaling is selected, so there is nothing to advise about.
  notApplicable,

  /// The source is being enlarged, which is what an upscaler is for.
  beneficial,

  /// Source and panel are about the same size, so the mode does very little.
  neutral,

  /// The source already meets or exceeds the panel.
  notRecommended,
}

/// Classifies a source resolution against the panel it is shown on.
///
/// [sourceWidth] and [sourceHeight] come from the decoder; [displayWidth] and
/// [displayHeight] from the laid-out video pane. The comparison is the
/// letterboxed scale rather than raw width, so a 1920x800 film on a 16:9 panel
/// is not mistaken for a 4K source.
UpscaleAdvisory adviseForUpscaling({
  required Anime4KPreset preset,
  required int sourceWidth,
  required int sourceHeight,
  required double displayWidth,
  required double displayHeight,
}) {
  if (preset == Anime4KPreset.off) return UpscaleAdvisory.notApplicable;
  if (sourceWidth <= 0 || sourceHeight <= 0) return UpscaleAdvisory.neutral;
  if (displayWidth <= 0 || displayHeight <= 0) return UpscaleAdvisory.neutral;

  final byWidth = displayWidth / sourceWidth;
  final byHeight = displayHeight / sourceHeight;
  final scale = byWidth < byHeight ? byWidth : byHeight;

  if (scale > 1.15) return UpscaleAdvisory.beneficial;

  // A source that already fills the panel is the case worth warning about, and
  // that includes an exact match rather than only a source that overshoots it.
  // A 4K transfer on a 4K panel is a scale of exactly 1.0, so an earlier rule
  // that only warned above 1.0 let the most common case through unflagged.
  if (scale <= 1.0) return UpscaleAdvisory.notRecommended;

  // Between 1.0 and 1.15 the source is being enlarged, just marginally. The
  // smoothing pass has little to add and does little harm; the sharpening pass
  // has little to add and ringing to amplify, so it is the one still flagged.
  return preset == Anime4KPreset.fsrEasuRcas
      ? UpscaleAdvisory.notRecommended
      : UpscaleAdvisory.neutral;
}

/// One-line explanation of [UpscaleAdvisory] for the settings and player copy.
String describeUpscaleAdvisory(
  UpscaleAdvisory advisory,
  int sourceWidth,
  int sourceHeight,
) {
  final source = sourceWidth > 0 && sourceHeight > 0
      ? '${sourceWidth}x$sourceHeight'
      : 'this source';
  switch (advisory) {
    case UpscaleAdvisory.notApplicable:
      return '';
    case UpscaleAdvisory.beneficial:
      return 'Source is $source, below the panel size.';
    case UpscaleAdvisory.neutral:
      return 'Source is $source, about the panel size.';
    case UpscaleAdvisory.notRecommended:
      return 'Source is $source, at or above the panel. Sharpening here can '
          'look worse than leaving it off.';
  }
}

/// Central service managing video engine properties, Anime4K upscaling, and subtitle customization
/// using media_kit / libmpv.
///
/// All decoder, buffer, and engine settings are hardcoded to optimal MPV-native
/// defaults. Users cannot adjust these — MPV picks the best decoder based on
/// hardware natively. Subtitle styling and Anime4K upscaling are user-configurable.
abstract final class PlayerSettings {
  // Video & Anime4K Upscaling Keys
  static const _keyAnime4kPreset = 'player_anime4k_preset';
  static const _keyHwdecMode = 'player_hwdec_mode';
  static const _keyAutoRecoverBlackScreen = 'player_auto_recover_black_screen';

  // Subtitle Customization Keys
  static const _keySubStylePreset = 'player_sub_style_preset';
  static const _keySubFont = 'player_sub_font';
  static const _keySubFontSize = 'player_sub_font_size';
  static const _keySubScale = 'player_sub_scale';
  static const _keySubColor = 'player_sub_color';
  static const _keySubBackColor = 'player_sub_back_color';
  static const _keySubBorderColor = 'player_sub_border_color';
  static const _keySubBorderSize = 'player_sub_border_size';
  static const _keySubShadowOffset = 'player_sub_shadow_offset';
  static const _keySubShadowColor = 'player_sub_shadow_color';
  static const _keySubBold = 'player_sub_bold';
  static const _keySubItalic = 'player_sub_italic';
  static const _keySubMarginY = 'player_sub_margin_y';
  static const _keySubPos = 'player_sub_pos';
  static const _keySubAlignX = 'player_sub_align_x';
  static const _keySubAssOverride = 'player_sub_ass_override';
  static const _keyUseLibass = 'player_use_libass';
  static const _keyEnableSurfaceProducer = 'player_enable_surface_producer';
  static const _keyPlayerVolume = 'player_saved_volume';

  // Hardcoded engine defaults — not user-configurable
  // autoResyncOnStall and hardwareAudioClock are kept as ValueNotifiers for
  // compatibility with player_screen.dart but are always true.
  static final ValueNotifier<bool> autoResyncOnStall = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> hardwareAudioClock = ValueNotifier<bool>(true);

  /// Persisted player volume across sessions (0.0 to 2.50). Default: 1.0 (100%).
  static final ValueNotifier<double> savedVolume = ValueNotifier<double>(1.0);

  /// Android Direct Surface (SurfaceProducer / SurfaceView) toggle. Default: false (off).
  static final ValueNotifier<bool> enableSurfaceProducer = ValueNotifier<bool>(false);

  /// Hardware acceleration mode for video decoding. Default: autoSafe.
  static final ValueNotifier<HardwareAccelerationMode> hwdecMode =
      ValueNotifier<HardwareAccelerationMode>(HardwareAccelerationMode.autoSafe);

  /// Automatically fall back to software decoding if hardware decoder produces black screen / stalls. Default: true.
  static final ValueNotifier<bool> autoRecoverBlackScreen = ValueNotifier<bool>(true);

  // Anime4K Video Upscaling ValueNotifier
  static final ValueNotifier<Anime4KPreset> anime4kPreset =
      ValueNotifier<Anime4KPreset>(Anime4KPreset.off);

  // Subtitle Customization ValueNotifiers
  static final ValueNotifier<SubtitleStylePreset> subStylePreset =
      ValueNotifier<SubtitleStylePreset>(SubtitleStylePreset.classicWhite);
  static final ValueNotifier<String> subFont = ValueNotifier<String>('subfont');
  static final ValueNotifier<int> subFontSize = ValueNotifier<int>(32);
  static final ValueNotifier<double> subScale = ValueNotifier<double>(1.0);
  static final ValueNotifier<String> subColor = ValueNotifier<String>('#FFFFFFFF');
  static final ValueNotifier<String> subBackColor = ValueNotifier<String>('#00000000');
  static final ValueNotifier<String> subBorderColor = ValueNotifier<String>('#FF000000');
  static final ValueNotifier<double> subBorderSize = ValueNotifier<double>(2.0);
  static final ValueNotifier<double> subShadowOffset = ValueNotifier<double>(0.0);
  static final ValueNotifier<String> subShadowColor = ValueNotifier<String>('#80000000');
  static final ValueNotifier<bool> subBold = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> subItalic = ValueNotifier<bool>(false);
  static final ValueNotifier<double> subMarginY = ValueNotifier<double>(30.0);
  static final ValueNotifier<double> subPos = ValueNotifier<double>(100.0);
  static final ValueNotifier<String> subAlignX = ValueNotifier<String>('center');
  static final ValueNotifier<String> subAssOverride = ValueNotifier<String>('no');
  static final ValueNotifier<bool> useLibass = ValueNotifier<bool>(false);
  static final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  // Extracted shader paths for Anime4K GLSL engine
  static String? _extractedAnime4kDir;
  static String? get extractedAnime4kDir => _extractedAnime4kDir;

  /// Where the FSR shaders were extracted. Separate from the Anime4K directory
  /// so [Anime4KPreset.shaderFiles] resolves against the right folder for the
  /// family the selected mode belongs to.
  static String? _extractedFsrDir;
  static String? get extractedFsrDir => _extractedFsrDir;

  /// Mirrors the FSR entries bundled in pubspec.yaml.
  static const List<String> _fsrShaderFiles = [
    'FSR_EASU.glsl',
    'FSR_RCAS.glsl',
  ];

  // Extracted font paths for libass font fallback
  static String? _extractedFontDir;
  static String? _extractedFontPath;
  static String? get extractedFontDir => _extractedFontDir;
  static String? get extractedFontPath => _extractedFontPath;

  /// Popular available system fonts across platforms
  static const List<String> popularFonts = [
    'subfont',
    'Poppins',
    'Roboto',
    'Arial',
    'Trebuchet MS',
    'Open Sans',
    'Montserrat',
    'Comic Sans MS',
    'Courier New',
    'Georgia',
    'Times New Roman',
    'Impact',
    'Verdana',
  ];

  /// Initializes subtitle & Anime4K upscaling preferences from disk and extracts bundled assets.
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Persisted Player Volume
    savedVolume.value = prefs.getDouble(_keyPlayerVolume) ?? 1.0;

    // Load Anime4K Upscaling Preference
    final anime4kPresetStr = prefs.getString(_keyAnime4kPreset);
    if (anime4kPresetStr != null) {
      anime4kPreset.value = Anime4KPreset.values.firstWhere(
        (p) => p.name == anime4kPresetStr,
        orElse: () => Anime4KPreset.off,
      );
    }

    // Load Subtitle Customization Preferences
    final subPresetStr = prefs.getString(_keySubStylePreset);
    if (subPresetStr != null) {
      subStylePreset.value = SubtitleStylePreset.values.firstWhere(
        (p) => p.name == subPresetStr,
        orElse: () => SubtitleStylePreset.classicWhite,
      );
    }
    subFont.value = prefs.getString(_keySubFont) ?? 'subfont';
    subFontSize.value = prefs.getInt(_keySubFontSize) ?? 32;
    subScale.value = prefs.getDouble(_keySubScale) ?? 1.0;
    subColor.value = prefs.getString(_keySubColor) ?? '#FFFFFFFF';
    subBackColor.value = prefs.getString(_keySubBackColor) ?? '#00000000';
    subBorderColor.value = prefs.getString(_keySubBorderColor) ?? '#FF000000';
    subBorderSize.value = prefs.getDouble(_keySubBorderSize) ?? 2.0;
    subShadowOffset.value = prefs.getDouble(_keySubShadowOffset) ?? 0.0;
    subShadowColor.value = prefs.getString(_keySubShadowColor) ?? '#80000000';
    subBold.value = prefs.getBool(_keySubBold) ?? false;
    subItalic.value = prefs.getBool(_keySubItalic) ?? false;
    subMarginY.value = prefs.getDouble(_keySubMarginY) ?? 30.0;
    subPos.value = prefs.getDouble(_keySubPos) ?? 100.0;
    subAlignX.value = prefs.getString(_keySubAlignX) ?? 'center';
    subAssOverride.value = prefs.getString(_keySubAssOverride) ?? 'no';
    useLibass.value = prefs.getBool(_keyUseLibass) ?? false;
    enableSurfaceProducer.value = prefs.getBool(_keyEnableSurfaceProducer) ?? false;

    // Load Hardware Decoding Preference
    final hwdecModeStr = prefs.getString(_keyHwdecMode);
    if (hwdecModeStr != null) {
      hwdecMode.value = HardwareAccelerationMode.values.firstWhere(
        (m) => m.name == hwdecModeStr,
        orElse: () => HardwareAccelerationMode.autoSafe,
      );
    }
    autoRecoverBlackScreen.value = prefs.getBool(_keyAutoRecoverBlackScreen) ?? true;

    // Extract bundled font for libass fallback
    await _extractLibassFontFallback();

    // Extract bundled Anime4K GLSL shaders for libmpv upscaling pipeline
    await _extractAnime4kShaders();
  }

  /// Extracts bundled Anime4K GLSL shaders from assets to persistent disk storage for libmpv glsl-shaders property.
  static Future<void> _extractAnime4kShaders() async {
    try {
      Directory? targetDir;
      try {
        targetDir = await getApplicationSupportDirectory();
      } catch (_) {
        targetDir = await getTemporaryDirectory();
      }

      final shadersDir = Directory(p.join(targetDir.path, 'shaders', 'anime4k'));
      if (!await shadersDir.exists()) {
        await shadersDir.create(recursive: true);
      }

      // Mirrors the Anime4K entries bundled in pubspec.yaml — the union of the
      // shader files the presets above reference.
      final shaderFiles = [
        'Anime4K_AutoDownscalePre_x2.glsl',
        'Anime4K_AutoDownscalePre_x4.glsl',
        'Anime4K_Clamp_Highlights.glsl',
        'Anime4K_Restore_CNN_M.glsl',
        'Anime4K_Restore_CNN_Soft_M.glsl',
        'Anime4K_Restore_CNN_VL.glsl',
        'Anime4K_Upscale_CNN_x2_M.glsl',
        'Anime4K_Upscale_CNN_x2_VL.glsl',
        'Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
      ];

      for (final filename in shaderFiles) {
        final shaderFile = File(p.join(shadersDir.path, filename));
        if (!await shaderFile.exists() || (await shaderFile.length()) == 0) {
          try {
            final data = await rootBundle.load('assets/shaders/anime4k/$filename');
            if (data.lengthInBytes > 0) {
              await shaderFile.writeAsBytes(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
                flush: true,
              );
            }
          } catch (_) {}
        }
      }

      // FSR ships beside it rather than inside it. The two families are never
      // mixed in one chain, and keeping them apart means a stale Anime4K extract
      // cannot make an FSR preset look broken, or the other way round.
      final fsrDir = Directory(p.join(targetDir.path, 'shaders', 'fsr'));
      if (!await fsrDir.exists()) {
        await fsrDir.create(recursive: true);
      }
      for (final filename in _fsrShaderFiles) {
        final shaderFile = File(p.join(fsrDir.path, filename));
        if (!await shaderFile.exists() || (await shaderFile.length()) == 0) {
          try {
            final data = await rootBundle.load('assets/shaders/fsr/$filename');
            if (data.lengthInBytes > 0) {
              await shaderFile.writeAsBytes(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
                flush: true,
              );
            }
          } catch (_) {}
        }
      }
      _extractedFsrDir = fsrDir.path;

      _extractedAnime4kDir = shadersDir.path;
      debugPrint('[PlayerSettings] Anime4K shaders extracted to: $_extractedAnime4kDir');
    } catch (e) {
      debugPrint('[PlayerSettings] Error extracting Anime4K shaders: $e');
    }
  }

  /// Extracts assets/fonts/Poppins-Medium.ttf or subfont.ttf to persistent disk storage for libass font provider
  static Future<void> _extractLibassFontFallback() async {
    try {
      Directory? targetDir;
      try {
        targetDir = await getApplicationSupportDirectory();
      } catch (_) {
        targetDir = await getTemporaryDirectory();
      }

      final fontsDir = Directory(p.join(targetDir.path, 'fonts'));
      if (!await fontsDir.exists()) {
        await fontsDir.create(recursive: true);
      }

      final fontFile = File(p.join(fontsDir.path, 'Poppins.ttf'));
      if (!await fontFile.exists() || (await fontFile.length()) == 0) {
        ByteData? data;
        final candidateAssets = [
          'assets/fonts/Poppins-Medium.ttf',
          'assets/fonts/Poppins-SemiBold.ttf',
          'assets/fonts/Poppins-Regular.ttf',
          'assets/fonts/subfont.ttf',
        ];
        for (final candidate in candidateAssets) {
          try {
            data = await rootBundle.load(candidate);
            if (data.lengthInBytes > 0) break;
          } catch (_) {}
        }

        if (data != null) {
          await fontFile.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true,
          );
        }
      }

      if (await fontFile.exists() && (await fontFile.length()) > 0) {
        _extractedFontDir = fontsDir.path;
        _extractedFontPath = fontFile.path;
        debugPrint('[PlayerSettings] libass font extracted successfully to: $_extractedFontPath');
      }
    } catch (e) {
      debugPrint('[PlayerSettings] Error extracting libass font fallback: $e');
    }
  }

  /// Returns a configured [VideoControllerConfiguration] for media_kit [VideoController].
  /// Uses user-selected [hwdecMode] with 'auto-safe' default.
  /// androidAttachSurfaceAfterVideoParameters is set to false so surfaces attach immediately,
  /// eliminating MediaCodec initialization deadlocks and black screens.
  static VideoControllerConfiguration getVideoControllerConfiguration() {
    return VideoControllerConfiguration(
      hwdec: hwdecMode.value.mpvValue,
      enableHardwareAcceleration: true,
      androidAttachSurfaceAfterVideoParameters: false,
      enableAndroidSurfaceProducer: enableSurfaceProducer.value,
    );
  }

  /// Returns a configured [PlayerConfiguration] for constructing a media_kit [Player].
  static PlayerConfiguration getMediaKitPlayerConfiguration() {
    return PlayerConfiguration(
      libass: useLibass.value,
      libassAndroidFont: 'assets/fonts/Poppins-Medium.ttf',
      libassAndroidFontName: 'Poppins',
      bufferSize: 157286400, // 150MB — sensible default
      logLevel: MPVLogLevel.warn,
    );
  }

  /// Configures network stream continuity with strict separation between Live IPTV and VOD.
  static Future<void> applyStreamContinuity(Player player, {bool isLive = false}) async {
    try {
      final dynamic platform = player.platform;
      if (platform == null) return;
      if (isLive) {
        // Live IPTV stream continuity: reconnect on dropouts at the protocol layer
        await platform.setProperty(
          'stream-lavf-o',
          'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_on_http_error=500,502,503,504,reconnect_delay_max=5',
        );
      } else {
        // VOD / HLS / Movies / Episodes: DO NOT set reconnect=1 because FFmpeg treats HLS segments
        // as unseekable streams when reconnect=1 is active. Keeping it clean enables full HLS seeking!
        await platform.setProperty('stream-lavf-o', '');
      }
    } catch (e) {
      debugPrint('[PlayerSettings] applyStreamContinuity warning: $e');
    }
  }

  /// Pre-Open Properties: Demuxer, hardware decoder, cache buffer, and FFmpeg flags
  /// that MUST be configured before opening media.
  static Future<void> applyPreOpenProperties(Player player, {bool isLive = false, bool isTorrent = false}) async {
    try {
      final dynamic platform = player.platform;
      if (platform == null) return;

      // 1. Audio Filter & Volume
      await platform.setProperty('af', 'scaletempo2=max-speed=8');
      // Must reach the control's ceiling, not sit under it: PlayerVolumeControl
      // offers up to 250%, and mpv clamps the 201-250 range to 200 when the
      // engine is set lower, so the top of the slider did nothing.
      await platform.setProperty('volume-max', '250');

      // 2. Hardware Decoder — configured from user preferences or auto-safe default
      await platform.setProperty('hwdec', hwdecMode.value.mpvValue);
      await platform.setProperty('framedrop', 'vo');
      await platform.setProperty('tone-mapping', 'auto');
      await platform.setProperty('target-colorspace-hint', 'yes');

      // 3. Libass Engine & Font directory pre-configuration
      if (useLibass.value) {
        if (_extractedFontDir != null) {
          await platform.setProperty('sub-fonts-dir', _extractedFontDir!);
        }
        if (_extractedFontPath != null) {
          await platform.setProperty('sub-font-file', _extractedFontPath!);
        }
        await platform.setProperty('sub-ass', 'yes');
        await platform.setProperty('sub-visibility', 'yes');
      } else {
        await platform.setProperty('sub-visibility', 'no');
      }

      // 4. A/V sync — hardware audio clock is always the master timeline
      await platform.setProperty('video-sync', 'audio');

      // 5. GLSL upscaling pipeline: Anime4K for line art, FSR 1 for live
      // action. The two families are never chained together — both upscale, so
      // stacking them would scale the same pixels twice. Each resolves against
      // the directory it was extracted to.
      final preset = anime4kPreset.value;
      final shaderDir = preset.isFsr ? _extractedFsrDir : _extractedAnime4kDir;
      if (preset != Anime4KPreset.off && shaderDir != null) {
        final files = preset.shaderFiles;
        if (files.isNotEmpty) {
          final separator = Platform.isWindows ? ';' : ':';
          final shaderChain = files
              .map((f) => p.join(shaderDir, f))
              .join(separator);
          await platform.setProperty('glsl-shaders', shaderChain);
          debugPrint('[PlayerSettings] Applied shader chain: ${preset.label} -> $shaderChain');
        } else {
          await platform.setProperty('glsl-shaders', '');
        }
      } else {
        await platform.setProperty('glsl-shaders', '');
      }

      // 6. Seekability for VOD and torrent playback (never for Live IPTV).
      // Provider VOD URLs (plain MP4 or HLS behind unsigned CDN links) do not
      // advertise byte-range support, so mpv refuses the start time seek that a
      // resume passes to open() and answers "Cannot seek in this stream", which
      // the player then treats as a dead source. Pretending seekability makes
      // mpv honour the saved position instead. Live IPTV is excluded on purpose:
      // its window is not seekable and the live UI has no seek bar.
      if (!isLive) {
        await platform.setProperty('force-seekable', 'yes');
      }

      // ──────────────────────────────────────────────────────────────────────
      // TORRENT STREAMS: TorrServer is a local HTTP server that may have data
      // gaps while downloading pieces. MPV needs generous cache, timeouts, and
      // reconnect to handle this gracefully instead of dying on any stall.
      // ──────────────────────────────────────────────────────────────────────
      if (isTorrent) {
        await platform.setProperty('cache', 'yes');
        await platform.setProperty('cache-secs', '30');
        await platform.setProperty('demuxer-readahead-secs', '30');
        await platform.setProperty('demuxer-max-bytes', '157286400');   // 150MB
        await platform.setProperty('demuxer-max-back-bytes', '52428800'); // 50MB back buffer
        await platform.setProperty('network-timeout', '60');            // 60s — torrents need patience
        await platform.setProperty('stream-lavf-o',
          'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=10',
        );
        return;
      }

      // ──────────────────────────────────────────────────────────────────────
      // HTTP / HLS / CDN STREAMS: Standard buffering and probing
      // ──────────────────────────────────────────────────────────────────────
      await platform.setProperty('cache', 'yes');
      await platform.setProperty('demuxer-max-bytes', '157286400');   // 150MB
      await platform.setProperty('demuxer-max-back-bytes', '52428800'); // 50MB back buffer
      await platform.setProperty('cache-secs', '15');
      await platform.setProperty('demuxer-readahead-secs', '15');
      await platform.setProperty('network-timeout', '30');

      // Network Stream Continuity (Live IPTV vs VOD separation)
      await applyStreamContinuity(player, isLive: isLive);

      // Fast probing to avoid stream startup freezes and demuxer timeouts
      await platform.setProperty('hls-bitrate', 'max');
      await platform.setProperty('demuxer-lavf-probesize', isLive ? '4194304' : '8388608');
      await platform.setProperty('demuxer-lavf-analyzeduration', isLive ? '3' : '5');
      await platform.setProperty('demuxer-lavf-o', 'strict=experimental');
    } catch (e) {
      debugPrint('[PlayerSettings] applyPreOpenProperties warning: $e');
    }
  }

  /// Post-Open / Dynamic Properties: Subtitle styling and real-time tweaks that can be
  /// applied safely after media open or during live playback.
  static Future<void> applyPostOpenProperties(Player player) async {
    try {
      await applySubtitleStyling(player);
    } catch (e) {
      debugPrint('[PlayerSettings] applyPostOpenProperties warning: $e');
    }
  }

  /// Checks if an error emitted by media_kit / MPV / FFmpeg is a non-fatal,
  /// routine protocol warning or demuxer hiccup that should be ignored during playback.
  static bool isNonFatalError(dynamic err) {
    if (err == null) return false;
    final errorMsg = err.toString().trim();
    if (errorMsg.isEmpty) return false;
    final lower = errorMsg.toLowerCase();

    // 0. Subtitles loading or parsing errors are always non-fatal
    if (lower.contains('can not open external file') ||
        lower.contains('subtitle') ||
        lower.contains('sub-add') ||
        lower.contains('.srt') ||
        lower.contains('.vtt') ||
        lower.contains('.ass')) {
      return true;
    }

    // 1. FATAL error indicators: These MUST NEVER be ignored, as they indicate dead streams or broken formats.
    if (lower.contains('failed to open') ||
        lower.contains('cannot open') ||
        lower.contains('can not open') ||
        lower.contains('could not open') ||
        lower.contains('unable to open') ||
        lower.contains('failed to recognize file format') ||
        lower.contains('unsupported file format') ||
        lower.contains('format not supported') ||
        lower.contains('no such file or directory') ||
        lower.contains('server returned 4') ||
        lower.contains('server returned 5') ||
        lower.contains('failed to resolve hostname') ||
        lower.contains('failed host lookup') ||
        lower.contains('no such host is known') ||
        lower.contains('name or service not known') ||
        lower.contains('connection refused') ||
        lower.contains('host unreachable') ||
        lower.contains('network is unreachable') ||
        lower.contains('error opening')) {
      return false;
    }

    // 2. FFmpeg URL protocol & socket read/write return codes (e.g. "tcp: ffurl_read returned 0xffffff99")
    if (lower.contains('ffurl_read') ||
        lower.contains('ffurl_write') ||
        lower.contains('ffurl_') ||
        lower.contains('av_read_frame') ||
        lower.contains('0xffffff') ||
        lower.contains('returned -') ||
        lower.contains('returned 0x')) {
      return true;
    }

    // 3. Transient socket/stream level warnings during active playback where demuxer reconnects or handles EOF
    if (lower.contains('averror_eof') ||
        lower.contains('end of file') ||
        lower.contains('connection reset') ||
        lower.contains('connection closed') ||
        lower.contains('connection timed out') ||
        lower.contains('broken pipe') ||
        lower.contains('resource temporarily unavailable')) {
      return true;
    }

    // 4. Codec, demuxer packet or hardware acceleration fallbacks that don't prevent playback
    if (lower.contains('invalid nal unit') ||
        lower.contains('corrupt input packet') ||
        lower.contains('missing picture') ||
        lower.contains('packet corrupt') ||
        lower.contains('error while decoding') ||
        lower.contains('hardware decoder') ||
        lower.contains('hwdec') ||
        lower.contains('auto-safe') ||
        lower.contains('swscaler') ||
        lower.contains('scaletempo')) {
      return true;
    }

    return false;
  }

  /// Checks if an error emitted by MPV is the refusal of a start time seek:
  /// "Cannot seek in this stream." followed by the hint "You can force it with
  /// '--force-seekable=yes'.". MPV prints both lines, so both are matched.
  ///
  /// This is NOT a dead stream. MPV has opened the media and only the requested
  /// position could not be honoured, which is exactly what a resume hits when
  /// the provider URL does not advertise seekability. Callers must recover by
  /// reopening without a start position (see PlayerScreen._recoverFromRefusedSeek)
  /// and must never route it to the "Playback error" / source picker state.
  static bool isSeekRefusedError(dynamic err) {
    if (err == null) return false;
    final lower = err.toString().toLowerCase();
    // "force-seekable" is advice mpv prints only for this refusal.
    return lower.contains('cannot seek') ||
        lower.contains('could not seek') ||
        lower.contains('force-seekable');
  }

  /// Checks if an error emitted by MPV indicates a hardware decoding or video pipeline failure.
  static bool isHardwareDecoderError(dynamic err) {
    if (err == null) return false;
    final lower = err.toString().toLowerCase();
    return lower.contains('hardware decoder') ||
        lower.contains('hwdec') ||
        lower.contains('error while decoding') ||
        lower.contains('cannot load nvcuda') ||
        lower.contains('d3d11va') ||
        lower.contains('vaapi') ||
        lower.contains('mediacodec: failed') ||
        lower.contains('could not open codec') ||
        lower.contains('failed to configure mediacodec') ||
        lower.contains('shader compilation failed') ||
        lower.contains('glsl') ||
        lower.contains('egl_bad_attribute') ||
        lower.contains('unsupported pixel format');
  }

  /// Dynamically forces software decoding on an active player (e.g. when watchdog detects black screen).
  /// Re-syncs the decoder and re-evaluates the video track smoothly without crashing.
  static Future<bool> fallbackToSoftware(Player player) async {
    try {
      final dynamic platform = player.platform;
      if (platform == null) return false;

      debugPrint('[PlayerSettings] Triggering dynamic fallback to Software Decoding (hwdec: no)...');
      // 1. Clear any active GLSL shaders that might have failed compilation or overloaded GPU
      await platform.setProperty('glsl-shaders', '');
      // 2. Set hardware decoding to 'no' (pure CPU software decoding with FFmpeg libavcodec)
      await platform.setProperty('hwdec', 'no');
      // 3. Ensure video track is enabled and auto-selected
      await platform.setProperty('vid', 'auto');
      // 4. Force decoder re-init and keyframe refresh at current position
      final currentPos = player.state.position;
      await player.seek(currentPos);
      debugPrint('[PlayerSettings] Dynamic fallback to Software Decoding applied successfully.');
      return true;
    } catch (e) {
      debugPrint('[PlayerSettings] Error during software fallback: $e');
      return false;
    }
  }

  /// Automatically resolves all required Referer, Origin, and User-Agent headers for known streaming CDNs.
  static Map<String, String> resolveStreamHeaders(String url, [Map<String, String>? initialHeaders]) {
    final h = <String, String>{
      'Connection': 'keep-alive',
      'Accept': '*/*',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    };
    if (initialHeaders != null) {
      h.addAll(initialHeaders);
    }

    final lower = url.toLowerCase();
    if (lower.contains('hakunaymatata.com')) {
      h['User-Agent'] = 'Lavf/60.16.100';
    } else if (lower.contains('sabrina-stream-proxy') || lower.contains('dulo.') || lower.contains('dulo.gd')) {
      h['Referer'] = 'https://d.dulo.gd/';
      h['Origin'] = 'https://d.dulo.gd';
    } else if (lower.contains('movieboxnoob.cc') ||
        lower.contains('moviebox.ph') ||
        lower.contains('cinejoy.to') ||
        lower.contains('cinejoy')) {
      h['Referer'] = 'https://cinejoy.to/';
      h['Origin'] = 'https://cinejoy.to';
    } else if (lower.contains('peakstorm.top') ||
        lower.contains('majorplay.net') ||
        lower.contains('slast430did.com') ||
        lower.contains('vidzy.cc') ||
        lower.contains('vimeos.zip') ||
        lower.contains('wecollege.net')) {
      final customRef = initialHeaders?['Referer'] ?? initialHeaders?['referer'];
      if (customRef != null && customRef.isNotEmpty) {
        h['Referer'] = customRef;
        h['Origin'] = customRef.replaceAll(RegExp(r'/+$'), '');
      } else {
        h['Referer'] = 'https://www.movy.bz/';
        h['Origin'] = 'https://www.movy.bz';
      }
    } else if (lower.contains('chillflix.lol')) {
      h['Referer'] = 'https://www.chillflix.lol/';
      h['Origin'] = 'https://www.chillflix.lol';
    } else if (lower.contains('hclod.qzz.io') || lower.contains('watchplay.shop')) {
      h['Referer'] = 'https://v1.watchplay.shop/';
      h['Origin'] = 'https://v1.watchplay.shop';
    } else if (lower.contains('valhallastream') || lower.contains('1shows.app') || lower.contains('rivestream')) {
      h['Referer'] = 'https://www.rivestream.app/';
      h['Origin'] = 'https://www.rivestream.app';
    } else if (lower.contains('videasy') || lower.contains('speedracelight')) {
      h['Referer'] = 'https://player.videasy.to/';
      h['Origin'] = 'https://player.videasy.to';
    } else if (lower.contains('streamraiwind.stream') || lower.contains('vuflix.co')) {
      h['Referer'] = 'https://vuflix.co/';
      h['Origin'] = 'https://vuflix.co';
    } else if (lower.contains('net77.cc') || lower.contains('nm-cdn4.top')) {
      h['Referer'] = 'https://net77.cc/';
      h['Origin'] = 'https://net77.cc';
    } else if (lower.contains('gn1r5n.org') || lower.contains('owphbf24.com')) {
      h['Referer'] = 'https://gn1r5n.org/';
      h['Origin'] = 'https://gn1r5n.org';
    } else if (lower.contains('watching.onl') ||
        lower.contains('livedns.my') ||
        lower.contains('sugevideo.xyz') ||
        lower.contains('anivideo.sbs') ||
        lower.contains('trycloud.pro') ||
        lower.contains('cloudvideo.lat') ||
        lower.contains('megaplay.buzz') ||
        lower.contains('vidwish.live') ||
        (initialHeaders != null && initialHeaders['Referer']?.contains('megaplay.buzz') == true) ||
        (initialHeaders != null && initialHeaders['Referer']?.contains('vidwish') == true)) {
      h['Referer'] = 'https://megaplay.buzz/';
      h['Origin'] = 'https://megaplay.buzz';
      h['Cookie'] = 'SITE_TOTAL_ID=ce655f0eea754f2888ea98ded373e3b5';
    } else if (lower.contains('anidb.app') ||
        lower.contains('hls.anidb.app') ||
        (initialHeaders != null && initialHeaders['Referer']?.contains('anidb.app') == true)) {
      h['Referer'] = 'https://anidb.app/';
      h['Origin'] = 'https://anidb.app';
    }
    return h;
  }

  /// Convenience method that applies both pre-open and post-open properties to a media_kit [Player].
  static Future<void> applyToPlayer(Player player, {bool isLive = false}) async {
    await applyPreOpenProperties(player, isLive: isLive);
    await applyPostOpenProperties(player);
  }

  /// Live-applies all subtitle appearance properties directly to the underlying libmpv instance.
  static Future<void> applySubtitleStyling(Player player) async {
    try {
      final dynamic platform = player.platform;
      if (platform != null) {
        if (useLibass.value) {
          // Ensure subtitle visibility and libass engine are activated in libmpv
          await platform.setProperty('sub-visibility', 'yes');
          await platform.setProperty('sub-ass', 'yes');

          // Font paths
          if (_extractedFontDir != null) {
            await platform.setProperty('sub-fonts-dir', _extractedFontDir!);
          }
          if (_extractedFontPath != null) {
            await platform.setProperty('sub-font-file', _extractedFontPath!);
          }

          // Font family
          final font = (subFont.value.trim().isEmpty || subFont.value == 'subfont')
              ? 'Poppins'
              : subFont.value.trim();
          await platform.setProperty('sub-font', font);

          // Typography
          await platform.setProperty('sub-font-size', subFontSize.value.toString());
          await platform.setProperty('sub-scale', subScale.value.toStringAsFixed(2));
          await platform.setProperty('sub-bold', subBold.value ? 'yes' : 'no');
          await platform.setProperty('sub-italic', subItalic.value ? 'yes' : 'no');

          // Colors
          await platform.setProperty('sub-color', _formatMpvColor(subColor.value));
          await platform.setProperty('sub-back-color', _formatMpvColor(subBackColor.value));

          // Borders & Outlines
          await platform.setProperty('sub-border-color', _formatMpvColor(subBorderColor.value));
          await platform.setProperty('sub-border-size', subBorderSize.value.toStringAsFixed(1));

          // Shadows
          await platform.setProperty('sub-shadow-offset', subShadowOffset.value.toStringAsFixed(1));
          await platform.setProperty('sub-shadow-color', _formatMpvColor(subShadowColor.value));

          // Positioning & Layout
          await platform.setProperty('sub-margin-y', subMarginY.value.round().toString());
          await platform.setProperty('sub-pos', subPos.value.round().toString());
          await platform.setProperty('sub-align-x', subAlignX.value);

          // ASS/SSA Script Preservation vs Override
          await platform.setProperty('sub-ass-override', subAssOverride.value);
          await platform.setProperty('sub-ass-force-margins', 'yes');
          await platform.setProperty('sub-use-margins', 'yes');

          // Force style string for ASS subtitles when override is active
          if (subAssOverride.value != 'no') {
            final assForceStyle = _buildAssForceStyleString(font);
            if (assForceStyle.isNotEmpty) {
              await platform.setProperty('sub-ass-force-style', assForceStyle);
            }
          }
        } else {
          // Flutter Subtitle Engine: hide native MPV text rendering so Flutter's SubtitleView renders cleanly
          await platform.setProperty('sub-visibility', 'no');
        }
      }
    } catch (e) {
      debugPrint('[PlayerSettings] applySubtitleStyling error: $e');
    }
  }

  /// Builds a reactive [SubtitleViewConfiguration] for Flutter's subtitle overlay widget.
  static SubtitleViewConfiguration getSubtitleViewConfiguration() {
    if (useLibass.value) {
      return const SubtitleViewConfiguration(
        visible: false,
      );
    }

    Color parseColor(String hex, {Color fallback = Colors.white}) {
      var str = hex.replaceAll('#', '').trim();
      if (str.length == 6) str = 'FF$str';
      if (str.length == 8) {
        final val = int.tryParse(str, radix: 16);
        if (val != null) return Color(val);
      }
      return fallback;
    }

    final textColor = parseColor(subColor.value);
    final boxColor = parseColor(subBackColor.value, fallback: Colors.transparent);
    final borderColor = parseColor(subBorderColor.value, fallback: Colors.black);
    final shadowColor = parseColor(subShadowColor.value, fallback: Colors.black54);

    final font = (subFont.value.isEmpty || subFont.value == 'subfont') ? 'Poppins' : subFont.value;
    final align = subAlignX.value == 'left'
        ? TextAlign.left
        : (subAlignX.value == 'right' ? TextAlign.right : TextAlign.center);

    final shadows = <Shadow>[];
    if (subBorderSize.value > 0) {
      final r = subBorderSize.value * 0.8;
      final d = r * 0.707;
      shadows.addAll([
        Shadow(color: borderColor, offset: Offset(-r, 0)),
        Shadow(color: borderColor, offset: Offset(r, 0)),
        Shadow(color: borderColor, offset: Offset(0, -r)),
        Shadow(color: borderColor, offset: Offset(0, r)),
        Shadow(color: borderColor, offset: Offset(-d, -d)),
        Shadow(color: borderColor, offset: Offset(d, -d)),
        Shadow(color: borderColor, offset: Offset(-d, d)),
        Shadow(color: borderColor, offset: Offset(d, d)),
      ]);
    }
    if (subShadowOffset.value > 0) {
      shadows.add(
        Shadow(
          color: shadowColor,
          offset: Offset(subShadowOffset.value, subShadowOffset.value),
          blurRadius: 3.0,
        ),
      );
    }

    return SubtitleViewConfiguration(
      visible: true,
      textAlign: align,
      padding: EdgeInsets.fromLTRB(
        subAlignX.value == 'left' ? 32 : 16,
        0,
        subAlignX.value == 'right' ? 32 : 16,
        subMarginY.value.clamp(8.0, 300.0),
      ),
      style: TextStyle(
        fontFamily: font,
        fontSize: (subFontSize.value * subScale.value).clamp(12.0, 96.0),
        fontWeight: subBold.value ? FontWeight.bold : FontWeight.w600,
        fontStyle: subItalic.value ? FontStyle.italic : FontStyle.normal,
        color: textColor,
        backgroundColor: boxColor,
        shadows: shadows.isNotEmpty ? shadows : null,
      ),
    );
  }

  static String _formatMpvColor(String hex) {
    var str = hex.replaceAll('#', '').trim().toUpperCase();
    if (str.length == 6) {
      return '#FF$str';
    }
    if (str.length == 8) {
      return '#$str';
    }
    return '#FFFFFFFF';
  }

  static String _buildAssForceStyleString(String font) {
    try {
      final isBoxed = subBackColor.value != '#00000000' && !subBackColor.value.startsWith('#00');
      final borderStyle = isBoxed ? 3 : 1;
      final primaryColour = _toAssColor(subColor.value);
      final outlineColour = _toAssColor(subBorderColor.value);
      final backColour = _toAssColor(isBoxed ? subBackColor.value : subShadowColor.value);

      final size = (subFontSize.value * subScale.value).round();
      final bold = subBold.value ? 1 : 0;
      final italic = subItalic.value ? 1 : 0;
      final outline = subBorderSize.value.toStringAsFixed(1);
      final shadow = subShadowOffset.value.toStringAsFixed(1);
      final marginV = subMarginY.value.round();

      return 'Fontname=$font,Fontsize=$size,PrimaryColour=$primaryColour,BackColour=$backColour,OutlineColour=$outlineColour,Bold=$bold,Italic=$italic,BorderStyle=$borderStyle,Outline=$outline,Shadow=$shadow,MarginV=$marginV';
    } catch (e) {
      debugPrint('[_buildAssForceStyleString] error: $e');
      return '';
    }
  }

  static String _toAssColor(String hex) {
    var str = hex.replaceAll('#', '').trim().toUpperCase();
    if (str.length == 6) {
      str = 'FF$str';
    }
    if (str.length != 8) return '&H00FFFFFF';

    final alpha = int.tryParse(str.substring(0, 2), radix: 16) ?? 255;
    final r = str.substring(2, 4);
    final g = str.substring(4, 6);
    final b = str.substring(6, 8);

    // Invert alpha for ASS (00 = opaque, FF = transparent)
    final assAlpha = (255 - alpha).toRadixString(16).padLeft(2, '0').toUpperCase();

    return '&H$assAlpha$b$g$r';
  }

  /// Backward compatible stub for any controller calls
  static void applyToController(dynamic controller) {
    // No-op for media_kit
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Subtitle Customization Setters (the only user-configurable settings)
  // ───────────────────────────────────────────────────────────────────────────

  static Future<void> setSubStylePreset(SubtitleStylePreset preset, {Player? player}) async {
    subStylePreset.value = preset;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySubStylePreset, preset.name);

    if (preset != SubtitleStylePreset.custom) {
      await setSubColor(preset.textColor, notify: false);
      await setSubBackColor(preset.backColor, notify: false);
      await setSubBorderColor(preset.borderColor, notify: false);
      await setSubBorderSize(preset.borderSize, notify: false);
      await setSubShadowOffset(preset.shadowOffset, notify: false);
      await setSubShadowColor(preset.shadowColor, notify: false);
      await setSubBold(preset.bold, notify: false);
      await setSubItalic(preset.italic, notify: false);
    }

    if (player != null) applySubtitleStyling(player);
    _notify();
  }

  static Future<void> setSubFont(String font, {Player? player}) async {
    subFont.value = font;
    subStylePreset.value = SubtitleStylePreset.custom;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySubFont, font);
    await prefs.setString(_keySubStylePreset, SubtitleStylePreset.custom.name);
    if (player != null) applySubtitleStyling(player);
    _notify();
  }

  static Future<void> setSubFontSize(int size, {Player? player}) async {
    subFontSize.value = size.clamp(14, 80);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySubFontSize, subFontSize.value);
    if (player != null) applySubtitleStyling(player);
    _notify();
  }

  static Future<void> setSubScale(double scale, {Player? player}) async {
    subScale.value = (scale.clamp(0.5, 3.0) * 100).round() / 100.0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySubScale, subScale.value);
    if (player != null) applySubtitleStyling(player);
    _notify();
  }

  static Future<void> setSubColor(String hex, {bool notify = true, Player? player}) async {
    subColor.value = hex;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySubColor, hex);
    if (player != null) applySubtitleStyling(player);
    if (notify) _notify();
  }

  static Future<void> setSubBackColor(String hex, {bool notify = true, Player? player}) async {
    subBackColor.value = hex;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySubBackColor, hex);
    if (player != null) applySubtitleStyling(player);
    if (notify) _notify();
  }

  static Future<void> setSubBorderColor(String hex, {bool notify = true, Player? player}) async {
    subBorderColor.value = hex;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySubBorderColor, hex);
    if (player != null) applySubtitleStyling(player);
    if (notify) _notify();
  }

  static Future<void> setSubBorderSize(double size, {bool notify = true, Player? player}) async {
    subBorderSize.value = size.clamp(0.0, 8.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySubBorderSize, subBorderSize.value);
    if (player != null) applySubtitleStyling(player);
    if (notify) _notify();
  }

  static Future<void> setSubShadowOffset(double offset, {bool notify = true, Player? player}) async {
    subShadowOffset.value = offset.clamp(0.0, 8.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySubShadowOffset, subShadowOffset.value);
    if (player != null) applySubtitleStyling(player);
    if (notify) _notify();
  }

  static Future<void> setSubShadowColor(String hex, {bool notify = true, Player? player}) async {
    subShadowColor.value = hex;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySubShadowColor, hex);
    if (player != null) applySubtitleStyling(player);
    if (notify) _notify();
  }

  static Future<void> setSubBold(bool val, {bool notify = true, Player? player}) async {
    subBold.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySubBold, val);
    if (player != null) applySubtitleStyling(player);
    if (notify) _notify();
  }

  static Future<void> setSubItalic(bool val, {bool notify = true, Player? player}) async {
    subItalic.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySubItalic, val);
    if (player != null) applySubtitleStyling(player);
    if (notify) _notify();
  }

  static Future<void> setSubMarginY(double val, {Player? player}) async {
    subMarginY.value = val.clamp(0.0, 200.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySubMarginY, subMarginY.value);
    if (player != null) applySubtitleStyling(player);
    _notify();
  }

  static Future<void> setSubPos(double val, {Player? player}) async {
    subPos.value = val.clamp(0.0, 100.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySubPos, subPos.value);
    if (player != null) applySubtitleStyling(player);
    _notify();
  }

  static Future<void> setSubAlignX(String val, {Player? player}) async {
    subAlignX.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySubAlignX, val);
    if (player != null) applySubtitleStyling(player);
    _notify();
  }

  static Future<void> setSubAssOverride(String val, {Player? player}) async {
    subAssOverride.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySubAssOverride, val);
    if (player != null) applySubtitleStyling(player);
    _notify();
  }

  static Future<void> setUseLibass(bool val, {Player? player}) async {
    useLibass.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseLibass, val);
    if (player != null) applySubtitleStyling(player);
    _notify();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Video & Anime4K Upscaling Setters
  // ───────────────────────────────────────────────────────────────────────────

  static Future<void> setAnime4kPreset(Anime4KPreset preset) async {
    anime4kPreset.value = preset;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAnime4kPreset, preset.name);
    _notify();
  }

  static Future<void> setEnableSurfaceProducer(bool val) async {
    enableSurfaceProducer.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableSurfaceProducer, val);
    _notify();
  }

  static Future<void> resetSubtitleDefaults({Player? player}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySubStylePreset);
    await prefs.remove(_keySubFont);
    await prefs.remove(_keySubFontSize);
    await prefs.remove(_keySubScale);
    await prefs.remove(_keySubColor);
    await prefs.remove(_keySubBackColor);
    await prefs.remove(_keySubBorderColor);
    await prefs.remove(_keySubBorderSize);
    await prefs.remove(_keySubShadowOffset);
    await prefs.remove(_keySubShadowColor);
    await prefs.remove(_keySubBold);
    await prefs.remove(_keySubItalic);
    await prefs.remove(_keySubMarginY);
    await prefs.remove(_keySubPos);
    await prefs.remove(_keySubAlignX);
    await prefs.remove(_keySubAssOverride);
    await prefs.remove(_keyUseLibass);

    useLibass.value = false;
    subStylePreset.value = SubtitleStylePreset.classicWhite;
    subFont.value = 'Poppins';
    subFontSize.value = 32;
    subScale.value = 1.0;
    subColor.value = '#FFFFFFFF';
    subBackColor.value = '#00000000';
    subBorderColor.value = '#FF000000';
    subBorderSize.value = 2.0;
    subShadowOffset.value = 0.0;
    subShadowColor.value = '#80000000';
    subBold.value = false;
    subItalic.value = false;
    subMarginY.value = 30.0;
    subPos.value = 100.0;
    subAlignX.value = 'center';
    subAssOverride.value = 'no';

    if (player != null) applySubtitleStyling(player);
    _notify();
  }

  static Future<void> setHwdecMode(HardwareAccelerationMode mode) async {
    hwdecMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHwdecMode, mode.name);
    _notify();
  }

  static Future<void> setAutoRecoverBlackScreen(bool val) async {
    autoRecoverBlackScreen.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoRecoverBlackScreen, val);
    _notify();
  }

  static Future<void> setSavedVolume(double val) async {
    final clamped = val.clamp(0.0, 2.50);
    savedVolume.value = clamped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyPlayerVolume, clamped);
  }

  static Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAnime4kPreset);
    await prefs.remove(_keyEnableSurfaceProducer);
    await prefs.remove(_keyHwdecMode);
    await prefs.remove(_keyAutoRecoverBlackScreen);
    await prefs.remove(_keyPlayerVolume);
    anime4kPreset.value = Anime4KPreset.off;
    enableSurfaceProducer.value = false;
    hwdecMode.value = HardwareAccelerationMode.autoSafe;
    autoRecoverBlackScreen.value = true;
    savedVolume.value = 1.0;
    await resetSubtitleDefaults();
  }

  static void _notify() {
    changeNotifier.value++;
  }
}
