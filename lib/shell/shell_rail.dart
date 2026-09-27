import 'package:flutter/material.dart';

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
  static const double _televisionRailWidth = 236;
  static const double _expandedRowHeight = 44;

  /// The wordmark is brand art rather than copy: the type scale's steps around
  /// it are body sizes (15 and 18) and read undersized at the head of a 236 px
  /// rail. Declared as a token rather than a bare `fontSize` so it still travels
  /// through the same [ZplayTextToken] path as every other string here.
  static const ZplayTextToken _wordmark = ZplayTextToken(
    size: 20,
    weight: FontWeight.w700,
    height: 1.0,
    letterSpacing: -0.4,
  );

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
                Expanded(child: _row(slot, television: false, height: ZplaySpacing.s48)),
            ],
          ),
        ),
      ),
    );
  }

  /// Tablet, desktop and ten-foot: a left rail at three widths and row targets.
  Widget _sideRail(BuildContext context, EdgeInsets inset, FormFactor formFactor) {
    final tokens = context.tokens;
    final television = formFactor == FormFactor.television;
    final rowHeight = switch (formFactor) {
      FormFactor.medium => ZplaySpacing.s48,
      FormFactor.expanded => _expandedRowHeight,
      _ => ZplaySpacing.s64,
    };
    final rowGap = television ? ZplaySpacing.s8 : ZplaySpacing.s4;
    final padH = television ? ZplaySpacing.s12 : ZplaySpacing.s8;
    final padV = television ? ZplaySpacing.s16 : ZplaySpacing.s8;

    // Settings is pinned to the foot on every rail, which is what the prototype
    // does at all three widths: it is the least-used row and the one that should
    // not sit between the content rows.
    final leading = <Widget>[];
    for (final slot in ShellSlot.values) {
      if (slot == ShellSlot.settings) continue;
      if (leading.isNotEmpty) leading.add(SizedBox(height: rowGap));
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
              _fullscreenRow(television: television, height: rowHeight),
              SizedBox(height: rowGap),
              _row(ShellSlot.settings, television: television, height: rowHeight),
            ],
          ),
        ),
      ),
    );
  }

  /// The mark and wordmark, ten-foot only: 88 px cannot hold both, and the mark
  /// alone carries the brand at that width.
  Widget _head(BuildContext context, ZplayTokens tokens) => Row(
        children: [
          Image.asset(
            'assets/icon_small.png',
            width: ZplaySpacing.s48,
            height: ZplaySpacing.s48,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: ZplaySpacing.s12),
          Text('ZPlay', style: _wordmark.toStyle(color: tokens.textPrimary)),
        ],
      );

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
    final duration =
        MediaQuery.disableAnimationsOf(context) ? Duration.zero : ZplayMotion.base;

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
            padding:
                television ? const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12) : null,
            decoration: BoxDecoration(
              color: selected ? tokens.accentSubtle : Colors.transparent,
              borderRadius: ZplayRadius.smAll,
              // The selection ring is ten-foot only. A remote has no pointer to
              // show where it is, and the focus ring alone reads as hover at ten
              // feet. It is always present, transparent when idle, so selecting
              // a row cannot nudge its contents by two pixels.
              border: television
                  ? Border.all(
                      color: selected ? tokens.accent : Colors.transparent,
                      width: ZplaySpacing.s2,
                    )
                  : null,
            ),
            // Icon only away from the ten-foot chrome: a pointer and a thumb
            // both have the page's own title in front of them, so a name under
            // every icon was repeating what the destination already says, and
            // five names in a bottom bar is a lot of type for a row of five.
            // A television keeps its labels, because at ten feet a glyph is a
            // guess, which is why both Android TV and tvOS name their rail rows.
            // The tooltip is the pointer path back to the name.
            child: television
                ? Row(
                    children: [
                      _icon(icon, tokens, state),
                      const SizedBox(width: ZplaySpacing.s12),
                      Expanded(child: _label(label, tokens, state)),
                    ],
                  )
                : Tooltip(
                    message: tooltipMessage,
                    child: _icon(icon, tokens, state),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _icon(IconData icon, ZplayTokens tokens, CardInteraction state) => Icon(
        icon,
        // 24 is the size a 44 px rail row is built around; the ten-foot rail
        // reads better a step larger.
        size: television ? ZplaySpacing.s32 : ZplaySpacing.s24,
        color: _foreground(tokens, state),
      );

  /// The ten-foot rail is the only caller: away from it a row is its icon, and
  /// the name lives in the tooltip and in the semantics label.
  Widget _label(String label, ZplayTokens tokens, CardInteraction state) => Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: ZplayType.subtitle.toStyle(color: _foreground(tokens, state)),
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
