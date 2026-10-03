/// Guards that a D-pad can move focus into the content on the two screens a
/// television reported it cannot.
///
/// Both bugs came from a Chromecast with Google TV against the 22:42 build, and
/// both are invisible on the pointer desktop the app is usually run in. They
/// are pinned here by driving real `LogicalKeyboardKey.arrowDown` events through
/// the real shell at the television's own canvas, and asserting on where
/// `FocusManager.instance.primaryFocus` actually ends up - not on widget types,
/// which is how the first attempt at these went: every node on Home is a plain
/// `Focus`, so the widget type identifies nothing.
///
/// **The Browse half of this file no longer claims a stall.** It did: the
/// previous version pinned "focus freezes three rows into the Discover grid
/// while the grid keeps scrolling", on evidence that was a focused rect holding
/// at one position while the scroll offset advanced by exactly one row pitch per
/// press. That is also what *correct* focus-following looks like -
/// `defaultTraversalRequestFocusCallback` calls `Scrollable.ensureVisible(...,
/// alignment: 1)`, which pins the focused card to the viewport's trailing edge
/// and lets the content move under it - so the rect could not tell the two
/// apart. Re-measured on a 960x540 television with a probe that logged the
/// focused card's movie id alongside its rect, focus advances on every press:
///
/// | press | id | rect (settled) | scroll |
/// |--:|:--|:--|--:|
/// | 1 | tt6933238  | `16,256 220x192` | 0 |
/// | 2 | tt27165187 | `16,348 220x192` | 116 |
/// | 3 | tt4154796  | `16,348 220x192` | 324 |
/// | 4 | tt12042730 | `16,348 220x192` | 532 |
/// | 5 | tt37969426 | `16,348 220x192` | 740 |
///
/// Four different cards, one row pitch (208 dp = 192 + the 16 dp gutter) further
/// down the scroll each time, at one screen position - and 348 is `540 - 192`,
/// which is `alignment: 1` doing exactly what it says. The rect is the *settled*
/// one: logged at the moment the focus change is notified it still reads `556`,
/// because the scroll jump and the focus change land in the same frame and the
/// notification is applied before the new layout is. That is the second reason a
/// rect is the wrong instrument here - it is not even stable within the frame
/// that produced it.
///
/// The two Browse tests below therefore assert identity - a different card every
/// press, and the grid scrolled under it - rather than a rect that is the same
/// whether focus is working or not.
///
/// The harness is the one `tv_chrome_density_test.dart` and
/// `tv_shell_focus_test.dart` already established:
///
/// | | |
/// |:--|:--|
/// | `physicalSize` | 1920x1080 |
/// | `devicePixelRatio` | 2.0 |
/// | logical canvas | 960x540 dp |
/// | `MediaQuery` | MaterialApp's own - zero insets, which is what a television reports |
/// | television | `DeviceProfile.debugSetTelevision(value: true)` |
/// | highlight | `FocusHighlightStrategy.alwaysTraditional` |
///
/// `DeviceProfile` rather than `MediaQuery.navigationMode`: nothing on Android
/// populates that field (`device_profile.dart` argues it at length, and
/// `tv_shell_focus_test.dart` notes a harness that states
/// `navigationMode: directional` only agrees with itself).
///
/// The whole `AppShell` is mounted rather than the page alone, because both
/// failures turn on an ancestor that only exists there: the shell's
/// `Shortcuts`/`Actions` pair and the `ExcludeFocus`/`SkipPageShellFocus`
/// wrapper around each slot.
///
/// Every request is scripted through `MetadataService.client` and the addon
/// list through `AddonManager.readStoredForTesting`; nothing here reaches the
/// network. The vertical pills of the other seven Browse verticals are mounted
/// alongside Discover and do try to load - they fail and are ignored, which is
/// why `MovieCard` counts rather than catalogue titles are what the assertions
/// are written against.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/addon/addon_manager.dart';
import 'package:zplay/services/home/home_page_settings.dart';
import 'package:zplay/services/metadata/metadata_service.dart';
import 'package:zplay/services/playback/now_playing_service.dart';
import 'package:zplay/shell/app_shell.dart';
import 'package:zplay/services/layout/form_factor.dart';
import 'package:zplay/shell/app_shell_scope.dart';
import 'package:zplay/widgets/common/focusable_card.dart';
import 'package:zplay/widgets/movie/movie_card.dart';

