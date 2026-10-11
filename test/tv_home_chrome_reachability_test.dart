/// Reachability of Home's own top-chrome row, and what the hero does when the
/// remote leaves it.
///
/// The defects this pins, all from a 960x540 remote-only sweep of the television
/// build:
///
///  * **The calendar glyph could not be focused at all.** DOWN from the nav bar's
///    trailing Fullscreen row skipped the page's own row and landed on a rail's
///    See All; UP from that rail was a dead key. The cause is geometric, and it is
///    the whole reason the shell needs a hand-over: directional traversal
///    considers the candidates that overlap the focused row's own x-band, and a
///    page's top row sits to the *right* of every row in the bar - so the control
///    directly under the bar was not a candidate, while a rail's See All link, a
///    whole header lower, was.
///  * **A 16x3 dp carousel mark was focusable on a television.** UP out of the
///    first rail landed on it: a ring nobody at ten feet can see, on a control the
///    hero's own code means to exclude.
///  * **The hero's action row painted under an unrelated card's expansion.** The
///    first rail is directly beneath the band, so a focused card's panel clipped
///    "More Info" to "e Info" while the hero was not what had focus.
///  * **The bar underlined Browse after a press on Live TV** - a mark reporting a
///    destination the user did not choose.
///  * **The scroll grab-pill covered the rails on a television**, because the
///    pointer-only affordance was gated on the window being wider than 800 dp.
///  * **The media-type chip sat in the last ten dp of the canvas**, inside a
///    television's overscan.
///
/// Everything here drives real D-pad events through the real shell at the
/// television's own canvas and asserts on where focus actually ends up, or on
/// what is actually painted. The harness is the one
/// `tv_dpad_focus_regression_test.dart` established: 1920x1080 physical at DPR 2
/// (a 960x540 dp canvas), `DeviceProfile.debugSetTelevision`,
/// `FocusHighlightStrategy.alwaysTraditional`, a scripted metadata client and a
/// stored addon list - nothing reaches the network.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/addon/addon_manager.dart';
import 'package:zplay/services/home/home_page_settings.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/services/metadata/metadata_service.dart';
import 'package:zplay/services/playback/now_playing_service.dart';
import 'package:zplay/shell/app_shell.dart';
import 'package:zplay/shell/shell_rail.dart';
import 'package:zplay/widgets/common/custom_scroll_track.dart';
import 'package:zplay/widgets/common/focusable_card.dart';

const Size _canvas = Size(960, 540);
const double _dpr = 2.0;
const String _addonHost = 'chrome-probe.test';

/// One addon with one auto-loading `movie` catalog. Every item carries a poster,
/// so `visibleHomeSections` keeps the rails and the page has the See All link and
/// the cards these tests move between.
String _storedAddons() => jsonEncode([
      {
        'baseUrl': 'https://$_addonHost',
        'enabled': true,
        'enableCatalogs': true,
        'enableSearch': true,
        'enableSubtitles': true,
        'enableStreams': true,
        'manifest': {
          'id': 'org.zplay.chromeprobe',
          'name': 'Chrome Probe',
          'version': '1.0.0',
          'resources': ['catalog', 'meta'],
          'types': ['movie'],
          'catalogs': [
            {'type': 'movie', 'id': 'popular', 'name': 'Popular'},
          ],
        },
      }
    ]);

String _catalogBody() => jsonEncode({
      'metas': [
        for (var i = 0; i < 24; i++)
          {
            'id': 'ttchrome${i.toString().padLeft(6, '0')}',
            'name': 'Chrome Title ${i + 1}',
            'type': 'movie',
            'poster': 'https://$_addonHost/poster/$i.jpg',
          }
      ]
    });

class _SilentOwner implements NowPlayingCommands {
  @override
  Future<void> togglePlayPause() async {}

  @override
  Future<void> next() async {}

  @override
  Future<void> previous() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stop() async {}

