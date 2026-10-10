/// The popped surface must stay inside the television's viewable area, and its
/// details panel must be invisible to the page's scrolling.
///
/// `movie_card_focus_expansion_test.dart` pins what the pop does to *layout*
/// (nothing) and what it paints (one 1.15x surface growing from the card's
/// centre). This file pins the two consequences that only show up on the real
/// 960x540 television canvas:
///
/// 1. **The details must fit.** The surface is `box.height + extra` tall and
///    is scaled 1.15 about the card's centre, so a card sitting low in the
///    page paints its details past y=540 - the reported bug. The harness
///    proves the overflow is real (the *unclamped* painted bottom is computed
///    from the card's centre, the full surface height and the zoom, and must
///    exceed 540), then asserts the measured painted bounds - through the
///    paint transform - lie inside the window.
/// 2. **The panel never moves a scroll offset.** This second family is a
///    *regression guard*, not the finder of the reported bug: the pop lives
///    entirely in the root `Overlay` behind a pinned layout slot, so no
///    scroll disturbance is expected. Its value is that it fails loudly if
///    anyone ever puts the expansion back into layout - the walk comparison
///    starts two runs on the *same* card box with the *same* Down presses and
///    varies only whether the details panel exists (`expandedExtra` present
///    vs null), so any layout leakage shows up as different scroll offsets or
///    a different scroll extent.
///
/// The harness is the device's own window - 960x540 logical dp at density 320,
/// bound through `tester.view` via `pumpTelevision` - with the platform pinned
/// to the Android TV the device actually runs (the production card picks its
/// rail arrows from `defaultTargetPlatform`, and a Windows host would build
/// desktop-only focusables into the D-pad's path).
///
/// No test here touches the network: the movies' ids are not `tt...`, so the
/// card falls back to `MissingPoster` and the details widget skips its info
/// read - the seam `movie_rail_stagger_test.dart` stands on. The details'
/// synopsis placeholder pulses forever, so settling is explicit pumps and
/// `pumpAndSettle` is never used.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/models/addon/addon.dart';
import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/models/movie/movie_section.dart';
import 'package:zplay/services/theme/design_tokens.dart';
import 'package:zplay/widgets/common/card_focus_expansion.dart';
import 'package:zplay/widgets/common/focusable_card.dart';
import 'package:zplay/widgets/common/section_header.dart';
import 'package:zplay/widgets/movie/movie_card.dart';
import 'package:zplay/widgets/movie/movie_slider_section.dart';

import '../support/tv_nav_harness.dart';

/// The pop's expansion factor, mirrored from the widget's own `_popScale`
/// (lib/widgets/common/card_focus_expansion.dart) because the unclamped
/// scenario geometry has to be computed by hand.
const double _zoom = 1.15;

/// The window the television lays out against.
const Size _window = tvLogicalCanvas; // 960x540.

/// The rect [finder]'s render box actually paints at, with every paint
/// transform on the way up applied - including the pop's 1.15 scale and any
/// position the fix clamps it to. Same helper as
/// `movie_card_focus_expansion_test.dart`; duplicated because both files keep
/// it private.
Rect _paintedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject(finder) as RenderBox;
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

/// The popped surface: the one `DecoratedBox` the copy fills itself with.
Finder _surface() => find.descendant(
  of: find.byKey(CardFocusExpansion.copyKey),
  matching: find.byType(DecoratedBox),
);

