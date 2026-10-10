/// The focus pop changes what is painted, never what is laid out.
///
/// `CardFocusExpansion` answers a focused card by painting an expanded copy of
/// it in the app's `Overlay`, above every neighbour, while the card's layout
/// box stays exactly where it was. The layout box is the expensive invariant:
/// a card whose box moves re-flows the rail under the D-pad, which is the
/// jitter this project spent weeks killing (`card_anatomy_test.dart` pins the
/// same fact for the ring; this pins it for the pop, with neighbours present).
///
/// The second assertion family is that the pop *exists* and grows from the
/// centre - a no-op implementation would keep every box still too.
///
/// The third is that it *tracks* the card. The copy's position is read from the
/// card's own render box every frame it is visible, rather than from a layer
/// transform the card recorded when it last painted - and a card inside a
/// scrolling list sits inside a repaint boundary the list inserts for it, so a
/// scroll moves that boundary without repainting the card and a cached transform
/// goes stale by exactly the distance scrolled. That is the reported "the expand
/// box renders like three rows above the movie selected". The invariant is
/// pinned here; the device case that motivated it does not reproduce in a widget
/// test, where nothing caches a layer.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/widgets/common/card_focus_expansion.dart';
import 'package:zplay/widgets/movie/movie_card.dart';

/// The rect [finder]'s render box actually paints at, with every paint
/// transform on the way up applied. `WidgetController.getRect` reports the
/// *layout* rect - exactly what must not move - while this reports what the
/// screen shows, which is exactly what must.
Rect _paintedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject(finder) as RenderBox;
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

/// Whether [copy]'s render subtree is attached outside [scope]'s render box.
/// Widgets may nest anywhere - the overlay copy is even an element descendant
/// of the card - but paint order follows the *render* tree, and a copy rendered
/// inside the card would be painted under the next sibling along the row.
bool _renderedOutside(WidgetTester tester, Finder copy, Finder scope) {
  final scopeBox = tester.renderObject(scope);
  RenderObject? node = tester.renderObject(copy);
  while (node != null) {
    if (identical(node, scopeBox)) return false;
    node = node.parent;
  }
  return true;
}

