/// The Library switcher was two 448 dp buttons on a television.
///
/// The band that held the switcher was a `Column` with
/// `CrossAxisAlignment.stretch`, so the control got a *tight* width - the whole
/// page minus the gutters. `SegmentedTabs` has one rule for a tight parent and
/// one for a loose one, and the tight rule is "divide whatever you are given":
/// `trackWidth / options.length`. With two options across 896 dp that is a pair
/// of 448 dp buttons, which is why My List looked like a different app from
/// Browse even after its height had been matched to the rail's. The band is
/// gone now (the switcher is an overlay on the canvas, held loose by an
/// `Align`), so what this guards is that the control stays sized to its labels
/// rather than to whatever width it is handed.
///
/// The height fix and the width fix are one investigation. The height was
/// obvious in a screenshot; the width was the same bug from the other side, and
/// fixing only the height made the page look *worse* - a full-width pair of
/// buttons on a 540 dp screen reads as broken, where a 64 dp one read as merely
/// oversized.
///
/// This drives the real page. An earlier version mounted `SegmentedTabs` in a
/// hand-built tree that reproduced the constraint shape, and it passed with the
/// `Align` removed from the page - so it was testing a copy of the bug rather
/// than the bug, and would have passed against a page that was still wrong.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/pages/library/library_page.dart';
import 'package:zplay/widgets/common/segmented_tabs.dart';

void main() {
  // The 2 GB Chromecast with Google TV: 1920x1080 at DPR 2, so 960x540 dp.
  const tvSize = Size(1920, 1080);

  Future<void> mountOnTelevision(WidgetTester tester) async {
    tester.view.physicalSize = tvSize;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LibraryPage())),
    );
    await tester.pump();
  }

  testWidgets('the switcher is not as wide as the page it sits in', (
    tester,
  ) async {
    await mountOnTelevision(tester);

    final control = tester.getSize(find.byType(SegmentedTabs<LibraryTab>));
    // Measured against the page, not against the band that used to back the
    // switcher. That band was an opaque `DecoratedBox` carrying `tokens.bg` and
    // a hairline, and the redesign removed it - the switcher is an overlay on
    // the canvas now - so `find.byType(DecoratedBox).first` resolved to an
    // unrelated box deeper in the tree and the ratio stopped describing
    // anything. The page's own width is the constraint the control is loose
    // inside, which is the thing this test is actually about.
    final page = tester.getSize(find.byType(LibraryPage));

    // The bug: the control took the whole width, so the two segments were about
    // 448 dp each - the thing that made My List look like another app.
    expect(
      control.width,
      lessThan(page.width * 0.6),
      reason: 'a two-tab switcher sized to its labels is a fraction of the '
          '${page.width} dp page. A full-width track is the reported bug.',
    );
  });


  testWidgets('both labels are shown in full', (tester) async {
    await mountOnTelevision(tester);

    // Scoped to the control: the page underneath has its own "My List" heading,
    // so an unscoped finder matches two and proves nothing about the tab.
    final inSwitcher = find.byType(SegmentedTabs<LibraryTab>);
    expect(
      find.descendant(of: inSwitcher, matching: find.text('My List')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: inSwitcher, matching: find.text('Downloads')),
      findsOneWidget,
    );
    // Neither tab label is shortened. An ellipsised tab is the same failure as
    // the focused filter pill that rendered "Movi...".
    expect(
      find.descendant(of: inSwitcher, matching: find.textContaining('…')),
      findsNothing,
      reason: 'a label shortened inside the track means the track is too narrow',
    );
  });

  testWidgets('the switcher is in proportion with the rail rows beside it', (
    tester,
  ) async {
    await mountOnTelevision(tester);

    // The ten-foot control is 48 dp, matching `ShellRail._televisionRowHeight`.
    // Before this was fixed it was 64, which is a third taller than the rail it
    // sits next to and nearly half again as tall as Home's filter pills.
    final control = tester.getSize(find.byType(SegmentedTabs<LibraryTab>));
    expect(control.height, 48.0);
  });
}