/// The in-layout box of the card the remote is on, located by walking up from
/// the focused node to its `FocusableCard` - the widget both harness card
/// shapes share (`MovieCard` builds one; the walk's panel-less control card
/// is one), so the answer works in either run and cannot drift with widget
/// order while the pop is up (the overlay copy reuses the card's visual
/// inside the card's own element subtree, which would fool a plain
/// `find.text` ancestor query into matching twice).
Rect _focusedCardRect() {
  final node = FocusManager.instance.primaryFocus;
  expect(node, isNotNull, reason: 'precondition: something holds focus');
  final element = node!.context;
  expect(
    element,
    isNotNull,
    reason: 'precondition: the focused node is attached',
  );
  RenderObject? card;
  element!.visitAncestorElements((ancestor) {
    if (ancestor.widget is FocusableCard) {
      card = ancestor.findRenderObject();
      return false;
    }
    return true;
  });
  expect(
    card,
    isNotNull,
    reason: 'precondition: focus is on a card, not on the chrome',
  );
  final box = card! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// One real rail: the production `MovieSliderSection` over six movies whose
/// ids are not `tt...`, so nothing here reaches for the network.
///
/// `showSeeAll: false` removes the header's `See All` focusable so the only
/// things a D-pad can land on in this page are the chrome and the cards.
Widget _rail(String title) => MovieSliderSection(
  showSeeAll: false,
  section: MovieSection(
    title: title,
    subtitle: '',
    contentType: 'movie',
    addonBaseUrl: 'https://example.invalid',
    catalog: AddonCatalog(type: 'movie', id: 'viewport-probe'),
    movies: _movies(title),
  ),
);

List<Movie> _movies(String rail) => [
  for (var i = 0; i < 6; i++)
    Movie(
      id: 'vp-$rail-$i',
      name: '$rail $i',
      year: '2024',
      type: 'movie',
      addonBaseUrl: 'https://example.invalid',
    ),
];

/// The remote's starting point: a narrow, centred, autofocusing `Focus` -
/// deliberately *not* a `FocusableCard`, because the scroll assertions need
/// "no card focused" to mean exactly that no `MovieCard` (and therefore no
/// pop) is up. Its box (x 440..520) overlaps only rail one's middle card
/// (x 400..576), so a D-pad Down from it lands on that card deterministically.
Widget _chrome() => const SizedBox(
  height: 96,
  child: Center(
    child: Focus(autofocus: true, child: SizedBox(width: 80, height: 40)),
  ),
);

/// The page tests 1-4 run on: chrome + two *real* rails in one vertical
/// scroll view.
///
/// Geometry, at the 960-wide canvas with the default card density: chrome 96,
/// rail header 8 + 44, gap 12, poster card 176 x 307.58 - so rail one's cards
/// span y=160..467.6, fully on screen (focusing one scrolls nothing) but low
/// enough that a details surface of card-height + ~116 dp, scaled 1.15 from
/// the card's centre, paints past y=540. Rail two starts at y=491.6, putting
/// its cards below the fold and giving the page real scroll range.
Widget _page(ScrollController controller) => SingleChildScrollView(
  controller: controller,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [_chrome(), _rail('R1'), _rail('R2')],
  ),
);