/// The device's own canvas: 1920x1080 physical at density 320, so 960x540 dp.
const Size _televisionCanvas = Size(960, 540);

/// A dp is two physical px on this panel.
const double _dpr = 2.0;

const String _addonHost = 'focus-probe.test';

/// One addon with one auto-loadable `movie` catalog named "Popular", so the chip
/// the tester described is actually on screen. `skip` is declared so the catalog
/// paginates and the grid has rows below the first - a grid that fits entirely on
/// screen cannot reproduce "the grid scrolls but focus does not".
String _manifest() => jsonEncode({
      'id': 'org.zplay.focusprobe',
      'name': 'Focus Probe',
      'version': '1.0.0',
      'resources': ['catalog', 'meta'],
      'types': ['movie', 'series'],
      'catalogs': [
        {
          'type': 'movie',
          'id': 'popular',
          'name': 'Popular',
          'extra': [
            {'name': 'skip'}
          ],
          'supportsSkip': true,
        },
        {'type': 'series', 'id': 'popular', 'name': 'Popular'},
      ],
    });

/// The stored addon list, in the shape `InstalledAddon.fromJson` reads. Going
/// through storage rather than `addAddon` keeps the manager's in-memory list out
/// of the test's way, and it is the same path a real install takes.
String _storedAddonList() => jsonEncode([
      {
        'baseUrl': 'https://$_addonHost',
        'enabled': true,
        'enableCatalogs': true,
        'enableSearch': true,
        'enableSubtitles': true,
        'enableStreams': true,
        'manifest': jsonDecode(_manifest()),
      }
    ]);

/// [count] titles of [type]. Every catalog answers, so a rail and the grid both
/// have real cards whatever the page asks for.
String _catalogBody(int count, String type) => jsonEncode({
      'metas': [
        for (var i = 0; i < count; i++)
          {
            'id': 'tt$type${i.toString().padLeft(6, '0')}',
            'name': '$type Title ${i + 1}',
            'type': type,
          }
      ]
    });

/// The now-playing bar reads a `ValueListenable` the shell consumes on its first
/// build. With nothing registered it collapses to zero height, which is what it
/// does on a device with nothing playing - so the measured geometry is the
/// geometry a user is looking at.
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
  void openFullPlayer(BuildContext context) {}
}

/// The focus node a widget subtree actually installs.
///
/// [Focus.of] and [Focus.maybeOf] both read the *nearest ancestor* [Focus], so
/// called on a widget's own element they answer with the node **above** it -
/// which above a card is the `FocusableActionDetector` wrapping the whole page,
/// and which above a grid viewport is the page's own node. A test written with
/// them reports a 896x540 rect for every card and can pass for entirely the
/// wrong reason. That is not theoretical: it is what the first draft of this
/// file did, and it reported "focus never moves" for the wrong node.
///
/// Two wrappers cover everything reached for here, and both publish the node
/// they own, so neither needs private state:
///   * [FocusableCard] builds a [FocusableActionDetector], whose `focusNode`
///     is the card's own.
///   * A bare [Focus] is resolved by asking from one of its children, because
///     the nearest [Focus] above a child is the one that element installed.
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
  // A subtree with neither wrapper has no node of its own. That is a bug in the
  // caller, and a loud null beats a plausible answer.
  return found!;
}

/// [_ownNode] for a [Finder]'s first match.
FocusNode _ownNodeOf(Finder f) => _ownNode(f.evaluate().first);


