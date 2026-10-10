/// Guards the trailer modal's own behaviour: what it is made of, how it is
/// dismissed, where it sits in the window, and the fallback it must offer when
/// the embed cannot start.
///
/// **What this cannot cover.** There is no platform webview under `flutter
/// test`, so no frame here proves that a trailer *plays*. What is asserted is
/// everything around that: `TrailerModal.debugHost` answers the two platform
/// questions, and the modal is checked with the embed unavailable - which is
/// exactly the state a machine without the WebView2 runtime reaches in
/// production.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/common/trailer_modal.dart';

/// Answers [TrailerHost] for a platform a widget test does not have.
class _FakeHost implements TrailerHost {
  _FakeHost({required this.embedAvailable});

  final bool embedAvailable;

  /// Every URL the fallback handed to the browser, in order.
  final List<Uri> launched = <Uri>[];

  @override
  Future<bool> get canEmbed async => embedAvailable;

  @override
  Future<bool> launchExternal(Uri uri) async {
    launched.add(uri);
    return true;
  }
}

const String _key = 'dQw4w9WgXcQ';
const String _title = 'A Trailer Title';

/// The host the wrapper's iframe must point at, spelled out rather than shared
/// with the widget: a test that imports the constant under test cannot fail.
const String _youtubeOrigin = 'https://www.youtube-nocookie.com';

final Uri _watchUri = Uri.https('www.youtube.com', '/watch', {'v': _key});

