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
/// Nothing here carries a resting border or a band. A chip's selected state is
/// its fill and its label colour, and the only outline a chip ever wears is the
/// app's single 3 dp accent focus ring, painted over it. Both are paint-only, so
/// neither selection nor focus moves a chip or the row it sits in. The banner
/// itself is bare: it sits on the shelf's own canvas under the page's transparent
/// chrome, and the `tokens.surface` fill with a bottom hairline it used to draw
/// was a second opaque band inside a page whose whole language is canvas first.
class MangaReaderControlBar extends StatelessWidget {
  const MangaReaderControlBar({super.key});

  @override
  Widget build(BuildContext context) {
    final isCompact = FormFactorService.of(context) == FormFactor.compact;

    return Padding(
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
          // Two disclosure chips, one line, always. A 540 dp television
          // canvas cannot afford the chip group here - see
          // [MangaAtmosphereChip] - and a `Row` of two fixed-size chips
          // cannot wrap, so this banner is one 48 dp row whatever the
          // settings behind it say.
          : const Row(
              children: [
                MangaAtmosphereChip(),
                SizedBox(width: ZplaySpacing.s16),
                MangaPageModeChip(),
              ],
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

/// Opens [values] as a focusable menu anchored under the chip at [context].
///
/// Shared by the page-mode and atmosphere chips so the two cannot drift into
/// two menu behaviours. `PopupMenuItem` rows are focusable and traversable,
/// which a bare `PopupMenuButton` child is not: it draws no focus indicator of
/// its own, so on a television the chip would be a control with no visible
/// position. The chip is therefore the trigger and the anchor, and the menu is
/// the only thing this builds.
Future<T?> _openChoiceMenu<T>(
  BuildContext context, {
  required List<T> values,
  required T current,
  required String Function(T value) label,
}) async {
  final tokens = context.tokens;
  final box = context.findRenderObject() as RenderBox?;
  final overlayBox =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (box == null || overlayBox == null) return null;

  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
  final bottomRight = box.localToGlobal(
    box.size.bottomRight(Offset.zero),
    ancestor: overlayBox,
  );

  return showMenu<T>(
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
      for (final value in values)
        PopupMenuItem<T>(
          value: value,
          child: Text(
            label(value),
            style: ZplayType.body.toStyle(
              color: value == current ? tokens.accent : tokens.textPrimary,
            ),
          ),
        ),
    ],
  );
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
    final picked = await _openChoiceMenu<MangaReadingMode>(
      context,
      values: MangaReadingMode.values,
      current: current,
      label: (mode) => mode.label,
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

/// The atmosphere group as one disclosure chip, for the shelf banner.
///
/// [MangaAtmosphereChips] is right for a pointer and for a phone. On a 540 dp
/// television canvas it is the wrong shape entirely: a label plus four 48 dp
/// chips inside an `Expanded` reflow across two or three `Wrap` rows, and the
/// banner then spends ~120 dp - nearly a quarter of the screen - restating a
/// setting the user changes once. That is what the shelf looked like on the TV:
/// a filter block that had eaten the grid.
///
/// One chip keeps the control, its focus target, its swatch and its effect on
/// the reader, and gives the shelf its screen back. The group is still the
/// control for a pointer, where it is the better shape.
class MangaAtmosphereChip extends StatelessWidget {
  const MangaAtmosphereChip({super.key});

  Future<void> _openMenu(
    BuildContext context,
    MangaReaderBackground current,
  ) async {
    final picked = await _openChoiceMenu<MangaReaderBackground>(
      context,
      values: MangaReaderBackground.values,
      current: current,
      label: (background) => background.label,
    );

    if (picked != null) await MangaSettings.setReaderBackground(picked);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MangaReaderBackground>(
      valueListenable: MangaSettings.readerBackground,
      builder: (context, current, _) => Builder(
        builder: (chipContext) => ReaderChoiceChip(
          label: 'Atmosphere: ${current.label}',
          swatch: current.color,
          selected: false,
          trailingIcon: Icons.arrow_drop_down_rounded,
          onTap: () => _openMenu(chipContext, current),
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
