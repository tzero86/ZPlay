import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';

/// What a card needs to know about how it is currently being pointed at.
///
/// [hovered] and [focused] are deliberately separate: a design may want to
/// answer them differently, and the ring is drawn for focus only. Most cards
/// want [highlighted], which is the union — a D-pad user and a mouse user should
/// both see the card they are on.
@immutable
class CardInteraction {
  const CardInteraction({
    required this.hovered,
    required this.focused,
    required this.pressed,
  });

  final bool hovered;
  final bool focused;
  final bool pressed;

  /// True when either input family is pointing at this card. Use this for lift,
  /// zoom and poster brightening so pointer and D-pad behave identically.
  bool get highlighted => hovered || focused;

  static const CardInteraction idle =
      CardInteraction(hovered: false, focused: false, pressed: false);
}

/// The one way a card becomes reachable without a pointer.
///
/// Every content card in the app previously hand-rolled
/// `MouseRegion > GestureDetector`, and that pair is pointer-only —
/// `GestureDetector` is not a `Focus` widget, so no key, remote or D-pad event
/// can reach it. On Android TV that made the entire catalogue unreachable
/// (docs/UX_FINDINGS.md, Critical: "Android TV (D-pad) has no focus traversal").
///
/// [FocusableActionDetector] supplies exactly what the old pair did — hover in
/// and out, press, activation, cursor — and adds focus. Activation is wired to
/// [ActivateIntent], which `WidgetsApp`'s default shortcuts already bind to the
/// remote's centre button (`LogicalKeyboardKey.select`), Enter, Space and
/// gamepad A, so no card needs its own key handling. Arrow keys traverse via the
/// same defaults without any code here.
///
/// Cards keep their own layout and visuals: [builder] receives the state and
/// returns the card, so each surface styles its own hover/focus treatment while
/// the *behaviour* stays identical everywhere.
class FocusableCard extends StatefulWidget {
  const FocusableCard({
    super.key,
    required this.builder,
    this.onTap,
    this.autofocus = false,
    this.enabled = true,
    this.cursor = SystemMouseCursors.click,
    this.focusNode,
  });

  final Widget Function(BuildContext context, CardInteraction state) builder;

  /// Invoked by a tap, and by [ActivateIntent] from the keyboard or a remote.
  final VoidCallback? onTap;

  /// Give this to exactly one card per screen so a remote has somewhere to
  /// start; otherwise the first D-pad press does nothing.
  final bool autofocus;

  /// Whether this card can be focused and activated. A disabled card still
  /// installs an opaque hit target, so it swallows taps it will not act on —
  /// harmless for a leaf, but it will silently break a child or ancestor
  /// handler. `_HoverScale` in details_page.dart could not be used inside a
  /// [PopupMenuButton] for exactly this reason. If you need a card that
  /// declines taps, use `deferToChild` there instead.
  final bool enabled;
  final MouseCursor cursor;

  /// Supply one only when traversal order must be controlled from outside.
  final FocusNode? focusNode;

  @override
  State<FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<FocusableCard> {
  FocusNode? _ownedNode;
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  FocusNode get _node => widget.focusNode ?? (_ownedNode ??= FocusNode());

  @override
  void dispose() {
    _ownedNode?.dispose();
    super.dispose();
  }

  void _activate() {
    if (!widget.enabled) return;
    widget.onTap?.call();
  }

  void _set(void Function() change) {
    if (mounted) setState(change);
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: _node,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      mouseCursor: widget.cursor,
      onShowHoverHighlight: (value) {
        if (_hovered != value) _set(() => _hovered = value);
      },
      onShowFocusHighlight: (value) {
        if (_focused != value) _set(() => _focused = value);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(() => _pressed = true),
        onTapCancel: () => _set(() => _pressed = false),
        onTapUp: (_) => _set(() => _pressed = false),
        onTap: _activate,
        child: widget.builder(
          context,
          CardInteraction(hovered: _hovered, focused: _focused, pressed: _pressed),
        ),
      ),
    );
  }
}

/// The single focus indicator, so a focused card looks the same on every screen.
///
/// Painted over [child] rather than around it: the ring has to sit on the card's
/// own edge, and wrapping would change its outer size and knock the surrounding
/// grid out of alignment.
///
/// The colour comes from the active palette rather than a literal, because this
/// is exactly the class of hardcoded chrome the design audit counted 421 of.
class CardFocusRing extends StatelessWidget {
  const CardFocusRing({
    super.key,
    required this.focused,
    required this.radius,
    required this.child,
  });

  final bool focused;

  /// Must match the radius of the surface underneath, or the ring will not hug it.
  final BorderRadius radius;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!focused) return child;

    final accent = ZplayTokens.of(context).accent;

    return Stack(
      // `loose`, not `passthrough`. Passthrough sizes the stack from its own
      // constraints, so the `Positioned.fill` holding the border had nothing to
      // cover and the ring rendered at zero width: it never appeared at all.
      // Invisible on a pointer, because `if (!focused) return child` means the
      // branch is not taken when nothing is focused - and on a television every
      // card, rail row and settings row went unmarked.
      //
      // `loose` takes the stack's size from the child, so the fill covers the
      // card and nothing else. `expand` is the tempting wrong answer: it sizes
      // the stack to the loosest constraint, which for a card in a rail in a
      // column is the whole window, and the ring covered every sibling.
      fit: StackFit.loose,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                // A crisp 3 dp accent border: the user reported the 2 dp ring was
                // too subtle to see on a television, so the one accent line got
                // thicker rather than a second decoration joining it. Still no
                // glow — see the note below.
                border: Border.all(color: accent, width: 3),
                // **No glow.**
                //
                // A `BoxShadow` with no offset is centred on the box's own edge,
                // so half of it always bleeds *inside* the border. A 6 dp blur
                // puts a soft 3 dp wash on the inner edge of a 2 dp ring, and a
                // border whose inner edge is soft has two visible edges - which
                // is the "ghost border inside the shape" the user reported on
                // the rail three times. Tightening the blur from 18 to 6 made it
                // smaller without making it go away, because the offset was the
                // problem, not the size.
                //
                // A crisp 2 dp accent border is also what this design language
                // wants: one accent, one line, no decoration on the control that
                // tells the user where they are. If a focus ring ever needs to
                // lift off a busy background, the answer is a second ring drawn
                // *outside* this one on its own layer - not a shadow on this.
              ),
            ),
          ),
        ),
      ],
    );
  }
}
