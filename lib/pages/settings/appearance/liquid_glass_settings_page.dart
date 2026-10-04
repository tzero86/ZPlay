import 'package:flutter/material.dart';
import '../../../services/theme/design_tokens.dart';
import '../../../services/theme/glass_settings.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../widgets/common/segmented_tabs.dart';
import '../../../widgets/settings/settings_app_bar.dart';

class LiquidGlassSettingsPage extends StatefulWidget {
  const LiquidGlassSettingsPage({super.key});

  @override
  State<LiquidGlassSettingsPage> createState() => _LiquidGlassSettingsPageState();
}

class _LiquidGlassSettingsPageState extends State<LiquidGlassSettingsPage> {
  bool _previewHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: SettingsAppBar(
        title: 'Liquid Glass Setup',
        actions: [
          TextButton.icon(
            onPressed: () async {
              await GlassSettings.resetToDefaults();
              setState(() {});
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Liquid Glass settings reset to defaults.'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppThemeService.currentPalette.value.primaryColor,
                ),
              );
            },
            icon: Icon(Icons.restore_rounded, size: 18, color: tokens.textEmphasis),
            label: Text(
              'Reset',
              style: ZplayType.label.toStyle(color: tokens.textEmphasis),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              // Master Switch Card
              ValueListenableBuilder<bool>(
                valueListenable: GlassSettings.enabled,
                builder: (context, enabled, _) {
                  return Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: ZplayRadius.mdAll,
                      border: Border.all(
                        color: enabled
                            ? AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.45)
                            : tokens.borderDefault,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: ZplayOpacity.overlayHover),
                            borderRadius: ZplayRadius.smAll,
                          ),
                          child: Icon(Icons.blur_on_rounded, color: AppThemeService.currentPalette.value.primaryColor, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Enable Liquid Glass',
                                style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Real-time refraction shaders, jelly springs, and lenses',
                                style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Switch.adaptive(
                          value: enabled,
                          activeColor: AppThemeService.currentPalette.value.primaryColor,
                          onChanged: (val) {
                            GlassSettings.setEnabled(val);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              // Interactive Live Sandbox Preview
              _buildLivePreviewCard(),

              const SizedBox(height: 24),

              // Presets Selection
              Text(
                'PRESETS',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 10),
              _buildPresetsRow(),

              const SizedBox(height: 24),

              // Detailed Sliders
              Text(
                'PHYSICS & OPTICAL PARAMETERS',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),

              // 1. Hover Scale Impact
              ValueListenableBuilder<double>(
                valueListenable: GlassSettings.hoverScale,
                builder: (context, val, _) {
                  return _buildSliderTile(
                    title: 'Hover Scale Impact',
                    subtitle: 'Magnification amount applied to the player glass controls on hover',
                    valueDisplay: '${val.toStringAsFixed(2)}x',
                    value: val,
                    min: 0.95,
                    max: 1.40,
                    divisions: 45,
                    onChanged: (newVal) => GlassSettings.updateCustom(newHoverScale: newVal),
                  );
                },
              ),
              const SizedBox(height: 12),

              // 3. Wobble & Elasticity
              ValueListenableBuilder<double>(
                valueListenable: GlassSettings.wobbleIntensity,
                builder: (context, val, _) {
                  return _buildSliderTile(
                    title: 'Wobble & Fluid Elasticity',
                    subtitle: 'Spring bounce intensity and deformation responsiveness',
                    valueDisplay: '${val.toStringAsFixed(1)}x',
                    value: val,
                    min: 0.5,
                    max: 2.5,
                    divisions: 20,
                    onChanged: (newVal) => GlassSettings.updateCustom(newWobbleIntensity: newVal),
                  );
                },
              ),
              const SizedBox(height: 12),

              // 4. Lens Refraction Index
              ValueListenableBuilder<double>(
                valueListenable: GlassSettings.refractionIndex,
                builder: (context, val, _) {
                  return _buildSliderTile(
                    title: 'Optical Refraction Index',
                    subtitle: 'Light bending and background warp index inside glass lenses',
                    valueDisplay: val.toStringAsFixed(2),
                    value: val,
                    min: 1.0,
                    max: 2.2,
                    divisions: 24,
                    onChanged: (newVal) => GlassSettings.updateCustom(newRefractionIndex: newVal),
                  );
                },
              ),
              const SizedBox(height: 12),

              // 5. Magnification
              ValueListenableBuilder<double>(
                valueListenable: GlassSettings.magnification,
                builder: (context, val, _) {
                  return _buildSliderTile(
                    title: 'Lens Magnification',
                    subtitle: 'Underlying zoom factor seen through the glass volume',
                    valueDisplay: '${val.toStringAsFixed(3)}x',
                    value: val,
                    min: 1.00,
                    max: 1.12,
                    divisions: 24,
                    onChanged: (newVal) => GlassSettings.updateCustom(newMagnification: newVal),
                  );
                },
              ),
              const SizedBox(height: 12),

              // 6. Chromatic Aberration (Prism RGB)
              ValueListenableBuilder<double>(
                valueListenable: GlassSettings.chromaticAberration,
                builder: (context, val, _) {
                  return _buildSliderTile(
                    title: 'Chromatic Aberration (Prism Split)',
                    subtitle: 'Separates RGB spectrum colors along optical glass bevels',
                    valueDisplay: val.toStringAsFixed(4),
                    value: val,
                    min: 0.000,
                    max: 0.008,
                    divisions: 32,
                    onChanged: (newVal) => GlassSettings.updateCustom(newChromaticAberration: newVal),
                  );
                },
              ),
              const SizedBox(height: 12),

              // 7. Frosted Blur Sigma
              ValueListenableBuilder<double>(
                valueListenable: GlassSettings.blurSigma,
                builder: (context, val, _) {
                  return _buildSliderTile(
                    title: 'Frosted Glass Blur',
                    subtitle: 'Gaussian blur diffusion applied behind glass components',
                    valueDisplay: '${val.toStringAsFixed(1)} px',
                    value: val,
                    min: 0.0,
                    max: 10.0,
                    divisions: 20,
                    onChanged: (newVal) => GlassSettings.updateCustom(newBlurSigma: newVal),
                  );
                },
              ),
              const SizedBox(height: 12),

              // 8. Light Intensity
              ValueListenableBuilder<double>(
                valueListenable: GlassSettings.lightIntensity,
                builder: (context, val, _) {
                  return _buildSliderTile(
                    title: 'Specular Light & Shimmer',
                    subtitle: 'Glossy specular reflection and border illumination intensity',
                    valueDisplay: val.toStringAsFixed(2),
                    value: val,
                    min: 0.5,
                    max: 2.5,
                    divisions: 20,
                    onChanged: (newVal) => GlassSettings.updateCustom(newLightIntensity: newVal),
                  );
                },
              ),
              const SizedBox(height: 12),

              // 9. Border Width
              ValueListenableBuilder<double>(
                valueListenable: GlassSettings.borderWidth,
                builder: (context, val, _) {
                  return _buildSliderTile(
                    title: 'Border Width',
                    subtitle: 'Thickness of the refractive outer boundary edge',
                    valueDisplay: '${val.toStringAsFixed(1)} px',
                    value: val,
                    min: 0.5,
                    max: 3.0,
                    divisions: 25,
                    onChanged: (newVal) => GlassSettings.updateCustom(newBorderWidth: newVal),
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

  Widget _buildLivePreviewCard() {
    return ValueListenableBuilder<int>(
      valueListenable: GlassSettings.styleRevision,
      builder: (context, _, __) {
        final tokens = context.tokens;
        final enabled = GlassSettings.enabled.value;
        final hoverScaleVal = GlassSettings.hoverScale.value;
        final wobbleVal = GlassSettings.wobbleIntensity.value;

        return Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: ZplayRadius.lgAll,
            border: Border.all(color: tokens.borderDefault),
            // The sandbox backdrop is simulated content (a scene to refract),
            // not chrome, so it keeps its own hues.
            gradient: const LinearGradient(
              colors: [
                Color(0xFF2E0854),
                Color(0xFF0F172A),
                Color(0xFF00384D),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Background pattern circles
              Positioned(
                top: 20,
                left: 30,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppThemeService.currentPalette.value.primaryColor, const Color(0xFFFF2A85)],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 20,
                right: 40,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppThemeService.currentPalette.value.primaryColor, tokens.success],
                    ),
                  ),
                ),
              ),

              // Sandbox Header
              Positioned(
                top: 12,
                left: 16,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: tokens.bg.withValues(alpha: 0.4),
                        borderRadius: ZplayRadius.xsAll,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: enabled ? tokens.success : tokens.warning,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            enabled ? 'LIVE INTERACTIVE PREVIEW' : 'PREVIEW (ENABLE GLASS ABOVE)',
                            style: ZplayType.overline.toStyle(color: tokens.textEmphasis),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Interactive glass button & lens
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Glass preview button 1
                    MouseRegion(
                      onEnter: (_) => setState(() => _previewHovered = true),
                      onExit: (_) => setState(() => _previewHovered = false),
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: (190 / wobbleVal.clamp(0.5, 2.0)).round()),
                        curve: ZplayMotion.spring,
                        width: _previewHovered ? 56 * hoverScaleVal : 56,
                        height: _previewHovered ? 56 * hoverScaleVal : 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: ZplayOpacity.overlayHover),
                          borderRadius: ZplayRadius.mdAll,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: ZplayOpacity.textMuted),
                            width: GlassSettings.borderWidth.value,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.4),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(Icons.play_arrow_rounded, color: tokens.textPrimary, size: 28),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Glass preview button 2
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: ZplayOpacity.overlayHover),
                        borderRadius: ZplayRadius.mdAll,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: ZplayOpacity.textMuted),
                          width: GlassSettings.borderWidth.value,
                        ),
                      ),
                      child: Icon(Icons.auto_awesome_rounded, color: AppThemeService.currentPalette.value.primaryColor, size: 24),
                    ),
                    const SizedBox(width: 16),

                    // Glass preview button 3
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: ZplayOpacity.overlayHover),
                        borderRadius: ZplayRadius.mdAll,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: ZplayOpacity.textMuted),
                          width: GlassSettings.borderWidth.value,
                        ),
                      ),
                      child: const Icon(Icons.favorite_rounded, color: Color(0xFFFF2A85), size: 24),
                    ),
                  ],
                ),
              ),

              // Helper instruction at bottom
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'Hover or tap the icons to preview spring wobble & scale',
                    style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPresetsRow() {
    return ValueListenableBuilder<GlassPreset>(
      valueListenable: GlassSettings.preset,
      builder: (context, currentPreset, _) {
        return SegmentedTabs<GlassPreset>(
          selected: currentPreset,
          onSelected: (preset) {
            // applyPreset rewrites every slider from the preset, so re-tapping
            // the active one must stay a no-op exactly as the chip row was:
            // only a different, non-custom preset applies.
            if (preset == currentPreset || preset == GlassPreset.custom) return;
            GlassSettings.applyPreset(preset);
            setState(() {});
          },
          options: [
            for (final preset in GlassPreset.values)
              SegmentedTabOption(value: preset, label: preset.label),
          ],
        );
      },
    );
  }

  Widget _buildSliderTile({
    required String title,
    required String subtitle,
    required String valueDisplay,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: ZplayOpacity.overlayHover),
                  borderRadius: ZplayRadius.xsAll,
                ),
                child: Text(
                  valueDisplay,
                  style: ZplayType.labelNumeric.toStyle(
                    color: AppThemeService.currentPalette.value.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppThemeService.currentPalette.value.primaryColor,
              inactiveTrackColor: Colors.white.withValues(alpha: ZplayOpacity.borderDefault),
              thumbColor: AppThemeService.currentPalette.value.primaryColor,
              overlayColor: AppThemeService.currentPalette.value.primaryColor.withValues(alpha: ZplayOpacity.overlayHover),
              trackHeight: 4,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
