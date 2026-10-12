/// Guards the source list a television could not reach at all.
///
/// Reported on the 1.5.5 build (960x540 dp, Google TV): on the Watch Sources
/// screen three Down presses left the screen pixel-identical and the centre
/// button started nothing, so a remote could not pick a source and the player was
/// unreachable — the sweep had to fall back to a pointer tap. Two causes:
///
/// 1. The row was a `MouseRegion` around an `InkWell`. An `InkWell` does install
///    a focus node, but the row painted nothing on focus, so even a remote that
///    landed on it saw no ring.
/// 2. Nothing handed focus to the list. A pushed route opens with its own
///    `FocusScope` holding focus, and a directional search from a node whose rect
///    is the whole screen looks for a neighbour *outside* that rectangle — every
///    row is inside it, so the arrows had nothing to move to. This is the same
///    dead end `PlayerScreen`'s page node had, and it takes the same answer: the
///    screen owns the node and requests it once its target exists.
///
/// The screen is driven whole, at the television's own canvas, with the sources
/// the episode carries itself — no addon fan-out, and nothing here reaches the
/// network. Identity is asserted, never rects: the focused row is named by the
/// text it draws, as `tv_nav_harness.dart` requires.
///
/// `PlayerScreen` cannot be pumped (it owns a `media_kit` `Player`), so the route
/// the rows open is stood in for by `WatchScreen.debugPlayerBuilderForTesting`,
/// which receives the source the row was on. That is the handover under test:
/// a keypress on a focused row has to arrive at *that* row's source.
///
/// Two readings from the 1.6.1 device pass are settled here rather than taken on
/// trust, because the emulator they were taken on was CPU-starved and its frames
/// are not evidence on their own:
///
///  * **The Direct-filtered list was said to give the remote rows that paint
///    nothing.** The filter is chosen here with the remote's own centre button,
///    and every stop the walk makes inside the filtered list is checked for the
///    one lit ring this app paints, at the row's own box. It holds: a row in that
///    list takes focus with its ring painted, on the same screen path the reading
///    came from. The two lists do build a row differently - only a magnet row
///    gets the key-handling wrapper - and that wrapper is the only thing in the
///    row that a filter can add or remove, so there is nothing here for a stale
///    frame to have been hiding.
///  * **Left on a row was said to land on another row's copy-magnet button.** It
///    does not, and it cannot: the button is `skipTraversal`, which keeps it out
///    of the arrow search entirely. Left leaves the panel for the information
///    column, which is what the row's own comment claims.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/models/movie/movie_detail.dart';
import 'package:zplay/models/movie/video.dart';
import 'package:zplay/models/stream/stream_model.dart';
import 'package:zplay/pages/player/watch_screen.dart';
import 'package:zplay/services/theme/glass_settings.dart';
import 'package:zplay/widgets/common/focusable_card.dart';

import 'support/tv_nav_harness.dart';

/// Two playable rows, highest quality first.
///
/// The list sorts by quality rank, so the order here is the order on screen:
/// `2160p` outranks `1080p`. Each title states its own bitrate, which is what
/// keeps `StreamBitrateBadge` from probing a manifest with no server behind it.
/// Neither source is a magnet, so no copy-magnet button is drawn: these rows
/// carry their own activation and nothing else, which is what the list's own walk
/// tests. [_magnetSources] is the magnet pair, where a row draws a second control
/// - the action the rest of this file is about.
final List<StreamSource> _sources = <StreamSource>[
  StreamSource(
    name: 'Torrentio',
    title: 'A Show 2160p 8.5 Mb/s',
    url: 'https://cdn.example.test/high.m3u8',
    addonName: 'Torrentio',
    description: 'The high quality row',
  ),
  StreamSource(
    name: 'Second Source',
    title: 'A Show 1080p 4.2 Mb/s',
    url: 'https://cdn.example.test/second.m3u8',
    addonName: 'Second Addon',
    description: 'The second row',
  ),
];