  @override
  void openFullPlayer(BuildContext context) {}
}

/// The focus node a widget subtree actually installs.
///
/// [Focus.of] answers with the node **above** the widget it is asked about, so a
/// test written with it reports the page's own node for every control on it. The
/// two wrappers below publish the node they own: [FocusableCard] builds a
/// [FocusableActionDetector] whose `focusNode` is the card's, and a bare [Focus]
/// resolves by asking from one of its children.
FocusNode _ownNode(Element widget) {
  FocusNode? found;
  void visit(Element element) {
    if (found != null) return;
    final w = element.widget;
    if (w is FocusableActionDetector) {
      found = w.focusNode;
      return;
    }
    if (w is Focus) {
      var queried = false;
      element.visitChildElements((child) {
        if (queried) return;
        queried = true;
        found = Focus.maybeOf(child, scopeOk: true);
      });
      if (found != null) return;
    }
    element.visitChildElements(visit);
  }

  visit(widget);
  return found!;
}

FocusNode _ownNodeOf(Finder f) => _ownNode(f.evaluate().first);

/// One line worth putting in a failure message: what holds focus, where it is and
/// how big it is. Rects are not decoration here - "focus is on the page's own
/// row" and "focus is on the whole page" are the same widget type, and a
/// traversal failure is invisible without them.
String _describe(FocusNode? node) {
  if (node == null) return '<primaryFocus is null>';
  final rect = node.rect;
  return '${node.debugLabel ?? node.context?.widget.runtimeType}'
      ' at ${rect.left.toStringAsFixed(0)},${rect.top.toStringAsFixed(0)}'
      ' ${rect.width.toStringAsFixed(0)}x${rect.height.toStringAsFixed(0)}';
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await _settle(tester);
}

/// Mounts the whole shell on the television canvas and waits for the cold start
/// (a 1.8 s splash plus the addon rail) to land.
Future<void> _pumpTelevisionShell(WidgetTester tester) async {
  DeviceProfile.debugSetTelevision(value: true);
  tester.view.devicePixelRatio = _dpr;
  tester.view.physicalSize = _canvas * _dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: AppShell()));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(seconds: 3));
}

/// Mounts the shell on a desktop-sized window that is *not* a television, for the
/// one test that has to prove a pointer affordance survived.
Future<void> _pumpDesktopShell(WidgetTester tester) async {
  DeviceProfile.debugSetTelevision(value: false);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1440, 1080);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: AppShell()));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(seconds: 3));
}

Finder _calendar() => find.byTooltip('TV Airing Calendar');
Finder _quiz() => find.byTooltip('AI Taste Quiz');

/// A row of the shell's own bar.
///
/// Scoped to [ShellRail] because the slot pages are all mounted at once and book
/// their labels twice over: Browse draws its own Live TV vertical, so "Live TV"
/// names two controls on two different screens at the same time, and only one of
/// them is the row these tests press.
Finder _barRow(String label) => find.ancestor(
      of: find.descendant(
        of: find.byType(ShellRail),
        matching: find.text(label),
      ),
      matching: find.byType(FocusableCard),
    );

Finder _heroPill(String label) => find
    .ancestor(of: find.text(label), matching: find.byType(FocusableCard))
    .first;

/// Whether the control [control] names is wearing the app's focus ring.
///
/// [CardFocusRing] paints nothing unless it is focused, so a `focused: true` ring
/// in the tree is a control a remote can actually see itself on - which on a
/// television is the only thing that proves a control is reachable.
///
/// The ring is searched both ways round, because the two shapes it is used in
/// differ: a `FocusableCard` builds the ring *inside* itself, while a hand-rolled
/// row wraps the ring *around* a Material button.
bool _ringIsPainted(WidgetTester tester, Finder control) {
  for (final rings in <Finder>[
    find.ancestor(of: control, matching: find.byType(CardFocusRing)),
    find.descendant(of: control, matching: find.byType(CardFocusRing)),
  ]) {
    for (final element in rings.evaluate()) {
      if ((element.widget as CardFocusRing).focused) return true;
    }
  }
  return false;
}

