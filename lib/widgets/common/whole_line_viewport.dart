import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A scroll body whose viewport ends on a whole line of the content it shows.
///
/// Two dialogs were sliced by their own scroll viewport. The viewport stopped
/// at an arbitrary height and painted whatever crossed that edge half-way:
/// glyph tops with the rest clipped, and no ellipsis, because the engine is
/// clipping a scroll viewport rather than eliding a paragraph. At ten feet on
/// a television the reader gets half a line of prose where the content should
/// be.
///
/// The evidence is two screenshots off the emulator. In
/// `build/emu_shots/sweep_58_nav6.png` - the first-run P2P advisory, body
/// viewport about 331 dp tall - the engine box's second row title,
/// `ZPlay (Torrent Engine)`, starts about 5 dp above the fold, so only the top
/// sliver of the row is painted; the body's fixed blocks total about 460 dp
/// against a 540 dp screen, so the fold has to fall somewhere and it fell
/// there. In `build/emu_shots/sweep_59_nav6.png` - the update dialog's
/// `WHAT'S NEW` box - the eighth line's ascenders are painted and nothing
/// else; `...so the strip would have been published` is the last whole line
/// the box shows.
///
/// Bottom padding on the content cannot fix either one. Adding padding changes
/// only how far the content can be scrolled, not where the fold rests; the
/// fold is the viewport's own bottom edge, `free` dp below the top of the
/// content, and the resting view paints whatever crosses it. The only lever is
/// the viewport's height, and it cannot be a constant: the blocks are not on
/// one uniform grid - a three-line question box, a five-line paragraph and
/// two-line engine rows with their own leading and their own padding - so no
/// multiple of a line height lands on a boundary in both dialogs. The height
/// has to come from the lines themselves: measure them, then end the viewport
/// on the last whole line that fits.
///
/// The measurement is a post-frame layout read. Line boxes do not exist until
/// the paragraph has been laid out, and layout runs after build, so the read
/// is taken in a post-frame callback for each new `free` and the resulting
/// height is applied on the following frame. That settles rather than loops:
/// the content sits inside a scroll view that lays it out with unbounded
/// height, so its own extent and its lines do not depend on the viewport
/// height this widget chooses; the second measurement of the same content at
/// the same `free` returns the same boundary and no further `setState` is
/// scheduled.
///
/// The content's height is taken from the last measured line bottom rather
/// than from the size of the subtree root. The root sits under this widget's
/// own `SizedBox`, so its height is the viewport height that was just imposed
/// on it, which can never reveal that the content overflows; the line bottoms
/// are the content's own extent. When they fit inside `free`, the child is
/// returned unwrapped and a parent that sizes to its content - the changelog
/// box, whose `maxHeight: 180` is a bound and not a height - keeps hugging it.
///
/// The outer box keeps `free` so a fixed footer below the body does not move
/// when the viewport snaps; the leftover between the snapped height and `free`
/// is blank, which is what makes the difference between a whole line and half
/// a line invisible.
///
/// One thing this does not fix: once the user scrolls, a resting position can
/// still put the viewport's edge mid-line, because an offset is not a line
/// boundary. That is the user's own doing and the scrollbar says so.
class WholeLineViewport extends StatefulWidget {
  const WholeLineViewport({super.key, required this.child});

  /// The scrollable body. Everything under it is measured for its lines; the
  /// box it is given is the box whose height is snapped.
  final Widget child;

  @override
  State<WholeLineViewport> createState() => _WholeLineViewportState();
}

class _WholeLineViewportState extends State<WholeLineViewport> {
  /// Identifies the measured subtree. `findRenderObject` on this key lands on
  /// the first render object under it, which is the scroll view's own box, and
  /// the line walk below accumulates layout offsets from there.
  final GlobalKey _contentKey = GlobalKey();

  /// The `free` that [_snapped] was measured for, or null before the first
  /// measurement has been applied.
  double? _measuredFor;

  /// The height the viewport should take, or null when the content fits inside
  /// `free` and the child is left to size itself.
  double? _snapped;