/// Twelve rows, so the list is taller than the panel and focus has to follow the
/// scroll to stay on screen.
List<StreamSource> _twelveSources() => List<StreamSource>.generate(
      12,
      (i) => StreamSource(
        name: 'Row ${i + 1}',
        title: 'A Show 1080p row ${i + 1} 4.2 Mb/s',
        url: 'https://cdn.example.test/row$i.m3u8',
        addonName: 'Torrentio',
      ),
    );

/// Whether the row showing [label] is the one the ring is painted on.
///
/// The harness's own [focusedId] answers with the *first* `Text` inside the
/// focused card, and a source row draws its addon's initial as a 40 dp badge
/// before its own name — so it reports `T` for every row. Asking the tree the
/// other way round, whether the ring under this row's label is lit, names the row
/// itself.
bool _rowRingIsLit(WidgetTester tester, String label) {
  final Finder row = find.ancestor(
    of: find.text(label),
    matching: find.byType(FocusableCard),
  );
  return tester
      .widgetList<CardFocusRing>(
        find.descendant(of: row, matching: find.byType(CardFocusRing)),
      )
      .any((ring) => ring.focused);
}

/// One torrent row and the two direct links below it, highest quality first.
///
/// This is the list the 1.6.1 sweep filtered: `Torrentio` holds the same quality
/// rank as the rows under it, so it sorts first and the Direct filter then hands
/// index 0 - the row carrying the screen's own focus node - to a different kind
/// of row, one built without the magnet action and without the key handling that
/// goes with it. [_sources] cannot show that: it is direct-only, so the filter
/// changes the count and nothing else.
List<StreamSource> _mixedSources() => <StreamSource>[
  StreamSource(
    name: 'Torrentio',
    title: 'A Show 2160p 8.5 Mb/s',
    infoHash: 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1',
    addonName: 'Torrentio',
  ),
  StreamSource(
    name: 'Torrentio',
    title: 'A Show 1080p 4.2 Mb/s',
    url: 'https://cdn.example.test/direct1.m3u8',
    addonName: 'Torrentio',
  ),
  StreamSource(
    name: 'Torrentio',
    title: 'A Show 720p 2.1 Mb/s',
    url: 'https://cdn.example.test/direct2.m3u8',
    addonName: 'Torrentio',
  ),
];

/// The focus node the row showing [label] installs.
///
/// Read off the card's own detector - the first one under the row, since a
/// torrent row's copy-magnet action is a card of its own further down - so the
/// walk starts from the row a user would name rather than from a node this test
/// invented.
FocusNode _rowNode(WidgetTester tester, String label) {
  final Finder detector = find.descendant(
    of: _row(label),
    matching: find.byType(FocusableActionDetector),
  );
  expect(detector, findsWidgets,
      reason: 'precondition: the row "$label" is on screen');
  final FocusNode? node =
      tester.widget<FocusableActionDetector>(detector.first).focusNode;
  expect(node, isNotNull, reason: 'a row has to be reachable by a remote');
  return node!;
}

/// The focus node the panel's Direct chip installs, so the filter can be chosen
/// with a real remote key rather than by reaching into the screen.
///
/// A Material chip keeps its own node private, so it is read the way [Focus.of]
/// reads any control: from a widget inside it, where the answer is the chip's own
/// node and not the panel's.
FocusNode _directChipNode(WidgetTester tester) {
  final Finder label = find.textContaining('Direct (');
  expect(label, findsOneWidget,
      reason: 'precondition: the panel offers the Direct filter');
  return Focus.of(label.evaluate().single, scopeOk: true);
}