/// The card for the walk's *panel-absent* run: structurally the same shape
/// `MovieCard` builds - a `FocusableCard` driving a `CardFocusExpansion` -
/// but with the expansion's details slot null, i.e. the pop with no panel
/// under it. Focus traversal sees the same widget depth and the same box (the
/// rail forces a tight 176 x 307.58 either way); the only variable against
/// the `MovieCard` run is whether `SizeTransition` ever mounts an extra.
Widget _bareCard(Movie movie) => FocusableCard(
  builder: (_, state) => CardFocusExpansion(
    focused: state.focused,
    expandedExtra: null,
    child: SizedBox.expand(
      child: Center(
        child: Text(movie.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ),
  ),
);

/// The walk's rail: `MovieSliderSection`'s exact vertical arithmetic (header,
/// 12 dp gap, card row sized from `MovieCardSizing`, 24 dp bottom padding,
/// 16 dp side padding, 16 dp separators) with the *card widget* injectable,
/// because `MovieSliderSection` hardcodes `MovieCard` and the walk needs the
/// same cards with `expandedExtra: null` for its control run. Both walk runs
/// share this rail, so only the panel differs between them.
class _ReplicaRail extends StatelessWidget {
  const _ReplicaRail({required this.title, required this.card});

  final String title;
  final Widget Function(Movie movie) card;

  @override
  Widget build(BuildContext context) {
    final sizing = MovieCardSizing.fromWidth(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: const EdgeInsets.only(bottom: ZplaySpacing.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title, count: 6),
          const SizedBox(height: ZplaySpacing.s12),
          SizedBox(
            height: sizing.totalHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: sizing.sidePadding),
              itemCount: 6,
              separatorBuilder: (context, index) =>
                  SizedBox(width: sizing.spacing),
              itemBuilder: (context, index) => SizedBox(
                width: sizing.cardWidth,
                child: card(_movies(title)[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The walk's page: same chrome, same rail arithmetic as [_page], but the
/// cards come from the injectable builder (real `MovieCard`s for the panel
/// run, [_bareCard]s for the control run).
Widget _walkPage(
  ScrollController controller, {
  required Widget Function(Movie movie) card,
}) => SingleChildScrollView(
  controller: controller,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _chrome(),
      _ReplicaRail(title: 'R1', card: card),
      _ReplicaRail(title: 'R2', card: card),
    ],
  ),
);

void main() {
  // No `debugDefaultTargetPlatformOverride`: the framework verifies
  // foundation vars at the end of the test body, before any teardown can
  // clear the override. The windows test host therefore builds the rail's
  // desktop arrows - which sit outside the window (x -60..-12 / 972..1020)
  // and lose every directional search in this file to the cards, and if one
  // ever won, the focus preconditions below would fail loudly. The television
  // shape comes from `pumpTelevision` and `tester.view`, not the platform.
  setUp(() {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });
  tearDown(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  /// Sends [key] and settles fully: enough frames for focus to land, the copy
  /// to mount on the following frame, the pop's 200 ms zoom (and the clamp
  /// displacement, which rides the same progress) to finish, any focus-driven
  /// `ensureVisible` animation to land - and one more frame for the
  /// *previous* card's copy to unmount: its pop finishes shrinking, retires
  /// in a post-frame callback, and the rebuild that takes the copy down is
  /// the following frame. Without it, an assertion right after a focus move
  /// sees both the outgoing copy and the incoming one.
  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  /// Mounts `page`, waits out the rails' entry stagger, and checks the rest
  /// state: focus on the chrome, no pop up.
  Future<void> mount(WidgetTester tester, Widget page) async {
    await pumpTelevision(tester, page);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      FocusManager.instance.primaryFocus,
      isNotNull,
      reason: 'precondition: the remote starts on the chrome',
    );
    expect(
      find.byKey(CardFocusExpansion.copyKey),
      findsNothing,
      reason: 'precondition: nothing is popped at rest',
    );
  }

  testWidgets('scenario sanity: the low rail\'s popped details paint past the '
      'window bottom', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await mount(tester, _page(controller));

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(
      find.byKey(CardFocusExpansion.copyKey),
      findsOneWidget,
      reason:
          'precondition: Down from the chrome focused the low rail\'s '
          'middle card and its pop went up',
    );

    // The unclamped painted bottom, from the card's own centre: the surface
    // sits at the card's box, is `card + extra` tall once open, and the
    // transform scales it 1.15 about the box centre - so the painted bottom
    // is center.dy + (H - h/2) * zoom. Nothing here reads the copy's
    // position (exactly what a fix clamps), so this value proves the
    // *scenario* overflows regardless of whether the clamp has landed.
    final card = _focusedCardRect();
    final surface = tester.getSize(_surface().first);
    final unclampedBottom =
        card.center.dy + (surface.height - card.height / 2) * _zoom;

    debugPrint(
      '[viewport] unclamped painted bottom = '
      '${unclampedBottom.toStringAsFixed(1)} (window bottom = '
      '${_window.height.toStringAsFixed(1)})',
    );

    expect(
      unclampedBottom,
      greaterThan(_window.height),
      reason:
          'the harness must genuinely reproduce the reported overflow: '
          'this card\'s details, painted from its centre at 1.15x, run past '
          'the bottom of the screen. Got ${unclampedBottom.toStringAsFixed(1)}',
    );
  });

  testWidgets('the popped surface stays inside the viewable area', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await mount(tester, _page(controller));

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(
      find.byKey(CardFocusExpansion.copyKey),
      findsOneWidget,
      reason:
          'precondition: the low rail\'s middle card is focused and its '
          'pop is up',
    );
    expect(
      find.textContaining('2024 · Movie'),
      findsOneWidget,
      reason:
          'precondition: the details are fully grown - the sanity value '
          'below measures the fully open surface',
    );

    final card = _focusedCardRect();
    final surface = tester.getSize(_surface().first);
    final unclampedBottom =
        card.center.dy + (surface.height - card.height / 2) * _zoom;
    debugPrint(
      '[viewport] unclamped painted bottom = '
      '${unclampedBottom.toStringAsFixed(1)} (window bottom = '
      '${_window.height.toStringAsFixed(1)})',
    );
    expect(
      unclampedBottom,
      greaterThan(_window.height),
      reason:
          'precondition: without the clamp this card paints its details '
          'past y=${_window.height}',
    );

    // What the eye gets: the surface's layout box through every paint
    // transform - the 1.15 scale, and any position the fix clamps it to.
    final painted = _paintedRect(tester, _surface().first);
    debugPrint('[viewport] painted surface = $painted');

    expect(
      painted.left,
      greaterThanOrEqualTo(-0.5),
      reason: 'the surface must not paint past the left edge: $painted',
    );
    expect(
      painted.top,
      greaterThanOrEqualTo(-0.5),
      reason: 'the surface must not paint past the top edge: $painted',
    );
    expect(
      painted.right,
      lessThanOrEqualTo(_window.width + 0.5),
      reason: 'the surface must not paint past the right edge: $painted',
    );
    expect(
      painted.bottom,
      lessThanOrEqualTo(_window.height + 0.5),
      reason:
          'the whole point of the fix: the details a user selects must '
          'show up inside the viewable area, not below it. Unclamped this '
          'card paints to ${unclampedBottom.toStringAsFixed(1)}. Got $painted',
    );
  });

  testWidgets(
    'the right-most card\'s pop stays within the window horizontally',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await mount(tester, _page(controller));

      // Chrome -> rail one's middle card -> two Rights: the card whose box ends
      // flush with the window's right edge (16 dp side padding + 4 x (176 + 16)
      // puts its box at 784..960). Its 1.15x pop grows ~13 dp past x=960
      // unclamped.
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        find.byKey(CardFocusExpansion.copyKey),
        findsOneWidget,
        reason:
            'precondition: focus walked to the right end of the rail and '
            'the pop is up',
      );

      final card = _focusedCardRect();
      expect(
        card.right,
        greaterThan(_window.width - 1.0),
        reason:
            'precondition: this really is the rail\'s right-most card, '
            'flush against the window edge (box right = ${card.right})',
      );
      final surface = tester.getSize(_surface().first);
      final unclampedRight = card.center.dx + surface.width / 2 * _zoom;
      debugPrint(
        '[viewport] unclamped painted right = '
        '${unclampedRight.toStringAsFixed(1)} (window right = '
        '${_window.width.toStringAsFixed(1)})',
      );
      expect(
        unclampedRight,
        greaterThan(_window.width),
        reason:
            'the harness must genuinely reproduce a horizontal overflow '
            'too: unclamped this card paints to '
            'x=${unclampedRight.toStringAsFixed(1)}',
      );

      final painted = _paintedRect(tester, _surface().first);
      debugPrint('[viewport] painted surface = $painted');
      expect(
        painted.left,
        greaterThanOrEqualTo(-0.5),
        reason: 'the surface must not paint past the left edge: $painted',
      );
      expect(
        painted.right,
        lessThanOrEqualTo(_window.width + 0.5),
        reason:
            'the pop of the card nearest the right edge must stay inside '
            'the window horizontally. Got $painted',
      );
    },
  );

  testWidgets('the pop never changes how far the page can scroll', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await mount(tester, _page(controller));

    final pristine = controller.position.maxScrollExtent;
    expect(
      pristine,
      greaterThan(0),
      reason:
          'precondition: the page has scroll range (second rail below '
          'the fold)',
    );

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(
      find.byKey(CardFocusExpansion.copyKey),
      findsOneWidget,
      reason: 'precondition: the pop is fully up',
    );

    expect(
      controller.position.maxScrollExtent,
      pristine,
      reason:
          'the expansion lives in the root Overlay and must never change '
          'the scroll extent: with no pop the page scrolls to $pristine, '
          'with the pop up it scrolls to '
          '${controller.position.maxScrollExtent}',
    );
  });

  testWidgets('the details panel never changes how the D-pad scrolls the '
      'page', (tester) async {
    // Regression guard, stated plainly: the pop lives entirely in the root
    // Overlay behind a pinned layout slot, so a scroll disturbance is *not*
    // expected - this does not find the reported bug. Its value is that it
    // fails loudly if anyone ever puts the expansion back into layout.
    //
    // Like for like: both runs mount the identical page and start on the
    // identical card box, take the identical fixed sequence of four Down
    // presses, and differ in exactly one variable - run A's cards carry the
    // details panel (the real `MovieCard`), run B's carry the same expansion
    // with `expandedExtra: null`.
    final controllerA = ScrollController();
    final controllerB = ScrollController();
    addTearDown(controllerA.dispose);
    addTearDown(controllerB.dispose);

    Future<({Rect start, double maxExtent, List<double> offsets})> walk(
      WidgetTester tester,
      ScrollController controller, {
      required bool panel,
    }) async {
      // Unrecorded setup: Down from the chrome lands on the low rail's
      // middle card in both runs; the pop is settled before any press is
      // recorded (the clamp's displacement rides the pop's progress).
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(
        find.byKey(CardFocusExpansion.copyKey),
        findsOneWidget,
        reason: 'precondition: the pop went up in this run',
      );
      expect(
        find.textContaining('2024 · Movie'),
        panel ? findsOneWidget : findsNothing,
        reason: panel
            ? 'precondition: run A carries the details panel'
            : 'precondition: run B carries no details panel',
      );

      // The premise of the comparison: both walks start on this same box.
      final start = _focusedCardRect();

      final offsets = <double>[];
      for (var i = 0; i < 4; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
        offsets.add(controller.position.pixels);
      }
      final result = (
        start: start,
        maxExtent: controller.position.maxScrollExtent,
        offsets: offsets,
      );
      debugPrint(
        '[viewport] walk (panel: $panel): start=${result.start}, '
        'maxExtent=${result.maxExtent}, offsets=${result.offsets}',
      );
      return result;
    }

    // Run A: real cards, details panel present.
    await mount(
      tester,
      _walkPage(controllerA, card: (m) => MovieCard(movie: m)),
    );
    final a = await walk(tester, controllerA, panel: true);

    // Run B: structurally identical cards, panel slot null. Scroll state can
    // carry over from run A within one test (the binding's restoration), so
    // pin the control run to the top before walking it.
    await mount(tester, _walkPage(controllerB, card: _bareCard));
    controllerB.jumpTo(0);
    await tester.pump();
    final b = await walk(tester, controllerB, panel: false);

    expect(
      b.start,
      a.start,
      reason:
          'the premise of this comparison: both walks start focused on '
          'the identical card box - if the panel moved layout, the start '
          'boxes would already differ',
    );
    expect(
      b.maxExtent,
      a.maxExtent,
      reason: 'the details panel must never change the page\'s scroll range',
    );
    expect(
      b.offsets,
      a.offsets,
      reason:
          'the same D-pad presses from the same start must produce the '
          'same scroll offsets with and without the details panel - if they '
          'differ, the expansion has leaked into layout and is moving what '
          'ensureVisible measures',
    );
    expect(
      a.offsets.first,
      greaterThan(0),
      reason:
          'precondition: the recorded walk actually scrolls (the second '
          'rail\'s cards are below the fold), so this comparison is not two '
          'lists of zeros. Got ${a.offsets}',
    );
  });
}
