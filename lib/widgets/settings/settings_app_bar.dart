import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';

/// The one app bar every settings sub-page draws.
///
/// The sub-pages hand-rolled the same band: the palette fill, a transparent
/// surface tint, the same bottom hairline, the same 20 dp back chevron, the same
/// `titleLarge` title, under the same comment. They were copied rather than
/// shared, so they drifted a line at a time - and that drift is what reads as
/// "you were there before and it looked nice, but this is another different
/// thing". The difference was never a decision; it was a copy that lost a line.
///
/// Assign it to `Scaffold.appBar`; the page keeps its own body, its own
/// constraints and its own scrolling. Nothing here is about a page's content,
/// which is exactly why every page can share it.
///
/// **The band is a wash, not a band.** It used to be an opaque `tokens.bg`
/// strip with a bottom hairline, which is the shell's own bar recipe - and on
/// every settings page it re-created the seam the shell's blended nav exists to
/// remove: a page that wears the app's canvas got a flat palette rectangle
/// pinned across its top instead. A settings sub-page is a *pushed route*, so
/// the shell's nav is not painted over it and this header is the page's own top
/// chrome; it stays transparent and quiet and lets the page's canvas show
/// through, exactly as the shell's own nav rests on the canvas of a shell slot.
///
/// That means a page using this owes the header a canvas: pair it with
/// `AnimatedAmbientBackground` (or any full-bleed page surface) behind the
/// `Scaffold`, or the transparent band lands on flat `tokens.bg`.
///
/// The title is [ZplayType.titleLarge], the app's one screen-title step (the
/// same token Browse-style pages wear). It sits one step above
/// [SectionHeader]'s `title`, which is what makes a page read as a page and its
/// sections read as its parts; `ZplayType.display` is the hero/detail headline
/// and would shout at the top of a dense settings list.
///
/// The hub ([SettingsPage]) deliberately does not use this: its bar carries the
/// section sidebar's own theme and is the shell rather than a sub-page of it.
class SettingsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SettingsAppBar({
    super.key,
    required this.title,
    this.actions,
    this.toolbarHeight,
  });

  final String title;

  /// Trailing controls, passed through untouched. A page that needs them keeps
  /// them; a page that does not is one argument shorter.
  final List<Widget>? actions;

  /// Defaults to Material's own toolbar height, so a page that passes nothing is
  /// the height it always was.
  final double? toolbarHeight;

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight ?? kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AppBar(
      // No fill. The page's own canvas is the band; anything opaque here is the
      // seam this widget exists to remove.
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      // Flat, and flat on scroll too: `scrolledUnderElevation` is what a
      // Material 3 app bar uses to tint itself once content slides under it, and
      // a tinted strip reappearing at the top is the band coming back.
      elevation: 0,
      scrolledUnderElevation: 0,
      // No hairline. A bottom rule was the second half of the opaque band, and a
      // page header separated by a line is a page header that looks like a
      // different app from the canvas it sits on.
      toolbarHeight: toolbarHeight,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        // One title style and one scale for every page, so no page can restyle
        // its own - and `titleLarge` is that scale app-wide.
        title,
        style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
      ),
      actions: actions,
    );
  }
}
