import 'package:flutter/material.dart';
import '../../widgets/common/zplay_logo.dart';

import '../pages/browse/browse_page.dart';
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
/// affordance in the bar, and the desktop keyboard map (`Ctrl+K`) is what makes
/// it fast there.
///
/// The bar reserves its own space: it is a real layout child with a pinned
/// height, so no page ever needs padding to clear the shell. Tablet, desktop and
/// television get the prototype's sidebar-free **top bar**; the phone keeps its
/// bottom bar, which is also what the prototype shows (it hides the top navbar
/// on a phone).
class ShellRail extends StatelessWidget {
  const ShellRail({
    super.key,
    required this.current,
    required this.onSelect,
    required this.onLiveTv,
    this.autofocus = false,
  });

  final ShellSlot current;
  final ValueChanged<ShellSlot> onSelect;

  /// The Live TV shortcut: Browse with its `liveTv` vertical selected.
  ///
  /// Not a [ShellSlot], because it is not a page of its own - the shell routes it
  /// to Browse and lets Browse choose the vertical
  /// (`AppShellController.goBrowseVertical`). The bar draws it next to Browse
  /// because that is where it lands, and it is the one destination whose row is
  /// never marked selected: the slot it belongs to is Browse, and Browse's own
  /// row already carries that state.
  final VoidCallback onLiveTv;

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

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context);
    return switch (FormFactorService.of(context)) {
      FormFactor.compact => _bottomBar(context, inset),
      final formFactor => _topBar(context, inset, formFactor),
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

  /// Tablet, desktop and ten-foot: the destinations in a bar across the top.
  ///
  /// This is the prototype's sidebar-free layout, and the shell's only chrome on
  /// these form factors. It is a real layout child pinned to the top of the
  /// window, so no page pads to clear it, and it owns the status bar strip
  /// itself: the shell mounts it flush with the window's top edge and wraps
  /// nothing in a `SafeArea`, so the inset is added to the pinned 48 dp rather
  /// than taken out of it. The shell hands the slot pages a [MediaQuery] with the
  /// top padding already removed (`_AppShellState._layout`), because the bar is
  /// what spent it.
  ///
  /// The bar is a fixed 48 dp of content, and the brand badge, the five slots,
  /// the Live TV shortcut and the fullscreen toggle are centred in it. **Labels
  /// come back here.** The old 64 dp ten-foot side rail was icons only because a
  /// quarter of a 960 dp canvas is too much to spend on names; a horizontal bar
  /// has the width for them, and the prototype draws icon plus text at every
  /// width. The accessibility floor is why the row is 48 dp rather than the
  /// prototype's 32: it fills the bar, so a remote's target is never smaller
  /// than the bar itself.
  Widget _topBar(
    BuildContext context,
    EdgeInsets inset,
    FormFactor formFactor,
  ) {
    final tokens = context.tokens;
    final television = formFactor == FormFactor.television;
    return SizedBox(
      height: ZplaySpacing.s48 + inset.top,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surface,
          // The content is below the bar, so the hairline is on its bottom edge.
          border: Border(bottom: tokens.hairline),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            ZplaySpacing.s24 + inset.left,
            inset.top,
            ZplaySpacing.s24 + inset.right,
            0,
          ),
          child: Row(
            children: <Widget>[
              _brand(tokens),
              const SizedBox(width: ZplaySpacing.s16),
              // Destinations lead from the left and share what is left of the
              // bar between them.
              //
              // `Flexible` with its default loose fit is what keeps a narrow
              // window from overflowing: a `Row` gives a non-flex child
              // unbounded width, so six labelled destinations plus the brand
              // paint straight past the edge of a 600 dp `medium` window (and
              // past the test font's much wider metrics on the 960 dp
              // television canvas). Sharing the width lets each row take at
              // most its share and ellipsise its name instead. On a real
              // television canvas every name fits, so nothing is cut there; the
              // tooltip and the semantics label carry the full name either way.
              Expanded(
                child: Row(
                  children: <Widget>[
                    for (final slot in ShellSlot.values) ...[
                      const SizedBox(width: ZplaySpacing.s4),
                      Flexible(
                        child: _row(
                          slot,
                          television: television,
                          height: ZplaySpacing.s48,
                          showLabel: true,
                        ),
                      ),
                      // Live TV rides beside Browse, which is the slot it opens.
                      if (slot == ShellSlot.browse)
                        Flexible(
                          child: _liveTvRow(
                            television: television,
                            height: ZplaySpacing.s48,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              // The fullscreen toggle sits at the opposite end, which is where
              // the prototype keeps its utility cluster. It is labelled like
              // every other top-bar item: an icon-only row would be 28 dp wide,
              // below the 48 dp ten-foot target floor, and a remote user would
              // have to guess what the glyph toggles.
              _fullscreenRow(
                television: television,
                height: ZplaySpacing.s48,
                showLabel: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The brand anchor, in the bar's leading corner.
  ///
  /// The drawn mark on an accent-tinted plate, which is what replaced the old
  /// side rail's `_head`. The plate is what makes it read as the app's identity
  /// rather than a stray glyph, and it is not a control: the prototype's brand is
  /// a way home, but the bar's own Home destination already is one, so the anchor
  /// stays decorative and adds no seventh focus target for a remote to cross.
  Widget _brand(ZplayTokens tokens) => DecoratedBox(
    decoration: BoxDecoration(
      color: tokens.accentSubtle,
      borderRadius: ZplayRadius.xsAll,
    ),
    child: const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ZplaySpacing.s8,
        vertical: ZplaySpacing.s4,
      ),
      child: ZplayLogo(size: ZplaySpacing.s24),
    ),
  );

  Widget _row(
    ShellSlot slot, {
    required bool television,
    required double height,
    bool showLabel = false,
  }) {
    final chrome = _slotChrome(slot);
    return _RailRow(
      label: chrome.label,
      icon: chrome.icon,
      selected: slot == current,
      television: television,
      height: height,
      showLabel: showLabel,
      // Only the selected row claims the starting focus, so the shell's
      // autofocus cannot land on two rows at once when the bar is rebuilt.
      autofocus: autofocus && slot == current,
      onTap: () => onSelect(slot),
    );
  }

  /// The Live TV shortcut, drawn beside Browse.
  ///
  /// A [BrowseVertical], not a [ShellSlot], so it borrows Browse's own chrome
  /// for its label and icon rather than repeating the strings here. It is never
  /// `selected`: the slot it opens is Browse, and Browse's row carries that
  /// state. It is only ever drawn in the top bar, which is why it has no
  /// `television` branch of its own beyond the border the other rows use.
  Widget _liveTvRow({required bool television, required double height}) =>
      _RailRow(
        label: BrowseVertical.liveTv.label,
        icon: BrowseVertical.liveTv.icon,
        selected: false,
        television: television,
        height: height,
        showLabel: true,
        onTap: onLiveTv,
      );

  /// The fullscreen toggle, at the trailing end of the top bar.
  ///
  /// Fullscreen is window state, not a destination: no page is mounted for it
  /// and it never owns the content area, which is why it is not a [ShellSlot].
  /// It rides in the bar because the bar is the one piece of chrome every slot
  /// paints, so both the way in and the way out of fullscreen follow the user
  /// instead of being reachable only from Home. The keyboard path is the shell's
  /// F11 binding, so the tooltip names the key.
  ///
  /// The top bar has room for it at every width; the compact bottom bar does
  /// not: it is a phone, its five slot rows already fill the width, and the
  /// platform there owns the window insets rather than a key.
  Widget _fullscreenRow({
    required bool television,
    required double height,
    bool showLabel = false,
  }) {
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
        showLabel: showLabel,
        onTap: window.toggleFullscreen,
      ),
    );
  }
}

/// One row: the whole hit target, including its label.
///
/// Label and icon arrive already resolved rather than as a [ShellSlot], so the
/// bar's two kinds of row, a slot and the fullscreen toggle, share one look
/// instead of drifting apart as two near-identical styles. The same widget draws
/// the phone's icon-only bottom rows and the top bar's labelled ones, so the two
/// nav shapes cannot drift in behaviour.
class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.television,
    required this.height,
    required this.onTap,
    this.autofocus = false,
    this.showLabel = false,
    this.tooltip,
  });

  final String label;
  final IconData icon;

  /// Passed straight to [FocusableCard]; see [ShellRail.autofocus] for why only
  /// one row in a bar ever sets it.
  final bool autofocus;

  /// The pointer path to the name. Defaults to [label]; the fullscreen row
  /// overrides it to name its key.
  final String? tooltip;
  final bool selected;
  final bool television;
  final double height;

  /// Draw the name beside the glyph instead of glyph-only.
  ///
  /// True in the top bar, which has the width for names at every form factor it
  /// serves; false in the phone's bottom bar, which is five rows across one
  /// window and has no room for five names.
  final bool showLabel;

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
          radius: _radius,
          child: AnimatedContainer(
            duration: duration,
            curve: ZplayMotion.standard,
            height: height,
            // Only a labelled row pads horizontally. A bottom-bar row is the
            // glyph alone and keeps none, so it stays exactly the shape it
            // shipped with; a top-bar row pads so the name does not touch the
            // row's own reserved edge.
            padding: showLabel
                ? const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12)
                : null,
            decoration: BoxDecoration(
              // **A labelled row paints no fill.**
              //
              // The destinations are an overlay on the page under them rather
              // than controls sitting on it, and a bar of filled or outlined
              // destinations reads as a row of buttons however quiet the
              // colours are. Selection is carried by the accent bar under the
              // name ([_underline]) and by the name's own brightness.
              //
              // An icon-only row is the exception, because it has no name to
              // put a bar under, so the phone's bottom bar keeps the wash
              // (`overlayHover`) that marks the current slot - and this
              // container's animation, which has nothing to move in the top bar
              // and carries that wash between slots in the bottom one.
              color: showLabel
                  ? Colors.transparent
                  : selected
                      ? Colors.white
                          .withValues(alpha: ZplayOpacity.overlayHover)
                      : Colors.transparent,
              borderRadius: _radius,
              // **Reserved on a television, painted by nothing.**
              //
              // Flutter reserves a border's width whether or not the border is
              // painted, so a row that drops its border is 4 dp narrower than
              // one that keeps it, and the glyph - centred in that box - moves
              // the moment the row is selected. A transparent border reserves
              // the space and paints nothing, so the box is identical in every
              // state, and [CardFocusRing] is left as the only line the row
              // ever draws: a second edge beside the focus ring is the ghost
              // border inside the shape.
              //
              // A pointer form factor never reserved one and still reserves
              // none.
              border: television
                  ? Border.all(
                      color: Colors.transparent,
                      width: ZplaySpacing.s2,
                    )
                  : null,
            ),
            // Glyph alone in the phone's bottom bar; glyph plus name in the top
            // bar.
            //
            // The old ten-foot side rail was icons only, and the reasoning was
            // sound: at ten feet a glyph is a guess. It does not survive a
            // narrow vertical strip, where the name costs a third of the rail's
            // width and truncates on a 960 dp canvas. A horizontal bar has the
            // width to spend, and the prototype draws icon plus text at every
            // width it serves, so [showLabel] decides rather than the form
            // factor.
            //
            // Either way the name survives for a screen reader (the `Semantics`
            // above) and for a pointer (the tooltip).
            child: Tooltip(
              message: tooltipMessage,
              // The accent bar is anchored to the *name's* box rather than to
              // the row's, so it needs a parent with a box of its own: a `Stack`
              // around the name alone, whose `Positioned` children cannot alter
              // it. The name carries the bar, not the row, so the row keeps the
              // width it had and the bar cannot widen it, crowd the name or move
              // the glyph.
              child: showLabel
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _icon(icon, tokens, state),
                        const SizedBox(width: ZplaySpacing.s8),
                        // Flexible, so the name ellipsises when the bar is
                        // narrower than its destinations need rather than
                        // overflowing the row. The `Stack` holds nothing but
                        // `Positioned` children, so it is loose: it takes the
                        // name's height from the name and its width from the
                        // `Row` around it, which is what makes the bar as wide
                        // as the name beside it.
                        Flexible(
                          child: Stack(
                            alignment: Alignment.bottomLeft,
                            children: <Widget>[
                              // The name, with room below it for the bar. The
                              // padding is what gives the bar somewhere to sit
                              // *inside* the stack: a `Positioned` child never
                              // contributes to a `Stack`'s size, so a bar hung
                              // below a text-only stack is drawn outside it and
                              // clipped away. That is why the bar was measured
                              // at the right rect and still never appeared.
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: ZplaySpacing.s4,
                                ),
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ZplayType.label.toStyle(
                                    color: _labelColor(tokens, state),
                                  ),
                                ),
                              ),
                              _underline(tokens, duration),
                            ],
                          ),
                        ),
                      ],
                    )
                  : _icon(icon, tokens, state),
            ),
          ),
        ),
      ),
    );
  }

  /// The one glyph size, so the gap between the glyph and the name has one
  /// definition as well.
  static const double _glyph = ZplaySpacing.s24;

  /// The gap between the name's line box and the accent bar under it.
  ///
  /// The bar is `Positioned` inside the same `Stack` as the name, so this is the
  /// only vertical arithmetic there is: the name is padded by this much at the
  /// bottom and the bar sits at the stack's own edge. A bar hung *past* that
  /// edge - which is what a negative `bottom` does - is drawn outside the stack
  /// and clipped away, and is why the bar measured at exactly the right rect on
  /// the television and still never appeared.

  Widget _icon(
    IconData icon,
    ZplayTokens tokens,
    CardInteraction state,
  ) => Icon(
    icon,
    // One size for every form factor. The ten-foot chrome used to draw 32 px
    // inside a 64 dp row in an 88 dp rail, which is the whole of what the user
    // called wasted space; 24 matches the reference app's ~22 px glyphs and the
    // pointer chrome this already shipped.
    size: _glyph,
    color: _iconColor(tokens, state),
  );

  /// The row's corner radius: the top bar's pill, or the phone bar's square.
  ///
  /// [showLabel] is the discriminator because it already is exactly that
  /// distinction - the top bar is the only bar that draws names beside its
  /// glyphs, and the prototype's top-bar tabs are pills (`border-radius: 20px`)
  /// while the phone's bottom rows are not. The focus ring and the phone's wash
  /// take it, so the two cannot disagree.
  BorderRadius get _radius =>
      showLabel ? ZplayRadius.fullAll : ZplayRadius.smAll;

  /// The selection mark for a labelled row: a short accent bar under the name.
  ///
  /// `Positioned`, so it is decoration over the name rather than part of it. It
  /// cannot widen the name, push it off centre or move the glyph, which is why
  /// it can exist on the selected row without that row changing shape. It is
  /// full-bleed across the name's width - `bottom` is the only inset that is not
  /// a zero - so a name that has been ellipsised brings its shorter bar with it.
  ///
  /// [ZplayMotion] drives the change. Losing selection collapses the bar to
  /// nothing and gaining it grows one out of the name's centre, so the accent
  /// travels between rows instead of blinking out here and back in there. The
  /// app has no reduced-motion branch here, so [ShellRail]'s
  /// `disableAnimations` check collapses the duration and keeps the curve.
  Widget _underline(ZplayTokens tokens, Duration duration) => Positioned(
        left: ZplaySpacing.s0,
        right: ZplaySpacing.s0,
        bottom: ZplaySpacing.s0,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: selected ? 1 : 0),
          duration: duration,
          curve: ZplayMotion.emphasized,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.scale(
              scaleX: t,
              alignment: Alignment.center,
              child: child,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(color: tokens.accent),
            child: const SizedBox(height: ZplaySpacing.s2),
          ),
        ),
      );

  /// The glyph is neutral in every state.
  ///
  /// It used to take the accent on the current slot. That put the brand hue on
  /// the smallest mark in the bar, where it is least legible, and marked
  /// selection twice; the accent bar under the name is the mark now. A row the
  /// pointer or the remote is on still brightens, so both input families can
  /// see what they are pointing at.
  Color _iconColor(ZplayTokens tokens, CardInteraction state) =>
      state.highlighted ? tokens.textPrimary : tokens.textSecondary;

  /// The name is the brightest thing on the current row and the dimmest on a
  /// resting one: the accent says which destination, the brightness says which
  /// words. A pointed-at row reads like the current one, for the same reason
  /// the glyph does.
  Color _labelColor(ZplayTokens tokens, CardInteraction state) =>
      selected || state.highlighted ? tokens.textPrimary : tokens.textSecondary;
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
