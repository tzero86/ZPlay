/// Guards both dialogs against a body whose fold crosses a line.
///
/// A scroll viewport that stops at an arbitrary height paints the line at its
/// bottom edge half-way: glyph tops and no ellipsis, because a viewport clips
/// instead of eliding. `build/emu_shots/sweep_58_nav6.png` is the first-run P2P
/// advisory with the second engine row title starting about 5 dp above the
/// fold, and `build/emu_shots/sweep_59_nav6.png` is the update dialog's
/// `WHAT'S NEW` box with the ascenders of its eighth line and nothing else. On
/// a television that is what the viewer reads where the content should be.
///
/// The invariant is the same for both: every line of the body's text is either
/// wholly inside the body's viewport or wholly outside it. The test drives the
/// real dialogs at the television canvas rather than a stand-in box, because
/// the fold's height is the product of the header, the footer and the dialog
/// inset as much as of the body.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/updater/app_updater_service.dart';
import 'package:zplay/widgets/common/whole_line_viewport.dart';
import 'package:zplay/widgets/p2p/p2p_warning_dialog.dart';
import 'package:zplay/widgets/updater/update_dialog.dart';

/// A line is either wholly inside the body's viewport or wholly outside it.
/// A line that straddles the fold is the defect: at ten feet the viewer reads
/// half a line of prose instead of the content.
void expectNoLineCrossesTheFold(WidgetTester tester) {
  final fold = tester.getRect(find.byType(SingleChildScrollView));
  final paragraphs = find.descendant(
    of: find.byType(SingleChildScrollView),
    matching: find.byType(Text),
  );
  var lines = 0;
  for (final element in paragraphs.evaluate()) {
    final ro = element.renderObject;
    if (ro is! RenderParagraph) continue;
    final text = ro.text.toPlainText();
    if (text.isEmpty) continue;
    for (final box in ro.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
      boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
    )) {
      // `ui.TextBox` exposes its edges, not a `Rect`.
      final top = ro.localToGlobal(Offset(box.left, box.top)).dy;
      final bottom = ro.localToGlobal(Offset(box.right, box.bottom)).dy;
      lines++;
      final inside = top >= fold.top - 0.5 && bottom <= fold.bottom + 0.5;
      final outside = bottom <= fold.top + 0.5 || top >= fold.bottom - 0.5;
      expect(
        inside || outside,
        isTrue,
        reason:
            'a line of "$text" straddles the fold: painted '
            '${top.toStringAsFixed(1)}..${bottom.toStringAsFixed(1)} against '
            'the edge at ${fold.bottom.toStringAsFixed(1)}',
      );
    }
  }
  expect(lines, greaterThan(0), reason: 'the probe must have measured something');
}

