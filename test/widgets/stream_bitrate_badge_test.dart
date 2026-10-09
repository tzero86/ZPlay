/// Guards what a source card actually puts in front of the viewer.
///
/// The badge resolves a bitrate in three tiers and must never let one pass for
/// another. A rate stated in the release name and one read off the HLS manifest
/// are measurements; a size/runtime figure is a guess, and it is drawn with a
/// leading `~` precisely so it reads as one. A viewer choosing between two
/// streams needs that distinction to be visible, not implied.
///
/// Also pins that the badge costs no space when there is nothing to show. A
/// source with no determinable rate renders nothing at all, so a card's chip row
/// must not grow a gap for a chip that is not there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/models/stream/stream_model.dart';
import 'package:zplay/widgets/player/stream_bitrate_badge.dart';

void main() {
  Future<void> pumpBadge(
    WidgetTester tester,
    StreamSource source, {
    int? runtimeMinutes,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamBitrateBadge(
            source: source,
            runtimeMinutes: runtimeMinutes,
            margin: margin,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a stated bitrate is shown as a measurement, without a tilde',
      (tester) async {
    await pumpBadge(
      tester,
      StreamSource(
        addonName: 'Test',
        title: 'Movie.2024.2160p.WEB-DL 15.2 Mb/s',
      ),
    );

    expect(find.text('15.2 Mb/s'), findsOneWidget);
    expect(find.textContaining('~'), findsNothing,
        reason: 'a rate written in the release name is a measurement and must '
            'not be drawn as an estimate');
  });

  testWidgets('a size/runtime estimate is marked with a tilde', (tester) async {
    // Nothing states a rate; 8 GB over 120 minutes is roughly 9.5 Mb/s.
    await pumpBadge(
      tester,
      StreamSource(
        addonName: 'Test',
        title: 'Movie.2024.1080p.WEB-DL 8 GB',
      ),
      runtimeMinutes: 120,
    );

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, startsWith('~'),
        reason: 'a figure derived from size and runtime is a guess and must '
            'read as one to the viewer');
    expect(text.data, endsWith('Mb/s'));
  });

  testWidgets('a source with no determinable rate renders no chip at all',
      (tester) async {
    await pumpBadge(
      tester,
      StreamSource(addonName: 'Test', title: 'Movie.2024.1080p'),
      runtimeMinutes: null,
      margin: const EdgeInsets.only(right: 6),
    );

    expect(
      tester.getSize(find.byType(StreamBitrateBadge)),
      Size.zero,
      reason: 'an empty badge must leave no gap in the row that hosts it, so '
          'its margin must not be laid out when there is no chip behind it',
    );
    expect(find.byType(Text), findsNothing);
  });
}
