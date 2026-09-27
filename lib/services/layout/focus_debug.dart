/// Prints the focus tree to logcat on every key, so a D-pad bug can be
/// diagnosed in seconds instead of by screenshot.
///
/// This exists because focus is the one defect class in this app that has cost
/// the most time, and every method tried so far was blind:
///
/// - A widget test asserts what the tree looks like, not where a remote ends up.
///   The shell's own focus test pressed `Tab` for a long time and passed over
///   three separate defects, because `Tab` takes the fallback order and never
///   runs the directional path at all.
/// - Screenshot diffing shows *that* a key did nothing but not *why*. And it
///   lies: the home page auto-rotates its hero every few seconds, so consecutive
///   frames differ whether or not focus moved, which is why the first version of
///   `tool/tv_nav_probe.sh` reported every key as working on a screen where the
///   D-pad did nothing.
/// - Reading the source and reasoning about `FocusScopeNode` semantics is how
///   three confident wrong answers were produced in a row. The tree the device
///   actually built is the only thing that settles it.
///
/// What it prints, per key:
///
/// 1. The primary focus node, its rect, and whether it is focused at all. The
///    rect is what identifies the control: `FocusableCard` creates its
///    `FocusNode` without a debug label, so position is the only handle.
/// 2. The chain of scopes above it, each with its
///    `directionalTraversalEdgeBehavior`. This is the one that matters: the
///    default is `TraversalEdgeBehavior.stop`, and any scope in the chain
///    holding `stop` is a wall focus cannot cross.
/// 3. How many focusable nodes each scope can see. If the rail's scope reports
///    only the rail's rows, the rail is walled off from the page; if it reports
///    the page's too, they share a tree and a boundary was the problem.
///
/// Debug only. Stripped from release builds, and never consumes a key: the
/// handler returns false so logging cannot become the reason input stops
/// working.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

abstract final class FocusDebug {
  /// Set `false` to silence the output on a screen that is behaving and is
  /// being filmed.
  static bool enabled = true;

  /// Nodes are reported by rect rather than by name, so the interesting values
  /// are rounded. Sub-pixel precision is noise here.
  static const int _maxDescendants = 24;

  static void install() {
    if (!kDebugMode) return;
    FocusManager.instance.addListener(_onFocusChanged);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  /// Never consumes. If this returned true it would be a focus bug of its own:
  /// a diagnostic that stops the keys it is diagnosing.
  static bool _onKey(KeyEvent event) {
    if (!enabled) return false;
    if (event is! KeyDownEvent) return false;
    // Post-frame, so the dump reflects where focus ended up rather than where
    // it was when the key arrived. Traversal is not synchronous.
    WidgetsBinding.instance.addPostFrameCallback((_) => _dump(event.logicalKey));
    return false;
  }

  static void _onFocusChanged() {
    if (!enabled || !kDebugMode) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _dump(null));
  }

  static String _label(FocusNode n) {
    final explicit = n.debugLabel;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return n.runtimeType.toString();
  }

  static String _rect(FocusNode n) {
    final r = n.rect;
    if (r.isEmpty) return 'no-rect';
    return '${r.left.toStringAsFixed(0)},${r.top.toStringAsFixed(0)} '
        '${r.width.toStringAsFixed(0)}x${r.height.toStringAsFixed(0)}';
  }

  static bool _focusable(FocusNode n) => n.canRequestFocus;

  static void _dump(LogicalKeyboardKey? key) {
    final primary = FocusManager.instance.primaryFocus;
    debugPrint('──── FOCUS ${key == null ? '(focus change)' : key.keyLabel} '
        '────');
    if (primary == null) {
      debugPrint('  no primary focus at all');
      return;
    }

    debugPrint('  primary ${_label(primary)} ${_rect(primary)} '
        'hasFocus=${primary.hasFocus} primary=${primary.hasPrimaryFocus} '
        'canRequest=${primary.canRequestFocus} '
        'skip=${primary.skipTraversal}');

    // The chain is the diagnosis. A `stop` on any scope in here is a wall.
    var scope = primary.nearestScope;
    var depth = 0;
    while (scope != null && depth < 12) {
      final visible = scope.descendants.where(_focusable).toList();
      debugPrint('  scope[$depth] ${_label(scope)} '
          'edge=${scope.directionalTraversalEdgeBehavior} '
          'focusable=${visible.length}');
      for (final n in visible.take(_maxDescendants)) {
        final mark = identical(n, primary) ? '*' : ' ';
        debugPrint('    $mark ${_label(n)} ${_rect(n)}');
      }
      if (visible.length > _maxDescendants) {
        debugPrint('      ... ${visible.length - _maxDescendants} more');
      }
      final next = scope.enclosingScope;
      if (next == scope) break;
      scope = next;
      depth++;
    }
    debugPrint('──── end ────');
  }
}
