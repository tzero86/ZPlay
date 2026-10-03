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
  final ValueNotifier<BrowseVertical> _browseVertical =
      ValueNotifier<BrowseVertical>(BrowseVertical.moviesAndTv);

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
  void goBrowseVertical(BrowseVertical vertical) {
    _browseVertical.value = vertical;
    _onSelect(ShellSlot.browse);
  }

  /// Releases the request channel. Called by `AppShell` when its state dies.
  void dispose() => _browseVertical.dispose();
}