/// Opens [dialog] the way the app opens it, at the television canvas.
///
/// A `Dialog` is a route with its own inset and minimum width, so pumping it as
/// `home` hands it an unbounded width and it overflows horizontally at every
/// size - a harness artefact already documented in `p2p_dialog_overflow_test`,
/// and one that would make this probe measure a layout the device never has.
///
/// The frames are pumped without advancing the clock, which is that same file's
/// convention, and the entrance animation is therefore not run to completion.
/// A settled route re-styles its action buttons with the theme's label style,
/// and under the test font - whose glyph advance is one em, about twice a real
/// font's - those labels grow past the footer's width. That overflow is real in
/// the test font, present before this fix as well, and nothing to do with the
/// fold the probe measures; letting it fire would only make the probe fail on a
/// defect it is not looking for.
Future<void> _pumpTelevision(WidgetTester tester, WidgetBuilder dialog) async {
  // The reported device: 1920x1080 at density 320 is 960x540 dp.
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () =>
                  showDialog<void>(context: context, builder: dialog),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // One frame to lay the route out, one for the body's post-frame measurement
  // to be applied, and two more so a measurement that is not stable would show
  // up here as a fold that keeps moving.
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

/// A release body long enough to overflow the changelog box many times over:
/// the box is 180 dp with 16 dp of padding, the body text sets at a 20 dp
/// pitch, so the inner viewport holds seven whole lines and the eighth is the
/// one the screenshot caught with its ascenders only.
String _longReleaseNotes() {
  final buffer = StringBuffer('ZPlay 1.5.0\n\n');
  for (var i = 1; i <= 12; i++) {
    buffer.writeln(
      '- Change $i: restored the download strip in the player controls so the '
      'published line stays readable end to end.',
    );
  }
  buffer.writeln('\n<!-- zplay:changelog-end -->\n');
  buffer.writeln('This trailer is dropped by the service before display.');
  return buffer.toString();
}

UpdateInfo _updateInfo() => UpdateInfo(
  currentVersion: '1.4.2',
  latestVersion: '1.5.0',
  downloadUrl: 'https://example.invalid/zplay-1.5.0.apk',
  releaseNotes: _longReleaseNotes(),
  publishedAt: DateTime(2026, 10, 1),
  isMacOS: false,
);

/// The probe text's style. It sets no leading (`height: 1.0`) on purpose: with
/// leading, the first and last line boxes lose their outer half to
/// `includeLineSpacingMiddle`, so the boundary grid starts below the
/// paragraph's top and a snapped viewport is a multiple of the line height
/// *plus* that offset. Without leading the boxes tile from the paragraph's own
/// top, which is what lets the test name the boundary it expects instead of
/// reading it off the render object first.
const TextStyle _probeStyle = TextStyle(
  fontSize: 16,
  height: 1.0,
  color: Color(0xFF000000),
);

String _probeText(int lines) =>
    List<String>.generate(lines, (i) => 'line ${i + 1}').join('\n');

Widget _probeBody(int lines) => SingleChildScrollView(
  child: Text(_probeText(lines), style: _probeStyle),
);

/// The distance between two consecutive lines of the probe text, measured from
/// its own line boxes so the expectation cannot drift from the font.
double _linePitch(WidgetTester tester) {
  final ro = tester.renderObject<RenderParagraph>(
    find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.byType(Text),
    ),
  );
  final text = ro.text.toPlainText();
  final boxes = List<ui.TextBox>.of(
    ro.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
      boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
    ),
  )..sort((a, b) => a.top.compareTo(b.top));
  expect(boxes.length, greaterThan(1));
  return boxes[1].top - boxes[0].top;
}

Future<void> _pumpProbe(WidgetTester tester, Widget box) async {
  await tester.pumpWidget(MaterialApp(home: Center(child: box)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the P2P advisory body ends on a whole line on a television', (
    tester,
  ) async {
    await _pumpTelevision(tester, (_) => const P2pWarningDialog());
    expectNoLineCrossesTheFold(tester);
  });

  testWidgets('the update changelog box ends on a whole line on a television', (
    tester,
  ) async {
    final info = _updateInfo();
    await _pumpTelevision(tester, (_) => UpdateDialog(updateInfo: info));
    expect(find.textContaining('Change 1:'), findsOneWidget);
    expectNoLineCrossesTheFold(tester);
  });

  testWidgets('the viewport ends on a line boundary of an overflowing body', (
    tester,
  ) async {
    // Twelve lines of 16 dp against a 100 dp box: the last whole line ends at
    // 96, so the fold leaves 4 dp of blank and the seventh line is the first
    // one wholly outside the viewport.
    await _pumpProbe(
      tester,
      SizedBox(
        width: 300,
        height: 100,
        child: WholeLineViewport(child: _probeBody(12)),
      ),
    );
    final pitch = _linePitch(tester);

    final viewport = tester.getSize(find.byType(SingleChildScrollView)).height;
    expect(
      viewport % pitch,
      closeTo(0, 0.01),
      reason: 'a viewport of $viewport against a $pitch pitch does not end on '
          'a line boundary',
    );
    expect(100 - viewport, lessThan(pitch));
    expect(100 - viewport, greaterThanOrEqualTo(0.0));

    // The outer box keeps the parent's height, so a fixed footer below the body
    // does not move when the viewport snaps.
    expect(tester.getSize(find.byType(WholeLineViewport)).height, closeTo(100, 0.01));
    expectNoLineCrossesTheFold(tester);
  });

  testWidgets('a body shorter than its box is left to hug its content', (
    tester,
  ) async {
    // The bound is loose here, not tight: a tight box hides whether the body
    // hugged or was padded out to the parent's height, because the parent
    // forces that height either way.
    await _pumpProbe(
      tester,
      SizedBox(
        width: 300,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: WholeLineViewport(child: _probeBody(3)),
        ),
      ),
    );
    final pitch = _linePitch(tester);

    expect(
      tester.getSize(find.byType(WholeLineViewport)).height,
      closeTo(3 * pitch, 0.01),
      reason: 'a shorter body must not be padded out to the available height',
    );
    expect(
      tester.getSize(find.byType(SingleChildScrollView)).height,
      closeTo(3 * pitch, 0.01),
    );
  });
}
