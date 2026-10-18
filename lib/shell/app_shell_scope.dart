/// Shell reachability: how a slot page, or a route pushed above one, asks the
/// shell to navigate.
///
/// The shell is the only writer of navigation state. A page that wants to leave
/// its own slot (Home opening Settings, a library row opening Search) calls
/// [AppShellController.go] instead of pushing a route. That is the whole
/// difference between this and the old model, where every page owned a dock and
/// pushed its neighbours with `Navigator.pushReplacement`.
///
/// An [InheritedWidget] rather than a provider because the contract needs one
/// nullable lookup with no rebuild churn: [AppShellScope.updateShouldNotify] is
/// false, so a descendant that only wants the controller is never rebuilt by a
/// slot switch, and a descendant that wants to *react* to one listens to
/// [AppShellController.current] instead.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../pages/browse/browse_page.dart' show BrowseVertical;
import '../services/layout/form_factor.dart';
import 'app_shell.dart';

// A page retargets an affordance with `AppShellScope.of(context)?.go(ShellSlot.x)`,
// so the enum and the scope come as a pair. Re-exported here so that call site
// needs one import: importing `app_shell.dart` from a page would make the shell
// import that page for its slot list and the page import the shell back, which
// Dart resolves but nobody should have to read twice.
export 'app_shell.dart' show ShellSlot;

/// Publishes the shell's [AppShellController] to the subtree the shell builds.
class AppShellScope extends InheritedWidget {
  const AppShellScope({
    super.key,
    required this.controller,
    required super.child,
  });

  /// The live shell controller. The shell creates one for its whole lifetime and
  /// never swaps it, which is what lets [updateShouldNotify] be false.
  final AppShellController controller;

  /// The shell's controller, or null when [context] is not below a shell.
  ///
  /// Null instead of a throw is deliberate. Part of the app is still pumped
  /// directly by widget tests, and entity routes (details, player, reader) are
  /// pushed above the shell rather than shown inside a slot, so neither has a
  /// shell above it. Callers therefore degrade:
  /// `AppShellScope.of(context)?.go(ShellSlot.settings)` is a no-op outside the
  /// shell, where a lookup that threw would take the page down with it.
  static AppShellController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppShellScope>()?.controller;

  /// False on purpose. The controller instance is stable for the shell's whole
  /// life and the fact a page can observe, the selected slot, is published as a
  /// [ValueListenable] instead, so notifying dependents here would rebuild every
  /// reader of the scope on each switch for a value that did not change.
  @override
  bool updateShouldNotify(AppShellScope oldWidget) => false;
}

/// What a page gets when it reaches the shell.
///
/// Built by `AppShell` and reached through [AppShellScope.of], never
/// constructed by a page: the shell owns the selected slot, and this is a handle
/// onto it rather than a copy of it.
class AppShellController {
  /// Wired by `AppShell` to its own state. The three callbacks are how the
  /// controller answers questions and requests switches without the shell's
  /// private state becoming part of the public surface.
  AppShellController({
    required ValueListenable<ShellSlot> current,
    required bool Function(ShellSlot slot) onSelect,
    required FormFactor Function() formFactor,
  }) : _current = current,
       _onSelect = onSelect,
       _readFormFactor = formFactor;

  final ValueListenable<ShellSlot> _current;
  final bool Function(ShellSlot slot) _onSelect;
  final FormFactor Function() _readFormFactor;

  /// The Browse vertical the top bar's Live TV destination asks for.
  ///
  /// Owned here rather than by the shell's own state because it is a *request*,
  /// not the selection: Browse owns which vertical it shows and subscribes to
  /// this ([browseVertical]). Live TV is not a [ShellSlot] - it is Browse with
  /// one of Browse's own verticals already selected - so the shell needs a
  /// channel to ask for it without reaching into the page.
  final _VerticalRequest _browseVertical = _VerticalRequest(
    BrowseVertical.moviesAndTv,
  );

  /// The focus node of the visible slot page's own top-chrome row, when it has
  /// one.
  ///
  /// The shell's bar and a page's own header are two storeys of one band, and
  /// the remote's DOWN out of the bar is geometric: it only considers candidates
  /// that overlap the focused row's own x-band, and a page's header row sits to
  /// the *right* of every row in the bar. So DOWN from the trailing rows skipped
  /// the page's own row entirely and landed on the first ring of content a whole
  /// header below it - on Home that made the calendar glyph unreachable from the
  /// bar, and the same key press landed on a rail's See All instead.
  ///
  /// Written by the page that owns the row and read by the bar's `_TopChromeHandover`
  /// at key time, never held for longer: a plain field rather than a listenable,
  /// because the shell only ever needs the answer while a key is being handled
  /// and a rebuild is not part of that.
  ///
  /// The shell never trusts it blindly. [FocusNode.canRequestFocus] is false for
  /// every slot the shell is not showing (`ExcludeFocus`) and for a node whose
  /// control is not on screen, and a control that has never been laid out
  /// reports an empty rect - so a stale handle can never take the remote.
  FocusNode? pageTopChrome;

  /// The slot the shell is showing, and a notification every time it changes.
  ///
  /// Listenable rather than a plain getter because a slot switch has no return
  /// moment. Home used to reload its rails in the `await` after pushing Settings,
  /// because an addon installed there invalidates the rails it already built.
  /// There is nothing to await once Settings is a sibling slot, so a page that
  /// needs to act on re-entry subscribes here and compares the new value with
  /// the slot it owns.
  ValueListenable<ShellSlot> get current => _current;

