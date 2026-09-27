/// Guards that the shell's own chrome is reachable with a D-pad.
///
/// `FocusableCard` made the catalogue reachable (see `tv_focus_navigation_test.dart`
/// and docs/UX_FINDINGS.md, Critical), but the chrome around it was never
/// converted: the now-playing bar was a bare `InkWell`, which is a `Focus` widget
/// only incidentally and draws no indicator, so a remote could land on it with
/// nothing on screen saying where it was. The shell also had no initial focus, so
/// a cold launch started with nothing focused and the first arrow press went
/// wherever traversal happened to look.
///
/// These drive the real widgets through real key events rather than inspecting
/// widget types, because the failure being guarded is behavioural: a control can
/// be a `Focus` node in the tree and still be unreachable, unactivatable, or give
/// no indication that it is the current target.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/playback/now_playing_service.dart';
import 'package:zplay/shell/now_playing_bar.dart';
import 'package:zplay/shell/app_shell.dart';
import 'package:zplay/shell/shell_rail.dart';
import 'package:zplay/widgets/common/focusable_card.dart';
import 'package:zplay/services/layout/device_profile.dart';

/// A television is told by the platform, not by `MediaQuery`.
///
/// This harness used to state `navigationMode: directional` and pass, which is
/// precisely the bug it was written to catch: nothing on Android ever populates
/// that field, so the app shipped the pointer-device chrome to real televisions
/// while the test agreed with itself. [DeviceProfile.debugSetTelevision] sets the
/// same value the native probe sets, so these drive the real path.
Widget _host({required Widget child, required bool television}) {
  DeviceProfile.debugSetTelevision(value: television);
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(1920, 1080)),
      child: Scaffold(body: child),
    ),
  );
}

/// The ring [CardFocusRing] paints, and only that: a 2 px accent border. The
/// tokens' own `hairline` is 1 px, so the width separates the focus indicator
/// from every ordinary border the bar and the rail draw.
Finder _focusRings() => find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).border?.top.width == 2.0,
    );

class _FakeOwner implements NowPlayingCommands {
  final List<String> calls = <String>[];

  @override
  Future<void> togglePlayPause() async => calls.add('togglePlayPause');

  @override
  Future<void> next() async => calls.add('next');

  @override
  Future<void> previous() async => calls.add('previous');

  @override
  Future<void> seek(Duration position) async => calls.add('seek');

  @override
  void openFullPlayer(BuildContext context) => calls.add('openFullPlayer');
}

void main() {
  setUp(() {
    // A TV has no touch and no pointer, so a focus highlight must always be
    // drawn. Under the default `automatic` strategy the app starts in touch
    // mode and a focused control would paint no ring at all.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });

  group('the now-playing bar', () {
    late _FakeOwner owner;

    setUp(() {
      owner = _FakeOwner();
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
    });

    testWidgets('a remote traverses onto it and the centre key opens the player',
        (tester) async {
      // The rail is a sibling here on purpose: it is the control a real remote
      // starts on, so traversal from it has to be able to reach the bar.
      await tester.pumpWidget(_host(
        television: true,
        child: const Stack(
          children: [
            // Full height. The rail is a tall column whose content does not fit a
            // fraction of the viewport, and an overflow is an artefact of the
            // harness, not of the focus behaviour under test. The bar is laid
            // over it rather than beside it, so both are laid out and both stay
            // in the tree for traversal to reach.
            Positioned.fill(child: ShellRail(current: ShellSlot.home, onSelect: _ignore)),
            Positioned(bottom: 0, left: 0, right: 0, child: NowPlayingBar()),
          ],
        ),
      ));
      await tester.pump();
      expect(owner.calls, isEmpty, reason: 'nothing on the rail is the bar');

      // Walk the traversal rather than assuming a step count: how many rows the
      // rail contributes, and in what order Flutter visits them, is a framework
      // detail. What is guarded is that the bar is REACHABLE and that it
      // ACTIVATES on the remote's centre key.
      await tester.tap(find.byType(FocusableCard).first, warnIfMissed: false);
      await tester.pump();

      var activated = false;
      for (var i = 0; i < 12 && !activated; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        activated = owner.calls.contains('openFullPlayer');
      }

      expect(activated, isTrue,
          reason: 'the bar must be reachable by traversal and activate on the '
              'remote centre key; recorded calls were ${owner.calls}');
    });

    testWidgets('a focused bar draws the ring an InkWell never drew',
        (tester) async {
      // A focusable sibling to move away from, so the bar gets focus the way a
      // remote gives it rather than by reaching into the card's own node.
      await tester.pumpWidget(_host(
        television: true,
        child: const Column(
          children: [
            Focus(child: SizedBox(height: 60)),
            Expanded(child: NowPlayingBar()),
          ],
        ),
      ));
      await tester.pump();

      expect(_focusRings(), findsNothing,
          reason: 'an unfocused bar must not paint a focus ring');

      // Walk until the ring appears rather than assuming the bar is one step
      // away: it comes after the bar's own transport controls in traversal order.
      var rang = false;
      for (var i = 0; i < 12 && !rang; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        rang = _focusRings().evaluate().isNotEmpty;
      }

      expect(rang, isTrue,
          reason: 'a focused bar with no visible ring is unusable on a TV');
    });

    testWidgets('its transport controls are focusable too', (tester) async {
      await tester.pumpWidget(_host(
        television: true,
        child: const NowPlayingBar(),
      ));
      await tester.pump();

      // The bar plus three transports. A skip button left on a raw InkWell is
      // focusable but silent, which is the same defect one level down.
      expect(find.byType(FocusableCard), findsNWidgets(4));
      expect(find.byType(InkWell), findsNothing,
          reason: 'no control in the bar may be a bare InkWell');
    });
  });

  group('the shell rail', () {
    testWidgets('autofocus gives a television a starting focus', (tester) async {
      await tester.pumpWidget(_host(
        television: true,
        child: ShellRail(
          current: ShellSlot.home,
          onSelect: (_) {},
          autofocus: true,
        ),
      ));
      await tester.pump();

      expect(
        FocusManager.instance.primaryFocus,
        isNot(FocusManager.instance.rootScope),
        reason: 'a cold launch on a TV must not start with nothing focused',
      );
      expect(_focusRings(), findsWidgets,
          reason: 'the starting focus has to be visible, or the user cannot '
              'tell where the remote is');
    });

    testWidgets('a desktop rail does not claim focus nobody asked for',
        (tester) async {
      await tester.pumpWidget(_host(
        television: false,
        child: ShellRail(current: ShellSlot.home, onSelect: (_) {}),
      ));
      await tester.pump();

      // The real guarantee is that nothing is RINGED, not which scope happens to
      // hold focus: MaterialApp places focus on its own ModalScope on desktop, so
      // asserting on the root scope would be testing a framework detail.
      expect(_focusRings(), findsNothing,
          reason: 'a mouse-driven desktop must not open on a ringed row');
    });
  });
}

void _ignore(ShellSlot slot) {}
