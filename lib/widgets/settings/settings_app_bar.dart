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
/// The band is opaque rather than a translucent wash: it is its own layout
/// child, so no content scrolls under it, and it wears the same `tokens.bg` and
/// `tokens.hairline` the shell's own bars do. That is what makes a sub-page read
/// as the surface its hub is painted on.
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
      backgroundColor: tokens.bg,
      surfaceTintColor: Colors.transparent,
      // Flat, explicitly. One converted page set this and the rest relied on the
      // theme's default, which is how a shared band ends up with two heights and
      // two shadows depending on which page copied it.
      elevation: 0,
      // The shell family draws this header as an opaque palette band with a
      // bottom hairline rather than a translucent wash over the page.
      shape: Border(bottom: tokens.hairline),
      toolbarHeight: toolbarHeight,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        title,
        style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
      ),
      actions: actions,
    );
  }
}
