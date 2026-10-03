import 'package:flutter/material.dart';
import '../../widgets/common/zplay_logo.dart';

import '../services/layout/form_factor.dart';
import '../services/theme/design_tokens.dart';
import '../services/window/window_service.dart';
import '../widgets/common/focusable_card.dart';
import 'app_shell.dart';

/// The app's only navigation control.
///
/// The shell owns navigation, so nothing below it may draw a rail, bar, drawer
/// or dock. That is the point of the rewrite: the old design let every page
/// mount its own floating dock, which is how the app ended up with four
/// competing navigation models (the dock, Home's app-bar icons, Home's filter
/// tabs, and Music's private sidebar), with Anime reachable from two of them.
///
/// **Search is a row on every form factor**, including desktop, where the
/// prototype drew a search field at the head of the content. A shell-level field
/// would stack a second bar on top of each page's own header, because every slot
/// page keeps its own top bar and its own `Scaffold`. Search therefore stays one
/// affordance in the rail, and the desktop keyboard map (`Ctrl+K`) is what makes
/// it fast there.
///
/// The rail reserves its own space: it is a real layout child with a pinned
/// width or height, so no page ever needs padding to clear the shell.
class ShellRail extends StatelessWidget {
  const ShellRail({
    super.key,
    required this.current,
    required this.onSelect,
    this.autofocus = false,
  });

  final ShellSlot current;
  final ValueChanged<ShellSlot> onSelect;

  /// Give the selected row the shell's starting focus.
  ///
  /// On the selected row and not the first one, because selection is the one
  /// state the rail already draws at ten feet: a remote that lands on a row
  /// which is not the slot the user is on is reading a control that disagrees
  /// with the page beside it.
  ///
  /// The caller decides, because only it knows the form factor. A television
  /// needs somewhere to start; a pointer device does not, and an autofocused
  /// row there is a ring the user never asked for.
  final bool autofocus;

  /// Pinned by the contract. These three have no step on [ZplaySpacing] (40 and
  /// 48 are the neighbours of 44), so they are named once here instead of being
  /// repeated as bare numbers at each use.
  static const double _sideRailWidth = 88;
  static const double _expandedRowHeight = 44;

  /// **The ten-foot rail is icons only, and its width follows from that.**
  ///
  /// It used to be a labelled 236 dp, which was a desktop number: 12% of a
  /// 1920 dp window, and comfortable. A television does not present that
  /// canvas. A Chromecast with Google TV reports 1920x1080 at density 320, so
  /// Flutter divides by 2.0 and the canvas is 960x540 dp - the same 236 dp is
  /// then a quarter of the screen, and the labels truncate to `H...` and
  /// `Br...` on a canvas below the 600 dp phone breakpoint. Verified on the
  /// device: `dumpsys window displays` reports
  /// `w960dp h540dp 320dpi television -touch dpad/v`, with the 1920x1080 as
  /// the device's own base display rather than an override the app asked for.
  ///
  /// **Density is the axis that actually mattered, and the first fix missed
  /// it.** Scaling by canvas width took the rail from 236 to 172 dp, which is
  /// only 17.9% of the panel instead of 24.5% - it helped, and it was still
  /// wrong. At DPR 2 every logical pixel is two physical ones, so 172 dp is
  /// **344 physical pixels** of a 3840 px panel: twice the physical width of
  /// the desktop rail it was copied from, and 30 physical pixels of label
  /// height. The proportion looked acceptable in a screenshot; the physical
  /// size, which is what crosses the room, was not.
  ///
  /// Dropping the labels removed the type ladder and the label-fit measurement
  /// with it. The rows keep their semantics label and their tooltip, so a screen
  /// reader and a pointer both still get the name.
  ///
  /// **64 dp, not 88, and the reference app on this exact panel is the
  /// measurement.** `_sideRailWidth` is the desktop number and was being reused
  /// for the television without asking whether a 10-foot surface wants a
  /// pointer-sized strip. Stremio, launched on the same Chromecast with Google
  /// TV at the same 1920x1080 / 320 density, draws a **~67 dp** sidebar with
  /// **~22 dp** glyphs on a **~53 dp** pitch; ours was 88 dp with 32 dp glyphs
  /// on a 72 dp pitch. Nothing about the rail needs the extra 24 dp - it is
  /// icons, and an icon does not get more legible for sitting in a wider box -
  /// so the width is content plus gutter and the difference goes to the page
  /// beside it. A background is allowed to bleed, which is why the fill and its
  /// hairline still run to the panel edge on every side.
  ///
  /// This departs from Android TV and tvOS, which both label their rails. The
  /// departure is deliberate and specific to a 55" set at across-room distance,
  /// where a wide labelled strip buys a name the focus ring and the selected
  /// page title already provide.
  static const double _televisionRailWidth = 64;

