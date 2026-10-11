/// The Library's switcher rendered `Downloa…` on a television with hundreds of
/// dp of spare row beside it.
///
/// `SegmentedTabs` sizes its segments from the widest label it can measure, so
/// the measurement has to be the one the label is painted with. It was not. The
/// private measurement laid out a bare `TextPainter` over `_labelStyle`, which
/// names metrics and no family, and left it on `TextScaler.noScaling` - while
/// the `Text` that paints the label inherits the theme's family from the
/// ambient `DefaultTextStyle` and scales with the viewer's system font setting.
/// Either difference moves the budget away from the painted width: the segment
/// comes out sized for a face that is not on screen, and a label that is a few
/// dp wider than its own budget loses its tail even though the row it sits in
/// is almost empty.
///
/// A system font scale is the lever this file uses to make that difference real
/// inside a test. The engine's fallback face and the theme's face cannot be
/// separated here - `flutter test` paints every family as the same test font
/// unless one is loaded - but the scale can: `TextScaler.linear(1.4)` is
/// honoured by the painted label and, before the fix, ignored by the
/// measurement. At 1.4 the budget came out as the 1.0 width of the label plus
/// its padding, the label asked for 40% more than that, and both tabs lost
/// their tails exactly as "Downloads" did on the television.
///
/// An earlier draft of this file loaded the shipped Poppins and set it as the
/// theme's family, to reproduce the family half of the defect as well. It was
/// deleted rather than kept: the engine's test face is *wider* than Poppins -
/// 117.9 dp against 74.7 dp for "Downloads" at 13 px - so the un-fixed
/// measurement produced a budget too generous for the painted font and the
/// control never ellipsised. That test passed with and without the fix, which
/// is not a guard. On the device the two faces are the other way round, the
/// platform fallback being narrower than Poppins, and `flutter test` cannot
/// reproduce that direction, so the family half has no unit test: it is covered
/// by the television screenshot the fix was written against
/// (`build/emu_shots/sweep_50_livetv.png`) and by the reasoning in
/// `SegmentedTabs._contentSegmentWidth`. `test/pages/library_switcher_width_test.dart`
/// drives the real page but asserts on the widget tree, and a `Text` whose data
/// is `Downloads` is still `Downloads` while it paints `Downloa…`, so it is no
/// guard for either half.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/widgets/common/segmented_tabs.dart';

void main() {
  // The 2 GB Chromecast with Google TV: 1920x1080 at DPR 2, so 960x540 dp.
  const tvSize = Size(1920, 1080);

  // The two labels the Library ships, which are the pair that failed: two
  // segments are few enough that a shortfall in the budget shows up as a
  // truncated label rather than as a control that merely looks tight.
  const options = <SegmentedTabOption<String>>[
    SegmentedTabOption(value: 'myList', label: 'My List'),
    SegmentedTabOption(value: 'downloads', label: 'Downloads'),
  ];

  /// Mounts the control the way the Library does - loose inside the page, so
  /// the segments come from the label budget rather than from a divided parent.
  ///
  /// The `MediaQuery` is the point of the harness. It sits between the
  /// `Scaffold` and the control, so it is the nearest ancestor of both the
  /// control and its labels: the measurement and the paint resolve the same
  /// scale, which is the invariant the fix restores and the un-fixed
  /// measurement broke by holding `TextScaler.noScaling`. A tighter wrapper
  /// would leave the control measuring under one scale and its label painting
  /// under another, which is the defect restated rather than tested.
  Future<void> mountAtTvScale(
    WidgetTester tester, {
    required double textScale,
  }) async {
    tester.view.physicalSize = tvSize;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: SegmentedTabs<String>(
                options: options,
                selected: 'downloads',
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The rendered paragraph, not the widget: `find.text('Downloads')` matches
  /// the widget whether or not the glyphs that came out read "Downloa…", so
  /// only the render object can answer whether the label fits.
  RenderParagraph paragraphOf(WidgetTester tester, String label) =>
      tester.renderObject<RenderParagraph>(find.text(label));

  testWidgets('both labels fit their segments at a larger system font scale',
      (tester) async {
    await mountAtTvScale(tester, textScale: 1.4);

    expect(
      paragraphOf(tester, 'Downloads').didExceedMaxLines,
      isFalse,
      reason: 'the tab rendered "Downloa…" while the row had hundreds of dp '
          'spare',
    );
    expect(paragraphOf(tester, 'My List').didExceedMaxLines, isFalse);
  });

  testWidgets('sizing to the labels did not make the control full-bleed', (
    tester,
  ) async {
    await mountAtTvScale(tester, textScale: 1.4);

    final control = tester.getSize(find.byType(SegmentedTabs<String>)).width;
    final page = tester.getSize(find.byType(Scaffold)).width;

    // The fix widened the budget to the painted width; it must not have widened
    // it into the parent. A control that took the whole page is the other
    // reported bug - two 448 dp buttons that made My List look like a different
    // app - and `library_switcher_width_test.dart` guards it at scale 1.0. This
    // is the same guard at the scale that exposed the truncation, because the
    // widened budget is where the regression would come from.
    expect(
      control,
      lessThan(page * 0.6),
      reason: 'the control measures its own labels, so two of them are a '
          'fraction of the $page dp page. A full-width track means the '
          'budget grew into the parent instead of into the label.',
    );
  });
}
