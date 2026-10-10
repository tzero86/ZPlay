import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/books/reader_settings.dart';
import '../../../services/theme/design_tokens.dart';
import '../../../widgets/common/focusable_card.dart';
import 'reader_design_tokens.dart';

class ReaderCustomizationSheet extends StatefulWidget {
  final String? realBookSampleText;

  const ReaderCustomizationSheet({
    super.key,
    this.realBookSampleText,
  });

  static Future<void> show(BuildContext context, {String? realBookSampleText}) {
    final isDesktop = MediaQuery.of(context).size.width > 760;

    if (isDesktop) {
      // Right side panel on desktop
      return showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Close Settings',
        barrierColor: Colors.black.withValues(alpha: 0.4),
        transitionDuration: ReaderTokens.motionSheet,
        pageBuilder: (ctx, anim1, anim2) {
          return Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Colors.transparent,
              child: ReaderCustomizationSheet(realBookSampleText: realBookSampleText),
            ),
          );
        },
        transitionBuilder: (ctx, anim1, anim2, child) {
          final curved = CurvedAnimation(parent: anim1, curve: ReaderTokens.curveSheet);
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(curved),
            child: child,
          );
        },
      );
    }

    // Bottom sheet on mobile
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReaderCustomizationSheet(realBookSampleText: realBookSampleText),
    );
  }

  @override
  State<ReaderCustomizationSheet> createState() => _ReaderCustomizationSheetState();
}