  /// The `free` a post-frame measurement is already queued for, so a rebuild at
  /// the same height does not queue a second one and the tree settles in the
  /// one extra frame the measurement costs.
  double? _queuedFor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final free = constraints.maxHeight;
        // A body laid out with unbounded height has nothing to snap to, and
        // returning it untouched keeps a list-like parent working.
        if (!free.isFinite) return widget.child;

        _queueMeasurement(free);

        if (_measuredFor != free) {
          // First layout at this height: the lines do not exist yet, so the
          // viewport takes the parent's whole offer for the one frame the
          // measurement costs. The geometry is the pre-fix geometry, which is
          // also what the caller sees when there is no measurement to make.
          return SizedBox(height: free, child: _content());
        }

        final snapped = _snapped;
        if (snapped == null) return _content();

        return SizedBox(
          height: free,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.max,
            children: [SizedBox(height: snapped, child: _content())],
          ),
        );
      },
    );
  }

  /// The caller's body, keyed so the post-frame read can find its render
  /// object. `KeyedSubtree` is layout-transparent, so the key costs the caller
  /// nothing and a hugging parent still hugs.
  Widget _content() =>
      KeyedSubtree(key: _contentKey, child: widget.child);

  void _queueMeasurement(double free) {
    if (_measuredFor == free || _queuedFor == free) return;
    _queuedFor = free;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _queuedFor = null;
      _measure(free);
    });
  }

  void _measure(double free) {
    final contentContext = _contentKey.currentContext;
    if (contentContext == null) return;
    final root = contentContext.findRenderObject();
    if (root is! RenderBox || !root.hasSize) return;

    final bottoms = <double>[];
    _collectLineBottoms(root, Offset.zero, bottoms);

    // Nothing measurable under this widget - an image body, or a widget test
    // stub. There are no lines to end on, so the body keeps the parent's height
    // instead of guessing one.
    if (bottoms.isEmpty) {
      _settle(free, free);
      return;
    }

    var lastBottom = 0.0;
    for (final bottom in bottoms) {
      if (bottom > lastBottom) lastBottom = bottom;
    }

    // The content fits: return it unwrapped so the parent can size to it.
    if (lastBottom <= free) {
      _settle(free, null);
      return;
    }

    // The last whole line that ends at or above the fold. A box's bottom is
    // where its line's ink stops, so this is a boundary a line really ends on
    // and not a height that happens to be near one.
    var snapped = 0.0;
    for (final bottom in bottoms) {
      if (bottom > snapped && bottom <= free) snapped = bottom;
    }
    if (snapped <= 0) snapped = free;
    _settle(free, snapped);
  }

  /// Applies a measurement, and only when it changes something.
  ///
  /// The post-frame read re-runs against the same content and the same `free`
  /// after the snap, so an equal value must not schedule another rebuild: that
  /// is what keeps the settle from becoming a loop.
  void _settle(double free, double? snapped) {
    if (_measuredFor == free && _snapped == snapped) return;
    setState(() {
      _measuredFor = free;
      _snapped = snapped;
    });
  }

  /// Collects the bottom edge of every line box under [node], in [node]'s
  /// coordinate space.
  ///
  /// [origin] is the accumulated layout offset on the way down; a child's box
  /// sits at its `BoxParentData.offset` inside its parent, and `visitChildren`
  /// visits direct children only, so the walk has to carry the sum itself.
  ///
  /// `includeLineSpacingMiddle` is what makes the boxes run line to line down a
  /// paragraph - each box covers its line plus the spacing around it, split
  /// between the two, so nothing is left unaccounted for between them - and a
  /// box bottom is therefore a place where a line really ends. Consecutive
  /// boxes can still differ by the engine's sub-pixel rounding, which is why
  /// the fold is put at a bottom and never between two of them.
  void _collectLineBottoms(
    RenderObject node,
    Offset origin,
    List<double> bottoms,
  ) {
    if (node is RenderParagraph) {
      final text = node.text.toPlainText();
      if (text.isNotEmpty) {
        final boxes = node.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length),
          boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
        );
        for (final box in boxes) {
          bottoms.add(origin.dy + box.bottom);
        }
      }
    }

    node.visitChildren((child) {
      final parentData = child.parentData;
      final offset =
          parentData is BoxParentData ? parentData.offset : Offset.zero;
      _collectLineBottoms(child, origin + offset, bottoms);
    });
  }
}
