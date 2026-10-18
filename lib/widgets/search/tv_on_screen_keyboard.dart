import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/theme/design_tokens.dart';
import '../common/focusable_card.dart';

/// The remote's keyboard, drawn by the app instead of borrowed from Android.
///
/// **Why the platform IME cannot be the television's keyboard.** A focused
/// `TextField` installs `DirectionalFocusAction.forTextField()`
/// (`editable_text.dart`), which answers every arrow press itself so the caret
/// can move - and answering means consuming: the press never reaches the
/// on-screen keyboard the IME drew over the page. Measured on the Google TV
/// emulator: the field takes focus, Gboard appears, and `DPAD_RIGHT` /
/// `DPAD_CENTER` do nothing at all, because Flutter holds primary focus and
/// eats the keys the keyboard needs. Android TV's own apps do not fight this -
/// they draw their own keyboard, and so does this one.
///
/// **What this widget is.** A QWERTY grid of [FocusableCard] keys wearing the
/// house [CardFocusRing], so the remote walks the keys exactly like it walks
/// any other row in the app, and every press edits the page's own
/// [TextEditingController] - the field above keeps showing the query and the
/// results keep updating through [onChanged], with no input connection and no
/// IME anywhere in the loop.
///
/// **The edges of the grid are the page's, not this widget's.** UP off the top
/// row and DOWN off the action row mean "leave the keyboard" - to the search
/// box above and to the results below - and only the page knows those nodes,
/// so they are callbacks ([onMoveUp], `onMoveDown`). BACK and `escape` close
/// the keyboard ([onClose]); while it is open this widget is the focused
/// subtree, so the field's own BACK handler is not in the key path at all.
///
/// **Which of the two closest BACKs is decided by [ownsBackKey]**, exactly one:
/// inside the shell the page claims the press
/// (`AppShellController.claimBack`), because Android delivers a back to the
/// root route on the `popRoute` path whatever a key handler answers; mounted
/// without a shell - a page in a route of its own - nothing else consumes it
/// and the key event is the only notice this widget will get.
///
/// A physical keyboard still types: printable characters, backspace and the
/// holding of `escape` are answered here for the whole subtree, so a paired
/// keyboard or a voice remote's text path edits the same controller.
class TvOnScreenKeyboard extends StatefulWidget {
  const TvOnScreenKeyboard({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClose,
    required this.onMoveUp,
    required this.onMoveDown,
    this.ownsBackKey = true,
    this.onVoice,
  });

  /// The search field's own controller. Every key edits it in place.
  final TextEditingController controller;

  /// Fired after every edit with the controller's new text, so the page's
  /// debounced live search runs exactly as if the text had been typed.
  final ValueChanged<String> onChanged;

  /// The Search key: run the query in full, then close the keyboard.
  final ValueChanged<String> onSubmitted;

  /// BACK, `escape`, and the Search key's second half.
  final VoidCallback onClose;

  /// UP off the top row: hand the ring back to the search box above.
  final VoidCallback onMoveUp;

  /// DOWN off the action row: hand the ring to the results below.
  final VoidCallback onMoveDown;

  /// Whether this widget is the one that answers the BACK key itself.
  ///
  /// False when the page claims the press at the shell instead, which it must
  /// whenever there *is* a shell: Android delivers back to the root route on
  /// the `popRoute` path as well as to this key handler, so a press claimed
  /// here too closes the keyboard and runs the shell's go-Home policy on the
  /// same press. The handler still answers the key-up in that mode, because an
  /// unhandled up is re-dispatched to Android - the second delivery of the same
  /// press - and it must not reach the shell either.
  final bool ownsBackKey;

  /// The microphone. Absent on a device with no recognizer, and then the
  /// action row simply has no voice key - a control that exists and fails is
  /// worse than no control on a television.
  final VoidCallback? onVoice;

  @override
  State<TvOnScreenKeyboard> createState() => TvOnScreenKeyboardState();
}

class TvOnScreenKeyboardState extends State<TvOnScreenKeyboard> {
  /// The key the keyboard opens on: `q`, the top-left of the letter rows.
  ///
  /// Owned here rather than passed in because nothing outside the keyboard has
  /// any business naming a letter key, and a node nobody owns defers its focus
  /// request forever.
  final FocusNode _firstKeyNode = FocusNode(debugLabel: 'TvKeyboardFirstKey');

