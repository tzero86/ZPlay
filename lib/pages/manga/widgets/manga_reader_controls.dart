import 'package:flutter/material.dart';

import '../../../services/layout/form_factor.dart';
import '../../../services/manga/manga_settings.dart';
import '../../../services/theme/design_tokens.dart';
import '../../../widgets/common/focusable_card.dart';

/// The prototype's `.reader-control-banner`: the reader's atmosphere and page
/// mode, on the shelf rather than three taps deep in a settings sheet.
///
/// Both controls write real settings that the reader already honours —
/// [MangaSettings.readerBackground] (the page colour the reader paints) and
/// [MangaSettings.defaultReadingMode] (the mode a chapter opens in) — so this
/// bar changes what the reader does instead of restating a preference that has
/// no effect.
///
/// Nothing here carries a resting border. A chip's selected state is its fill
/// and its label colour, and the only outline a chip ever wears is the app's
/// single 2 dp accent focus ring, painted over it. Both are paint-only, so
/// neither selection nor focus moves a chip or the row it sits in.
class MangaReaderControlBar extends StatelessWidget {
  const MangaReaderControlBar({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isCompact = FormFactorService.of(context) == FormFactor.compact;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: tokens.hairline),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? ZplaySpacing.s16 : ZplaySpacing.s24,
          vertical: ZplaySpacing.s8,
        ),
        child: isCompact
            ? const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MangaAtmosphereChips(),
                  SizedBox(height: ZplaySpacing.s8),
                  MangaPageModeChip(),
                ],
              )
            : const Row(
                children: [
                  Expanded(child: MangaAtmosphereChips()),
                  SizedBox(width: ZplaySpacing.s16),
                  MangaPageModeChip(),
                ],
              ),
      ),
    );
  }
}

/// The atmosphere group on its own, for the reader's own customiser.
class MangaAtmosphereChips extends StatelessWidget {
  const MangaAtmosphereChips({super.key, this.showLabel = true});

  /// The shelf banner names the group; a dialog that already has a heading for
  /// it does not need the name twice.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return ValueListenableBuilder<MangaReaderBackground>(
      valueListenable: MangaSettings.readerBackground,
      builder: (context, current, _) => Wrap(
        spacing: ZplaySpacing.s8,
        runSpacing: ZplaySpacing.s8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (showLabel)
            Text(
              'Reader Atmosphere:',
              style: ZplayType.label.toStyle(color: tokens.textEmphasis),
            ),
          for (final background in MangaReaderBackground.values)
            ReaderChoiceChip(
              label: background.label,
              swatch: background.color,
              selected: background == current,
              onTap: () => MangaSettings.setReaderBackground(background),
            ),
        ],
      ),
    );
  }
}

/// One chip in a reader control row. Shared by the atmosphere group and the
/// page-mode selector so both read as the same control.
class ReaderChoiceChip extends StatelessWidget {
  const ReaderChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.swatch,
    this.trailingIcon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// A colour dot for a chip that stands for a colour, e.g. a page atmosphere.
  final Color? swatch;

  /// A disclosure arrow for a chip that opens a menu rather than toggling.
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final foreground = selected ? tokens.accent : tokens.textEmphasis;

    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.xsAll,
        child: AnimatedContainer(
          duration: ZplayMotion.fast,
          curve: ZplayMotion.standard,
          height: FocusMetrics.controlHeight(context),
          padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? tokens.accentSubtle
                : (state.highlighted ? tokens.borderStrong : tokens.borderDefault),
            borderRadius: ZplayRadius.xsAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (swatch != null) ...[
                Container(
                  width: ZplaySpacing.s12,
                  height: ZplaySpacing.s12,
                  decoration: BoxDecoration(
                    color: swatch,
                    shape: BoxShape.circle,
                    border: Border.all(color: tokens.borderStrong),
                  ),
                ),
                const SizedBox(width: ZplaySpacing.s8),
              ],
              Text(
                label,
                // Weight is fixed across states: a chip that thickened its
                // label when selected would widen, and the row would reflow.
                style: ZplayType.label.toStyle(color: foreground),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: ZplaySpacing.s4),
                Icon(trailingIcon, size: 18, color: foreground),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The prototype's `Page Mode: Webtoon Scroll ▾` chip, over the three modes the
/// reader actually implements.
///
/// The menu is opened by the chip's own activation, so the control is one focus
/// target: `PopupMenuItem` rows are focusable and traversable, which a bare
/// [PopupMenuButton] child would not have been — it draws no focus indicator of
/// its own, so on a television the chip would have been a control with no
/// visible position.
class MangaPageModeChip extends StatelessWidget {
  const MangaPageModeChip({super.key});

  /// `Vertical Continuous (Webtoon)` is too long for a chip; the reader's own
  /// setting page still shows the full label.
  static String shortLabel(MangaReadingMode mode) => switch (mode) {
    MangaReadingMode.webtoon => 'Webtoon Scroll',
    MangaReadingMode.horizontalLtr => 'Horizontal LTR',
    MangaReadingMode.horizontalRtl => 'Horizontal RTL',
  };

  Future<void> _openMenu(BuildContext context, MangaReadingMode current) async {
    final tokens = context.tokens;
    final box = context.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null) return;

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final bottomRight = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlayBox,
    );

    final picked = await showMenu<MangaReadingMode>(
      context: context,
      color: tokens.surfaceOverlay,
      shape: RoundedRectangleBorder(
        borderRadius: ZplayRadius.smAll,
        side: tokens.hairlineStrong,
      ),
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        bottomRight.dy + ZplaySpacing.s4,
        overlayBox.size.width - bottomRight.dx,
        0,
      ),
      items: [
        for (final mode in MangaReadingMode.values)
          PopupMenuItem<MangaReadingMode>(
            value: mode,
            child: Text(
              mode.label,
              style: ZplayType.body.toStyle(
                color: mode == current ? tokens.accent : tokens.textPrimary,
              ),
            ),
          ),
      ],
    );

    if (picked != null) await MangaSettings.setDefaultReadingMode(picked);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MangaReadingMode>(
      valueListenable: MangaSettings.defaultReadingMode,
      builder: (context, mode, _) => Builder(
        builder: (chipContext) => ReaderChoiceChip(
          label: 'Page Mode: ${shortLabel(mode)}',
          selected: false,
          trailingIcon: Icons.arrow_drop_down_rounded,
          onTap: () => _openMenu(chipContext, mode),
        ),
      ),
    );
  }
}

/// The minimum size an actionable control may present, per form factor.
///
/// A television is pointed at from across a room with a five-way pad, so every
/// target on it is at least the 48 dp comfortable minimum; a phone is held, and
/// the prototype's own chips are smaller there.
abstract final class FocusMetrics {
  static double controlHeight(BuildContext context) =>
      FormFactorService.of(context) == FormFactor.compact
      ? 40.0
      : kMinInteractiveDimension;
}
