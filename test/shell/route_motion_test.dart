/// Guards the push motion of [FadeThroughRoute].
///
/// It used to be a 380 ms circular reveal: a `ClipPath` mask opened from the
/// tap point while the page swelled from 0.95 scale, so every push announced
/// its own machinery. The design charter (`docs/REDESIGN_DIRECTION.md`) retires
/// that theatre: a route now does one cross-fade, which is what the first test
/// pins (a `FadeTransition` on the standard curve, mid-flight, and no clipper
/// anywhere above the page).
///
/// The second test pins the reduced-motion branch. `ZplayMotion` collapses
/// durations at the call site, but a route's duration is fixed when the route
/// is built, before it has a context, so the branch lives in the transition
/// builder instead: the fade disappears and the page is shown at once, while
/// the duration (and therefore [PerfMonitor]'s measurement of it) stays the
/// same. What must not survive is motion, not the clock.
///
/// The route stays opaque, so the last test pins the other half of replacing a
/// transition: `Navigator.pop` still unwinds to the screen underneath.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/theme/design_tokens.dart';
import 'package:zplay/utils/navigation/route_transitions.dart';

/// The pushed page's own words. Distinct from the screen underneath so a
/// finder can never match both.
const String _pushedLabel = 'the next screen';

/// The screen the route is pushed over.
const String _baseLabel = 'the screen underneath';

/// Marks the pushed page itself, so a finder scoped to it can only see the
/// transition the route built around that page.
const Key _pushedKey = ValueKey<String>('pushed-page');

Widget _app(String label) => MaterialApp(home: Scaffold(body: Text(label)));

NavigatorState _navigator(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator).first);

/// Pushes [route] the way the app does and spends one frame installing it.
///
/// One pump only: the SDK's route tests pump twice because the push installs
/// the route's overlay entry on the frame after the call, and everything the
/// tests below assert about the transition is read on the frame after that.
Future<NavigatorState> _push(WidgetTester tester, Route<void> route) async {
  final navigator = _navigator(tester);
  navigator.push(route);
  await tester.pump();
  return navigator;
}

Finder _ancestorOfPushed(Type type) =>
    find.ancestor(of: find.byKey(_pushedKey), matching: find.byType(type));

void main() {
  testWidgets('a pushed FadeThroughRoute cross-fades instead of clipping', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_baseLabel));

    final route = FadeThroughRoute(
      page: const Scaffold(key: _pushedKey, body: Text(_pushedLabel)),
    );
    expect(
      route.opaque,
      isTrue,
      reason: 'an opaque route lets the old screen stop painting once it lands',
    );

    await _push(tester, route);
    // A third of the way into ZplayMotion.slow: the fade is provably in flight,
    // so what the test finds is the transition and not a settled page.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(_pushedLabel), findsOneWidget);

    // The nearest FadeTransition above the page is the route's own; nothing
    // from Material is involved in a PageRouteBuilder's transition subtree.
    final fadeFinder = _ancestorOfPushed(FadeTransition);
    expect(fadeFinder, findsWidgets);
    final fade = tester.widget<FadeTransition>(fadeFinder.first);

    expect(
      fade.opacity,
      isA<CurvedAnimation>(),
      reason: 'one fade on the shared curve, not the old organic cubic tail',
    );
    expect((fade.opacity as CurvedAnimation).curve, ZplayMotion.standard);
    expect(fade.opacity.value, greaterThan(0.0));
    expect(
      fade.opacity.value,
      lessThan(1.0),
      reason: 'the page is mid-fade, which is the whole of the transition now',
    );

    expect(
      _ancestorOfPushed(ClipPath),
      findsNothing,
      reason: 'the reveal mask is gone; nothing clips the incoming page',
    );
  });

  testWidgets('reduced motion shows the page without a fade', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        // The override has to live inside the app: `MaterialApp` establishes
        // its own MediaQuery above the Navigator, so a MediaQuery wrapped
        // around it would never reach the route. `builder` runs below that
        // MediaQuery and above the Navigator, which is exactly where the
        // route's transition builder looks.
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(body: Text(_baseLabel)),
      ),
    );

    final route = FadeThroughRoute(
      page: const Scaffold(key: _pushedKey, body: Text(_pushedLabel)),
    );
    await _push(tester, route);
    await tester.pump(const Duration(milliseconds: 100));

    // Visible on the first frames rather than at the end of the fade: with the
    // animation suppressed there is nothing to wait for.
    expect(find.text(_pushedLabel), findsOneWidget);
    expect(
      route.animation!.value,
      lessThan(1.0),
      reason:
          'still mid-transition, so the page being fully there on this frame '
          'is the reduced-motion branch and not a finished animation',
    );
    expect(
      _ancestorOfPushed(FadeTransition),
      findsNothing,
      reason: 'reduced motion means no visual motion, not a faster fade',
    );
    expect(_ancestorOfPushed(ClipPath), findsNothing);
    expect(
      route.transitionDuration,
      ZplayMotion.slow,
      reason:
          'the duration is settled before the route has a context, and keeping '
          'it fixed keeps PerfMonitor route timings comparable',
    );
  });

  testWidgets('popping the route returns to the screen underneath', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_baseLabel));

    final navigator = await _push(
      tester,
      FadeThroughRoute(
        page: const Scaffold(key: _pushedKey, body: Text(_pushedLabel)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(_pushedLabel), findsOneWidget);
    expect(find.text(_baseLabel), findsNothing);
    expect(navigator.canPop(), isTrue);

    navigator.pop();
    await tester.pumpAndSettle();

    expect(find.text(_pushedLabel), findsNothing);
    expect(find.text(_baseLabel), findsOneWidget);
    expect(
      navigator.canPop(),
      isFalse,
      reason: 'the route left the history instead of stacking another screen',
    );
  });
}
