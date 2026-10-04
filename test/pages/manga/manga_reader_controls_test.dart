/// The reader banner's shape, which is a density decision and not a taste one.
///
/// On the television the shelf banner is one 48 dp row: an atmosphere
/// disclosure chip and a page-mode disclosure chip. The chip *group* the
/// pointer layout uses reflows inside an `Expanded`, so on a 540 dp canvas it
/// spent ~120 dp of the screen on a setting the user changes once - measured
/// against the shelf stack it sits in, that plus the page's own app bar and the
/// Continue Reading shelf left almost nothing for the grid.
///
/// Both shapes are asserted, because the fix is only correct if it keeps the
/// pointer's version: the failure mode here is deleting the group rather than
/// choosing between them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/pages/manga/widgets/manga_reader_controls.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/services/manga/manga_settings.dart';

import '../../support/tv_nav_harness.dart';

/// A phone canvas, through the same classifier the app uses.
Widget _phoneHost(Widget child) => MaterialApp(
  home: MediaQuery(
    data: const MediaQueryData(size: Size(390, 844), devicePixelRatio: 2),
    child: Scaffold(body: child),
  ),
);

void main() {
  late MangaReaderBackground previousAtmosphere;

  setUp(() {
    previousAtmosphere = MangaSettings.readerBackground.value;
    MangaSettings.readerBackground.value = MangaReaderBackground.darkSlate;
  });

  tearDown(() {
    MangaSettings.readerBackground.value = previousAtmosphere;
  });

  group('MangaReaderControlBar on a television', () {
    testWidgets('is one row: the chip group is replaced by a disclosure chip',
        (tester) async {
      await pumpTelevision(tester, const MangaReaderControlBar());

      expect(
        find.byType(MangaAtmosphereChips),
        findsNothing,
        reason: 'the wrapping chip group is the shape that ate the canvas',
      );
      expect(find.byType(MangaAtmosphereChip), findsOneWidget);
      expect(find.byType(MangaPageModeChip), findsOneWidget);
    });

    testWidgets('the banner stays inside one 48 dp row', (tester) async {
      await pumpTelevision(tester, const MangaReaderControlBar());

      final height = tester.getSize(find.byType(MangaReaderControlBar)).height;
      // 8 padding + 48 control + 8 padding + the 1 dp hairline under it.
      expect(
        height,
        lessThanOrEqualTo(66),
        reason: 'the banner is one row: 48 dp of control plus its padding',
      );
      expect(
        height,
        greaterThanOrEqualTo(48),
        reason: 'a ten-foot target is still 48 dp, not a shrunk one',
      );
    });

    testWidgets('the atmosphere chip names the atmosphere it will change',
        (tester) async {
      await pumpTelevision(tester, const MangaReaderControlBar());

      expect(
        find.text('Atmosphere: ${MangaReaderBackground.darkSlate.label}'),
        findsOneWidget,
        reason: 'a disclosure chip that does not name its value is a mystery',
      );
    });
  });

  group('MangaReaderControlBar on a phone', () {
    testWidgets('keeps the chip group, because there the group is better',
        (tester) async {
      DeviceProfile.debugSetTelevision(value: false);
      addTearDown(() => DeviceProfile.debugSetTelevision(value: false));

      await tester.pumpWidget(_phoneHost(const MangaReaderControlBar()));
      await tester.pump();

      expect(find.byType(MangaAtmosphereChips), findsOneWidget);
      expect(
        find.byType(MangaAtmosphereChip),
        findsNothing,
        reason: 'the phone gets the group, not the disclosure chip',
      );
    });
  });
}
