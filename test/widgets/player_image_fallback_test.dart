/// Guards the artwork fallbacks on the player overlay.
///
/// A catalog logo URL can be dead - `images.metahub.space/logo/...` answers
/// 404 for ids it has not indexed - and `CachedNetworkImage` forwards the image
/// error to Flutter when it is given no `errorWidget`. In debug that renders
/// `ErrorWidget`: the red box with the raw `HttpException` across the middle of
/// the player, which is what the overlay shipped before these branches existed.
/// The overlay must show its fallback (spinner or nothing) instead.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/player/player_loading_overlay.dart';

import '../support/tv_nav_harness.dart';

void main() {
  testWidgets('dead artwork falls back instead of painting an ErrorWidget', (
    tester,
  ) async {
    await pumpTelevision(
      tester,
      PlayerLoadingOverlay(
        // Neither URL parses as a network image, so the provider fails without
        // any test needing a socket.
        backdropUrl: 'not-a-url/backdrop',
        logoUrl: 'not-a-url/logo',
        message: 'Opening the stream…',
        onChooseSource: () {},
        onGoBack: () {},
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(
      find.byType(ErrorWidget),
      findsNothing,
      reason: 'a dead logo must not paint the exception over the player',
    );
  });
}