class _ReaderCustomizationSheetState extends State<ReaderCustomizationSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _showResetSuccess = false;
  Timer? _resetTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _triggerReset() {
    HapticFeedback.lightImpact();
    ReaderSettings.resetToDefaults();
    setState(() => _showResetSuccess = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() => _showResetSuccess = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReaderSettingsData>(
      valueListenable: ReaderSettings.settingsNotifier,
      builder: (context, settings, _) {
        final isDesktop = MediaQuery.of(context).size.width > 760;

        final container = Container(
          width: isDesktop ? 380 : double.infinity,
          height: isDesktop ? double.infinity : null,
          constraints: isDesktop
              ? null
              : BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
          decoration: BoxDecoration(
            color: ReaderTokens.surfaceOverlay,
            borderRadius: isDesktop
                ? const BorderRadius.horizontal(left: Radius.circular(ReaderTokens.radius24))
                : const BorderRadius.vertical(top: Radius.circular(ReaderTokens.radius24)),
            // No outline: the sheet's own scrim is its edge, and a hairline
            // around a floating surface is the second frame the quiet language
            // drops. The soft shadow still separates it from the page.
            boxShadow: const [ReaderTokens.shadowMd],
          ),
          child: Column(
            mainAxisSize: isDesktop ? MainAxisSize.max : MainAxisSize.min,
            children: [
              // Mobile Drag Handle
              if (!isDesktop)
                Container(
                  margin: const EdgeInsets.only(top: ReaderTokens.space12, bottom: ReaderTokens.space8),
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ReaderTokens.textDisabled,
                    borderRadius: ReaderTokens.rounded4,
                  ),
                ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ReaderTokens.space24,
                  ReaderTokens.space12,
                  ReaderTokens.space16,
                  ReaderTokens.space8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tune_rounded, color: ReaderTokens.accent, size: 18),
                        const SizedBox(width: ReaderTokens.space8),
                        Text(
                          'Appearance',
                          style: ZplayType.title.toStyle(
                            color: ReaderTokens.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    FocusableCard(
                      onTap: () => Navigator.of(context).pop(),
                      builder: (context, state) => SizedBox(
                        width: 40,
                        height: 40,
                        child: CardFocusRing(
                          focused: state.focused,
                          radius: ZplayRadius.fullAll,
                          child: Center(
                            child: Icon(
                              Icons.close_rounded,
                              // Paints its own focus ring, so a Material
                              // button's highlight would be a second indicator
                              // on the one control that is always in reach.
                              color: ReaderTokens.textSecondary,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Real Book Text Live Preview
              _buildLivePreview(settings),

              // Underline Tab Bar. No bottom hairline under it: the control's
              // own accent indicator marks the selected tab, and the line the
              // container used to draw was a second edge under the sheet's
              // chrome.
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ReaderTokens.space24,
                  vertical: ReaderTokens.space8,
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicatorColor: ReaderTokens.accent,
                  indicatorWeight: 2.5,
                  labelColor: ReaderTokens.accent,
                  unselectedLabelColor: ReaderTokens.textSecondary,
                  labelStyle: ReaderTokens.tabLabel,
                  tabs: const [
                    Tab(text: 'Typography'),
                    Tab(text: 'Theme'),
                    Tab(text: 'Layout'),
                  ],
                ),
              ),

              // Tab Views
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2.5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: ReaderTokens.accent,
                    inactiveTrackColor: ReaderTokens.borderDefault,
                    thumbColor: ReaderTokens.accent,
                    showValueIndicator: ShowValueIndicator.onlyForContinuous,
                    valueIndicatorColor: ReaderTokens.accent,
                    valueIndicatorTextStyle: ZplayType.caption.toStyle(
                      color: ReaderTokens.onAccent,
                    ),
                  ),
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTypographyTab(settings),
                      _buildThemeTab(settings),
                      _buildLayoutTab(settings),
                    ],
                  ),
                ),
              ),

              // Bottom Actions. No top hairline: the row floats on the sheet's
              // own surface, and the quiet reset control marks focus with the
              // app's single ring rather than a Material button's highlight.
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ReaderTokens.space24,
                  vertical: ReaderTokens.space12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    FocusableCard(
                      onTap: _triggerReset,
                      builder: (context, state) => CardFocusRing(
                        focused: state.focused,
                        radius: ZplayRadius.smAll,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ReaderTokens.space8,
                            vertical: ReaderTokens.space8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _showResetSuccess
                                    ? Icons.check_rounded
                                    : Icons.restart_alt_rounded,
                                size: 16,
                                color: _showResetSuccess
                                    ? ReaderTokens.success
                                    : ReaderTokens.textSecondary,
                              ),
                              const SizedBox(width: ReaderTokens.space8),
                              Text(
                                _showResetSuccess ? 'Reset ✓' : 'Reset to Defaults',
                                style: ZplayType.label.toStyle(
                                  color: _showResetSuccess
                                      ? ReaderTokens.success
                                      : ReaderTokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Text(
                      'v2.0',
                      style: ZplayType.caption.toStyle(
                        color: ReaderTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        return container;
      },
    );
  }

  Widget _buildLivePreview(ReaderSettingsData settings) {
    final previewText = widget.realBookSampleText?.isNotEmpty == true
        ? widget.realBookSampleText!
        : '“It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.”';

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: ReaderTokens.space24,
        vertical: ReaderTokens.space8,
      ),
      padding: const EdgeInsets.all(ReaderTokens.space16),
      decoration: BoxDecoration(
        color: settings.backgroundColor,
        borderRadius: ReaderTokens.rounded16,
        border: Border.all(color: settings.borderColor),
        boxShadow: const [ReaderTokens.shadowSm],
      ),
      child: Text(
        previewText,
        textAlign: settings.textAlign,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: settings.fontFamily,
          fontSize: settings.fontSize.clamp(14.0, 20.0),
          height: settings.lineSpacing,
          letterSpacing: settings.letterSpacing,
          color: settings.textColor,
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 1. TYPOGRAPHY TAB
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildTypographyTab(ReaderSettingsData settings) {
    final fonts = [
      {'name': 'Georgia', 'key': 'Georgia', 'sub': 'Serif'},
      {'name': 'Merriweather', 'key': 'Merriweather', 'sub': 'Serif'},
      {'name': 'Inter', 'key': 'Inter', 'sub': 'Sans'},
      {'name': 'Poppins', 'key': 'Poppins', 'sub': 'Sans'},
      {'name': 'OpenDyslexic', 'key': 'OpenDyslexic', 'sub': 'Dyslexic'},
      {'name': 'Monospace', 'key': 'Courier New', 'sub': 'Mono'},
    ];

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(ReaderTokens.space24),
      children: [
        _buildSectionTitle('Font Family'),
        const SizedBox(height: ReaderTokens.space8),
        Wrap(
          spacing: ReaderTokens.space8,
          runSpacing: ReaderTokens.space8,
          children: fonts.map((f) {
            final isSelected = settings.fontFamily == f['key'];
            return ChoiceChip(
              label: Text('${f['name']}'),
              selected: isSelected,
              onSelected: (_) {
                HapticFeedback.selectionClick();
                ReaderSettings.updateFontFamily(f['key']!);
              },
              selectedColor: ReaderTokens.accent,
              backgroundColor: ReaderTokens.surface,
              shape: RoundedRectangleBorder(
                borderRadius: ReaderTokens.rounded8,
                side: BorderSide(
                  color: isSelected ? Colors.transparent : ReaderTokens.borderDefault,
                ),
              ),
              labelStyle: ZplayType.label
                  .toStyle(
                    color: isSelected
                        ? ReaderTokens.onAccent
                        : ReaderTokens.textPrimary,
                  )
                  .copyWith(fontFamily: f['key']),
            );
          }).toList(),
        ),
        const SizedBox(height: ReaderTokens.space24),

        // Font Size Slider
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle('Font Size'),
            Text(
              '${settings.fontSize.round()} px',
              style: ZplayType.label
                  .copyWith(weight: FontWeight.w700)
                  .toStyle(color: ReaderTokens.textPrimary),
            ),
          ],
        ),
        Row(
          children: [
            Text('A', style: ZplayType.bodySmall.copyWith(weight: FontWeight.w700).toStyle(color: ReaderTokens.textSecondary)),
            Expanded(
              child: Slider(
                value: settings.fontSize,
                min: 14,
                max: 34,
                divisions: 10,
                label: '${settings.fontSize.round()}px',
                onChanged: (val) => ReaderSettings.updateFontSize(val),
              ),
            ),
            Text('A', style: ZplayType.titleLarge.toStyle(color: ReaderTokens.textSecondary)),
          ],
        ),
        const SizedBox(height: ReaderTokens.space16),

        // Line Spacing Slider
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle('Line Height'),
            Text(
              '${settings.lineSpacing.toStringAsFixed(2)}×',
              style: ZplayType.label
                  .copyWith(weight: FontWeight.w700)
                  .toStyle(color: ReaderTokens.textPrimary),
            ),
          ],
        ),
        Slider(
          value: settings.lineSpacing,
          min: 1.2,
          max: 2.2,
          divisions: 10,
          label: '${settings.lineSpacing.toStringAsFixed(2)}×',
          onChanged: (val) => ReaderSettings.updateLineSpacing(val),
        ),
        const SizedBox(height: ReaderTokens.space16),

        // Alignment & First-Line Indent
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Alignment'),
                  const SizedBox(height: ReaderTokens.space8),
                  Row(
                    children: [
                      _buildAlignButton(Icons.format_align_left_rounded, TextAlign.left, settings),
                      const SizedBox(width: ReaderTokens.space8),
                      _buildAlignButton(Icons.format_align_justify_rounded, TextAlign.justify, settings),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('First-Line Indent'),
                  const SizedBox(height: ReaderTokens.space8),
                  Switch.adaptive(
                    value: settings.firstLineIndent,
                    activeColor: ReaderTokens.accent,
                    onChanged: (val) {
                      HapticFeedback.selectionClick();
                      ReaderSettings.updateFirstLineIndent(val);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 2. THEME & BRIGHTNESS TAB
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildThemeTab(ReaderSettingsData settings) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(ReaderTokens.space24),
      children: [
        _buildSectionTitle('Reading Themes'),
        const SizedBox(height: ReaderTokens.space12),
        Row(
          children: [
            _buildThemeSwatchCard(
              label: 'Light',
              theme: ReaderTheme.light,
              current: settings.theme,
              bg: const Color(0xFFFAFAFA),
              textColor: const Color(0xFF1F2328),
              border: const Color(0xFFD0D7DE),
            ),
            const SizedBox(width: ReaderTokens.space8),
            _buildThemeSwatchCard(
              label: 'Sepia',
              theme: ReaderTheme.sepia,
              current: settings.theme,
              bg: const Color(0xFFF4ECD8),
              textColor: const Color(0xFF382717),
              border: const Color(0xFFD4C8B0),
            ),
            const SizedBox(width: ReaderTokens.space8),
            _buildThemeSwatchCard(
              label: 'Dark',
              theme: ReaderTheme.dark,
              current: settings.theme,
              bg: const Color(0xFF141419),
              textColor: const Color(0xFFE6E8ED),
              border: const Color(0xFF2A2E3D),
            ),
            const SizedBox(width: ReaderTokens.space8),
            _buildThemeSwatchCard(
              label: 'AMOLED',
              theme: ReaderTheme.amoled,
              current: settings.theme,
              bg: Colors.black,
              textColor: const Color(0xFFE5E5E5),
              border: const Color(0xFF262626),
            ),
          ],
        ),
        const SizedBox(height: ReaderTokens.space32),

        // In-App Brightness Dimmer
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle('Reader Brightness'),
            Text(
              '${(settings.brightness * 100).round()}%',
              style: ZplayType.label
                  .copyWith(weight: FontWeight.w700)
                  .toStyle(color: ReaderTokens.textPrimary),
            ),
          ],
        ),
        Row(
          children: [
            Icon(Icons.brightness_low_rounded, color: ReaderTokens.textSecondary, size: 18),
            Expanded(
              child: Slider(
                value: settings.brightness,
                min: 0.2,
                max: 1.0,
                divisions: 8,
                label: '${(settings.brightness * 100).round()}%',
                onChanged: (val) => ReaderSettings.updateBrightness(val),
              ),
            ),
            Icon(Icons.brightness_high_rounded, color: ReaderTokens.textSecondary, size: 20),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 3. LAYOUT TAB
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildLayoutTab(ReaderSettingsData settings) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(ReaderTokens.space24),
      children: [
        _buildSectionTitle('Page Margins'),
        const SizedBox(height: ReaderTokens.space12),
        Row(
          children: [
            _buildMarginChip('Compact', MarginPreset.compact, settings),
            const SizedBox(width: ReaderTokens.space8),
            _buildMarginChip('Balanced', MarginPreset.balanced, settings),
            const SizedBox(width: ReaderTokens.space8),
            _buildMarginChip('Wide', MarginPreset.wide, settings),
          ],
        ),
        const SizedBox(height: ReaderTokens.space24),

        _buildSectionTitle('Reading Mode'),
        const SizedBox(height: ReaderTokens.space12),
        Row(
          children: [
            Expanded(
              child: _buildModeButton(
                icon: Icons.unfold_more_rounded,
                label: 'Continuous Scroll',
                mode: ReaderMode.scroll,
                settings: settings,
              ),
            ),
            const SizedBox(width: ReaderTokens.space12),
            Expanded(
              child: _buildModeButton(
                icon: Icons.auto_stories_rounded,
                label: 'Paginated Turns',
                mode: ReaderMode.paginated,
                settings: settings,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HELPER WIDGETS
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: ZplayType.label.toStyle(color: ReaderTokens.textSecondary),
    );
  }

  Widget _buildThemeSwatchCard({
    required String label,
    required ReaderTheme theme,
    required ReaderTheme current,
    required Color bg,
    required Color textColor,
    required Color border,
  }) {
    final isSelected = theme == current;
    return Expanded(
      child: FocusableCard(
        onTap: () {
          HapticFeedback.lightImpact();
          ReaderSettings.updateTheme(theme);
        },
        builder: (context, _) => Container(
          height: 64,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: ReaderTokens.rounded12,
            border: Border.all(
              color: isSelected ? ReaderTokens.accent : border,
              width: isSelected ? 2.2 : 1.0,
            ),
            boxShadow: isSelected
                ? [ReaderTokens.shadowGlow(ReaderTokens.accent)]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Mini color swatch dot pair
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: textColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: border, width: 0.5),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: bg,
                      shape: BoxShape.circle,
                      border: Border.all(color: textColor.withValues(alpha: 0.5), width: 0.8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ReaderTokens.space4),
              Text(
                label,
                style: ZplayType.caption
                    .copyWith(
                      weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    )
                    .toStyle(color: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlignButton(IconData icon, TextAlign align, ReaderSettingsData settings) {
    final isSelected = settings.textAlign == align;
    return IconButton.filledTonal(
      icon: Icon(icon, size: 20),
      onPressed: () {
        HapticFeedback.selectionClick();
        ReaderSettings.updateTextAlign(align);
      },
      style: IconButton.styleFrom(
        backgroundColor: isSelected ? ReaderTokens.accent : ReaderTokens.surface,
        foregroundColor: isSelected ? ReaderTokens.onAccent : ReaderTokens.textSecondary,
        side: BorderSide(
          color: isSelected ? Colors.transparent : ReaderTokens.borderDefault,
        ),
        shape: const RoundedRectangleBorder(borderRadius: ReaderTokens.rounded8),
      ),
    );
  }

  Widget _buildMarginChip(String label, MarginPreset preset, ReaderSettingsData settings) {
    final isSelected = settings.marginPreset == preset;
    return Expanded(
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          HapticFeedback.selectionClick();
          ReaderSettings.updateMarginPreset(preset);
        },
        selectedColor: ReaderTokens.accent,
        backgroundColor: ReaderTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: ReaderTokens.rounded8,
          side: BorderSide(
            color: isSelected ? Colors.transparent : ReaderTokens.borderDefault,
          ),
        ),
        labelStyle: ZplayType.caption
            .copyWith(
              weight: isSelected ? FontWeight.w700 : FontWeight.w400,
            )
            .toStyle(
              color: isSelected ? ReaderTokens.onAccent : ReaderTokens.textPrimary,
            ),
      ),
    );
  }

  Widget _buildModeButton({
    required IconData icon,
    required String label,
    required ReaderMode mode,
    required ReaderSettingsData settings,
  }) {
    final isSelected = settings.mode == mode;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        ReaderSettings.updateMode(mode);
      },
      borderRadius: ReaderTokens.rounded12,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: ReaderTokens.space12),
        decoration: BoxDecoration(
          color: isSelected ? ReaderTokens.accentSubtle : ReaderTokens.surface,
          borderRadius: ReaderTokens.rounded12,
          border: Border.all(
            color: isSelected ? ReaderTokens.accent : ReaderTokens.borderDefault,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? ReaderTokens.accent : ReaderTokens.textSecondary,
              size: 20,
            ),
            const SizedBox(height: ReaderTokens.space4),
            Text(
              label,
              style: ZplayType.caption
                  .copyWith(
                    weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  )
                  .toStyle(
                    color: isSelected
                        ? ReaderTokens.accent
                        : ReaderTokens.textPrimary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