void main() {
  late _FakeHost host;

  setUp(() {
    host = _FakeHost(embedAvailable: true);
    TrailerModal.debugHost = host;
  });

  tearDown(() => TrailerModal.debugHost = null);

  /// Pumps a page with one trailer control and presses it, the way the hero
  /// does. Opened through `show` rather than by pumping the widget directly: the
  /// route is where the dismissal and the barrier live.
  ///
  /// `settle` is false for the case whose loading state never ends under
  /// `flutter test` - `pumpAndSettle` waits for frames to stop and a spinner
  /// never does.
  Future<void> openTrailer(
    WidgetTester tester, {
    Size window = const Size(1280, 720),
    bool settle = true,
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => TrailerModal.show(
                  context,
                  trailerKey: _key,
                  title: _title,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  group('youtubeKeyFromUrl', () {
    test('reads the key out of every YouTube video URL a link can carry', () {
      expect(
        TrailerModal.youtubeKeyFromUrl('https://www.youtube.com/watch?v=$_key'),
        _key,
      );
      expect(TrailerModal.youtubeKeyFromUrl('https://youtu.be/$_key'), _key);
      expect(
        TrailerModal.youtubeKeyFromUrl(
          'https://www.youtube-nocookie.com/embed/$_key?autoplay=1',
        ),
        _key,
      );
      expect(
        TrailerModal.youtubeKeyFromUrl('https://m.youtube.com/shorts/$_key'),
        _key,
      );
    });

    test('leaves a search, another host and a lookalike to the browser', () {
      // Stremio links a trailer under a *category*, so the row can hold a
      // search, a channel or a video on someone else's site. Only a key this
      // modal can embed is its business.
      expect(TrailerModal.youtubeKeyFromUrl('ytsearch:Dune trailer'), isNull);
      expect(TrailerModal.youtubeKeyFromUrl('https://vimeo.com/12345'), isNull);
      expect(
        TrailerModal.youtubeKeyFromUrl(
          'https://youtube.com.evil.test/watch?v=$_key',
        ),
        isNull,
      );
      expect(
        TrailerModal.youtubeKeyFromUrl('https://www.youtube.com/watch?v=short'),
        isNull,
      );
    });
  });

  group('the wrapper the embed lives in', () {
    test('frames YouTube, not the wrapper\'s own origin', () {
      final html = TrailerModal.debugWrapperHtml(_key);

      // The document is served from `https://trailer.zplay.local`, so an iframe
      // rooted there asks the local host mapping for a file that does not exist.
      // That shipped once and rendered a page-load error inside the stage.
      expect(html, contains('src="$_youtubeOrigin/embed/$_key'));
      expect(html, isNot(contains('src="https://trailer.zplay.local')));
      expect(html, contains('autoplay=1'));
      expect(html, contains('playsinline=1'));
      expect(html, contains('rel=0'));
      // The origin is what stops YouTube refusing the request, so the document
      // must ask for exactly that much referrer and no less.
      expect(html, contains('referrerpolicy="strict-origin-when-cross-origin"'));
    });

    test('cannot be broken out of with a key that is not a key', () {
      final html = TrailerModal.debugWrapperHtml('a"><script>alert(1)</script>');
      expect(html, isNot(contains('<script>')));
    });
  });

  testWidgets('the modal states what is playing and offers a way out', (
    tester,
  ) async {
    await openTrailer(tester);

    expect(find.byType(TrailerModal), findsOneWidget);
    expect(find.text(_title), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    // `flutter test` mounts no webview, so the embed attempt fails and the
    // modal has to say so. A spinner that never resolves is the state this
    // guards against.
    expect(find.text('Trailer unavailable'), findsOneWidget);
    expect(find.text('Watch on YouTube'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the unavailable state is a way to watch, not a dead end', (
    tester,
  ) async {
    await openTrailer(tester);

    await tester.tap(find.text('Watch on YouTube'));
    await tester.pumpAndSettle();

    expect(host.launched, <Uri>[_watchUri]);
  });

  testWidgets('escape dismisses it', (tester) async {
    await openTrailer(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(TrailerModal), findsNothing);
  });

  testWidgets('the close control dismisses it', (tester) async {
    await openTrailer(tester);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(TrailerModal), findsNothing);
  });

  testWidgets('a build with no embed hands the key to YouTube, not to a '
      'modal with nothing in it', (tester) async {
    host = _FakeHost(embedAvailable: false);
    TrailerModal.debugHost = host;

    await openTrailer(tester);

    expect(find.byType(TrailerModal), findsNothing);
    expect(host.launched, <Uri>[_watchUri]);
  });

  testWidgets(
    'the Windows branch drives its own package, not the federated one',
    (tester) async {
      // The test binding forces `TargetPlatform.android`, so the cases above all
      // drive the federated branch. This one drives the Windows branch, whose
      // distinct failure mode is worth pinning: the federated controller asserts
      // when no platform is registered, and this branch must not reach for it.
      //
      // What it cannot cover is the fallback. `flutter_tester` never answers the
      // WebView2 plugin's channels, so `initialize()` neither completes nor
      // fails and the modal stays on its loading state - hence frames, not
      // `pumpAndSettle`. A machine without the WebView2 runtime is not this
      // case: there `canEmbed` is false before the modal opens at all.
      await openTrailer(tester, settle: false);

      expect(find.byType(TrailerModal), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Trailer unavailable'), findsNothing);
      expect(tester.takeException(), isNull);

      // Closed, so the spinner stops scheduling frames for the rest of the test.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TrailerModal), findsNothing);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.windows,
    }),
  );

  testWidgets('the video area is 16:9, centred, and clear of the edges', (
    tester,
  ) async {
    const window = Size(960, 540); // The television: 1920x1080 at density 320.
    await openTrailer(tester, window: window);

    final area = tester.getRect(
      find.byWidgetPredicate((w) => w is ColoredBox && w.color == Colors.black),
    );

    expect(area.width / area.height, closeTo(16 / 9, 0.01));
    expect(
      area.width / window.width,
      inInclusiveRange(0.70, 0.78),
      reason: 'the surface is capped by the window height on a television, so '
          'the width lands inside the band rather than on its ceiling',
    );
    expect((area.center.dx - window.width / 2).abs(), lessThan(0.5));
    // Header (~56 dp) plus the video, with a margin left above and below.
    expect(area.height + 56, lessThan(window.height * 0.86));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a desktop window is wide, not tall', (tester) async {
    const window = Size(1920, 1080);
    await openTrailer(tester, window: window);

    final area = tester.getRect(
      find.byWidgetPredicate((w) => w is ColoredBox && w.color == Colors.black),
    );

    expect(area.width / window.width, closeTo(0.78, 0.01));
    expect(area.height + 56, lessThan(window.height));
    expect(tester.takeException(), isNull);
  });
}
