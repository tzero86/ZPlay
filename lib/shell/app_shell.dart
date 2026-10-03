/// The one app shell: it owns navigation and the now-playing bar, and every
/// destination renders inside it.
///
/// This replaces the per-page floating liquid dock. Under that model each page
/// carried its own navigation and reached its neighbours with
/// `Navigator.pushReplacement`, which squashed history and destroyed the page it
/// left: scroll position, catalogue filters and search text were rebuilt from
/// scratch on every section change, and going "back" to a section was a fresh
/// push rather than the page the user left.
///
/// The shell keeps every slot mounted in one [IndexedStack] instead, so a switch
/// is a paint change and nothing else. State survives, there is no history entry
/// to unwind, and navigation stops being something a page can forget to render,
/// because pages no longer render any.
///
/// The layout follows the form factor and nothing else: a bottom bar with the
/// now-playing bar above it on a phone, and the prototype's top nav bar with the
/// now-playing bar at the foot of the content column on tablet, desktop and
/// television. The shell adds no app bar: a slot page keeps its own `Scaffold`
/// and its own header, so the app has exactly one nav bar and exactly one page
/// header at a time.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pages/browse/browse_page.dart';
import '../pages/home/home_page.dart';
import '../pages/library/library_page.dart';
import '../pages/search/search_page.dart';
import '../pages/settings/settings_page.dart';
import '../services/layout/form_factor.dart';
import '../services/theme/design_tokens.dart';
import '../services/window/window_service.dart';
import 'app_shell_scope.dart';
import 'now_playing_bar.dart';
import 'shell_back_guard.dart';
import 'shell_rail.dart';
import 'shortcuts_sheet.dart';
import 'skip_page_shell_focus.dart';

/// The five destinations the shell can show, in bar order.
///
/// One enum rather than five routes, because all five are mounted at once and
/// only one is painted: the slot is the index into that stack, so the
/// declaration order here is load bearing. Nothing repeats that order by hand,
/// though: [_AppShellState._pages] is built from [ShellSlot.values], so a sixth
/// slot is a compile error in `_pageFor` rather than a silently missing child.
enum ShellSlot {
  /// Home, the personalised landing page.
  home,

  /// Browse, the seven verticals behind one switcher.
  browse,

  /// Search.
  search,

  /// Library: My List and Downloads.
  library,

  /// Settings.
  settings,
}

/// A slot switch requested by the keyboard map.
///
/// Carries the destination rather than being one intent per slot, so `Ctrl+K`
/// and `Cmd+K` share one intent and one action: the platform reports one
/// modifier or the other, and the two must behave identically.
class _GoToSlotIntent extends Intent {
  const _GoToSlotIntent(this.slot);

  final ShellSlot slot;
}

/// A fullscreen toggle requested by the keyboard map.
///
/// The window state it flips is not a slot, so there is nothing to carry: the
/// intent exists only so the key can be echoed by the bar's fullscreen row
/// rather than being an unlabelled one-off in the shortcut table.
class _ToggleFullscreenIntent extends Intent {
  const _ToggleFullscreenIntent();
}

/// The keyboard reference sheet, requested by `?`.
///
/// A shortcut nobody can discover is a shortcut nobody uses, and Music had the
/// only reference in the app - on `?`, but only once the user was already on the
/// Music page. The map belongs to the shell, where the map it describes is bound.
class _ShowShortcutsIntent extends Intent {
  const _ShowShortcutsIntent();
}

/// The shell. Mount it once, above every destination and below anything pushed
/// on top of the shell (details, player, reader), so a route above the shell
/// covers the chrome instead of sitting inside it.

