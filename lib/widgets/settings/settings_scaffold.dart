import 'package:flutter/material.dart';

import '../common/animated_ambient_background.dart';
import 'settings_app_bar.dart';

/// The chrome every settings sub-page draws.
///
/// Nineteen sub-pages had copied the same four rungs by hand: an
/// [AnimatedAmbientBackground], a [Scaffold] whose surface is
/// `Colors.transparent`, a [SettingsAppBar] with the page's title, and a
/// [Center] around a `ConstrainedBox(maxWidth: 800)` holding the page's own
/// scroll view. Copy-per-page meant the numbers drifted - 800 here, 820 two
/// files over, `16`/`20` as tokens here and as literals there - and each drift
/// is a page that stops lining up with its neighbours when you walk between
/// them. This owns that nesting once; a page passes its title and its body.
///
/// **The scaffold is transparent because the page's canvas is the background.**
/// [AnimatedAmbientBackground] paints the moving lights, the palette wash and
/// the user's wallpaper across the whole route; an opaque [Scaffold] surface
/// draws a flat rectangle on top of it, which on a pushed settings route reads
/// as a panel pasted over the app rather than a page of it. The same reasoning
/// is why [SettingsAppBar] paints no fill and no hairline.
///
/// **Which makes the ambient background owed, not decorative.** The app bar is
/// a transparent wash, so the header only reads as part of the page while there
/// is a canvas underneath it; used over a bare `tokens.bg` it would be a title
/// floating on flat colour. Pairing the two here is the point: a page cannot
/// take the shared bar and forget its canvas.
///
/// **800 dp is the reading measure.** The sub-pages are lists of labelled rows,
/// switches and cards; without a ceiling a desktop window stretches each row the
/// full width of the screen and the eye has to travel the whole way to pair a
/// label with its value. 800 (the width the pages already used) keeps a row
/// scannable without going so narrow that the two-column cards inside stack
/// needlessly. [maxWidth] exists because two pages - music and audiobook - were
/// copied 820 wide before this existed; they pass 820 at the call site so that
/// number stays visible rather than disappearing into a fifth copy.
///
/// **The body is a `child`, not a `ListView`.** The pages do not agree on
/// scrolling: most hand over a `ListView`, language hands over a
/// `ValueListenableBuilder` that builds one, the music page asks for
/// `BouncingScrollPhysics`. Padding and physics belong to whatever scrolls, so
/// the wrapper takes the finished widget and leaves the scroll view, its
/// padding and its physics to the page. (The 800-wide pages settle on
/// `s16`/`s20`; about asks for `s24` and keeps it, and music/audiobook use the
/// `16`/`20` literals they always did.)
///
/// **The hub is not a client.** `SettingsPage` is the shell, not a sub-page of
/// it: its bar carries the section sidebar's own theme and its body is a
/// sidebar-and-detail split, so it has no meaningful `maxWidth` and its header
/// is not this wash. Every page reachable *from* the hub is a client; the hub
/// itself is what they are pushed from.
///
/// The two player-studio pages are not clients either, for a smaller reason:
/// their bar carries a two-line title and a glyph, which [SettingsAppBar]'s
/// single `String` cannot hold, and their body is a two-pane editor at 440 dp
/// rather than a centred list. They keep their own chrome deliberately.
///
/// [actions] is passed through untouched - a page that wants trailing controls
/// (the Liquid Glass reset button) keeps them and its position, and one that
/// does not is a shorter call.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.child,
    this.maxWidth = 800,
    this.actions,
  });

  /// The page title, drawn by [SettingsAppBar] at the app's screen-title step.
  final String title;

  /// The page body: whatever scrolls, with its own padding and physics.
  final Widget child;

  /// Ceiling for the body's content box. Defaults to the measure the
  /// sub-pages use.
  final double maxWidth;

  /// Trailing app-bar controls, passed to [SettingsAppBar] untouched.
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return AnimatedAmbientBackground(
      child: Scaffold(
        // No fill: the ambient canvas behind this scaffold is the page surface,
        // and anything opaque here would cover it.
        backgroundColor: Colors.transparent,
        appBar: SettingsAppBar(title: title, actions: actions),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        ),
      ),
    );
  }
}