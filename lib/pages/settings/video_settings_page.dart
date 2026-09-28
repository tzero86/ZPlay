import 'package:flutter/material.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/player/player_settings.dart';

class VideoSettingsPage extends StatefulWidget {
  const VideoSettingsPage({super.key});

  @override
  State<VideoSettingsPage> createState() => _VideoSettingsPageState();
}

class _VideoSettingsPageState extends State<VideoSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        surfaceTintColor: Colors.transparent,
        // The shell family draws this header as an opaque palette band with a
        // bottom hairline rather than a translucent wash over the page.
        shape: Border(bottom: tokens.hairline),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Video & Upscaling',
          style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              // ── Top Intro Banner ──
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: ZplayRadius.mdAll,
                  border: Border.fromBorderSide(tokens.hairline),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: tokens.accentSubtle,
                        borderRadius: ZplayRadius.mdAll,
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: tokens.accent,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GPU Upscaling',
                            style: ZplayType.subtitle.toStyle(
                              color: tokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Real-time GLSL upscaling on the video engine. Anime4K reconstructs line art; '
                                'AMD FSR upscales live action and film. Pick one family — they are never combined.',
                            style: ZplayType.bodySmall.toStyle(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Section: Presets ──
              Text(
                'UPSCALING PRESETS',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),

              ValueListenableBuilder<Anime4KPreset>(
                valueListenable: PlayerSettings.anime4kPreset,
                builder: (context, currentPreset, _) {
                  return Column(
                    children: [
                      _buildPresetCard(
                        preset: Anime4KPreset.off,
                        title: 'Disabled (Off)',
                        subtitle: 'Standard video playback without GLSL neural filters. Lowest GPU overhead.',
                        tag: 'Standard',
                        tagColor: tokens.textMuted,
                        icon: Icons.block_rounded,
                        isSelected: currentPreset == Anime4KPreset.off,
                        onTap: () => PlayerSettings.setAnime4kPreset(Anime4KPreset.off),
                      ),
                      const SizedBox(height: 10),
                      _buildPresetCard(
                        preset: Anime4KPreset.modeAFast,
                        title: 'Mode A — Fast / Balanced',
                        subtitle: 'Sharp line restoration & 2x CNN upscale. Best for 1080p anime and balanced GPU power.',
                        tag: 'Recommended',
                        tagColor: tokens.success,
                        icon: Icons.speed_rounded,
                        isSelected: currentPreset == Anime4KPreset.modeAFast,
                        onTap: () => PlayerSettings.setAnime4kPreset(Anime4KPreset.modeAFast),
                      ),
                      const SizedBox(height: 10),
                      _buildPresetCard(
                        preset: Anime4KPreset.modeAHQ,
                        title: 'Mode A — High Quality (Ultra)',
                        subtitle: 'Maximum perceptual fidelity using Very Large CNNs. Recommended for discrete GPUs (RTX/Radeon).',
                        tag: 'Ultra Quality',
                        tagColor: tokens.accent,
                        icon: Icons.diamond_rounded,
                        isSelected: currentPreset == Anime4KPreset.modeAHQ,
                        onTap: () => PlayerSettings.setAnime4kPreset(Anime4KPreset.modeAHQ),
                      ),
                      const SizedBox(height: 10),
                      _buildPresetCard(
                        preset: Anime4KPreset.modeB,
                        title: 'Mode B — Soft / Denoise',
                        subtitle: 'Smooth line reconstruction and artifact reduction. Best for blurry, compressed, or older anime.',
                        tag: 'Denoise',
                        tagColor: tokens.accent,
                        icon: Icons.blur_linear_rounded,
                        isSelected: currentPreset == Anime4KPreset.modeB,
                        onTap: () => PlayerSettings.setAnime4kPreset(Anime4KPreset.modeB),
                      ),
                      const SizedBox(height: 10),
                      _buildPresetCard(
                        preset: Anime4KPreset.modeC,
                        title: 'Mode C — Deblur & Scale',
                        subtitle: 'Aggressive deblurring and scaling. Best for 480p and 720p low-resolution anime episodes.',
                        tag: 'Deblur',
                        tagColor: tokens.warning,
                        icon: Icons.high_quality_rounded,
                        isSelected: currentPreset == Anime4KPreset.modeC,
                        onTap: () => PlayerSettings.setAnime4kPreset(Anime4KPreset.modeC),
                      ),
                      const SizedBox(height: 10),
                      _buildPresetCard(
                        preset: Anime4KPreset.fsrEasu,
                        title: 'FSR 1.0 — Smooth',
                        subtitle: 'AMD FidelityFX edge-adaptive upscaling, for live action and film. '
                            'Upscales without sharpening, so it is the safe FSR option. Runs on '
                            'any GPU, unlike NVIDIA RTX Video.',
                        tag: 'Live action',
                        tagColor: tokens.success,
                        icon: Icons.filter_none_rounded,
                        isSelected: currentPreset == Anime4KPreset.fsrEasu,
                        onTap: () => PlayerSettings.setAnime4kPreset(Anime4KPreset.fsrEasu),
                      ),
                      const SizedBox(height: 10),
                      _buildPresetCard(
                        preset: Anime4KPreset.fsrEasuRcas,
                        title: 'FSR 1.0 — Sharp',
                        subtitle: 'FSR with contrast-adaptive sharpening. Adds bite to soft or low-bitrate '
                            'video. On a 2K or 4K source this can look worse than no upscaling at all.',
                        tag: 'Use with care',
                        tagColor: tokens.warning,
                        icon: Icons.filter_alt_rounded,
                        isSelected: currentPreset == Anime4KPreset.fsrEasuRcas,
                        onTap: () =>
                            PlayerSettings.setAnime4kPreset(Anime4KPreset.fsrEasuRcas),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 28),

              // ── Section: Details & Performance Note ──
              Text(
                'PIPELINE & COMPATIBILITY',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: ZplayRadius.mdAll,
                  border: Border.fromBorderSide(tokens.hairline),
                ),
                child: Column(
                  children: [
                    _buildInfoRow(
                      icon: Icons.info_outline_rounded,
                      title: 'Playback Start Application',
                      description: 'Shaders are configured before playback begins. Changing a preset applies to the next opened stream or video.',
                    ),
                    Divider(color: tokens.borderStrong, height: 24),
                    _buildInfoRow(
                      icon: Icons.memory_rounded,
                      title: 'Hardware Decoder Acceleration',
                      description: 'media_kit uses native auto-safe hardware decoding to feed GPU texture memory directly into the GLSL shader pass.',
                    ),
                    Divider(color: tokens.borderStrong, height: 24),
                    _buildInfoRow(
                      icon: Icons.devices_rounded,
                      title: 'Platform Recommendation',
                      description: 'For desktop (Windows/macOS/Linux), Mode A HQ provides crystal-clear lines. For mobile devices, Mode A Fast offers smooth 60fps playback.',
                    ),
                  ],
                ),
              ),

              // ── Section: Hardware Acceleration & Decoding Engine ──
              const SizedBox(height: 28),
              Row(
                children: [
                  Text(
                    'HARDWARE ACCELERATION & DECODING',
                    style: ZplayType.overline.toStyle(color: tokens.accent),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(
                        alpha: ZplayOpacity.overlayHover,
                      ),
                      borderRadius: ZplayRadius.xsAll,
                    ),
                    child: Text(
                      'All Platforms',
                      style: ZplayType.caption.toStyle(color: tokens.accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              ValueListenableBuilder<HardwareAccelerationMode>(
                valueListenable: PlayerSettings.hwdecMode,
                builder: (context, currentMode, _) {
                  return Column(
                    children: [
                      _buildHwdecCard(
                        mode: HardwareAccelerationMode.autoSafe,
                        title: 'Auto-Safe (Recommended)',
                        subtitle: 'GPU hardware decoding with safe driver fallbacks. Best efficiency for most PCs and devices.',
                        badgeText: 'Default',
                        badgeColor: tokens.accent,
                        icon: Icons.speed_rounded,
                        currentMode: currentMode,
                      ),
                      const SizedBox(height: 8),
                      _buildHwdecCard(
                        mode: HardwareAccelerationMode.software,
                        title: 'Software Decoding (Crash-Proof)',
                        subtitle: 'Pure CPU decoding via FFmpeg libavcodec. Eliminates black screens and driver lockups on older GPUs or virtual machines.',
                        badgeText: '100% Reliable',
                        badgeColor: tokens.success,
                        icon: Icons.memory_rounded,
                        currentMode: currentMode,
                      ),
                      const SizedBox(height: 8),
                      _buildHwdecCard(
                        mode: HardwareAccelerationMode.forceHardware,
                        title: 'Direct Hardware',
                        subtitle: 'Direct GPU decoding (Direct3D 11 / MediaCodec / VAAPI). Fastest on modern high-end graphics.',
                        badgeText: 'Max GPU',
                        badgeColor: tokens.warning,
                        icon: Icons.bolt_rounded,
                        currentMode: currentMode,
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 12),

              // Auto-Recover Black Screens Toggle Card
              ValueListenableBuilder<bool>(
                valueListenable: PlayerSettings.autoRecoverBlackScreen,
                builder: (context, autoRecover, _) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: autoRecover
                          ? tokens.accentSubtle
                          : tokens.surface,
                      borderRadius: ZplayRadius.mdAll,
                      border: Border.all(
                        color: autoRecover
                            ? tokens.accent
                            : tokens.borderDefault,
                        width: autoRecover ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: autoRecover
                                ? tokens.accent
                                    .withValues(alpha: ZplayOpacity.overlayHover)
                                : tokens.borderSubtle,
                            borderRadius: ZplayRadius.smAll,
                          ),
                          child: Icon(
                            Icons.shield_rounded,
                            color: autoRecover ? tokens.accent : tokens.textEmphasis,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Auto-Recover Black Screens',
                                      style: ZplayType.subtitle.toStyle(
                                        color: tokens.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: tokens.success.withValues(
                                        alpha: ZplayOpacity.borderStrong,
                                      ),
                                      borderRadius: ZplayRadius.smAll,
                                    ),
                                    child: Text(
                                      'Active Watchdog',
                                      style: ZplayType.caption.toStyle(
                                        color: tokens.success,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Monitors stream startup. If audio plays for 2.5s without video frames, or a GPU decoder error occurs, the player recovers automatically. On Android it switches to software decoding only up to 1080p and re-syncs the hardware decoder above that, because a software 4K decoder needs more memory than the device has. A source that is merely not delivering data yet is waited on rather than treated as a decoder fault.',
                                style: ZplayType.bodySmall.toStyle(
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch.adaptive(
                          value: autoRecover,
                          activeColor: tokens.accent,
                          onChanged: (val) {
                            PlayerSettings.setAutoRecoverBlackScreen(val);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),

              // ── Section: Android Rendering Engine ──
              const SizedBox(height: 28),
              Row(
                children: [
                  Text(
                    'ANDROID RENDERING ENGINE',
                    style: ZplayType.overline.toStyle(color: tokens.accent),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(
                        alpha: ZplayOpacity.overlayHover,
                      ),
                      borderRadius: ZplayRadius.xsAll,
                    ),
                    child: Text(
                      'Android',
                      style: ZplayType.caption.toStyle(color: tokens.accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<bool>(
                valueListenable: PlayerSettings.enableSurfaceProducer,
                builder: (context, isSurface, _) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSurface
                          ? tokens.accentSubtle
                          : tokens.surface,
                      borderRadius: ZplayRadius.mdAll,
                      border: Border.all(
                        color: isSurface
                            ? tokens.accent
                            : tokens.borderDefault,
                        width: isSurface ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSurface
                                ? tokens.accent
                                    .withValues(alpha: ZplayOpacity.overlayHover)
                                : tokens.borderSubtle,
                            borderRadius: ZplayRadius.smAll,
                          ),
                          child: Icon(
                            Icons.layers_rounded,
                            color: isSurface ? tokens.accent : tokens.textEmphasis,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Direct Surface (SurfaceView)',
                                      style: ZplayType.subtitle.toStyle(
                                        color: tokens.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: (isSurface
                                              ? tokens.success
                                              : tokens.warning)
                                          .withValues(
                                            alpha: ZplayOpacity.borderStrong,
                                          ),
                                      borderRadius: ZplayRadius.smAll,
                                    ),
                                    child: Text(
                                      isSurface ? 'Zero-Copy' : 'Off (TextureView)',
                                      style: ZplayType.caption.toStyle(
                                        color: isSurface
                                            ? tokens.success
                                            : tokens.warning,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Uses Flutter SurfaceProducer to render frames directly to hardware surface without texture blitting. Significantly boosts 4K/60fps playback and reduces battery usage on Android. (Keep disabled if your device experiences display glitches).',
                                style: ZplayType.bodySmall.toStyle(
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch.adaptive(
                          value: isSurface,
                          activeColor: tokens.accent,
                          onChanged: (val) {
                            PlayerSettings.setEnableSurfaceProducer(val);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetCard({
    required Anime4KPreset preset,
    required String title,
    required String subtitle,
    required String tag,
    required Color tagColor,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: ZplayRadius.mdAll,
      child: AnimatedContainer(
        duration: ZplayMotion.base,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? tokens.accentSubtle
              : tokens.surface,
          borderRadius: ZplayRadius.mdAll,
          border: Border.all(
            color: isSelected
                ? tokens.accent
                : tokens.borderDefault,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? tokens.accent
                        .withValues(alpha: ZplayOpacity.overlayHover)
                    : tokens.borderSubtle,
                borderRadius: ZplayRadius.smAll,
              ),
              child: Icon(
                icon,
                color: isSelected ? tokens.accent : tokens.textEmphasis,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: ZplayType.subtitle.toStyle(
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: tagColor.withValues(
                            alpha: ZplayOpacity.borderStrong,
                          ),
                          borderRadius: ZplayRadius.smAll,
                        ),
                        child: Text(
                          tag,
                          style: ZplayType.caption.toStyle(color: tagColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: ZplayType.bodySmall.toStyle(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: isSelected ? tokens.accent : tokens.textDisabled,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHwdecCard({
    required HardwareAccelerationMode mode,
    required String title,
    required String subtitle,
    required String badgeText,
    required Color badgeColor,
    required IconData icon,
    required HardwareAccelerationMode currentMode,
  }) {
    final tokens = context.tokens;
    final isSelected = mode == currentMode;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => PlayerSettings.setHwdecMode(mode),
        borderRadius: ZplayRadius.mdAll,
        child: AnimatedContainer(
          duration: ZplayMotion.base,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? tokens.accentSubtle
                : tokens.surface,
            borderRadius: ZplayRadius.mdAll,
            border: Border.all(
              color: isSelected
                  ? tokens.accent
                  : tokens.borderDefault,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? tokens.accent
                          .withValues(alpha: ZplayOpacity.overlayHover)
                      : tokens.borderSubtle,
                  borderRadius: ZplayRadius.smAll,
                ),
                child: Icon(
                  icon,
                  color: isSelected ? tokens.accent : tokens.textEmphasis,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: ZplayType.subtitle.toStyle(
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(
                              alpha: ZplayOpacity.borderStrong,
                            ),
                            borderRadius: ZplayRadius.smAll,
                          ),
                          child: Text(
                            badgeText,
                            style: ZplayType.caption.toStyle(color: badgeColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: ZplayType.bodySmall.toStyle(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? tokens.accent : tokens.textDisabled,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: tokens.accent,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String description,
  }) {
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: tokens.accent, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: ZplayType.label.toStyle(color: tokens.textPrimary),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: ZplayType.bodySmall.toStyle(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