/// The slot named by `ZPLAY_INITIAL_SLOT`, or [ShellSlot.home].
///
/// A compile-time constant read once at startup, so an ordinary build carries
/// the string and never the value. It exists because reaching a screen on a
/// television is a dozen D-pad presses, and a test driving the remote can
/// confirm only which screen it ended up on - not which control it pressed,
/// which is what made nine separate defects slow to diagnose.
///
/// Top level rather than a static on the widget, because a field initializer
/// runs before the class's own members are reachable.
ShellSlot initialShellSlot() {
  const name = String.fromEnvironment('ZPLAY_INITIAL_SLOT');
  if (name.isEmpty) return ShellSlot.home;
  for (final slot in ShellSlot.values) {
    if (slot.name == name) return slot;
  }
  // A typo in a build flag should not take the app down on a device nobody is
  // watching, so an unrecognised value opens Home rather than throwing.
  debugPrint('[AppShell] ignoring unknown ZPLAY_INITIAL_SLOT "$name"');
  return ShellSlot.home;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// The selected slot, and the shell's single piece of navigation state.
  ///
  /// A [ValueNotifier] rather than a bare index because a slot switch has no
  /// return moment for a page to hook. Home used to reload its rails in the
  /// `await` after pushing Settings, since an addon installed there invalidates
  /// the rails it already built; a listener here is what replaces that
  /// (`AppShellController.current`). Written in one place only, [_select], so
  /// the notifier and the painted index cannot disagree.
  final ValueNotifier<ShellSlot> _slot =
      ValueNotifier<ShellSlot>(initialShellSlot());

  /// One page per slot, built once for the shell's whole life.
  ///
  /// The list is derived from [ShellSlot.values] through [_pageFor] so the enum
  /// and the stack cannot drift, and it is built here rather than in [build] so
  /// the pages are constructed exactly once and their elements survive every
  /// rebuild of the shell.
  late final List<Widget> _pages = <Widget>[
    for (final ShellSlot slot in ShellSlot.values) _pageFor(slot),
  ];

  /// Cached in [build] before any descendant can read it.
  ///
  /// `AppShellController.formFactor` is a synchronous getter that a page may call
  /// from an event handler, where there is no build phase to look an inherited
  /// widget up in. The shell already resolves the form factor every frame it
  /// rebuilds, so it publishes that value instead of resolving a second time onto
  /// a context that is not building.
  FormFactor _formFactor = FormFactor.compact;

  late final AppShellController _controller = AppShellController(
    current: _slot,
    onSelect: _select,
    formFactor: () => _formFactor,
  );

  /// The desktop keyboard map: the conventional desktop chords plus fullscreen.
  ///
  /// Plain letters are deliberately absent. The player and the music surface
  /// bind their own keys (`Space`, `M`, arrows), and a shell binding on the same
  /// key would fire both, once here and once there. Ctrl+K and Ctrl+comma are
  /// chords nothing else claims, and they are what a keyboard user reaches for
  /// before the bar: the bar keeps its own rows, so the shortcut is a faster
  /// path to the same slot rather than the only one. F11 joins them because a
  /// window state outlives the slot you are on, so it cannot belong to a page.
  ///
  /// Both modifiers are bound for each shortcut: `Meta` is Command on macOS and
  /// Super or Windows elsewhere, so binding both pairs costs one extra activator
  /// and covers a desktop that reports either.
  static const Map<ShortcutActivator, Intent> _desktopShortcuts =
      <ShortcutActivator, Intent>{
        // Search, on the modifier that desktop search fields conventionally use.
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _GoToSlotIntent(ShellSlot.search),
        SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _GoToSlotIntent(ShellSlot.search),
        // Settings: Ctrl+comma and Cmd+comma, the platform's own preferences
        // chord, so a user's muscle memory already knows it.
        SingleActivator(LogicalKeyboardKey.comma, control: true):
            _GoToSlotIntent(ShellSlot.settings),
        SingleActivator(LogicalKeyboardKey.comma, meta: true):
            _GoToSlotIntent(ShellSlot.settings),
        // Fullscreen, on the key every desktop reserves for it. Global rather
        // than per page: the bar's fullscreen row is the pointer path to the same
        // state, and a user who is fullscreen on any slot needs a way out that
        // is not a trip back to Home. F11 is a function key, so unlike a letter
        // it cannot be swallowed by a text field mid-word.
        SingleActivator(LogicalKeyboardKey.f11): _ToggleFullscreenIntent(),
        // The five slots by number, which is the bar's own verb on a keyboard.
        // `Alt` rather than bare digits: a bare `1` must stay typeable, because
        // Search is a slot and its field is the first thing a `1` would
        // otherwise land in. `Alt` is what a desktop application uses for exactly
        // this, and it is held rather than pressed, so it does not disturb text.
        //
        // Settings is `5` rather than `0`: the bar puts it last, and a bar the
        // user can count is a bar they do not have to read.
        SingleActivator(LogicalKeyboardKey.digit1, alt: true):
            _GoToSlotIntent(ShellSlot.home),
        SingleActivator(LogicalKeyboardKey.digit2, alt: true):
            _GoToSlotIntent(ShellSlot.browse),
        SingleActivator(LogicalKeyboardKey.digit3, alt: true):
            _GoToSlotIntent(ShellSlot.search),
        SingleActivator(LogicalKeyboardKey.digit4, alt: true):
            _GoToSlotIntent(ShellSlot.library),
        SingleActivator(LogicalKeyboardKey.digit5, alt: true):
            _GoToSlotIntent(ShellSlot.settings),
        // The reference sheet, on the key that asks the question. `?` is shift
        // plus `/`, so a desktop user's hand is already on it.
        SingleActivator(LogicalKeyboardKey.slash, shift: true):
            _ShowShortcutsIntent(),
        SingleActivator(LogicalKeyboardKey.slash):
            _ShowShortcutsIntent(),
      };

  /// True where the shell binds the keyboard map. Positive on purpose: a future
  /// form factor must opt in, because a shell level key that collides with a
  /// player control is a bug the user sees, while a missing shortcut is one they
  /// never notice.
  bool get _usesKeyboard =>
      _formFactor == FormFactor.medium || _formFactor == FormFactor.expanded;

  /// Switches slots. False when the shell is gone.
  ///
  /// The mount check is here, not in [AppShellController.go], because this is
  /// the only place that knows whether there is still a tree to switch: a caller
  /// holding the controller past the shell's life gets a false instead of a
  /// `setState` on a disposed element.
  bool _select(ShellSlot slot) {
    if (!mounted) return false;
    if (slot == _slot.value) return true;
    // Notify first, then repaint. A page that listens (Home reloading its rails
    // on re-entry) sees the new slot before the frame that shows it, so it
    // cannot render against the old one, and its own `setState` joins the same
    // frame this one schedules.
    _slot.value = slot;
    setState(() {});
    return true;
  }

  @override
  void dispose() {
    // The notifiers die with the shell. Their only readers sit below
    // [AppShellScope], which goes away with this state, so nothing can hold a
    // listener on a disposed notifier.
    _slot.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// The page for a slot, exhaustive by construction: a new [ShellSlot] fails to
  /// compile here until it has a destination, which is the only guard that keeps
  /// the enum and the stack in step.
  Widget _pageFor(ShellSlot slot) => switch (slot) {
    ShellSlot.home => const HomePage(),
    ShellSlot.browse => const BrowsePage(),
    ShellSlot.search => const SearchPage(),
    ShellSlot.library => const LibraryPage(),
    ShellSlot.settings => const SettingsPage(),
  };

  /// Every slot stays in the tree, so every slot has to be told when it is
  /// hidden. [IndexedStack] lays out all of its children, which is exactly what
  /// preserves their state and their measurements, and this is the price of it.
  ///
  /// [TickerMode] is the one that nothing else covers. `IndexedStack` paints,
  /// hit-tests and visits semantics for the selected child only, and it already
  /// excludes the others from focus, but it leaves their tickers running: a
  /// hidden Home would keep its ambient background animating and burn frames for
  /// a surface nobody can see. [ExcludeFocus] and [ExcludeSemantics] restate the
  /// focus and screen reader halves at the point where the slots are declared, so
  /// the three boundaries sit together and a change to the widget above cannot
  /// quietly drop one of them.
  List<Widget> _slotChildren() {
    final int active = _slot.value.index;
    return <Widget>[
      for (int i = 0; i < _pages.length; i++)
        ExcludeFocus(
          excluding: i != active,
          child: ExcludeSemantics(
            excluding: i != active,
            child: TickerMode(
              enabled: i == active,
              // A page's own `Scaffold` installs a `Focus` node covering the
              // whole page, and it is a candidate for directional traversal like
              // any other. On a television that made it a wall: it took the
              // focus the bar's autofocus released, covered every control
              // beneath it, and no arrow could move to any of them, so the page
              // opened and could not be used.
              //
              // Verified on a Chromecast with Google TV: the focus tree showed
              // three nodes at 88,0 872x540 - one per `IndexedStack` child -
              // and primary focus sat on the active page's. The bar row kept
              // its ring, so it looked like navigation worked while the page
              // underneath was unreachable.
              //
              // `Focus.skipTraversal` on the page node rather than excluding it,
              // so the node stays active and the controls inside it remain
              // ordinary candidates. Wrapping in `ExcludeFocus(excluding: true)`
              // would take the whole page with it.
              child: SkipPageShellFocus(child: _pages[i]),
            ),
          ),
        ),
    ];
  }

  /// The two placements from the prototype. The nav chrome reserves its own
  /// space either way, so a slot page never pads to clear the shell.
  ///
  /// **The shell consumes exactly one inset, and only where it draws chrome over
  /// it.** On tablet, desktop and television the top bar owns the status bar
  /// strip, so the content column hands the pages a [MediaQuery] with the top
  /// padding removed: a page that positions a floating header from
  /// `MediaQuery.paddingOf(context).top` (Home, Anime, IPTV, Manga, Catalog,
  /// Discover, Calendar) or takes a `SafeArea` of its own (Books) would otherwise
  /// double-pad under the bar, and several of them paint a backdrop behind the
  /// status bar on purpose, which the bar now covers. On a phone the nav bar is
  /// at the foot, nothing has spent the top inset, and the pages keep the read
  /// they had - so the removal lives inside the top-bar branch and never touches
  /// compact.
  ///
  /// The shell still wraps nothing in [SafeArea]. Nothing else about the inset
  /// contract changed: a phone page owns its top inset, and the bottom bar owns
  /// its own.
  Widget _layout(Duration barDuration) {
    // **No `FocusTraversalGroup`, and that is the fix.**
    //
    // The group installed its own internal node, which became the `nearestScope`
    // of every nav row. Traversal running off that edge hit
    // `_onEdgeForDirection`, read
    // `directionalTraversalEdgeBehavior` - whose default is
    // `TraversalEdgeBehavior.stop` (`focus_manager.dart:1369`) - and returned
    // false. So an arrow from a nav row did nothing at all: focus could not
    // leave the nav, and the hero, the filter tabs, the hero buttons and every
    // content card were unreachable with a remote.
    //
    // Wrapping the nav in a `FocusScope` with `parentScope` did not help,
    // because the group node sits *inside* that scope and is still the
    // `nearestScope` the behaviour is read from. The boundary could only be
    // released by removing it.
    //
    // What the group bought was an ordering the nav already had. Its rows are
    // laid out left to right in the order they are built, so the geometric
    // order and the reading order are the same list, and the platform's
    // Cartesian search over the whole shell now does the thing the group was
    // emulating: right runs along the bar, down runs out of it into the page.
    //
    // Measured on a Chromecast with Google TV. The shell's own focus test
    // passed over this for a long time because it pressed `Tab`, which takes
    // the fallback order and never runs the directional path at all.
    final Widget nav = ShellRail(
      current: _slot.value,
      onSelect: _select,
      onLiveTv: () => _controller.goBrowseVertical(BrowseVertical.liveTv),
      autofocus: _formFactor == FormFactor.television,
    );
    // Clipped, and this is the shell's obligation rather than a page's.
    //
    // Flutter never clips by default and the layout paints its children in
    // order, so the slot page is painted AFTER the nav bar above it: anything a
    // page lets overflow past its own top or left edge draws straight over the
    // bar. Two of the app's rail widgets overflow deliberately. A slider parks
    // its hidden hover arrow at `left: -60`, and it scrolls its card list with
    // `clipBehavior: Clip.none` so a card can hang past the edge. Both were
    // written when the page WAS the window, where "outside the box" and "off
    // screen" were the same place. Under persistent shell chrome they are not.
    //
    // So the clip belongs here, once, instead of in the ~21 widgets that set
    // `Clip.none` for a peek or a parked overlay, and it is correct on its own
    // terms: a slot page has no business painting on the shell's navigation. It
    // also restores what those scrollers already assumed, because a horizontal
    // ListView clips at its own viewport edge, which is this column's edge.
    // No `FocusTraversalGroup` here either, for the same reason as the nav bar:
    // it is a second scope boundary, and a boundary is what stopped a remote
    // crossing between the chrome and the page. With both gone the shell is one
    // focus tree and the platform's own Cartesian search does the work.
    final Widget content = ClipRect(
      child: IndexedStack(
        index: _slot.value.index,
        // Expand, not the default loose fit: the slot pages are full-window
        // surfaces, and a loose stack would let a page size itself to its
        // content and leave the rest of the shell showing through.
        sizing: StackFit.expand,
        children: _slotChildren(),
      ),
    );
    // Animated rather than a plain child because the bar mounts at zero height
    // when nothing is playing and grows when something starts, and collapsing
    // that in one frame would reflow the whole page above it with a jolt. It is
    // also the shell's only transition: a slot switch is instant by design, so
    // the five mounted pages are never asked to cross-fade.
    final Widget bar = AnimatedSize(
      duration: barDuration,
      curve: ZplayMotion.standard,
      child: const NowPlayingBar(),
    );

    // Top bar or bottom bar is decided by the form factor, never by a width
    // here: a window can be wide and still be classified medium, and a second,
    // width-guarded bar beside the shell's is exactly the duplication this
    // rewrite exists to delete.
    if (_formFactor != FormFactor.compact) {
      // The nav bar is a full-width row pinned to the top, so the now-playing
      // bar sits at the foot of the content column below it, matching the
      // prototype's top-bar layout.
      return Column(
        children: <Widget>[
          nav,
          Expanded(
            // The top bar consumed the status bar strip, so the pages under it
            // must not pay the same inset a second time. Only here: the phone's
            // nav bar is at the foot and the pages still own their top inset.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: content,
            ),
          ),
          bar,
        ],
      );
    }
    return Column(
      children: <Widget>[
        Expanded(child: content),
        bar,
        nav,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _formFactor = FormFactorService.of(context);

    // The bar is the only thing in the shell whose size changes while the app
    // runs, so it is the only duration the shell spends. Reduced motion collapses
    // that one duration and keeps the curve, per the token layer's own note. A
    // repo-wide reduced motion pass is a separate change.
    final Duration barDuration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : ZplayMotion.base;

    // The back guard is the outermost widget of the shell's subtree, and it has
    // to be: it is what tells `Navigator.maybePop` that the root route refuses
    // to pop, and a `PopScope`'s registration is scoped to the route it is
    // built into. It sits above `AppShellScope` rather than below it so the one
    // widget that can end the process does not depend on the shell's own
    // subtree having built. Its own notes are the whole story
    // (`shell_back_guard.dart`).
    return ShellBackGuard(
      current: _slot,
      onGoHome: () => _select(ShellSlot.home),
      child: AppShellScope(
        controller: _controller,
        // Shortcuts and Actions stay in the tree on every form factor, with an
        // empty map on the ones without a keyboard. Swapping the widgets out
        // instead would change the tree's depth, and a desk window dragged
        // across the 1024 breakpoint would lose whatever had focus.
        child: Shortcuts(
          shortcuts: _usesKeyboard
              ? _desktopShortcuts
              : const <ShortcutActivator, Intent>{},
          child: Actions(
            actions: <Type, Action<Intent>>{
              _GoToSlotIntent: CallbackAction<_GoToSlotIntent>(
                onInvoke: (_GoToSlotIntent intent) {
                  _select(intent.slot);
                  return null;
                },
              ),
              _ToggleFullscreenIntent: CallbackAction<_ToggleFullscreenIntent>(
                onInvoke: (_ToggleFullscreenIntent intent) {
                  WindowService.instance.toggleFullscreen();
                  return null;
                },
              ),
              _ShowShortcutsIntent: CallbackAction<_ShowShortcutsIntent>(
                onInvoke: (_ShowShortcutsIntent intent) {
                  ShortcutsSheet.show(context);
                  return null;
                },
              ),
            },
            // The shell paints the canvas the nav bar and every slot sit on, so
            // a page that has not filled its slot yet shows the app background
            // instead of whatever the last frame left there.
            //
            // A `Material` and not a bare `ColoredBox`, because everything the
            // shell itself draws (the nav bar, its labels, the switcher bands in
            // Browse and Library) sits OUTSIDE the slot pages' own Scaffolds
            // and therefore outside any Material. `MaterialApp` hands
            // `WidgetsApp` a DefaultTextStyle of `_errorTextStyle` for exactly
            // that case (material/app.dart): red, monospace, and a yellow
            // double underline, so unstyled text is impossible to miss. The
            // shell's own text was inheriting the underline and the fallback
            // face. One Material here gives every one of them the theme's text
            // style instead.
            child: Material(
              color: context.tokens.bg,
              child: _layout(barDuration),
            ),
          ),
        ),
      ),
    );
  }
}
