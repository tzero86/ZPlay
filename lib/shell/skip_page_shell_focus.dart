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
    if (!mounted) return;
    final target = context;
    if (target is! Element || !target.mounted) return;
    final nodes = _findPageNodes();
    for (final node in nodes) {
      node.skipTraversal = true;
      if (node.canRequestFocus) {
        node.descendantsAreFocusable = true;
        node.canRequestFocus = false;
      }
    }
  }

  List<FocusNode> _findPageNodes() {
    final page = context as Element;
    final found = <FocusNode>[];

    bool isInsidePage(FocusNode? node) {
      final nodeContext = node?.context;
      if (nodeContext is! Element) return false;
      var inside = false;
      nodeContext.visitAncestorElements((Element ancestor) {
        if (identical(ancestor, page)) {
          inside = true;
          return false;
        }
        return true;
      });
      return inside;
    }

    // A node is the page's own root when it sits inside the page, its focus
    // parent does not, and it actually covers focus descendants. Deciding it
    // locally, from the parent, is what keeps the page's controls out of the
    // result.
    //
    // The previous walk carried a "we are inside the page now" flag down the
    // tree, which only works while the focus tree nests the way the element tree
    // does. It does not: the shell's own `ExcludeFocus` node sits between the
    // page's contents and the page, so the flag was never raised at a page root,
    // every control below it was classified on its own, and all of them were
    // marked. Disabling them is what made the search field untappable — the
    // field's own node had `canRequestFocus = false`, so a tap put no cursor in
    // the box and no text ever reached the controller.
    //
    // The covering test is the other half. This widget exists to defuse a focus
    // node that covers a whole page, and in the Flutter pinned here `Scaffold`
    // creates none at all (`scaffold.dart` contains no `Focus`), so on most
    // pages the only node inside the page is a leaf control. Marking a leaf
    // gains nothing and costs the control its focusability, so a node is only
    // marked when something inside the page hangs off it.
    bool hasInsideDescendant(FocusNode node) {
      for (final FocusNode child in node.children) {
        if (isInsidePage(child) || hasInsideDescendant(child)) return true;
      }
      return false;
    }

    void visitNode(FocusNode node) {
      if (isInsidePage(node) && !isInsidePage(node.parent)) {
        if (hasInsideDescendant(node)) found.add(node);
      }
      for (final FocusNode child in node.children) {
        visitNode(child);
      }
    }

    visitNode(FocusManager.instance.rootScope);
    return found;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