  static const List<String> _rowDigits = <String>[
    '1', '2', '3', '4', '5', '6', '7', '8', '9', '0',
  ];
  static const List<String> _rowTop = <String>[
    'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p',
  ];
  static const List<String> _rowHome = <String>[
    'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', '-',
  ];
  static const List<String> _rowBottom = <String>[
    'z', 'x', 'c', 'v', 'b', 'n', 'm', '.', '_', '/',
  ];

  static const double _keyHeight = 42;
  static const double _actionHeight = 48;

  @override
  void initState() {
    super.initState();
    // The frame after mount, never during it: the field owns the frame that
    // opens the keyboard - it is the focus gain that asks the platform for
    // (and, on a television, is then answered instead of by) its IME - and a
    // request made while this subtree is still being attached would race it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _firstKeyNode.canRequestFocus) _firstKeyNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _firstKeyNode.dispose();
    super.dispose();
  }

  /// Appends [text] at the caret, or over a selection when one exists.
  void _insert(String text) {
    final value = widget.controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    widget.controller.value = value.copyWith(
      text: value.text.replaceRange(
        selection.start,
        selection.end.clamp(selection.start, value.text.length),
        text,
      ),
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    );
    widget.onChanged(widget.controller.text);
  }

  /// Backspace: drop the selection, or the one character before the caret.
  void _delete() {
    final value = widget.controller.value;
    if (!value.selection.isValid) {
      widget.controller.value = value.copyWith(
        selection: TextSelection.collapsed(offset: value.text.length),
      );
      return;
    }
    var start = value.selection.start;
    final end = value.selection.end;
    if (start == end) {
      if (start == 0) return;
      start -= 1;
    }
    widget.controller.value = value.copyWith(
      text: value.text.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
    );
    widget.onChanged(widget.controller.text);
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged('');
  }

  void _submit() {
    widget.onSubmitted(widget.controller.text);
    widget.onClose();
  }

  /// The physical-keyboard half of the widget: characters and backspace type,
  /// `escape` closes. `select` and `enter` are deliberately NOT here - they are
  /// the [ActivateIntent] a focused key answers to type its letter, and claiming
  /// them one node above would turn every centre press into a submit.
  ///
  /// **BACK has one owner, never two.** On Android it arrives by two routes:
  /// this key event, and the `popRoute` platform message that reaches the root
  /// route's `PopScope` on its own path. Answering both closed the keyboard and
  /// ran the shell's go-Home policy 47 ms apart for one press - measured on the
  /// Google TV emulator - which is what threw the ring onto the bar. So BACK is
  /// answered here only in [TvOnScreenKeyboard.ownsBackKey] mode; inside the
  /// shell the page claims it instead (`AppShellController.claimBack`) and this
  /// handler is inert for the down. Its key-up is still answered, because an
  /// unanswered up is re-dispatched to Android and becomes that second press.
  /// `escape` is different and stays here in both modes: it is a hardware key
  /// that never becomes `popRoute`, so nothing else can claim it.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final closesThisWidget = key == LogicalKeyboardKey.escape ||
        (key == LogicalKeyboardKey.goBack && widget.ownsBackKey);
    if (closesThisWidget) {
      // **Both halves, always.** A back press is a down and an up, and an up
      // nobody answered is re-dispatched to Android as a second press - the
      // double delivery this class exists to avoid, arriving a second later.
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        widget.onClose();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.goBack) {
      // The page claims the down at the shell. The up has no claimant of its
      // own, so it is answered here for the same reason as above.
      return event is KeyUpEvent
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.backspace) {
      _delete();
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (character == null || character.length != 1) {
      return KeyEventResult.ignored;
    }
    final unit = character.codeUnitAt(0);
    // Printable ASCII only: the control characters and the modifier-alone
    // events the engine also reports as one-character strings are not text.
    if (unit < 0x20 || unit > 0x7e) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    _insert(character);
    return KeyEventResult.handled;
  }

