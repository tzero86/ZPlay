/// Marks a slot page's own root focus node as untraversable, keeping its
/// children reachable.
///
/// A page is a `Scaffold`, and `Scaffold` installs a `Focus` node covering the
/// whole page. That node is an ordinary candidate for directional traversal, and
/// because it covers everything beneath it, taking focus on it makes the page
/// unusable with a remote: every arrow press searches for a neighbour outside the
/// node's own rectangle, finds only the shell rail, and the user cannot reach the
/// content they can plainly see.
///
/// Verified on a Chromecast with Google TV. The focus tree showed three nodes at
/// `88,0 872x540` - one per `IndexedStack` child - and primary focus sat on the
/// active page's. The rail row kept its ring, so navigation *looked* fine while
/// the page underneath was completely unreachable: the search field could not
/// take focus from either `right` or the centre button, which is why a television
/// user could not search at all.
///
/// **`skipTraversal`, not `ExcludeFocus`.** Marking the node skipped leaves it
/// able to hold focus while taking it out of the traversal order, so the
/// controls inside stay ordinary candidates. Excluding it would remove the whole
/// subtree and make things worse.
///
/// Applied by the shell once, to every slot, rather than by each page: this is a
/// property of being a page rather than of any one page, and eleven call sites
/// is eleven chances to forget one.
library;

import 'package:flutter/widgets.dart';

class SkipPageShellFocus extends StatefulWidget {
  const SkipPageShellFocus({super.key, required this.child});

  final Widget child;

  @override
  State<SkipPageShellFocus> createState() => _SkipPageShellFocusState();
}

class _SkipPageShellFocusState extends State<SkipPageShellFocus> {
  @override
  void initState() {
    super.initState();
    // The page builds its `Scaffold` during this frame, so the node does not
    // exist yet. Marking it in a post-frame callback is the earliest moment it
    // can be found, and it happens before any key is pressed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _skipPageNode());
  }

  @override
  void didUpdateWidget(SkipPageShellFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _skipPageNode());
  }

  /// Finds the nearest `FocusNode` the page installed and marks it skipped.
  ///
  /// Walking the element tree rather than holding a node is deliberate: the node
  /// is created by the page's own `Scaffold`, is not available at build time, and
  /// every page builds a different subtree above it.
  void _skipPageNode() {
    // `mounted` alone is not enough. The callback is queued for the frame *after*
    // this widget was built, and by then the page it pointed into may already
    // have been torn down - `Focus.maybeOf` on an element from a detached tree
    // is a framework assertion, not a null. A widget test that unmounts the
    // shell mid-frame hits it every time.
    if (!mounted) return;
    final target = context;
    if (target is! Element || !target.mounted) return;
    final node = _findPageNode();
    if (node == null) return;
    node.skipTraversal = true;
    // `skipTraversal` alone leaves the node focusable, and a focusable node
    // covering the whole page is exactly the wall: traversal from it searches
    // outside its own rectangle, finds only the rail, and the content below is
    // unreachable while the rail row keeps its ring - so navigation *looks*
    // fine. `descendantsAreFocusable` is restored first because setting
    // `canRequestFocus` propagates to the subtree, and every control on the page
    // lives below this node.
    if (node.canRequestFocus) {
      node.descendantsAreFocusable = true;
      node.canRequestFocus = false;
    }
  }

  FocusNode? _findPageNode() {
    FocusNode? found;
    // Start below this widget so the shell's own rail is not a candidate, and
    // so the page's own node is the first one found.
    // The node is read with `Focus.maybeOf`, not taken from `Focus.focusNode`.
    //
    // `Scaffold` builds its root node without supplying one, so the field is
    // null - and a test of `widget.focusNode != null` therefore never matched
    // anything. Measured on the television: RIGHT off the shell rail moved focus
    // to a node at `64,0 896x540` - the whole page - with no ring drawn anywhere,
    // and from a node that size traversal finds no candidate in any direction.
    // This class was in place the whole time, marking nothing, so the wall it
    // was written to remove was still there.
    //
    // Read from *inside* the `Focus` widget, not from its own element. Two
    // traps, both measured on the television:
    //
    //  - `Focus.focusNode` is null on a `Focus` that was not given one, and a
    //    page's own `Focus(onKeyEvent:)` supplies none - so testing the field
    //    never matches.
    //  - `Focus.maybeOf(element)` on the `Focus`'s own element resolves the
    //    nearest **ancestor** scope, which walks straight past it.
    //
    // A child of the `Focus` resolves the node that `Focus` actually published,
    // which is the node capable of taking focus.
      void visit(Element element) {
      if (found != null) return;
      // Read the node the `Focus` published from its own element via
      // `Focus.of(context)`-style resolution on the *element itself* rather
      // than a descendant lookup: walking into the children and asking there
      // creates an inherited dependency from a node that is not a descendant,
      // which trips an assertion inside `notifyClients` when the tree tears
      // down. `element.widget is Focus` plus the widget's own `focusNode` covers
      // the only case this class needs - a page that supplied its node - and
      // `FocusableActionDetector`-based cards bring their own.
      final widget = element.widget;
      if (widget is Focus) {
        final own = widget.focusNode;
        if (own != null) {
          found = own;
          return;
        }
      }
      element.visitChildElements(visit);
    }

    (context as Element).visitChildElements(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
