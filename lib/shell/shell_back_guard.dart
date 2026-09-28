/// The shell's answer to the remote's back button, which is the whole app's
/// answer: nothing else may exit it.
///
/// **The defect this exists for.** Android delivers the remote's back key as
/// the `popRoute` platform message, and the framework walks its observers until
/// one claims it (`WidgetsBinding.handlePopRoute`, `widgets/binding.dart`). The
/// only observer that claims it for a Navigator is `WidgetsApp`, which asks
/// `Navigator.maybePop()`. That consults the *top* route's pop disposition, and
/// the shell declares none: `MaterialApp(home: AppShell())` (`lib/main.dart:250`)
/// makes the shell the root route, and a route with no [PopScope] above it
/// reports [RoutePopDisposition.bubble] when it is the first entry. `maybePop`
/// answers false, no other observer claims the press, and `handlePopRoute`
/// finishes with `SystemNavigator.pop()` - on Android, "remove this activity
/// from the stack", which is the launcher. So one press dropped the viewer out
/// of the app from every slot, and the five slots being one route is why: below
/// the shell there is no history to unwind and nothing to catch the press.
///
/// The shell is the only object that can fix it, and that is not incidental.
/// "Which screen was I on" is `_AppShellState._slot`, and the policy below is
/// entirely a function of it. A guard mounted beside the shell could not read
/// that value; a route-level guard that pushed a Home *route* would trade the
/// [IndexedStack]'s preserved page state for the history-squashing model this
/// shell was rewritten to delete.
///
/// **The policy, in the order it is applied.**
///
/// 1. A route pushed above the shell (details, settings, player, a dialog)
///    pops and nothing here runs. That is not special-cased: those routes carry
///    the press themselves, and a [PopScope] below them cannot be reached
///    because `Navigator.maybePop` only ever looks at the topmost entry. The
///    pushed route is what the user is looking at, so it is what back closes.
/// 2. Any slot other than Home goes to Home, through the shell's own `_select`,
///    so the switch is the same paint change the rail makes and every slot
///    keeps the state it had.
/// 3. At Home the first press arms and the second exits, [shellExitWindow]
///    apart. A single stray press on a remote - and a television remote is
///    handled in the dark by someone who cannot see which button they found -
///    must never drop the viewer to the launcher, so the press that could do it
///    is never the first one.
///
/// The window is a [Timer] rather than a stored timestamp compared on the next
/// press, because the affordance has to *go away* when the window closes, and a
/// timer gives that for free: it is the same signal that disarms the state and
/// hides the banner, so the button and the pill can never disagree. It is also
/// the only one of the two that a widget test can drive without a fake clock.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/layout/form_factor.dart';
import '../services/theme/design_tokens.dart';
import 'app_shell.dart';

/// How long the shell stays armed for a second back press.
///
/// Two seconds is Android's own "press back again to exit" convention: the
/// framework's `Toast` for exactly this message is `LENGTH_SHORT`, and that is
/// the timing a viewer of any app on this platform already has in their hands.
/// Long enough to be a deliberate second press after reading the pill, short
/// enough that a press from an earlier, unrelated moment cannot be mistaken for
/// one and does not exit on a third press the user never intended.
const Duration shellExitWindow = Duration(seconds: 2);

/// Claims the root route's back press and applies the shell's three-way policy.
///
/// Mounted once, around the whole shell, by [AppShell]. Everything it needs is
/// passed in rather than looked up, because it deliberately sits *above*
/// `AppShellScope`: the press has to be caught even if some future frame fails
/// to build the shell's subtree, and this is the one widget that decides whether
/// the process lives or leaves.
class ShellBackGuard extends StatefulWidget {
  const ShellBackGuard({
    super.key,
    required this.current,
    required this.onGoHome,
    required this.child,
  });

  /// The shell's slot, read at the moment of the press.
  ///
  /// Only read, never a reason to rebuild: the pop handler is called from an
  /// event, not from a build, so `current.value` is always the slot on screen.
  /// It is listened to for one narrower reason, [initState]'s note.
  final ValueListenable<ShellSlot> current;

  /// Switches the shell to Home, through the shell's own select path.
  final VoidCallback onGoHome;

  final Widget child;

  @override
  State<ShellBackGuard> createState() => _ShellBackGuardState();
}

class _ShellBackGuardState extends State<ShellBackGuard> {
  /// True between the first back press at Home and the window closing.
  bool _armed = false;

  Timer? _disarm;

  @override
  void initState() {
    super.initState();
    // A slot switch disarms. The pill says "press back again to exit", and the
    // only way to leave Home while it is up is the rail or a keyboard chord, so
    // without this the affordance would ride into Browse on top of a screen
    // where back does something else entirely - and a press there would go Home
    // rather than exit, which is a state the pill would have been lying about.
    widget.current.addListener(_onSlotChanged);
  }

