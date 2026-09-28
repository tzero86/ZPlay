/// Guards the ten-foot chrome's density against the measurement that set it.
///
/// The user's complaint was that the app spends screen on chrome where the
/// reference app spends it on content, and the numbers came from Stremio launched
/// on the same Chromecast with Google TV at the same 1920x1080 / density 320 (so
/// 960x540 dp at DPR 2, and physical pixels are logical ones times two):
///
/// | | Stremio | ours before |
/// |:--|:--|:--|
/// | sidebar width | ~67 dp | 88 dp |
/// | sidebar glyph | ~22 dp | 32 dp |
/// | sidebar pitch | ~53 dp | 72 dp |
/// | top chrome | none, content at the top | ~118 dp to the first pixel of content |
/// | filter row | ~23 dp of inline text | 44 dp of pills |
///
/// Every assertion here is one of those rows, on both sides of the form-factor
/// split: a television gets the compact numbers, and a pointer device keeps the
/// geometry it already shipped, byte for byte. The two branches are pumped from
/// the same canvas and differ only in [DeviceProfile], so a number that moved has
/// moved for the form factor and for nothing else.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/services/playback/now_playing_service.dart';
import 'package:zplay/shell/app_shell.dart';
import 'package:zplay/shell/now_playing_bar.dart';
import 'package:zplay/shell/shell_rail.dart';
import 'package:zplay/widgets/common/focusable_card.dart';
import 'package:zplay/widgets/common/segmented_tabs.dart';

/// The device's own canvas: 1920x1080 physical at density 320, so 960x540 dp.
const Size _televisionCanvas = Size(960, 540);

/// A desk window, where the side rail is the chrome on screen. Wide enough on its
/// shortest side that the form factor is `expanded`: a pointer device on the
/// television's own canvas classifies as `compact` and would be comparing a
/// bottom bar against a rail.
const Size _desktopCanvas = Size(1920, 1080);

/// Every canvas is pumped at the device's density, so a dp is two physical px.
const double _dpr = 2.0;

/// The hero band's height on the television canvas.
///
/// Mirrored from `test/pages/home_hero_height_test.dart`, which pins it: the band
/// takes its 0.78 ceiling of a 540 dp window because the immersive floor is
/// larger than the window. It is here rather than imported because the function
/// is private to the page, and the arithmetic below needs the number the page
/// actually produces.
const double _televisionHeroHeight = 421.2;

Future<void> _pump(
  WidgetTester tester, {
  required bool television,
  required Size canvas,
  required Widget child,
}) async {
  DeviceProfile.debugSetTelevision(value: television);
  tester.view.devicePixelRatio = _dpr;
  tester.view.physicalSize = canvas * _dpr;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: canvas),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpRail(WidgetTester tester, {required bool television}) => _pump(
      tester,
      television: television,
      canvas: television ? _televisionCanvas : _desktopCanvas,
      child: const ShellRail(current: ShellSlot.home, onSelect: _ignore),
    );

/// The row boxes in rail order: the four leading slots, then the fullscreen
/// toggle and Settings at the foot.
Finder _rows() => find.byType(FocusableCard);

/// The glyph a row draws.
///
/// The `Icon` widget's own box is the whole row box once the row's constraints
/// tighten it, so the thing worth measuring for "centred in the rail" is the text
/// it paints.
Finder _glyphOf(Finder row) =>
    find.descendant(of: row, matching: find.byType(RichText));

/// The bar at the foot of the canvas, which is where the shell mounts it.
Future<void> _pumpBar(WidgetTester tester, {required bool television}) => _pump(
      tester,
      television: television,
      canvas: _televisionCanvas,
      child: const Column(
        children: [Spacer(), NowPlayingBar()],
      ),
    );

/// Home's filter row.
///
/// A predicate rather than `find.byType`, because the control is generic
/// (`SegmentedTabs<_HomeFilter>`) and `byType` compares runtime types exactly.
/// It is also the only segmented control in the shell tree, which is what makes
/// "the filter row" unambiguous here.
Finder _filterRow() => find.byWidgetPredicate((w) => w is SegmentedTabs);

class _FakeOwner implements NowPlayingCommands {
  @override
  Future<void> next() async {}

  @override
  Future<void> previous() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> togglePlayPause() async {}

  @override
  void openFullPlayer(BuildContext context) {}
}