/// The focus node of the button [f]'s label sits inside.
///
/// [_ownNode] answers a different question - what node does *this* subtree
/// install - and the two are not interchangeable. `find.text('Watch Now')`
/// matches a [Text], which installs no node; the button around it is what a
/// remote focuses. `Element` publishes no parent, so this finds the enclosing
/// button with the public finder rather than by walking the element tree, then/// Puts focus on a Material button the way a television would, and reports
/// whether it got there.
///
/// [ElevatedButton] owns its node privately and there is no public accessor, so
/// the node is found the way `tv_shell_focus_test.dart` already finds one: walk
/// [LogicalKeyboardKey.tab] until the wanted widget's subtree holds focus. Tab
/// is the framework's own traversal, so the node it lands on is the node a
/// remote's focus ring would be painted on - this is not a way around the
/// behaviour under test, it *is* the behaviour under test.
///
/// A bounded walk returning false turns "the CTA is unreachable" into a
/// One line worth putting in a failure message: what holds focus and how big it
/// is. The geometry is not decoration - "focus is on a node the size of the
/// whole page" and "focus is on the right card" are the same widget type, and a
/// directional traversal failure is invisible without the rects.
String _describe(FocusNode? node) {
  if (node == null) return '<primaryFocus is null>';
  final rect = node.rect;
  return '${node.context?.widget.runtimeType}'
      ' at ${rect.left.toStringAsFixed(0)},'
      '${rect.top.toStringAsFixed(0)} '
      '${rect.width.toStringAsFixed(0)}x${rect.height.toStringAsFixed(0)}'
      '${node.hasFocus ? '' : ' (NOT in the focus path)'}';
}

/// Whether the nearest vertical [Scrollable] is at [offset].
bool _pageIsScrolledTo(WidgetTester tester, double offset) {
  for (final element in find.byType(Scrollable).evaluate()) {
    final state = (element as StatefulElement).state;
    if (state is ScrollableState &&
        state.widget.axisDirection == AxisDirection.down &&
        (state.position.pixels - offset).abs() < 0.5) {
      return true;
    }
  }
  return false;
}