/// Two torrent rows, highest quality first.
///
/// A magnet row is the one that draws a control *beside* its own activation: the
/// copy-magnet button. That button is what the action assertions below are about -
/// it was pointer-only on a screen where a pointer is not the input - so these
/// rows carry an info hash and are otherwise the same rows as [_sources].
List<StreamSource> _magnetSources() => <StreamSource>[
  StreamSource(
    name: 'Torrentio',
    title: 'A Show 2160p 8.5 Mb/s',
    infoHash: 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1',
    addonName: 'Torrentio',
    description: 'The high quality row',
  ),
  StreamSource(
    name: 'Second Source',
    title: 'A Show 1080p 4.2 Mb/s',
    infoHash: 'b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2',
    addonName: 'Second Addon',
    description: 'The second row',
  ),
];

/// The card a row is drawn on, named by the provider label it shows.
Finder _row(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(FocusableCard));

/// The rows' own action, as a viewer sees it: the copy-magnet button.
///
/// Found by the tooltip it draws, because the widget itself is private to the
/// screen - and the tooltip is what the pointer user has been reading all along.
Finder get _magnetAction => find.byTooltip('Copy Magnet Link');

/// Whether two rects are the same box, to the sub-pixel.
bool _sameBox(Rect a, Rect b) =>
    (a.left - b.left).abs() < 0.01 &&
    (a.top - b.top).abs() < 0.01 &&
    (a.width - b.width).abs() < 0.01 &&
    (a.height - b.height).abs() < 0.01;

/// Fails unless the remote is on [control], ring and all.
///
/// Identity three ways over, because on a television the ring *is* the identity:
/// exactly one control may be lit, the lit ring has to be painted over this
/// control's own box, and the focus node itself has to sit on that box. A rect
/// read alone would pass with the remote on a sibling that happens to line up.
void _expectRemoteOn(WidgetTester tester, Finder control, String what) {
  final Rect box = tester.getRect(control);
  final lit = find.byWidgetPredicate((w) => w is CardFocusRing && w.focused);
  expect(lit, findsOneWidget, reason: 'exactly one control may be lit: $what');
  expect(_sameBox(tester.getRect(lit), box), isTrue,
      reason: 'the lit ring must be painted over $what, not beside it');
  expect(_sameBox(FocusManager.instance.primaryFocus!.rect, box), isTrue,
      reason: 'the remote itself must be on $what, not merely near it');
}