  @override
  void dispose() {
    widget.current.removeListener(_onSlotChanged);
    _disarm?.cancel();
    super.dispose();
  }

  void _onSlotChanged() {
    if (widget.current.value == ShellSlot.home) return;
    // Silent on purpose, and no `setState`. `_select` writes the notifier
    // *before* its own `setState`, and the shell is this widget's parent, so the
    // rebuild that follows already reaches this `build` and paints the pill
    // away. Marking this element dirty as well would be redundant, and it is a
    // hazard rather than a nicety: a slot can be requested from a listener that
    // fires mid-frame (the music bridge does), and `setState` there is an error.
    _disarm?.cancel();
    _disarm = null;
    _armed = false;
  }

  /// Ends the window and takes the pill down, if it is up.
  ///
  /// Idempotent, and silent when there is nothing to do, because it is called
  /// from the timer and from both branches of a press.
  void _disarmNow() {
    _disarm?.cancel();
    _disarm = null;
    if (!_armed || !mounted) return;
    setState(() => _armed = false);
  }

  /// The press, once the framework has established that nothing above the shell
  /// wanted it.
  ///
  /// `didPop` cannot be true under `canPop: false`, but the callback contract
  /// is not worth relying on: if a future change lets the root route pop, the
  /// shell must not also act on the same press.
  void _onPop(bool didPop, Object? result) {
    if (didPop) return;

    if (widget.current.value != ShellSlot.home) {
      _disarmNow();
      widget.onGoHome();
      return;
    }

    if (_armed) {
      _disarmNow();
      // The same call the unhandled press used to make, now made on purpose:
      // on Android it removes the activity from the stack and returns to the
      // launcher. Chosen over `dart:io`'s `exit` because that reports a crash
      // to the platform, and over popping the root route because a Navigator
      // pop of the last route leaves the app with nothing to show.
      SystemNavigator.pop();
      return;
    }

    _disarm = Timer(shellExitWindow, _disarmNow);
    setState(() => _armed = true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // **False on the root route, and that is what makes the press arrive
      // here.** A route reports `doNotPop` as soon as one of its pop entries
      // refuses, and `Navigator.maybePop` then calls this callback and answers
      // true, so `handlePopRoute` stops before its `SystemNavigator.pop()`
      // fallback. Routes pushed above the shell are their own entries and keep
      // popping normally; this only ever speaks for the root.
      canPop: false,
      onPopInvokedWithResult: _onPop,
      // Expand rather than the default loose fit: the shell's layout is a
      // full-window surface, and a loose stack would let it size to its content
      // and leave the window showing through. The overlay is positioned, so it
      // neither measures nor moves anything here.
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          widget.child,
          if (_armed)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _PressAgainPill(),
            ),
        ],
      ),
    );
  }
}

/// "Press back again to exit", over the shell's own chrome.
///
/// A pill and not a `SnackBar`, for a concrete reason rather than a taste one:
/// the shell mounts five `Scaffold`s at once in its `IndexedStack`, every one of
/// them registers with `MaterialApp`'s single `ScaffoldMessenger`, and a snack
/// bar is pushed into *all* registered scaffolds. Only the visible slot would
/// paint it, but the state would outlive the press and be thrown at whichever
/// slot was on screen when the duration expired. This widget's life is exactly
/// `_armed`, which is exactly the window.
///
/// [IgnorePointer] because an exit prompt must not be the thing a remote lands
/// on: the shell's own focus tree traverses straight through it, and the pill
/// adds no focus node of its own to be landed on.
class _PressAgainPill extends StatelessWidget {
  const _PressAgainPill();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final inset = MediaQuery.viewPaddingOf(context);
    // Clear the shell's bottom chrome, which is what the pill would otherwise
    // cover: on a phone the bottom bar is pinned to the edge (64 dp plus the
    // home indicator, `ShellRail._bottomBar`) and rides below the pill's own
    // gutter, while everywhere else the rail is a side column and the now
    // playing bar sits at the foot only while something is playing.
    final bottom = switch (FormFactorService.of(context)) {
      FormFactor.compact => ZplaySpacing.s64 + inset.bottom + ZplaySpacing.s16,
      _ => ZplaySpacing.s24 + inset.bottom,
    };

    return IgnorePointer(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          ZplaySpacing.s24 + inset.left,
          ZplaySpacing.s24,
          ZplaySpacing.s24 + inset.right,
          bottom,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: tokens.surfaceOverlay,
            elevation: 8,
            borderRadius: BorderRadius.circular(ZplaySpacing.s24),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ZplaySpacing.s20,
                vertical: ZplaySpacing.s12,
              ),
              child: Text(
                'Press back again to exit',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}