Future<void> _pumpTelevisionShell(WidgetTester tester) async {
  DeviceProfile.debugSetTelevision(value: true);
  tester.view.devicePixelRatio = _dpr;
  tester.view.physicalSize = _televisionCanvas * _dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const MaterialApp(home: AppShell()));
  // The cold-start splash holds a 1.8 s timer and Home's rails arrive over the
  // addon fetch; both must land before focus is asked any question.
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  final owner = _SilentOwner();

  setUp(() async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    MetadataService.client = MockClient((request) async {
      if (request.url.path.contains('/catalog/')) {
        final type = request.url.pathSegments.firstWhere(
          (s) => s == 'movie' || s == 'series',
          orElse: () => 'movie',
        );
        return http.Response(_catalogBody(24, type), 200);
      }
      return http.Response(jsonEncode(<String, Object?>{}), 200);
    });
    MetadataService.clearCache();
    NowPlayingService.register(owner);

    // The hero's rotation timer is the obvious suspect for "the dots moved".
    // Turning it off is what makes "the dots moved because DPAD_DOWN did
    // something" a claim the test can falsify.
    HomePageSettings.heroAutoRotate.value = false;

    // The recommendation rails are local services (my list, Trakt, Simkl) with
    // nothing configured in a test process; leaving them on only adds network
    // that has to fail. Home's own addon rails are what is under test.
    HomePageSettings.enableSimilar.value = false;
    HomePageSettings.enableWatchingSimilar.value = false;
    HomePageSettings.enableTraktRecommendations.value = false;
    HomePageSettings.enableSimklRecommendations.value = false;

    AddonManager.readStoredForTesting = () async => _storedAddonList();
    await AddonManager.instance.reload();
  });

  tearDown(() {
    NowPlayingService.unregister(owner);
    HomePageSettings.heroAutoRotate.value = true;
    HomePageSettings.enableSimilar.value = true;
    HomePageSettings.enableWatchingSimilar.value = true;
    HomePageSettings.enableTraktRecommendations.value = true;
    HomePageSettings.enableSimklRecommendations.value = true;
    MetadataService.client = http.Client();
    MetadataService.clearCache();
    AddonManager.readStoredForTesting = null;
    DeviceProfile.debugSetTelevision(value: false);
  });


  group('Browse: D-pad DOWN from the catalog chip row', () {
    testWidgets('DOWN from the Popular chip walks the grid one row at a time',
        (tester) async {
      await _pumpTelevisionShell(tester);

      // Land on Browse the way the rail does.
      AppShellScope.of(tester.element(find.byType(FocusableCard).first))!
          .go(ShellSlot.browse);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      // The Discover catalog chip. It is not the Browse vertical pill of the
      // same name above it: those are 64 dp tall at y=20, this is a chip inside
      // the page, and the page is what the finder scopes it to.
      final chip = find.ancestor(
        of: find.text('Popular'),
        matching: find.byType(FocusableCard),
      );
      expect(chip, findsOneWidget,
          reason: 'precondition: the Popular catalog chip must exist');

      expect(find.byType(MovieCard), findsWidgets,
          reason: 'precondition: the grid must have loaded cards');

      final chipNode = _ownNodeOf(chip);
      chipNode.requestFocus();
      await tester.pump();
      debugPrint('[Browse] focus starts on the chip: '
          '${_describe(FocusManager.instance.primaryFocus)}');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final firstId = _focusedCardId(FocusManager.instance.primaryFocus);
      debugPrint('[Browse] DOWN #1 -> '
          '${_describe(FocusManager.instance.primaryFocus)} id=$firstId');
      expect(firstId, isNotNull,
          reason: 'the first DPAD_DOWN from the chip row must reach a card; '
              'it ended on ${_describe(FocusManager.instance.primaryFocus)}');

      // **Identity, not geometry.**
      //
      // The two are not interchangeable here, and reading the rect is what made
      // this look like a stall: `defaultTraversalRequestFocusCallback` pins the
      // focused card to the viewport's trailing edge (`ensureVisible(...,
      // alignment: 1)`), so a card that is being followed *down* the grid and a
      // card that never moves report the same rect. The table of the television
      // measurement is in this file's header; this is the same shape, and the
      // assertion below is on the id.
      final ids = <String>[firstId!];
      final offsets = <double>[_gridOffset(tester)];
      for (var i = 2; i <= 5; i++) {
        final before = _verticalOffsets(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        // `ensureVisible` animates the grid, so a single frame catches it
        // mid-flight. `pumpAndSettle` cannot be used: the load-more spinner
        // under the last card spins forever, so the tree never settles. Pump
        // past the scroll animation instead.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        final id = _focusedCardId(FocusManager.instance.primaryFocus);
        debugPrint('[Browse] DOWN #$i -> '
            '${_describe(FocusManager.instance.primaryFocus)} id=$id, '
            'offsets $before -> ${_verticalOffsets(tester)}');
        expect(id, isNotNull,
            reason: 'press $i took focus out of the grid, to '
                '${_describe(FocusManager.instance.primaryFocus)}');
        ids.add(id!);
        offsets.add(_gridOffset(tester));
      }

      expect(
        ids.toSet(),
        hasLength(ids.length),
        reason: 'each of the five DPAD_DOWN presses must land on a different '
            'card. They landed on ${ids.join(" / ")}. A rect cannot tell the '
            'difference between this and a stall - see the table above - so '
            'this asserts the card identity the focus manager actually moved.',
      );

      // And the grid really moved under the ring. `ensureVisible` only runs
      // when traversal focuses a new node, so a node that had genuinely
      // stalled would stop the scroll as well; an advancing offset is the
      // second half of the same proof.
      expect(
        offsets.last,
        greaterThan(offsets.first),
        reason: 'five presses down a grid that is taller than the viewport '
            'must scroll it. The offsets were $offsets.',
      );
    });

    testWidgets('focus follows the grid down and keeps the ring on screen',
        (tester) async {
      // The behaviour this replaces was pinned as "focus never leaves the
      // viewport it entered", on the theory that `ensureVisible` moved the
      // focused rect to the viewport edge and left traversal nothing to find
      // below it. Re-measured on the device, that is not what happens: every
      // press focuses a *different* card one row further down, and
      // `ensureVisible` keeps that card on screen while the content moves under
      // it. So the assertion is the pair - a new card each press, and that card
      // inside the viewport - which is what focus-following means and what a
      // stall would break.
      await _pumpTelevisionShell(tester);
      AppShellScope.of(tester.element(find.byType(FocusableCard).first))!
          .go(ShellSlot.browse);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      final cards = find.byType(MovieCard);
      expect(cards, findsWidgets,
          reason: 'precondition: the grid must have loaded cards');

      final first = _ownNodeOf(cards);
      first.requestFocus();
      await tester.pump();
      debugPrint('[Browse] grid card #0 starts at ${first.rect}');

      final viewport = tester.getRect(find.byType(GridView));
      debugPrint('[Browse] grid viewport: $viewport');

      var stalled = 0;
      String? previous = _focusedCardId(first);
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        final node = FocusManager.instance.primaryFocus;
        final id = _focusedCardId(node);
        debugPrint('[Browse] DOWN #$i -> ${_describe(node)} id=$id '
            '(page at top: ${_pageIsScrolledTo(tester, 0)})');

        expect(id, isNotNull,
            reason: 'press $i took focus off the grid, to ${_describe(node)}');
        if (id == previous) stalled++;
        previous = id;

        expect(viewport.overlaps(node!.rect), isTrue,
            reason: 'the focused card must be scrolled into view: '
                '${_describe(node)} is outside the grid viewport $viewport');
      }

      expect(stalled, 0,
          reason: 'focus must not stall while the grid scrolls under it; '
              '$stalled of five presses left focus on the card it was already '
              'on. Measured on the device the identity advances every press, '
              'so a repeat here is a real regression and not a rect that '
              'happens to be pinned to the viewport edge.');
    });
  });

  group('competing explanations, checked one at a time', () {
    testWidgets('(a) Shortcuts+Actions with an empty map does not block traversal',
        (tester) async {
      // The shell keeps `Shortcuts`/`Actions` in the tree on every form factor
      // (`app_shell.dart:456`) with an empty map on a television. The claim to
      // falsify is that the pair swallows arrow keys. It does not: the same key
      // moves focus through the page, so the widget is present and inert.
      await _pumpTelevisionShell(tester);

      final focus = find.byType(Focus);
      expect(focus, findsWidgets,
          reason: 'precondition: the tree has Focus widgets');

      AppShellScope.of(tester.element(find.byType(FocusableCard).first))!
          .go(ShellSlot.browse);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      final card = _ownNodeOf(find.byType(MovieCard));
      card.requestFocus();
      await tester.pump();
      final before = card;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      final after = FocusManager.instance.primaryFocus;

      debugPrint('[a] right from a grid card: ${_describe(before)} '
          '-> ${_describe(after)}');
      expect(after, isNot(same(before)),
          reason: 'if an empty Shortcuts map blocked traversal, no arrow key '
              'would move focus anywhere on this screen');
    });

    testWidgets('(b) ExcludeFocus/SkipPageShellFocus does not exclude the grid',
        (tester) async {
      // `app_shell.dart:282-306` wraps each slot in `ExcludeFocus` plus
      // `SkipPageShellFocus`. The claim to falsify is that the grid is excluded.
      // Every card in the grid is `canRequestFocus && !skipTraversal`, so it is
      // in `traversalDescendants` and can be reached.
      await _pumpTelevisionShell(tester);
      AppShellScope.of(tester.element(find.byType(FocusableCard).first))!
          .go(ShellSlot.browse);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      final cards = find.byType(MovieCard).evaluate();
      expect(cards, isNotEmpty, reason: 'precondition: the grid must have cards');

      var traversable = 0;
      for (final element in cards) {
        final node = _ownNode(element);
        if (node.canRequestFocus && !node.skipTraversal) traversable++;
      }
      debugPrint('[b] first card rect: ${_ownNode(cards.first).rect}');
      debugPrint('[b] $traversable/${cards.length} grid cards are traversable');

      expect(traversable, cards.length,
          reason: 'a card the shell excluded could never be reached, which is '
              'a different bug from the one reported and would not present as '
              '"right and left work, down does not"');

      // And a requestFocus on one really takes.
      final node = _ownNode(cards.first);
      node.requestFocus();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(node),
          reason: 'a traversable node must accept focus');
    });

    testWidgets('(c) the GridView installs no focusable node of its own',
        (tester) async {
      // The claim to falsify is that the `GridView` swallows DOWN to scroll
      // itself. It does not: `Scrollable` has no `Focus` in it at all in this
      // Flutter version, so there is no node to swallow with. The only node
      // involved is on the cards.
      await _pumpTelevisionShell(tester);
      AppShellScope.of(tester.element(find.byType(FocusableCard).first))!
          .go(ShellSlot.browse);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      final grid = find.byType(GridView);
      expect(grid, findsOneWidget, reason: 'precondition: the grid must exist');

      // Every traversable node in the grid belongs to a card.
      //
      // A node owned by the viewport rather than by a card would be a real
      // competing explanation for "DOWN scrolls the grid but does not move
      // focus" - and there is none, because a [Scrollable] contains no [Focus]
      // of its own. Checked structurally rather than by behaviour, because
      // "DOWN scrolled the grid" is exactly what a card that *did* receive
      // focus also does via Flutter's own `ensureVisible`; after the fact the
      // two are indistinguishable.
      //
      // The test is "no node outside the cards is traversable", not "there is
      // one node per card": the cache extent keeps a third row of cards built
      // below the viewport, and those nodes belong to cards the finder does not
      // match because only the visible ones are realised as elements.
      final cardElements = find.byType(MovieCard).evaluate().toSet();
      final cardNodes = <FocusNode>{};
      for (final element in cardElements) {
        cardNodes.add(_ownNode(element));
      }
      debugPrint('[c] realised card elements: ${cardElements.length}, '
          'distinct nodes they own: ${cardNodes.length}');

      final allNodes = <FocusNode>[];
      for (final element in grid.evaluate()) {
        void visit(Element e) {
          if (e.widget is Focus) {
            // Asked from a child, so this is the node *this* element installed
            // rather than an ancestor's.
            var queried = false;
            e.visitChildElements((child) {
              if (queried) return;
              queried = true;
              final node = Focus.maybeOf(child, scopeOk: true);
              if (node != null) allNodes.add(node);
            });
          }
          e.visitChildElements(visit);
        }

        visit(element);
      }

      // A node is a viewport's own only if it is traversable *and* no card
      // owns it *and* it is inside the viewport. The last clause is what
      // separates "a row the cache extent built below the fold" - which is
      // still a card - from a node the viewport installed to swallow keys.
      // All four extras here are cards at y=624, below the 540 dp viewport.
      final viewport = tester.getRect(find.byType(GridView));
      final orphans = allNodes.where((n) {
        if (cardNodes.contains(n)) return false;
        if (!n.canRequestFocus || n.skipTraversal) return false;
        return viewport.overlaps(n.rect);
      }).toList();
      debugPrint('[c] traversable nodes in the grid: ${allNodes.length}, '
          'traversable ones inside the viewport that no card owns: '
          '${orphans.length}');
      for (final n in orphans) {
        debugPrint('[c]   orphan ${_describe(n)}');
      }
      debugPrint('[c] the 4 extras are cards at y=624, below the fold: '
          '${allNodes.where((n) => !cardNodes.contains(n)).map((n) => n.rect.top).toList()}');
      debugPrint('[c] the node DOWN actually moves to: '
          '${_describe(_ownNodeOf(find.byType(MovieCard)))}');

      expect(orphans, isEmpty,
          reason: 'a traversable node in the grid that belongs to no card '
              'would be a real competing explanation for "DOWN scrolls the '
              'grid but does not move focus" - a viewport that took the key '
              'and scrolled itself would look exactly like that');
    });

    testWidgets('(d) the two autofocus TextFields are not built',
        (tester) async {
      // Both `TextField`s in `discover_page.dart` - the one inside the
      // "enter a custom extra" dialog and the in-catalog search bar - are
      // `autofocus: true` on the pointer path, and the search bar is now
      // explicitly guarded off a television (`autofocus: FormFactorService
      // .of(context) != FormFactor.television`, the same guard `SearchPage`
      // carries). Both are behind state that is off here. A focused
      // `EditableText` installs `DirectionalFocusAction.forTextField()`, which
      // ignores directional intents - the trap
      // `test/pages/search_field_focus_test.dart` already guards against on
      // Search.
      await _pumpTelevisionShell(tester);
      AppShellScope.of(tester.element(find.byType(FocusableCard).first))!
          .go(ShellSlot.browse);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      final fields = find.byType(EditableText);
      debugPrint('[d] EditableText widgets on Browse: ${fields.evaluate().length}');
      debugPrint('[d] primary focus: ${_describe(FocusManager.instance.primaryFocus)}');

      expect(fields, findsNothing,
          reason: 'a focused text field swallows every arrow press; if one were '
              'mounted on Browse at rest, that would be the cause and not the '
              'one these tests pin');
    });
  });
}