void main() {
  final owner = _FakeOwner();

  setUp(() {
    NowPlayingService.register(owner);
    NowPlayingService.publish(
      const NowPlayingSnapshot(
        kind: NowPlayingKind.music,
        title: 'Probe Track',
        subtitle: 'Probe Artist',
        isPlaying: true,
        position: Duration(seconds: 30),
        duration: Duration(minutes: 3),
        canPrevious: true,
        canNext: true,
      ),
    );
  });

  tearDown(() {
    NowPlayingService.publish(null);
    NowPlayingService.unregister(owner);
    DeviceProfile.debugSetTelevision(value: false);
  });

  group('the ten-foot rail', () {
    testWidgets('is 64 dp wide, a 40 dp row box and 24 dp glyphs on a 52 dp pitch',
        (tester) async {
      await _pumpRail(tester, television: true);

      // The fill and its hairline still run to the panel edge on every side; it
      // is the rows that are compact, which is what lets the background bleed.
      final rail = tester.getRect(find.byType(ShellRail));
      expect(rail, const Rect.fromLTWH(0, 0, 64, 540));

      final rows = _rows();
      final first = tester.getRect(rows.first);
      expect(first.left, 12.0, reason: 'the rail gutter');
      expect(first.width, 40.0, reason: '64 less two 12 dp gutters');
      expect(first.height, 48.0, reason: 'the accessibility floor, not 64');

      // Centred in the rail, which is what a 12 dp gutter either side buys.
      final glyph = tester.getRect(_glyphOf(rows.first));
      expect(glyph.center.dx, rail.center.dx);

      expect(
        tester.getRect(rows.at(1)).top - first.top,
        52.0,
        reason: 'a 48 dp row plus a 4 dp gap, against the reference app\'s '
            '~53 dp pitch and the 72 dp it was',
      );
      expect(
        tester.getRect(rows.last).bottom,
        540 - 16,
        reason: 'Settings is pinned to the foot, above the rail gutter',
      );
    });

    testWidgets('and the pointer rail keeps every number it had',
        (tester) async {
      await _pumpRail(tester, television: false);

      final rail = tester.getRect(find.byType(ShellRail));
      expect(rail, const Rect.fromLTWH(0, 0, 88, 1080));

      final rows = _rows();
      expect(tester.getRect(rows.first).left, 8.0);
      expect(tester.getRect(rows.first).height, 44.0);
      expect(
        tester.getRect(rows.at(1)).top - tester.getRect(rows.first).top,
        48.0,
        reason: '44 dp row plus the 4 dp gap',
      );
      expect(tester.getRect(rows.last).bottom, 1080 - 8);
    });
  });

  group('the now-playing strip', () {
    testWidgets('is not inset differently on either form factor', (tester) async {
      // It briefly carried a 5% margin on its right and bottom edges; the margin
      // is gone and this pins that the strip is back to one padding for both.
      for (final television in <bool>[true, false]) {
        await _pumpBar(tester, television: television);
        final next = find.byType(FocusableCard).last;
        expect(tester.getRect(next).right, 960 - 12);
        expect(
          tester.getRect(
            find.ancestor(of: next, matching: find.byType(Row)).first,
          ).bottom,
          540 - 8,
        );
      }
    });
  });

  group('the home top chrome', () {
    /// Pumps the real shell and reads Home's filter row, which is the control the
    /// user was pointing at.
    ///
    /// The row is measured rather than the bar, because the bar is private to the
    /// page: on a television the row *is* the whole chrome, with 4 dp above and
    /// below it, and on a pointer device it is the 24 dp of spacing under a
    /// 58 dp wordmark band.
    Future<Rect> filterRow(WidgetTester tester,
        {required bool television}) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      DeviceProfile.debugSetTelevision(value: television);
      tester.view.devicePixelRatio = _dpr;
      tester.view.physicalSize = _televisionCanvas * _dpr;
      await tester.pumpWidget(const MaterialApp(home: AppShell()));
      // The cold-start splash holds a 1.8 s timer; let it fire rather than leave
      // the harness with a pending timer when the tree comes down.
      await tester.pump(const Duration(seconds: 2));
      // `byType` compares runtime types exactly, and this one is generic
      // (`SegmentedTabs<_HomeFilter>`), so the predicate is the way in.
      final row = tester.getRect(_filterRow());
      await tester.pumpWidget(const SizedBox.shrink());
      return row;
    }

    testWidgets('is one 28 dp row where a pointer device has a 44 dp row under '
        'a wordmark band', (tester) async {
      final television = await filterRow(tester, television: true);
      final pointer = await filterRow(tester, television: false);

      // The television's row sits inside the bar: 4 dp down, 28 dp tall, so the
      // chrome ends at 36 dp and the first pixel of content lands at 44. 24 dp
      // was the first attempt and it reported a 1 px RenderFlex overflow from
      // `segmented_tabs.dart`; the label needs 19 dp inside the track's 3 dp
      // inset.
      expect(television.top, 4.0);
      expect(television.height, 28.0);
      // The rail's 64 dp, then the bar's own 20 dp gutter. The pointer branch has
      // no rail at this canvas size, so its row starts at the window edge.
      expect(television.left, 64.0 + 20);

      // A pointer device keeps the wordmark band and the 44 dp control below it.
      expect(pointer.top, 70.0, reason: '8 dp of bar padding + 34 dp of logo '
          '+ 16 dp of bar padding, then the list slot\'s 12 dp');
      expect(pointer.height, 44.0);
      expect(pointer.left, 20.0, reason: 'the list slot\'s own gutter');

      // The same canvas, so the whole difference is the form factor: the second
      // control row a television no longer pays for is 44 dp of it.
      expect(television.top + television.height, 32.0);
      expect(pointer.top + pointer.height, 114.0);
    });

    testWidgets('leaves the carousel dots on the first screen', (tester) async {
      final row = await filterRow(tester, television: true);

      // The chrome's own extent: the row, the 4 dp of padding below it, and the
      // 8 dp the list slot reserves after the bar.
      final contentStart = row.top + 4 + row.height + 8;
      expect(contentStart, 44.0);

      // The dots are `Positioned(bottom: 16)` in a 7 dp stack inside the hero
      // band, so their lower edge is 16 dp above the band's bottom: 449.2 dp of
      // the 540 dp panel, 90.8 dp clear of the bottom edge. Before the chrome
      // was cut the first pixel of content sat at 118 dp and the same sum landed
      // at 523.2 - 16.8 dp from the edge, with half the dot row already off the
      // screen.
      final dotsBottom = contentStart + _televisionHeroHeight - 16;
      expect(dotsBottom, closeTo(449.2, 0.1));
      expect(
        540 - dotsBottom,
        greaterThanOrEqualTo(48),
        reason: 'the dots have to be on the first screen, not just inside the '
            'panel edge',
      );
    });
  });
}

void _ignore(ShellSlot slot) {}