void main() {
  late bool glassWasEnabled;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    glassWasEnabled = GlassSettings.enabled.value;
    // The plain path: no liquid-glass lens in a test.
    GlassSettings.enabled.value = false;
    WatchScreen.debugPlayerBuilderForTesting = null;
  });

  tearDown(() {
    GlassSettings.enabled.value = glassWasEnabled;
    WatchScreen.debugPlayerBuilderForTesting = null;
  });

  /// Mounts the real screen with the rows above, and the player route stood in
  /// for by a marker that names the source it was handed.
  Future<void> pumpWatchSources(
    WidgetTester tester, {
    List<StreamSource>? sources,
  }) async {
    WatchScreen.debugPlayerBuilderForTesting = (source) =>
        Scaffold(body: Center(child: Text('player:${source.title}')));
    await pumpTelevision(
      tester,
      WatchScreen(
        detail: MovieDetail(
          id: 'tt0000001',
          type: 'series',
          name: 'A Show',
          year: '2026',
        ),
        selectedEpisode: Video(
          id: 'tt0000001:1:1',
          title: 'Pilot',
          season: 1,
          episode: 1,
          streams: sources ?? _sources,
        ),
        type: 'series',
      ),
    );
  }

  testWidgets('the screen opens with the remote on the first source row', (
    tester,
  ) async {
    await pumpWatchSources(tester);

    expect(
      _rowRingIsLit(tester, 'Torrentio'),
      isTrue,
      reason: 'the remote has to start somewhere on this screen; it started on '
          'the route scope, from which no arrow could move',
    );
  });

  testWidgets('Down walks the rows and the centre button starts the one it is on', (
    tester,
  ) async {
    await pumpWatchSources(tester);

    final Rect firstBefore = cardLayoutRect(tester, 'Torrentio');
    final Rect secondBefore = cardLayoutRect(tester, 'Second Source');
    await pressDpad(tester, LogicalKeyboardKey.arrowDown);

    expect(
      _rowRingIsLit(tester, 'Second Source'),
      isTrue,
      reason: 'Down has to move the ring onto the next row',
    );
    expect(
      _rowRingIsLit(tester, 'Torrentio'),
      isFalse,
      reason: 'the first row must not stay lit beside it',
    );

    // The two rows travel together: the framework's own
    // `defaultTraversalRequestFocusCallback` scrolls a focused node into view, so
    // the absolute rects are expected to move, and what must not move is the
    // layout — the ring is painted over the row, and one row's arrival cannot
    // re-flow the list around it.
    final Rect firstAfter = cardLayoutRect(tester, 'Torrentio');
    final Rect secondAfter = cardLayoutRect(tester, 'Second Source');
    expect(
      secondAfter.size.width,
      closeTo(secondBefore.size.width, 0.01),
      reason: 'the focused row keeps the width it had before the ring arrived',
    );
    expect(
      secondAfter.size.height,
      closeTo(secondBefore.size.height, 0.01),
      reason: 'the focused row keeps the height it had before the ring arrived',
    );
    expect(
      secondAfter.top - firstAfter.top,
      closeTo(secondBefore.top - firstBefore.top, 0.01),
      reason: 'the rows keep their spacing when focus moves between them',
    );

    await pressDpad(tester, LogicalKeyboardKey.select);
    expect(
      find.text('player:A Show 1080p 4.2 Mb/s'),
      findsOneWidget,
      reason: 'the centre button has to start the row the ring is on, which is '
          'the whole point of the list',
    );
  });

  testWidgets('the centre button starts the row the screen handed focus to', (
    tester,
  ) async {
    await pumpWatchSources(tester);

    expect(_rowRingIsLit(tester, 'Torrentio'), isTrue);
    await pressDpad(tester, LogicalKeyboardKey.select);

    expect(find.text('player:A Show 2160p 8.5 Mb/s'), findsOneWidget);
    expect(
      find.text('player:A Show 1080p 4.2 Mb/s'),
      findsNothing,
      reason: 'the wrong row must not be the one that started',
    );
  });

  testWidgets('focus follows the scroll, so no row is off the screen', (
    tester,
  ) async {
    await pumpWatchSources(tester, sources: _twelveSources());

    for (int i = 0; i < 11; i++) {
      await pressDpad(tester, LogicalKeyboardKey.arrowDown);
    }

    expect(
      _rowRingIsLit(tester, 'Row 12'),
      isTrue,
      reason: 'the arrows have to walk the whole list, not stop at the fold',
    );
    final Rect focused = cardLayoutRect(tester, 'Row 12');
    expect(
      focused.top,
      greaterThanOrEqualTo(0.0),
      reason: 'the row the remote is on has to be inside the canvas',
    );
    expect(
      focused.bottom,
      lessThanOrEqualTo(tvLogicalCanvas.height),
      reason: 'a row scrolled past the bottom edge is a row the user cannot see',
    );
  });

  testWidgets("Right steps into the row's own action, which the centre button runs", (
    tester,
  ) async {
    // The 960x540 device pass measured Right as a dead key on this list: a single
    // column has no neighbour to the right, and the row's own copy-magnet button
    // is drawn *inside* the row's rectangle, where a directional search cannot
    // find it. So the button was pointer-only, which on a television means the
    // magnet link could not be copied at all.
    await pumpWatchSources(tester, sources: _magnetSources());

    _expectRemoteOn(tester, _row('Torrentio'), 'the first row');

    // Right is the move towards a control drawn at the right end of the row.
    await pressDpad(tester, LogicalKeyboardKey.arrowRight);
    _expectRemoteOn(
      tester,
      _magnetAction.first,
      "the first row's copy-magnet action",
    );

    await pressDpad(tester, LogicalKeyboardKey.select);
    expect(
      find.text('Magnet link copied to clipboard'),
      findsOneWidget,
      reason: 'the centre button on the action has to run the action',
    );
    expect(
      find.textContaining('player:'),
      findsNothing,
      reason: 'and it must not also start the source: one press, one action',
    );
  });

  testWidgets('the action lets the remote back out, and the row still starts', (
    tester,
  ) async {
    await pumpWatchSources(tester, sources: _magnetSources());

    await pressDpad(tester, LogicalKeyboardKey.arrowRight);
    _expectRemoteOn(
      tester,
      _magnetAction.first,
      "the first row's copy-magnet action",
    );

    // Out again, onto the row the action belongs to. A stop a remote can enter
    // and not leave would be worse than the dead key it replaced.
    await pressDpad(tester, LogicalKeyboardKey.arrowLeft);
    _expectRemoteOn(tester, _row('Torrentio'), 'the row the action belongs to');

    await pressDpad(tester, LogicalKeyboardKey.select);
    expect(
      find.text('player:A Show 2160p 8.5 Mb/s'),
      findsOneWidget,
      reason: "the row's own activation still starts that row, so the centre "
          'button has not become ambiguous',
    );
  });

  testWidgets("Down walks the list from a row's action too", (tester) async {
    await pumpWatchSources(tester, sources: _magnetSources());

    await pressDpad(tester, LogicalKeyboardKey.arrowRight);
    _expectRemoteOn(
      tester,
      _magnetAction.first,
      "the first row's copy-magnet action",
    );

    // The rows are still the list's own traversal, from either stop: a remote
    // that stepped into a row must not be stuck there.
    await pressDpad(tester, LogicalKeyboardKey.arrowDown);
    _expectRemoteOn(tester, _row('Second Source'), 'the second row');

    await pressDpad(tester, LogicalKeyboardKey.arrowRight);
    _expectRemoteOn(
      tester,
      _magnetAction.last,
      "the second row's copy-magnet action",
    );
  });

  testWidgets('a row with nothing beside its activation leaves Right as it was', (
    tester,
  ) async {
    // A direct link has no magnet to copy, so this row offers nothing but its own
    // activation and must not have gained a stop: the fix is one action, one
    // stop, and no control that is drawn but cannot be reached.
    await pumpWatchSources(tester);

    _expectRemoteOn(tester, _row('Torrentio'), 'the first row');

    await pressDpad(tester, LogicalKeyboardKey.arrowRight);
    _expectRemoteOn(tester, _row('Torrentio'), 'the first row, unchanged');

    await pressDpad(tester, LogicalKeyboardKey.arrowDown);
    _expectRemoteOn(tester, _row('Second Source'), 'the second row, unchanged');
  });

  testWidgets('every row the Direct-filtered list gives the remote paints the '
      'ring it took focus with', (tester) async {
    // The 1.6.1 sweep reported rows taking focus with nothing drawn once the
    // list was filtered to direct links: the accessibility tree named a row as
    // focused, the row painted its unfocused border with no ember line, and UP
    // and RIGHT were dead from it - which is what an unfocused-looking row that
    // is really focused would look like. This is the pass that has to settle it,
    // because a reading taken on a CPU-starved emulator can be a stale frame: the
    // filter is chosen with the remote, the rows are walked to the bottom of the
    // panel, and every stop inside the list is checked for the one ring this app
    // paints. It holds - see the note this test carries in the file header.
    await pumpWatchSources(tester, sources: _mixedSources());

    final FocusNode directChip = _directChipNode(tester);
    directChip.requestFocus();
    await tester.pump();
    await pressDpad(tester, LogicalKeyboardKey.select, step: 'Direct');
    expect(
      find.text('2 sources found'),
      findsOneWidget,
      reason: 'precondition: the list is filtered down to the two direct links',
    );

    /// Walks down the list with the remote and checks every stop it makes inside
    /// it; answers how many of those stops there were.
    ///
    /// The check is the whole point of the pass: on a television the ring is the
    /// only thing that says where the remote is, so a row that holds focus and
    /// paints nothing is a row nobody can see themselves on.
    Future<int> walkRows(int presses) async {
      int rows = 0;
      for (int i = 0; i < presses; i++) {
        await pressDpad(tester, LogicalKeyboardKey.arrowDown, step: 'down$i');
        final FocusNode? node = FocusManager.instance.primaryFocus;
        final String? label = node?.debugLabel;
        if (label != 'WatchFirstSourceRow' && label != 'WatchSourceRow') {
          continue;
        }
        rows++;
        final Finder lit = find.byWidgetPredicate(
          (Widget w) => w is CardFocusRing && w.focused,
        );
        expect(
          lit,
          findsOneWidget,
          reason: 'a row holding the remote has to be the one control wearing the '
              'app\'s ring, and the sweep found it painting nothing at all',
        );
        expect(
          _sameBox(tester.getRect(lit), node!.rect),
          isTrue,
          reason: 'and the lit ring has to be painted over the row the remote is '
              'on, not beside it',
        );
      }
      return rows;
    }

    expect(
      await walkRows(6),
      greaterThanOrEqualTo(2),
      reason: 'precondition: the walk has to reach the rows, or the assertions '
          'inside it prove nothing',
    );

    // The way back up has to be open as well: the sweep measured UP from these
    // rows as a dead key.
    await pressDpad(tester, LogicalKeyboardKey.arrowUp, step: 'up');
    expect(
      _rowRingIsLit(tester, 'A Show 1080p 4.2 Mb/s'),
      isTrue,
      reason: 'UP from the last row of the filtered list has to move the remote '
          'back up the list',
    );

    // And the centre button has to start the row the ring is on, which is the
    // other half of what the sweep read: "OK then closed the sheet".
    await pressDpad(tester, LogicalKeyboardKey.arrowDown, step: 'back down');
    await pressDpad(tester, LogicalKeyboardKey.select, step: 'select');
    expect(
      find.text('player:A Show 720p 2.1 Mb/s'),
      findsOneWidget,
      reason: 'the row the filtered list put the remote on has to be the one the '
          'centre button starts',
    );
  });

  testWidgets('Left out of a source row leaves the list for the column beside '
      'it, and never lands on a copy-magnet action', (tester) async {
    // The row's own key handling claims Left only on the way out of its action,
    // and its comment says why: on the row itself Left is how focus leaves the
    // list for the column beside it. The 1.6.1 sweep read Left on a row as
    // landing on another row's copy-magnet button, which is not what the comment
    // describes. What it actually does is pinned here, for both kinds of row: the
    // magnet button is `skipTraversal`, so no arrow can reach one by search -
    // Right from its own row is the only way in - and Left steps out of the
    // panel into the information column.
    await pumpWatchSources(tester, sources: _magnetSources());

    for (final String row in <String>['Torrentio', 'Second Source']) {
      _rowNode(tester, row).requestFocus();
      await tester.pump();
      final FocusNode from = FocusManager.instance.primaryFocus!;
      await pressDpad(tester, LogicalKeyboardKey.arrowLeft, step: 'left $row');
      final FocusNode left = FocusManager.instance.primaryFocus!;

      expect(
        left.debugLabel,
        isNot('WatchSourceRowAction'),
        reason: 'Left from a row must not land on a row\'s copy-magnet action: '
            'that control is out of the traversal order, so the arrows cannot '
            'reach it at all',
      );
      expect(
        left.rect.right,
        lessThanOrEqualTo(from.rect.left),
        reason: 'Left has to leave the list for the column beside it, which is '
            'what the row\'s comment claims. It ended at ${left.rect}',
      );
    }
  });
}