  /// The ten-foot row pitch, matched to the same sidebar measurement.
  ///
  /// 48 dp of target plus a 4 dp gap is a 52 dp pitch, against the reference
  /// app's ~53, and 48 dp is the accessibility floor rather than a taste call:
  /// the ten-foot row used to be 64 dp, which at 540 dp tall was 12% of the
  /// visible height per row for a glyph of 24.
  static const double _televisionRowHeight = 48;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context);
    return switch (FormFactorService.of(context)) {
      FormFactor.compact => _bottomBar(context, inset),
      final formFactor => _sideRail(context, inset, formFactor),
    };
  }

  /// Phone: the same five rows laid out horizontally.
  Widget _bottomBar(BuildContext context, EdgeInsets inset) {
    final tokens = context.tokens;
    return SizedBox(
      // The shell places this flush with the bottom edge and does not wrap it in
      // a `SafeArea`, so the home indicator inset is added to the pinned 64 px
      // rather than taken out of it.
      height: ZplaySpacing.s64 + inset.bottom,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          // The content is above the bar, so the hairline is on its top edge.
          border: Border(top: tokens.hairline),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            ZplaySpacing.s8 + inset.left,
            ZplaySpacing.s8,
            ZplaySpacing.s8 + inset.right,
            ZplaySpacing.s8 + inset.bottom,
          ),
          child: Row(
            spacing: ZplaySpacing.s4,
            children: [
              for (final slot in ShellSlot.values)
                Expanded(
                  child: _row(
                    slot,
                    television: false,
                    height: ZplaySpacing.s48,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tablet, desktop and ten-foot: a left rail at three widths and row targets.
  Widget _sideRail(
    BuildContext context,
    EdgeInsets inset,
    FormFactor formFactor,
  ) {
    final tokens = context.tokens;
    final television = formFactor == FormFactor.television;
    final rowHeight = switch (formFactor) {
      FormFactor.medium => ZplaySpacing.s48,
      FormFactor.expanded => _expandedRowHeight,
      _ => _televisionRowHeight,
    };
    // **The television rail's gutter is 12 dp, and the icon is centred in what
    // is left.** The 5% overscan margin this briefly carried was reverted on
    // measurement: this panel does not crop, a television reports no inset for
    // it, and the margin was 48 dp of the 64 dp rail - it left a 16 dp column
    // for a 24 dp glyph and it cost the page beside it every dp of the
    // difference. Density wins on a panel that does not overscan, so the rail is
    // gutter + glyph + gutter (12 + 40 + 12) and the icon lands 20 dp from the
    // edge, against the reference app's ~22.
    final double padH = television ? ZplaySpacing.s12 : ZplaySpacing.s8;
    final double padV = television ? ZplaySpacing.s16 : ZplaySpacing.s8;

    // Settings is pinned to the foot on every rail, which is what the prototype
    // does at all three widths: it is the least-used row and the one that should
    // not sit between the content rows.
    final leading = <Widget>[];
    for (final slot in ShellSlot.values) {
      if (slot == ShellSlot.settings) continue;
      if (leading.isNotEmpty) {
        leading.add(const SizedBox(height: ZplaySpacing.s4));
      }
      leading.add(_row(slot, television: television, height: rowHeight));
    }

    return SizedBox(
      // The rail fills the column it is given, so its fill and its hairline run
      // the whole height of the window rather than only behind the rows. The
      // shell mounts it with the default (centred) cross-axis alignment, which
      // would otherwise let it shrink to its content.
      width: (television ? _televisionRailWidth : _sideRailWidth) + inset.left,
      height: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          // Content sits to the right of a left rail.
          border: Border(right: tokens.hairline),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            padH + inset.left,
            padV + inset.top,
            padH,
            padV + inset.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (television) ...[
                _head(context, tokens),
                const SizedBox(height: ZplaySpacing.s16),
              ],
              ...leading,
              const Spacer(),
              // A hairline, not just the gap.
              //
              // The [Spacer] already pushes the fullscreen toggle and Settings
              // to the foot, which is positioning - and on a television with no
              // text labels in the rail, positioning is all the user had to go on
              // for "these two are utilities, those four are where the content
              // is". Four identical glyphs and two identical glyphs, sorted only
              // by distance from the bottom edge, is a rail that asks the user to
              // have already learned it.
              //
              // Drawn inside the rail's own padding rather than as a list
              // separator, so it spans the gutter the rows sit in and reads as a
              // division of the rail rather than as a rule floating over it.
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: television ? ZplaySpacing.s4 : 0,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: tokens.hairline),
                  ),
                  child: const SizedBox(height: ZplaySpacing.s8),
                ),
              ),
              _fullscreenRow(television: television, height: rowHeight),
              const SizedBox(height: ZplaySpacing.s4),
              _row(
                ShellSlot.settings,
                television: television,
                height: rowHeight,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The brand mark, ten-foot only.
  ///
  /// The wordmark was here with a comment already saying 88 px could not hold
  /// both, and the comment was right: at 88 dp the row below overflows by 94 px.
  /// The mark alone carries the brand at this width, and the selected page
  /// already says where the user is.
  ///
  /// 24 dp, the same as a row glyph and a step down from the 32 it was, because
  /// the rail is now 64 dp with a 40 dp content column. Matching the glyphs keeps
  /// the rail reading as one column of 24 dp marks rather than a mark that juts
  /// past every row beneath it.
  Widget _head(BuildContext context, ZplayTokens tokens) =>
      const ZplayLogo(size: ZplaySpacing.s24);

  Widget _row(
    ShellSlot slot, {
    required bool television,
    required double height,
  }) {
    final chrome = _slotChrome(slot);
    return _RailRow(
      label: chrome.label,
      icon: chrome.icon,
      selected: slot == current,
      television: television,
      height: height,
      // Only the selected row claims the starting focus, so the shell's
      // autofocus cannot land on two rows at once when the rail is rebuilt.
      autofocus: autofocus && slot == current,
      onTap: () => onSelect(slot),
    );
  }

  /// The fullscreen toggle, pinned to the rail foot above Settings.
  ///
  /// Fullscreen is window state, not a destination: no page is mounted for it
  /// and it never owns the content area, which is why it is not a [ShellSlot].
  /// It rides in the rail because the rail is the one piece of chrome every
  /// slot paints, so both the way in and the way out of fullscreen follow the
  /// user instead of being reachable only from Home. The keyboard path is the
  /// shell's F11 binding, so the tooltip names the key.
  ///
  /// Every rail that has room for it, which is the side rail at all three
  /// widths, gets it. The compact bottom bar does not: it is a phone, its five
  /// slot rows already fill the width, and the platform there owns the window
  /// insets rather than a key.
  Widget _fullscreenRow({required bool television, required double height}) {
    final window = WindowService.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: window.isFullscreenNotifier,
      builder: (context, isFullscreen, _) => _RailRow(
        label: isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
        tooltip: isFullscreen ? 'Exit Fullscreen (F11)' : 'Fullscreen (F11)',
        icon: isFullscreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
        // Taking the accent while the window is fullscreen is the state the row
        // has to report: the glyph alone is easy to miss at a glance.
        selected: isFullscreen,
        television: television,
        height: height,
        onTap: window.toggleFullscreen,
      ),
    );
  }
}

/// One row: the whole hit target, including its label.
///
/// Label and icon arrive already resolved rather than as a [ShellSlot], so the
/// rail's two kinds of row, a slot and the fullscreen toggle, share one look
/// instead of drifting apart as two near-identical styles.
class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.television,
    required this.height,
    required this.onTap,
    this.autofocus = false,
    this.tooltip,
  });

  final String label;
  final IconData icon;

  /// Passed straight to [FocusableCard]; see [ShellRail.autofocus] for why only
  /// one row in a rail ever sets it.
  final bool autofocus;

  /// The pointer path to the name. Defaults to [label]; the fullscreen row
  /// overrides it to name its key.
  final String? tooltip;
  final bool selected;
  final bool television;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final tooltipMessage = tooltip ?? label;
    // Collapsed when the platform asks for reduced motion, per the guidance on
    // [ZplayMotion]: the curve stays, the duration does not.
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : ZplayMotion.base;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      // Own the whole row: without excluding the descendants the icon and the
      // label are announced as separate items with no button or selected state
      // on either, and the tap action would be dropped along with them.
      excludeSemantics: true,
      onTap: onTap,
      child: FocusableCard(
        onTap: onTap,
        autofocus: autofocus,
        builder: (context, state) => CardFocusRing(
          focused: state.focused,
          radius: ZplayRadius.smAll,
          child: AnimatedContainer(
            duration: duration,
            curve: ZplayMotion.standard,
            height: height,
            // No horizontal padding. It was 8 dp on a television to centre a
            // 32 px icon in a 64 dp row box; the row box is now the rail less
            // its two 12 dp gutters, and the 24 px glyph is centred in it by the
            // row's own cross-axis stretch. Dropping it also makes the row and
            // the pointer devices' rows the same shape, which is one fewer
            // branch in this widget.
            decoration: BoxDecoration(
              color: selected ? tokens.accentSubtle : Colors.transparent,
              borderRadius: ZplayRadius.smAll,
              // **No border on a row that is focused.**
              //
              // This was `selected ? transparent : borderDefault`, on the
              // reasoning that a transparent border is "not painted". It is
              // painted - Flutter reserves the 2 dp and composites the
              // transparent colour over whatever is behind it, so the row's own
              // surface shows through the slot and you get a faint band beside
              // the focus ring. The comment above it claimed this was the fix
              // for the double border; it was the cause.
              //
              // Measured on the television, Home focused, vertical profile
              // through the row:
              //
              //   dp 137.5-139.5   2.5 dp   lum  54   <- this border
              //   dp 143.5-150.0   7.0 dp   lum 252   <- CardFocusRing
              //
              // Two rings, 4 dp apart: the "ghost border inside the shape". An
              // unfocused row shows one band at dp 198.5-220.5, which is its own
              // 2 dp border around the 24 dp glyph, and no second ring.
              //
              // So: when focused, no border at all - [CardFocusRing] is the only
              // ring, and it is the one that means something. The geometry the
              // unselected rows keep is untouched, so the icon cannot shift.
              // Every row carries a border of the same width, always.
              //
              // It used to be `!state.focused ? Border.all(...) : null`, on the
              // reasoning that removing the border would remove the second ring
              // - true, and it did that at the cost of something far worse.
              // Flutter reserves the space whether or not it is painted, so a
              // row that *drops* its border is 4 dp narrower than one that keeps
              // it. The icon is centred in that box, so selecting a row resized
              // it and nudged the glyph: visible as the sidebar icon jumping and
              // growing the moment it was selected. The user reported it as a
              // positioning bug and it was a box-size bug.
              //
              // A transparent border reserves the space and paints nothing, so
              // the box is identical in both states and the focus ring stands
              // alone. That is the whole fix: same width always, colour varies.
              border: television
                  ? Border.all(
                      color: state.focused ? Colors.transparent : tokens.borderDefault,
                      width: ZplaySpacing.s2,
                    )
                  : null,
            ),
            // Icons only on a television.
            //
            // Both Android TV and tvOS label their rails, and the reasoning was
            // sound: at ten feet a glyph is a guess. It does not survive a 55"
            // set at across-room distance, where the labelled rail is 344
            // physical pixels wide - two thirds of it label - and the labels
            // truncate on a 960 dp canvas anyway. Dropping them takes the rail
            // from 172 dp to 88, the same as every other form factor, and leaves
            // the page to name the destination, which it already does.
            //
            // The name is not lost: the `Semantics` above carries it for a
            // screen reader, and the tooltip is the pointer path back to it.
            child: Tooltip(
              message: tooltipMessage,
              child: _icon(icon, tokens, state),
            ),
          ),
        ),
      ),
    );
  }

  Widget _icon(
    IconData icon,
    ZplayTokens tokens,
    CardInteraction state,
  ) => Icon(
    icon,
    // One size for every form factor now. The ten-foot rail used to draw 32
    // px inside a 64 dp row in an 88 dp rail, which is the whole of what the
    // user called wasted space: the reference app draws ~22 px glyphs in a
    // ~67 dp sidebar on this same panel, and 24 matches the pointer rail it
    // already shipped.
    size: ZplaySpacing.s24,
    color: _foreground(tokens, state),
  );

  /// Hover and focus raise the row to primary text rather than filling it: the
  /// accent fill goes on meaning one thing, a state that is currently on, which
  /// is the slot you are on or the fullscreen row while the window is
  /// fullscreen.
  Color _foreground(ZplayTokens tokens, CardInteraction state) => selected
      ? tokens.accent
      : state.highlighted
      ? tokens.textPrimary
      : tokens.textSecondary;
}

/// Label and icon per slot. Kept out of the enum: the enum is the shell's
/// routing vocabulary and should not carry display strings.
({String label, IconData icon}) _slotChrome(ShellSlot slot) => switch (slot) {
  ShellSlot.home => (label: 'Home', icon: Icons.home_rounded),
  ShellSlot.browse => (label: 'Browse', icon: Icons.grid_view_rounded),
  ShellSlot.search => (label: 'Search', icon: Icons.search_rounded),
  ShellSlot.library => (label: 'Library', icon: Icons.bookmark_rounded),
  ShellSlot.settings => (label: 'Settings', icon: Icons.settings_rounded),
};
