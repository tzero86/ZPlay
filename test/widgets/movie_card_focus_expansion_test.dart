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
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/models/movie/movie.dart';
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
      tester.getSize(find.byType(CompositedTransformFollower)),
      before[1].size,
      reason: 'the overlay copy must be laid out at the card\'s own box',
    );

    // Invariant 2: the copy that expands is not painted inside the row's own
    // widget order - where a later sibling (the right neighbour, the next
    // rail) would paint over it - but through the overlay follower, which
    // puts it above every neighbour.
    final expanded = find.descendant(
      of: find.byType(CompositedTransformFollower),
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

    // And it genuinely pops: 1.15x the card, grown from the *card's* centre so
    // it eats into both neighbours evenly. The copy is the card's whole
    // subtree, so its Column is the card's own box under the pop's transform.
    final popped = _paintedRect(
      tester,
      find.descendant(
        of: find.byType(CompositedTransformFollower),
        matching: find.byType(Column),
      ),
    );
    final cardBefore = before[1].rect;
    expect(popped.width, closeTo(cardBefore.width * 1.15, 0.5),
        reason: 'the pop is roughly 1.15x the card');
    expect(popped.height, closeTo(cardBefore.height * 1.15, 0.5));
    expect(popped.center.dx, closeTo(cardBefore.center.dx, 0.5),
        reason: 'growth is centred on the card: it must split between both '
            'neighbours evenly');
    expect(popped.center.dy, closeTo(cardBefore.center.dy, 0.5));
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
}