void main() {
  // `onShowFocusHighlight` is only reported in the traditional highlight mode,
  // which is what a D-pad television is. Force it so focus reads the same in a
  // widget test as it does on the device.
  setUp(() {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });
  tearDown(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  Movie movie(String id) => Movie(
        id: id,
        name: 'Title $id',
        year: '2024',
        type: 'movie',
        addonBaseUrl: 'test',
      );

  /// Three cards side by side, the middle one with a neighbour to eat into on
  /// both sides - the case the pop exists for.
  ///
  /// Deliberately not wrapped in fixed cells: the row gives each card only a
  /// height to fill and lets its width come from its own content, which is the
  /// dimension a careless focus treatment actually inflates (a border or
  /// padding that appears on focus widens the card and re-flows the row).
  Widget host({VoidCallback? onTap}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: 340,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (index, id) in ['a', 'b', 'c'].indexed) ...[
                    if (index > 0) const SizedBox(width: 16),
                    MovieCard(movie: movie(id), onTap: onTap ?? () {}),
                  ],
                ],
              ),
            ),
          ),
        ),
      );

  /// Tab reaches the first card, arrowRight walks to the middle one - the same
  /// keys a remote's D-pad sends - and lands the pop *mid-animation*: the copy
  /// mounts on the frame after focus lands, and its first animation tick comes
  /// after that.
  Future<void> focusMiddleCard(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
  }

  testWidgets('a focused card pops over its neighbours without moving one '
      'layout box', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    final cards = find.byType(MovieCard);
    expect(cards, findsNWidgets(3), reason: 'precondition: the row of cards');

    final before = [
      for (var i = 0; i < 3; i++)
        (rect: tester.getRect(cards.at(i)), size: tester.getSize(cards.at(i))),
    ];

    // The middle card's artwork, which is what the "does it pop" assertions
    // below measure: the pop's surface is taller than the card on purpose, so
    // the card is measured inside it rather than as the whole copy.
    final artBefore = tester.getRect(
      find.descendant(of: cards.at(1), matching: find.byType(AspectRatio)),
    );

    await focusMiddleCard(tester);

    // Invariant 1: focus changes paint, not layout. Every card - the focused
    // one and both neighbours - keeps the box it had while the pop animates
    // and once it has settled.
    void expectBoxesStill(String when) {
      for (var i = 0; i < 3; i++) {
        expect(
          tester.getRect(cards.at(i)),
          before[i].rect,
          reason: 'card $i moved $when - the pop must never touch a layout box',
        );
        expect(
          tester.getSize(cards.at(i)),
          before[i].size,
          reason: 'card $i resized $when',
        );
      }
    }

    expectBoxesStill('mid-pop');
    await tester.pump(const Duration(milliseconds: 300));
    expectBoxesStill('once the pop settled');

    // The copy is laid out at the card's exact box before it scales, so at
    // scale 1.0 it lands pixel-on-top of the card it replaces.
    expect(
      tester.getSize(find.byKey(CardFocusExpansion.copyKey)),
      before[1].size,
      reason: 'the overlay copy must be laid out at the card\'s own box',
    );

    // Invariant 2: the copy that expands is not painted inside the row's own
    // widget order - where a later sibling (the right neighbour, the next
    // rail) would paint over it - but through the overlay follower, which
    // puts it above every neighbour.
    final expanded = find.descendant(
      of: find.byKey(CardFocusExpansion.copyKey),
      matching: find.byType(AspectRatio),
    );
    expect(
      expanded,
      findsOneWidget,
      reason: 'the focused card must paint its expanded copy through the '
          'overlay follower, above its neighbours',
    );
    expect(
      _renderedOutside(tester, expanded, cards.at(1)),
      isTrue,
      reason: 'a copy rendered inside the row\'s own paint order would sit '
          'under its right neighbour - exactly the bug the pop exists to avoid',
    );

    // And it genuinely pops: the card's own visual is drawn 1.15x, grown from
    // the *card's* centre so it eats into both neighbours evenly.
    //
    // Measured on the card's artwork - the only `AspectRatio` in the copy -
    // rather than on the copy's first `Column`: that column is now the popped
    // card's single surface, which carries the extra info under the card and is
    // therefore taller than the card by design. The artwork is inside the card,
    // so its painted rect is the card's own box under the pop's transform.
    final popped = _paintedRect(tester, expanded);
    final cardBefore = before[1].rect;
    Offset scaled(Offset point) =>
        cardBefore.center + (point - cardBefore.center) * 1.15;
    expect(
      (popped.topLeft - scaled(artBefore.topLeft)).distance,
      lessThan(0.5),
      reason: 'the pop is 1.15x the card, grown from the card\'s own centre - '
          'which is why it splits between both neighbours evenly',
    );
    expect(
      (popped.bottomRight - scaled(artBefore.bottomRight)).distance,
      lessThan(0.5),
      reason: 'the pop is a uniform scale about the card\'s centre: the card\'s '
          'painted bottom is half the growth below its box, no more',
    );
    expect(popped.center.dx, closeTo(cardBefore.center.dx, 0.5),
        reason: 'growth is centred on the card: it must split between both '
            'neighbours evenly');
    expect(popped.width, closeTo(artBefore.width * 1.15, 0.5),
        reason: 'the card is drawn 15% wider, not moved');
  });

  testWidgets('the expanded copy does not swallow taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(onTap: () => taps += 1));
    await tester.pump();

    await focusMiddleCard(tester);

    // The overlay copy covers the card and its surroundings; it is painted for
    // the eye only, and the tap must still land on the card underneath.
    await tester.tap(find.byType(MovieCard).at(1));
    await tester.pump();
    expect(taps, 1,
        reason: 'a popped card that eats taps is unopenable from the remote\'s '
            'centre key path and from a pointer alike');
  });

  testWidgets('a focused card grows its extras under it, and moves nothing',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    final cards = find.byType(MovieCard);
    final before = [for (var i = 0; i < 3; i++) tester.getRect(cards.at(i))];

    // At rest a card grows nothing. The extras are mounted by the overlay copy,
    // which exists only while the pop is up - so a rail nobody is pointing at
    // pays for none of them and reads nothing for them.
    expect(
      find.textContaining('2024 · Movie'),
      findsNothing,
      reason: 'the extras must not be in the layout of a card at rest',
    );

    await focusMiddleCard(tester);
    await tester.pump(const Duration(milliseconds: 300));

    final facts = find.textContaining('2024 · Movie');
    expect(
      facts,
      findsOneWidget,
      reason: 'the focused card grows the metadata the catalog does not carry',
    );

    // One surface, not a card with a detached panel under it. The popped card's
    // edges are its *card's* edges - the same width and the same top, with no
    // overhang on either side - and the extra is inside them, flush against the
    // card's painted bottom.
    //
    // This is the reported defect: the panel used to be 25% wider on each side
    // and to start 8 dp below the card's painted bottom, in its own box with its
    // own background, which from ten feet reads as another row rather than as
    // the selected card growing.
    final surface = _paintedRect(
      tester,
      find
          .descendant(
            of: find.byKey(CardFocusExpansion.copyKey),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final cardPainted = Rect.fromCenter(
      center: before[1].center,
      width: before[1].width * 1.15,
      height: before[1].height * 1.15,
    );
    expect(surface.left, closeTo(cardPainted.left, 0.5),
        reason: 'one surface: no overhang past the card\'s own left edge');
    expect(surface.right, closeTo(cardPainted.right, 0.5),
        reason: 'one surface: no overhang past the card\'s own right edge');
    expect(surface.top, closeTo(cardPainted.top, 0.5),
        reason: 'the artwork is the *top* of the surface, not a card with a '
            'panel hung above it');
    expect(surface.bottom, greaterThan(cardPainted.bottom),
        reason: 'the surface carries the extra under the card');

    final extra = _paintedRect(
      tester,
      find.descendant(
        of: find.byKey(CardFocusExpansion.copyKey),
        matching: find.byType(SizeTransition),
      ),
    );
    expect(extra.left, closeTo(cardPainted.left, 0.5));
    expect(extra.right, closeTo(cardPainted.right, 0.5));
    expect(extra.top, closeTo(cardPainted.bottom, 0.5),
        reason: 'the extra sits directly under the card: no gap, and nothing '
            'measured from a box that is not the card\'s own');

    // And no second edge. The surface the popped card is drawn on is a fill and
    // its drop shadow; the one border inside the copy is the card's ring - the
    // panel's own hairline was the second edge the brief forbids.
    expect(
      find.descendant(
        of: find.byKey(CardFocusExpansion.copyKey),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).border != null,
        ),
      ),
      findsOneWidget,
      reason: 'the popped card draws one edge - its focus ring - not a ring and '
          'a box around the extra',
    );

    // It hangs clear of the card's *painted* bottom edge. The copy scales around
    // the card's centre, so its painted bottom sits half the growth lower than
    // the box's - and a panel measured from the box would cover its bottom edge.
    expect(
      _paintedRect(tester, facts).top,
      greaterThanOrEqualTo(before[1].bottom),
      reason: 'the extras start below the card they belong to, not over it',
    );

    // The whole point of growing a *copy*: not one box moved, including the
    // neighbour whose space the extras paint over.
    for (var i = 0; i < 3; i++) {
      expect(
        tester.getRect(cards.at(i)),
        before[i],
        reason: 'card $i moved when its neighbour grew',
      );
    }
  });
}