  /// Switches to [slot]. Returns false when the shell is not mounted.
  ///
  /// Answers false instead of throwing or silently succeeding, so a caller that
  /// holds a controller past the shell's life (a test, or a route being torn
  /// down while a callback is in flight) can tell that nothing happened. The
  /// mount check lives in the shell's select handler, which is the only place
  /// that knows whether there is still a tree to switch.
  bool go(ShellSlot slot) => _onSelect(slot);

  /// The layout the shell is currently in, for a page that wants to match its
  /// own density to the chrome around it. Live rather than a snapshot, so a
  /// window resized across a breakpoint reports the new band on the next read.
  FormFactor get formFactor => _readFormFactor();

  /// The Browse vertical the shell last asked for, and a notification each time
  /// it changes.
  ///
  /// The top bar's Live TV destination is not a [ShellSlot]: it lands on the
  /// Browse slot with one of Browse's own verticals already selected. Browse
  /// owns that selection, so the shell publishes a request rather than reaching
  /// into the page - the same reason [current] is a listenable rather than a
  /// plain getter. Browse subscribes and switches itself.
  ValueListenable<BrowseVertical> get browseVertical => _browseVertical;

  /// Asks Browse to show [vertical], and switches to the Browse slot.
  ///
  /// Sets the request first: a caller that is already on Browse still needs the
  /// page to change, and `go` returns early when the slot is unchanged. A
  /// caller that is elsewhere has its page switched while hidden, so the switch
  /// that follows paints the vertical it asked for rather than the old one.
  ///
  /// Notifies even when the request names the value already held. Tapping the
  /// Live TV shortcut, visiting another vertical, then tapping it again leaves
  /// the value equal, and a plain set would stay silent while the slot switch
  /// returns early too - so the tap would do nothing at all.
  void goBrowseVertical(BrowseVertical vertical) {
    _browseVertical.request(vertical);
    _onSelect(ShellSlot.browse);
  }

  /// A page that wants the next back press for itself, while it is up.
  ///
  /// **Why this exists.** `ShellBackGuard` is the root route's only pop entry,
  /// so Android's back arrives there whichever page is on screen - and a page
  /// cannot refuse the press from below. A `Focus.onKeyEvent` that answers a
  /// `goBack` decides only what *it* does; the platform message is delivered on
  /// its own path, and the framework's `KeyEventResult.handled` never reaches
  /// it. Measured on a device with a transient overlay open: one press closed
  /// the overlay (the page's key handler) *and* ran the guard's go-Home policy
  /// 47 ms later, and the slot switch that followed made the control the page
  /// had just re-focused unfocusable - so the ring landed on the bar.
  ///
  /// **One claimant, the most recent.** Registrations nest in practice (a
  /// player opens a menu over a menu) but only the topmost layer is the one the
  /// user is looking at, so a stack with a single live owner is the honest
  /// shape: the last registration wins, and releasing a claim that is no longer
  /// on top is a no-op rather than an unwind of somebody else's.
  ///
  /// The guard calls the claim instead of applying its own policy, and the
  /// claimant is responsible for the whole press - closing its overlay and
  /// putting focus back where it belongs.
  VoidCallback? _backClaim;

  /// True while some page is claiming the back press.
  bool get hasBackClaim => _backClaim != null;

  /// Takes the back press until [releaseBackClaim], returning an idempotent
  /// callback that gives up the claim.
  ///
  /// [claim] runs *instead of* the shell's go-Home/exit policy, so a claimant
  /// that is silently unmounted would swallow the press and strand the viewer -
  /// which is why releasing is wrapped for repeat calls and why every caller
  /// releases from `dispose`.
  VoidCallback claimBack(VoidCallback claim) {
    _backClaim = claim;
    return () {
      if (identical(_backClaim, claim)) _backClaim = null;
    };
  }

  /// Applies the live claim, if any. Answers whether it did.
  bool consumeBackClaim() {
    final claim = _backClaim;
    if (claim == null) return false;
    claim();
    return true;
  }

  /// Drops any claim. Called by `AppShell` when its state dies.
  ///
  /// A page's own `dispose` has already released by then in every path that
  /// unmounts a page before the shell, but the shell outlives a page that was
  /// torn down while its claim was live, and a stale claim would eat the press
  /// that exits the app.
  void clearBackClaim() {
    _backClaim = null;
  }

  /// Releases the Browse vertical request channel. Called by `AppShell` when its
  /// state dies.
  ///
  /// The shell's pages are unmounted before the state that owns them
  /// (`_InactiveElements._unmount` is post-order), so nothing below the scope can
  /// still be listening by the time this runs.
  void dispose() {
    _browseVertical.dispose();
  }
}

/// A [BrowseVertical] request channel that can re-announce the value it holds.
///
/// `value =` is silent when the value is unchanged, which is exactly the tap
/// that must not be: choosing the bar's Live TV shortcut while Browse already
/// shows the Live TV vertical leaves the value equal, and the slot switch that
/// follows returns early too, so a plain set would make the tap do nothing at
/// all. Subclassing is the legal way to reach `notifyListeners` - it is
/// `@protected`, so a bare [ValueNotifier] cannot be told to repeat itself from
/// outside the class.
class _VerticalRequest extends ValueNotifier<BrowseVertical> {
  _VerticalRequest(super.value);

  /// Announces [vertical] to listeners whether or not it differs from [value].
  void request(BrowseVertical vertical) {
    if (value == vertical) {
      notifyListeners();
    } else {
      value = vertical;
    }
  }
}