SemanticsNode _semanticsOf(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder);

/// Whether [node] is standing on one of the shell's own bar rows.
bool _inShellRail(FocusNode? node) =>
    node?.context?.findAncestorWidgetOfExactType<ShellRail>() != null;

void main() {
  final owner = _SilentOwner();

  setUp(() async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    MetadataService.client = MockClient((request) async {
      if (request.url.path.contains('/catalog/')) {
        return http.Response(_catalogBody(), 200);
      }
      return http.Response(jsonEncode(<String, Object?>{}), 200);
    });
    MetadataService.clearCache();
    NowPlayingService.register(owner);
    // The rotation would move the slide under the assertions.
    HomePageSettings.heroAutoRotate.value = false;
    // The recommendation rails are local services with nothing configured in a
    // test process; leaving them on only adds network that has to fail.
    HomePageSettings.enableSimilar.value = false;
    HomePageSettings.enableWatchingSimilar.value = false;
    HomePageSettings.enableTraktRecommendations.value = false;
    HomePageSettings.enableSimklRecommendations.value = false;
    AddonManager.readStoredForTesting = () async => _storedAddons();
    await AddonManager.instance.reload();
  });

  tearDown(() {
    NowPlayingService.unregister(owner);
    HomePageSettings.heroAutoRotate.value = true;
    HomePageSettings.enableSimilar.value = true;
    HomePageSettings.enableWatchingSimilar.value = true;
    HomePageSettings.enableTraktRecommendations.value = true;
    HomePageSettings.enableSimklRecommendations.value = true;
    HomePageSettings.enableAiQuiz.value = true;
    HomePageSettings.enableCalendar.value = true;
    MetadataService.client = http.Client();
    MetadataService.clearCache();
    AddonManager.readStoredForTesting = null;
    DeviceProfile.debugSetTelevision(value: false);
  });

  group('Home: the page\'s own top row is reachable with a remote', () {
    testWidgets('DOWN out of the bar\'s fullscreen row reaches the calendar',
        (tester) async {
      // The state the sweep was in: one lone unlabelled glyph on the right.
      HomePageSettings.enableAiQuiz.value = false;
      await _pumpTelevisionShell(tester);

      final calendar = _calendar();
      expect(calendar, findsOneWidget,
          reason: 'precondition: the page shows its calendar action');
      final calendarNode = _ownNodeOf(calendar);
      debugPrint('[C3] calendar: ${_describe(calendarNode)}');

      final fullscreen = _barRow('Fullscreen');
      expect(fullscreen, findsOneWidget,
          reason: 'precondition: the bar has its fullscreen row');
      _ownNodeOf(fullscreen).requestFocus();
      await tester.pump();
      debugPrint('[C3] start: ${_describe(FocusManager.instance.primaryFocus)}');

      await _press(tester, LogicalKeyboardKey.arrowDown);
      final landed = FocusManager.instance.primaryFocus;
      debugPrint('[C3] DOWN -> ${_describe(landed)}');
      expect(
        landed,
        same(calendarNode),
        reason: 'DOWN from the bar\'s trailing row must reach the control in '
            'that column - the calendar. It ended on ${_describe(landed)}.',
      );
      expect(_ringIsPainted(tester, calendar), isTrue,
          reason: 'a control the remote stands on has to show it: the app\'s '
              'ring is CardFocusRing and nothing else paints one here');

      // And back: the bar's row is above it, so UP has to return there.
      await _press(tester, LogicalKeyboardKey.arrowUp);
      final back = FocusManager.instance.primaryFocus;
      debugPrint('[C3] UP -> ${_describe(back)}');
      expect(
        _ringIsPainted(tester, fullscreen),
        isTrue,
        reason: 'UP from the calendar must put the ring back on the bar. It '
            'ended on ${_describe(back)}.',
      );
    });

    testWidgets('DOWN out of the bar enters the row, and RIGHT walks it',
        (tester) async {
      await _pumpTelevisionShell(tester);

      final quiz = _quiz();
      final calendar = _calendar();
      expect(quiz, findsOneWidget, reason: 'precondition: the quiz is on');
      expect(calendar, findsOneWidget, reason: 'precondition: the calendar is on');
      final calendarNode = _ownNodeOf(calendar);

      _ownNodeOf(_barRow('Fullscreen')).requestFocus();
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.arrowDown);
      final entered = FocusManager.instance.primaryFocus;
      debugPrint('[C3] DOWN (both on) -> ${_describe(entered)}');
      expect(
        _ringIsPainted(tester, quiz) || _ringIsPainted(tester, calendar),
        isTrue,
        reason: 'DOWN from the bar must enter the page\'s own row. It ended on '
            '${_describe(entered)}.',
      );

      // One press to the side, and the other action in the same row is reached -
      // which is what makes the row a row rather than two separate targets.
      await _press(tester, LogicalKeyboardKey.arrowRight);
      final walked = FocusManager.instance.primaryFocus;
      debugPrint('[C3] RIGHT -> ${_describe(walked)}');
      expect(
        walked,
        anyOf(same(calendarNode), isNot(same(entered))),
        reason: 'RIGHT must walk along the page\'s own row. It ended on '
            '${_describe(walked)}.',
      );
    });

    testWidgets('UP out of the rail is never a dead key, and the bar is where '
        'the rail reaches it', (tester) async {
      await _pumpTelevisionShell(tester);

      // The press the sweep found dead: UP from the first rail's See All. What
      // it did was land on the hero's carousel marks - four 16x3 dp dashes that
      // were focusable on a television despite saying they were not - so it
      // moved the ring to something no one at ten feet can see. Both halves are
      // pinned here: the key must move, and where it moves must be a control.
      final seeAll = find.ancestor(
        of: find.text('See All'),
        matching: find.byType(FocusableCard),
      );
      expect(seeAll, findsWidgets,
          reason: 'precondition: the page has a rail with a See All link');
      _ownNode(seeAll.evaluate().first).requestFocus();
      await tester.pump();
      final from = FocusManager.instance.primaryFocus;
      debugPrint('[C3] start (See All): ${_describe(from)}');

      await _press(tester, LogicalKeyboardKey.arrowUp);
      final up = FocusManager.instance.primaryFocus;
      debugPrint('[C3] UP from See All -> ${_describe(up)}');
      expect(up, isNot(same(from)),
          reason: 'UP out of the rail must move focus: the sweep found it a '
              'dead key');
      expect(up!.rect.height, greaterThanOrEqualTo(24),
          reason: 'UP landed on ${_describe(up)} - a focus target too small to '
              'carry a ring anyone can see, which is what the hero\'s carousel '
              'marks are');

      // And from the hero the bar is one press up: that is the path the rail
      // takes to the page's own row, and its first half.
      _ownNodeOf(_heroPill('Play')).requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.arrowUp);
      final toBar = FocusManager.instance.primaryFocus;
      debugPrint('[C3] UP from the hero -> ${_describe(toBar)}');
      expect(
        _inShellRail(toBar),
        isTrue,
        reason: 'UP out of the hero must reach the shell\'s own bar, which is '
            'how a remote gets from the rail to the calendar: it ended on '
            '${_describe(toBar)}',
      );
    });

    testWidgets('the whole way round: a rail \'s See All to the calendar and '
        'back', (tester) async {
      // The acceptance this exists for is the whole loop, not its halves: a
      // remote that can reach the calendar only by starting on the bar has not
      // been given the control back. This walks it the way a user would - rail,
      // up through the page, along the bar, and down into the page's own row -
      // and then back out again.
      HomePageSettings.enableAiQuiz.value = false;
      await _pumpTelevisionShell(tester);

      final seeAll = find.ancestor(
        of: find.text('See All'),
        matching: find.byType(FocusableCard),
      );
      expect(seeAll, findsWidgets,
          reason: 'precondition: the page has a rail with a See All link');
      _ownNode(seeAll.evaluate().first).requestFocus();
      await tester.pump();
      debugPrint('[C3] loop start: '
          '${_describe(FocusManager.instance.primaryFocus)}');

      // Up out of the rail to the hero, and out of the hero to the bar.
      await _press(tester, LogicalKeyboardKey.arrowUp);
      final hero = FocusManager.instance.primaryFocus;
      debugPrint('[C3] loop 1 (hero): ${_describe(hero)}');
      await _press(tester, LogicalKeyboardKey.arrowUp);
      final bar = FocusManager.instance.primaryFocus;
      debugPrint('[C3] loop 2 (bar): ${_describe(bar)}');
      expect(_inShellRail(bar), isTrue,
          reason: 'the way up out of the page has to end on the shell\'s bar: '
              'it ended on ${_describe(bar)}');

      // Along the bar to the row the calendar sits under, which is where the
      // page's own row is in this column.
      final fullscreen = _ownNodeOf(_barRow('Fullscreen'));
      var presses = 0;
      while (!identical(FocusManager.instance.primaryFocus, fullscreen) &&
          presses < 8) {
        await _press(tester, LogicalKeyboardKey.arrowRight);
        presses++;
        expect(_inShellRail(FocusManager.instance.primaryFocus), isTrue,
            reason: 'RIGHT has to stay on the bar while walking to its '
                'trailing row; press $presses ended on '
                '${_describe(FocusManager.instance.primaryFocus)}');
      }
      expect(identical(FocusManager.instance.primaryFocus, fullscreen), isTrue,
          reason: 'RIGHT eight times must reach the bar\'s fullscreen row');

      // And down into the calendar, which is the control the sweep could not
      // reach at all.
      await _press(tester, LogicalKeyboardKey.arrowDown);
      final calendar = FocusManager.instance.primaryFocus;
      debugPrint('[C3] loop 3 (calendar): ${_describe(calendar)}');
      expect(identical(calendar, _ownNodeOf(_calendar())), isTrue,
          reason: 'the calendar must be reachable from the rail the long way '
              'round too: it ended on ${_describe(calendar)}');
      expect(_ringIsPainted(tester, _calendar()), isTrue);

      // And back out: up to the bar, and down into the page again - which for
      // this column is the calendar, because that is the control the bar's row
      // sits over.
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(_inShellRail(FocusManager.instance.primaryFocus), isTrue,
          reason: 'UP from the calendar returns to the bar');
      await _press(tester, LogicalKeyboardKey.arrowDown);
      final content = FocusManager.instance.primaryFocus;
      debugPrint('[C3] loop 4 (back into the page): ${_describe(content)}');
      expect(_inShellRail(content), isFalse,
          reason: 'and DOWN leaves the bar for the page again: it ended on '
              '${_describe(content)}');
    });

    testWidgets('the hand-over never reaches the page that is not on screen',
        (tester) async {
      await _pumpTelevisionShell(tester);

      // Home is still mounted - the shell keeps all five slots alive - so its
      // calendar node still exists and is still published to the bar. What must
      // stop the bar using it is the shell's own `ExcludeFocus`, which leaves
      // every node in a hidden slot unable to take focus.
      final homeCalendar = _ownNodeOf(_calendar());

      _ownNodeOf(_barRow('Browse')).requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));

      _ownNodeOf(_barRow('Fullscreen')).requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.arrowDown);
      final landed = FocusManager.instance.primaryFocus;
      debugPrint('[C3] DOWN off Home: ${_describe(landed)}');
      expect(landed, isNot(same(homeCalendar)),
          reason: 'DOWN from the bar must never hand the remote to a page the '
              'shell is not showing');
      expect(
        landed?.context?.findAncestorWidgetOfExactType<ShellRail>() != null,
        isFalse,
        reason: 'and it must have left the bar: it ended on '
            '${_describe(landed)}',
      );
    });

    testWidgets('the row is not in the graph at all when its setting is off',
        (tester) async {
      HomePageSettings.enableCalendar.value = false;
      HomePageSettings.enableAiQuiz.value = false;
      await _pumpTelevisionShell(tester);

      expect(_calendar(), findsNothing);
      _ownNodeOf(_barRow('Fullscreen')).requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.arrowDown);
      final landed = FocusManager.instance.primaryFocus;
      debugPrint('[C3] DOWN with no page row -> ${_describe(landed)}');
      expect(landed, isNotNull,
          reason: 'with nothing in the page\'s own row, DOWN must fall through '
              'to the content the framework finds: ${_describe(landed)}');
    });
  });

  group('Home: the bar marks the destination that was chosen', () {
    testWidgets('Live TV takes the mark, and its page is still Browse',
        (tester) async {
      // The `selected` flag the bar draws its mark from is read back through
      // semantics, so the tree has to be built and disposed inside the test.
      final semantics = tester.ensureSemantics();
      await _pumpTelevisionShell(tester);

      final liveTv = _barRow('Live TV');
      final browse = _barRow('Browse');
      expect(_semanticsOf(tester, _barRow('Home')).hasFlag(SemanticsFlag.isSelected),
          isTrue,
          reason: 'precondition: the shell starts on Home');
      expect(
          _semanticsOf(tester, liveTv).hasFlag(SemanticsFlag.isSelected), isFalse,
          reason: 'precondition: Live TV is not the chosen row yet');

      // Choose it the way a remote does.
      _ownNodeOf(liveTv).requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));

      expect(
          _semanticsOf(tester, liveTv).hasFlag(SemanticsFlag.isSelected), isTrue,
          reason: 'the bar must mark the destination the user chose - Live TV - '
              'and it marked Browse instead');
      expect(
          _semanticsOf(tester, browse).hasFlag(SemanticsFlag.isSelected), isFalse,
          reason: 'both rows open Browse, but only one of them is where the user '
              'pressed: Browse must not carry the mark at the same time');
      semantics.dispose();
    });

    testWidgets('choosing Browse takes the mark back off Live TV',
        (tester) async {
      // The `selected` flag the bar draws its mark from is read back through
      // semantics, so the tree has to be built and disposed inside the test.
      final semantics = tester.ensureSemantics();
      await _pumpTelevisionShell(tester);

      _ownNodeOf(_barRow('Live TV')).requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));
      expect(
          _semanticsOf(tester, _barRow('Live TV'))
              .hasFlag(SemanticsFlag.isSelected),
          isTrue,
          reason: 'precondition: the mark is on Live TV');

      _ownNodeOf(_barRow('Browse')).requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));

      expect(
          _semanticsOf(tester, _barRow('Browse'))
              .hasFlag(SemanticsFlag.isSelected),
          isTrue,
          reason: 'Browse\'s own row is the press that means "off Live TV", and '
              'it has to move the mark even though the slot does not change');
      expect(
          _semanticsOf(tester, _barRow('Live TV'))
              .hasFlag(SemanticsFlag.isSelected),
          isFalse);
      semantics.dispose();
    });
  });

  group('Home: the hero yields when the remote leaves it', () {
    testWidgets('a rail card takes focus and the hero\'s CTA row stands down',
        (tester) async {
      await _pumpTelevisionShell(tester);

      final play = _heroPill('Play');
      expect(play, findsOneWidget);
      _ownNodeOf(play).requestFocus();
      await tester.pump();
      expect(_heroActionsOpacity(tester), 1.0,
          reason: 'while the hero has focus its call to action is on screen');

      // Down once from the hero reaches the first rail's card, which is the case
      // the expansion panel used to clip "More Info" in.
      await _press(tester, LogicalKeyboardKey.arrowDown);
      final landed = FocusManager.instance.primaryFocus;
      debugPrint('[M3] focus after DOWN from the hero: ${_describe(landed)}');

      expect(_heroActionsOpacity(tester), 0.0,
          reason: 'the hero is not what has focus any more, so its action row '
              'must be out of the way of the card that does: the panel draws '
              'across it and clipped the labels');
      // The row is faded, never removed: a control the remote cannot reach is a
      // worse defect than one it cannot see.
      expect(play, findsOneWidget,
          reason: 'the CTA row must stay in the tree and in the traversal graph');
      expect(_ownNodeOf(play).canRequestFocus, isTrue,
          reason: 'and it must still be focusable, so UP returns to it');

      _ownNodeOf(play).requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_heroActionsOpacity(tester), 1.0,
          reason: 'focus back in the hero brings the row back');
    });

    testWidgets('on a pointer the row never stands down', (tester) async {
      await _pumpDesktopShell(tester);

      final play = _heroPill('Play');
      expect(play, findsOneWidget);
      expect(_heroActionsOpacity(tester), 1.0,
          reason: 'precondition: a pointer starts with nothing focused and the '
              'hero showing its actions');
      _ownNodeOf(play).requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_heroActionsOpacity(tester), 1.0,
          reason: 'a desktop has a pointer: the rails are used by hovering, not '
              'by focusing them, so the hero keeps its call to action');
    });
  });

  group('Home: the chrome the television was given', () {
    testWidgets('a television gets no scroll grab-pill', (tester) async {
      await _pumpTelevisionShell(tester);
      expect(
        find.byType(CustomScrollTrack),
        findsNothing,
        reason: 'the 55 x 412 dp grab-pill is a pointer affordance and covered '
            'the rail cards and their See All links on a 960 dp canvas',
      );

      // It must not appear once the page moves either: the gate is the input,
      // not the moment of scrolling.
      _ownNodeOf(_heroPill('Play')).requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CustomScrollTrack), findsNothing);
    });

    testWidgets('a wide pointer window still gets it', (tester) async {
      await _pumpDesktopShell(tester);
      expect(
        find.byType(CustomScrollTrack),
        findsOneWidget,
        reason: 'the pill is what a mouse or a trackpad uses to drag a long '
            'page: removing it from every wide window would be a regression, '
            'not a fix',
      );
    });

    testWidgets('the media-type chip sits inside the canvas\'s safe area',
        (tester) async {
      await _pumpTelevisionShell(tester);

      final chip = find.byWidgetPredicate(
        (w) => w is Text && (w.data == 'Film' || w.data == 'TV'),
      );
      expect(chip, findsWidgets,
          reason: 'precondition: the hero paints its media-type chip');
      final rect = tester.getRect(chip.first);
      debugPrint('[m4] chip rect: $rect');
      expect(
        rect.right,
        lessThanOrEqualTo(_canvas.width - 48),
        reason: 'a television keeps a 5% margin: at the window edge this box '
            'landed in the last ten dp of the canvas, in the overscan a panel '
            'may not show at all. It ended at ${rect.right}.',
      );
    });
  });
}

/// The opacity the hero's action row is currently drawn at.
///
/// Read off the `AnimatedOpacity` that wraps it, which is the row's own declared
/// state: 1 is a hero with its call to action, 0 is a hero standing down for
/// whatever has focus instead.
double _heroActionsOpacity(WidgetTester tester) {
  final row = find.ancestor(
    of: find.text('Play'),
    matching: find.byType(AnimatedOpacity),
  );
  expect(row, findsWidgets,
      reason: 'the hero\'s CTA row must be wrapped in the opacity that stands it '
          'down when focus leaves the hero');
  return tester.widget<AnimatedOpacity>(row.first).opacity;
}