  /// One row of keys.
  ///
  /// [onUp] and [onDown] are answered by the row rather than by each key,
  /// because leaving the keyboard is the row's answer and not the letter's: the
  /// event bubbles from the focused key to here, and only this wrapper knows
  /// that the whole row has already been walked.
  Widget _keyRow(
    List<String> labels, {
    FocusNode? firstKeyNode,
    VoidCallback? onUp,
    VoidCallback? onDown,
    double height = _keyHeight,
  }) {
    Widget row = Row(
      children: <Widget>[
        for (var i = 0; i < labels.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: ZplaySpacing.s8),
          Expanded(
            child: _TvKey(
              label: labels[i],
              height: height,
              focusNode: i == 0 ? firstKeyNode : null,
              onTap: () => _insert(labels[i]),
            ),
          ),
        ],
      ],
    );
    if (onUp != null || onDown != null) {
      row = Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (onUp != null && event.logicalKey == LogicalKeyboardKey.arrowUp) {
            onUp();
            return KeyEventResult.handled;
          }
          if (onDown != null &&
              event.logicalKey == LogicalKeyboardKey.arrowDown) {
            onDown();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: row,
      );
    }
    return row;
  }

  Widget _actionRow() {
    final tokens = context.tokens;
    return _keyRowCallback(
      onDown: widget.onMoveDown,
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: _TvKey(
              label: 'Space',
              height: _actionHeight,
              onTap: () => _insert(' '),
            ),
          ),
          const SizedBox(width: ZplaySpacing.s8),
          Expanded(
            flex: 2,
            child: _TvKey(
              label: '',
              icon: Icons.backspace_outlined,
              height: _actionHeight,
              onTap: _delete,
            ),
          ),
          const SizedBox(width: ZplaySpacing.s8),
          Expanded(
            flex: 2,
            child: _TvKey(
              label: 'Clear',
              height: _actionHeight,
              onTap: _clear,
            ),
          ),
          if (widget.onVoice != null) ...<Widget>[
            const SizedBox(width: ZplaySpacing.s8),
            Expanded(
              flex: 2,
              child: _TvKey(
                label: '',
                icon: Icons.mic_rounded,
                height: _actionHeight,
                onTap: widget.onVoice!,
              ),
            ),
          ],
          const SizedBox(width: ZplaySpacing.s8),
          Expanded(
            flex: 2,
            child: _TvKey(
              label: 'Search',
              icon: Icons.search_rounded,
              height: _actionHeight,
              accent: true,
              labelStyle: ZplayType.subtitle.toStyle(color: tokens.onAccent),
              onTap: _submit,
            ),
          ),
        ],
      ),
    );
  }

  /// Wraps [child] so a DOWN press leaving the last row reaches the page.
  Widget _keyRowCallback({
    required Widget child,
    required VoidCallback onDown,
  }) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          onDown();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.bg.withValues(alpha: 0.92),
          borderRadius: ZplayRadius.mdAll,
          border: Border.fromBorderSide(tokens.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(ZplaySpacing.s8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _keyRow(_rowDigits, onUp: widget.onMoveUp),
              const SizedBox(height: ZplaySpacing.s8),
              _keyRow(
                _rowTop,
                firstKeyNode: _firstKeyNode,
                onUp: widget.onMoveUp,
              ),
              const SizedBox(height: ZplaySpacing.s8),
              _keyRow(_rowHome),
              const SizedBox(height: ZplaySpacing.s8),
              _keyRow(_rowBottom),
              const SizedBox(height: ZplaySpacing.s8),
              _actionRow(),
            ],
          ),
        ),
      ),
    );
  }
}

/// One key: a [FocusableCard] wearing [CardFocusRing], the same pair every
/// control a remote can land on in this app wears.
class _TvKey extends StatelessWidget {
  const _TvKey({
    required this.label,
    required this.height,
    required this.onTap,
    this.icon,
    this.focusNode,
    this.accent = false,
    this.labelStyle,
  });

  final String label;
  final IconData? icon;
  final double height;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool accent;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return FocusableCard(
      focusNode: focusNode,
      onTap: onTap,
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.smAll,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: accent ? tokens.accent : tokens.surface,
            borderRadius: ZplayRadius.smAll,
            border: Border.fromBorderSide(
              accent ? BorderSide.none : tokens.hairline,
            ),
          ),
          alignment: Alignment.center,
          child: icon != null
              ? Icon(
                  icon,
                  size: 18,
                  color: accent ? tokens.onAccent : tokens.textPrimary,
                )
              : Text(
                  label,
                  style:
                      labelStyle ??
                      ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),
        ),
      ),
    );
  }
}
