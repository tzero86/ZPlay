/// Guards the preview as a card carries it.
///
/// The gate's own tests cover the dwell policy in isolation. This one mounts
/// the whole card, because the bug that shipped the feature without a trailer
/// was not in the gate: it was that the card handed the gate a key that was
/// never there, so the gate dutifully resolved nothing and the preview never
/// appeared.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/widgets/movie/movie_card.dart';
import 'package:zplay/widgets/movie/trailer_preview.dart';

void main() {
  setUp(() {
    DeviceProfile.debugSetTelevision(value: false);
    // A mouse hover only registers while the focus manager is in the
    // traditional highlight mode; the automatic strategy reads a touch
    // device and suppresses the hover highlight entirely.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    TrailerPreview.debugBuilder = (key) => ColoredBox(
      key: ValueKey<String>('trailer-preview-$key'),
      color: Colors.red,
    );
  });

  tearDown(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    DeviceProfile.debugSetTelevision(value: false);
    TrailerPreview.debugBuilder = null;
  });

  /// A card whose movie carries [trailerKey], hovered the way a pointer
  /// hovers it.
  Future<void> hoverCard(WidgetTester tester, {required Movie movie}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 200, child: MovieCard(movie: movie)),
          ),
        ),
      ),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(MovieCard)));
    await tester.pump();
  }

  testWidgets('a card with a catalog trailer starts a preview on hover', (
    tester,
  ) async {
    // The catalog names the trailer; the card must hand that key to the
    // gate rather than asking for one.
    final movie = Movie.fromJson({
      'id': 'tt34384900',
      'name': 'Love of Your Life',
      'type': 'movie',
      'trailers': [
        {'source': 'HzGx48E64Xg', 'type': 'Trailer'},
      ],
    }, 'https://v3-cinemeta.strem.io');

    expect(movie.trailerKey, 'HzGx48E64Xg');

    await hoverCard(tester, movie: movie);
    await tester.pump(const Duration(milliseconds: 1300));

    expect(
      find.byKey(const ValueKey<String>('trailer-preview-HzGx48E64Xg')),
      findsOneWidget,
    );
  });

  testWidgets('a card with no trailer never starts one', (tester) async {
    final movie = Movie(
      id: 'tt1',
      name: 'Nothing Here',
      type: 'movie',
      addonBaseUrl: 'https://example.test',
    );

    await hoverCard(tester, movie: movie);
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.byKey(const ValueKey<String>('trailer-preview-HzGx48E64Xg')),
      findsNothing,
    );
  });

  testWidgets('a television never starts one', (tester) async {
    DeviceProfile.debugSetTelevision(value: true);
    final movie = Movie.fromJson({
      'id': 'tt34384900',
      'name': 'Love of Your Life',
      'type': 'movie',
      'trailers': [
        {'source': 'HzGx48E64Xg', 'type': 'Trailer'},
      ],
    }, 'https://v3-cinemeta.strem.io');

    await hoverCard(tester, movie: movie);
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.byKey(const ValueKey<String>('trailer-preview-HzGx48E64Xg')),
      findsNothing,
    );
  });
}
