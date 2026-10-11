/// The details page's primary call to action, measured at a television's own
/// size.
///
/// At 960x540 dp the page picks its desktop layout (960 clears the 800 dp
/// breakpoint) and sizes the left column from the *poster's* height budget:
/// whatever is left after the two buttons, turned into a 2:3 width. On the 2 GB
/// Chromecast with Google TV that budget yields a 177 dp column, and the pill's
/// own geometry spends 24 + 24 + 20 + 8 = 76 dp of it on the inset, the glyph
/// and the gap, leaving 101 dp. "Play Episodes" at [ZplayType.subtitle] (15 dp,
/// w600) painted in the Poppins the bundle ships needs more, so the `expand`
/// pill laid the label out into what was left and drew "Play Episod…" while
/// hundreds of dp sat empty beside it.
///
/// This test mounts the real page at that size and reads the *painted*
/// paragraph rather than the widget: `find.text('Play Episodes')` finds one
/// widget in both the truncated and the intact case, which is exactly why the
/// rest of the suite passed while the app's main action was unreadable at ten
/// feet.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/pages/details/details_page.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/services/metadata/metadata_service.dart';
import 'package:zplay/services/theme/design_tokens.dart';
import 'package:zplay/widgets/common/pill_button.dart';

/// A Cinemeta series response, trimmed to what the page reads.
///
/// `videos` is the field that makes the page a series - it is what selects the
/// "Play Episodes" label - and one episode is the shortest list that still
/// renders. The rest is only here so the hero has something to draw.
const _seriesMeta = '''
{"meta":{"id":"tt0903747","type":"series","name":"Breaking Bad",
 "releaseInfo":"2008",
 "description":"A chemistry teacher turns to crime.",
 "runtime":"49 min","genres":["Crime","Drama"],"imdbRating":"9.5",
 "videos":[{"id":"tt0903747:1:1","season":1,"episode":1,"name":"Pilot",
            "released":"2008-01-20"}]}}''';

/// Answers every GET with the series meta.
///
/// The page reaches for the meta addon, then the `/%7B%7D`-prefixed retry if
/// that misses, then the BestSimilar scrape - and a script that matched one
/// route would only be one hop of that chain. Serving one body for every URL
/// keeps the meta resolving, which is the only thing this test needs the
/// network for.
MockClient _seriesMetaClient() => MockClient(
  (request) async => http.Response(
    _seriesMeta,
    200,
    headers: const {'content-type': 'application/json'},
  ),
);

/// The row the page would be opened with from a series rail.
Movie _seriesRow() => Movie(
  id: 'tt0903747',
  name: 'Breaking Bad',
  type: 'series',
  addonBaseUrl: 'https://v3-cinemeta.strem.io',
  poster: 'https://example.test/breaking-bad.jpg',
  year: '2008',
);

/// Pumps the real page on the 1920x1080 @ 2x television surface.
Future<void> _pumpTvDetails(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(home: DetailsPage(movie: _seriesRow())));

  // The meta fetch and the entrance animation: a few pumps land the response,
  // then the 650ms controller has to run out before the layout settles.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MetadataService.clearCache();
    MetadataService.client = _seriesMetaClient();
    // The real device reports itself a television, and the pill's height is
    // read from the form factor: at 44 dp the column arithmetic would be the
    // phone's, not the one this defect was measured on.
    DeviceProfile.debugSetTelevision(value: true);
  });

  tearDown(() {
    MetadataService.clearCache();
    MetadataService.client = http.Client();
    DeviceProfile.debugSetTelevision(value: false);
  });

  testWidgets('the series CTA is drawn whole in a 960x540 television column',
      (tester) async {
    await _pumpTvDetails(tester);

    final label = find.text('Play Episodes');
    expect(label, findsOneWidget,
        reason: 'the page is still loading or showing "Details unavailable." '
            'if its only call to action is absent, and then this test would be '
            'measuring the error state');

    expect(
      tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
      isFalse,
      reason: "the app's main action rendered \"Play Episod…\" at ten feet; a "
          'call to action that cannot be read is not a call to action',
    );

    final pill = find.ancestor(of: label, matching: find.byType(PillButton));
    expect(pill, findsOneWidget);

    final context = tester.element(label);
    final pillWidth = tester.getSize(pill).width;
    final labelWidth = tester.getSize(label).width;

    // The contract a caller that stretches a pill has to honour: the box it
    // hands the pill is at least as wide as the label the pill is drawing.
    final needed = PillButton.minWidthFor(
      context,
      'Play Episodes',
      icon: Icons.play_arrow_rounded,
    );
    expect(pillWidth, greaterThanOrEqualTo(needed),
        reason: 'the column is sized from the poster and has to take the CTA '
            'it puts in it into account; the poster keeps its own 2:3 width '
            'inside it, so a wider column costs the poster nothing');

    // And the same thing in the units the failure was visible in: the painted
    // label plus the pill's own inset has to fit inside the pill's box.
    final painted = context.textWidth(
      'Play Episodes',
      ZplayType.subtitle.toStyle(),
      maxLines: 1,
    );
    final insets = needed - painted.ceilToDouble();
    expect(labelWidth + insets, lessThanOrEqualTo(pillWidth),
        reason: 'a label wider than the room left for it inside the pill is '
            'what the ellipsis is drawn over');

    // A wider column may not cost the poster its own proportions either: the
    // poster keeps its own 2:3 box inside the column, so widening the column
    // for the label cannot make the poster taller and push the primary action
    // back below the fold - the bottom of the pill is still on screen.
    expect(tester.getRect(pill).bottom, lessThanOrEqualTo(540.0),
        reason: 'the height budget reserves exactly two pills and the poster '
            'between them; a poster stretched to the wider column would derive '
            'a taller 2:3 height from it and take the app\'s main action off '
            'the bottom of the screen');
  });
}
