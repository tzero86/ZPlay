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
    final node = _findPageNode();
    if (node == null || node.skipTraversal) return;
    node.skipTraversal = true;
  }

  FocusNode? _findPageNode() {
    FocusNode? found;
    // Start below this widget so the shell's own rail is not a candidate, and
    // so the page's own node is the first one found.
    void visit(Element element) {
      if (found != null) return;
      final widget = element.widget;
      if (widget is Focus && widget.focusNode != null) {
        found = widget.focusNode;
        return;
      }
      element.visitChildElements(visit);
    }

    (context as Element).visitChildElements(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