/// The id of the movie the focused node's card is showing, or null when the
/// focused node is not inside a [MovieCard].
///
/// This is the *identity* of the focused card, and it is the measurement these
/// tests need. The rect is not: `defaultTraversalRequestFocusCallback` calls
/// `Scrollable.ensureVisible(..., alignment: 1)`, which pins the focused card's
/// trailing edge to the viewport's trailing edge - so once focus is following
/// the grid down, the focused rect is the same rect every press, and a card
/// that is being followed is indistinguishable from one that is stuck.
/// Measured on the television, the id advances on every press while the rect
/// holds at `16,348 220x192`.
String? _focusedCardId(FocusNode? node) {
  final context = node?.context;
  if (context == null) return null;
  return context.findAncestorWidgetOfExactType<MovieCard>()?.movie.id;
}

/// The pixels of the discover grid's own vertical scrollable.
///
/// Scoped to the [GridView] rather than read off every vertical [Scrollable] in
/// the tree: the shell keeps five pages mounted, so `_verticalOffsets` answers
/// with all of them at once and a bare `values.first` would be whichever
/// happened to be built first.
double _gridOffset(WidgetTester tester) {
  final scrollable = find
      .descendant(of: find.byType(GridView), matching: find.byType(Scrollable))
      .evaluate()
      .first;
  return ((scrollable as StatefulElement).state as ScrollableState)
      .position
      .pixels;
}

/// Every vertical [Scrollable]'s offset, read so a scroll can be told from a
/// focus move.
Map<double, double> _verticalOffsets(WidgetTester tester) {
  final result = <double, double>{};
  for (final element in find.byType(Scrollable).evaluate()) {
    final state = (element as StatefulElement).state;
    if (state is ScrollableState &&
        state.widget.axisDirection == AxisDirection.down) {
      result[state.position.maxScrollExtent] = state.position.pixels;
    }
  }
  return result;
}
