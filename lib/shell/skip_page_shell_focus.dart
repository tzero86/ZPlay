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
    // Only nodes below this widget count, so the shell's own nav bar is never a
    // candidate and the page's own root node is the first one found.
    //
    // A page's whole-page `Focus(onKeyEvent:)` supplies no node, so there is no
    // widget field to read and an element walk cannot see it. That is how a node
    // covering the entire content area stayed an ordinary traversal candidate:
    // measured on the television as `FP 0,48 960x492` after two presses of
    // `down` from the nav bar, with no ring drawn anywhere.
    //
    // Resolving it from a child element with `Focus.maybeOf` was tried and
    // reverted: it registers an inherited dependency, and that dependency trips
    // an assertion inside `_FocusInheritedScope` when the tree tears down.
    // Measured - eleven shell tests failed on
    // `building _FocusInheritedScope(dirty, dependencies: ...)`.
    //
    // So walk the *node* tree instead. A `FocusNode` carries its own `context`,
    // which is what makes the node reachable without depending on anything, and
    // the shallowest node inside the page is the page's root node - the one that
    // covers the whole page and the one traversal must not stop on.
    final page = context as Element;

    bool isInsidePage(FocusNode node) {
      final nodeContext = node.context;
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

    void visitNode(FocusNode node) {
      if (found != null) return;
      if (isInsidePage(node)) {
        found = node;
        return;
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
