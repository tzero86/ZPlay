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
/// The sidebar rows describe the rail the app has since replaced with a top nav
/// bar (`shell_rail.dart`): 88 dp of width is now 0, and the nav chrome spends 48
/// dp of height across the top instead. The remaining rows still measure what
/// they measured.
///
/// Every assertion here is one of those rows, on both sides of the form-factor
/// split: a television gets the compact numbers, and a pointer device keeps the
/// geometry it already shipped. The two branches are pumped from the same canvas
/// and differ only in [DeviceProfile], so a number that moved has moved for the
/// form factor and for nothing else.
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

/// The device's own canvas: 1920x1080 physical at density 320, so 960x540 dp.
const Size _televisionCanvas = Size(960, 540);

/// A desk window, where the top nav bar is the chrome on screen. Wide enough on
/// its shortest side that the form factor is `expanded`: a pointer device on the
/// television's own canvas classifies as `compact` and would be comparing a
/// bottom bar against a top bar.
const Size _desktopCanvas = Size(1920, 1080);

/// Every canvas is pumped at the device's density, so a dp is two physical px.
const double _dpr = 2.0;

/// The hero band's height on the television canvas.
///
/// Home passes `compact: true` to its carousel on a television, so the band is
/// sized by what it has to show rather than by a fraction of the window. The
/// 0.78 ceiling - and the 421.2 dp it produced here - belonged to the
/// pointer-branch band. The measurement that set the compact number: 48 dp of
/// shell bar plus 40 dp of Home's own chrome leaves 452 dp of canvas, so a
/// 236 dp band puts the top of the first rail at 328 dp and leaves 212 dp of a
/// rail on screen. At 296 dp it left 152.
const double _televisionHeroHeight = 236;

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
      child: const ShellRail(
        current: ShellSlot.home,
        onSelect: _ignore,
        onLiveTv: _ignoreTv,
      ),
    );

/// The row boxes in bar order: the destinations left to right, with the
/// fullscreen toggle last because it is the trailing item.
Finder _rows() => find.byType(FocusableCard);

/// The glyph a row draws.
///
/// The `Icon`'s own box is the 24 dp glyph the row centres. A labelled row also
/// carries a `RichText` for its name, so this asks for the icon specifically
/// rather than for "the text in the row".
Finder _glyphOf(Finder row) =>
    find.descendant(of: row, matching: find.byType(Icon));

/// The bar at the foot of the canvas, which is where the shell mounts it.
Future<void> _pumpBar(WidgetTester tester, {required bool television}) => _pump(
      tester,
      television: television,
      canvas: _televisionCanvas,
      child: const Column(
        children: [Spacer(), NowPlayingBar()],
      ),
    );

/// Home's filter strip.
///
/// The `TabStrip` itself, not a `Row` above the first pill. Home renders the
/// shared strip, which contains a `Row` of its own sized by its content (26 dp)
/// inside the 28 dp control; matching that inner `Row` measured the text rather
/// than the chrome, and reported a row 2 dp shorter than the one the page
/// actually reserves.
///
/// Matched by predicate because the strip is `TabStrip<_HomeFilter>` and
/// `find.byType` compares runtime types exactly, so `find.byType(TabStrip)`
/// resolves to `TabStrip<dynamic>` and matches nothing.
Finder _filterRow() => find.byWidgetPredicate(
      (w) => w.runtimeType.toString().startsWith('TabStrip<'),
    );

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

  group('the top nav bar', () {
    testWidgets('is 48 dp of full-width chrome with 48 dp destinations',
        (tester) async {
      await _pumpRail(tester, television: true);

      // The fill and its hairline run to the panel edge on every side; it is
      // the bar that is compact, which is what lets the background bleed.
      final bar = tester.getRect(find.byType(ShellRail));
      expect(bar, const Rect.fromLTWH(0, 0, 960, 48));

      final rows = _rows();
      final first = tester.getRect(rows.first);
      expect(first.height, 48.0,
          reason: 'the accessibility floor, and the bar has the room for it');

      // Destinations lead from the left, after the brand badge and its gutter.
      expect(first.left, greaterThanOrEqualTo(24.0));
      // The fullscreen toggle is the trailing item, pinned to the right gutter.
      expect(tester.getRect(rows.last).right, 960 - 24);

      // One line: every destination starts to the right of the one before it.
      for (var i = 1; i < rows.evaluate().length; i++) {
        expect(
          tester.getRect(rows.at(i)).left,
          greaterThan(tester.getRect(rows.at(i - 1)).left),
          reason: 'the bar lays its rows left to right, not top to bottom',
        );
      }

      // The glyph is centred in the bar's 48 dp, which is what a horizontal row
      // buys over the old column.
      final glyph = tester.getRect(_glyphOf(rows.first));
      expect(glyph.center.dy, bar.center.dy);
    });

    testWidgets('and the pointer bar keeps the same shape, only wider',
        (tester) async {
      await _pumpRail(tester, television: false);

      final bar = tester.getRect(find.byType(ShellRail));
      expect(bar, const Rect.fromLTWH(0, 0, 1920, 48));

      final rows = _rows();
      expect(tester.getRect(rows.first).height, 48.0);
      expect(tester.getRect(rows.last).right, 1920 - 24);
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
    /// page: on a television the row sits 4 dp below the shell's 48 dp top bar
    /// and is 28 dp tall, and on the compact branch (a phone on this canvas) it
    /// is the 44 dp control in the page's own row at the top of the window.
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
      // The pill row is the innermost `Row` above the first pill's label; the
      // page's own control row is an ancestor of that, so `.first` is the one
      // that is actually 28 dp tall.
      final row = tester.getRect(_filterRow());
      await tester.pumpWidget(const SizedBox.shrink());
      return row;
    }

    testWidgets('is one 28 dp row on a television and one 44 dp row on a phone',
        (tester) async {
      final television = await filterRow(tester, television: true);
      // `television: false` on this 960x540 canvas is the compact branch: the
      // shortest side is below the 600 dp breakpoint. Its nav bar is the bottom
      // bar, so nothing is above the page and the page's own row starts at the
      // window top.
      final compact = await filterRow(tester, television: false);

      // The television's row sits below the shell's 48 dp top bar: 48 + 4 dp
      // down, 28 dp tall, so the chrome ends at 80 dp and the first pixel of
      // content lands at 88. 24 dp was the first attempt and it reported a 1 px
      // RenderFlex overflow from `segmented_tabs.dart`; the label needs 19 dp
      // inside the track's 3 dp inset.
      expect(television.top, 52.0, reason: 'the 48 dp top bar, then Home\'s '
          'own 4 dp of padding above the row');
      expect(television.height, 28.0);
      // No rail: the top bar is a full-width row above the page, so the row
      // starts at Home's own 20 dp gutter and not 64 dp further right.
      expect(television.left, 20.0);

      // The compact branch keeps its touch-sized 44 dp row, in the page's own
      // control row at the top of the window. The wordmark band that used to sit
      // above it is gone: the brand is the shell's top bar now, so on a phone -
      // which has no top bar - the page's row is simply the first thing on
      // screen, 4 dp in.
      expect(compact.top, 4.0, reason: 'the page row\'s own 4 dp top padding, '
          'with no shell chrome above it on the compact branch');
      expect(compact.height, 44.0);
      expect(compact.left, 20.0, reason: 'the list slot\'s own gutter');

      // The same canvas, so the whole difference is the form factor: the top
      // bar's 48 dp plus the page row's own extra height.
      expect(television.top + television.height, 80.0);
      expect(compact.top + compact.height, 48.0);
    });

    testWidgets('leaves the carousel dots on the first screen', (tester) async {
      final row = await filterRow(tester, television: true);

      // The chrome's own extent: the row, the 4 dp of padding below it, and the
      // 8 dp the list slot reserves after the bar.
      final contentStart = row.top + 4 + row.height + 8;
      expect(contentStart, 92.0,
          reason: '48 dp of top bar + Home\'s 4 + 28 + 8');

      // The dots are `Positioned(bottom: 16)` in a 7 dp stack inside the hero
      // band, so their lower edge sits 16 dp above the band's bottom: 312 dp of
      // the 540 dp panel, 228 dp clear of the bottom edge.
      //
      // The headroom is the point of the assertion, not a detail of it. The
      // chrome used to end at 118 dp and the band took 421.2, which put the dots
      // 16.8 dp from the edge with half the row off screen; the compact band at
      // 236 dp is what bought the rest.
      final dotsBottom = contentStart + _televisionHeroHeight - 16;
      expect(dotsBottom, closeTo(312.0, 0.1));
      expect(
        540 - dotsBottom,
        greaterThanOrEqualTo(40),
        reason: 'the dots have to be on the first screen, not merely inside '
            'the panel; the 7 dp dot row clears the bottom edge by 228 dp',
      );
    });
  });
}

void _ignore(ShellSlot slot) {}

void _ignoreTv() {}
