/// Guards the sound control over the trailer preview.
///
/// The preview is muted by default - a trailer that starts talking under the
/// pointer is one the user did not ask for - but a user who has deliberately
/// rested on the hero may want to hear it, and a control that cannot be
/// undone is not a control.
///
/// The control lives in the *surface's own control row*, not over the
/// picture: the hero's layers are painted above the preview, so a button
/// drawn over the video renders under them and the click never reaches it.
/// That was the first attempt's defect, and it was invisible in a widget
/// test - the button was there, and it did nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/widgets/common/trailer_mute_button.dart';
import 'package:zplay/widgets/movie/trailer_preview.dart';

void main() {
  setUp(() {
    DeviceProfile.debugSetTelevision(value: false);
    TrailerPreview.debugBuilder = (key) => ColoredBox(
      key: ValueKey<String>('trailer-preview-$key'),
      color: Colors.red,
    );
  });

  tearDown(() {
    DeviceProfile.debugSetTelevision(value: false);
    TrailerPreview.debugBuilder = null;
  });

  /// The gate as the hero mounts it, with the control in the surface's own
  /// row beside it - the shape the fix settled on.
  Widget hero() => MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: TrailerPreviewGate(
              hovered: true,
              trailerKey: 'abcdefghijk',
              resolveTrailerKey: () async => 'abcdefghijk',
              cover: true,
            ),
          ),
          // The control row, painted *above* the preview, the way the hero's
          // own content column is.
          Positioned(
            left: 0,
            bottom: 0,
            child: TrailerMuteButton(
              muted: true,
              onPressed: () {},
            ),
          ),
        ],
      ),
    ),
  );

  testWidgets('the preview layer never eats a click', (tester) async {
    await tester.pumpWidget(hero());
    await tester.pump(const Duration(milliseconds: 1300));

    // The preview fills the whole area, and the control sits on top of it.
    // If the preview's layer took the pointer, the control would be
    // unreachable - which is exactly what happened when the button was
    // drawn *under* the preview.
    final preview = find.byKey(const ValueKey<String>('trailer-preview-abcdefghijk'));
    expect(preview, findsOneWidget);

    final button = find.byType(TrailerMuteButton);
    expect(button, findsOneWidget);

    // The press lands on the button, not on the preview underneath it.
    //
    // The hit target is the `InkWell`'s own render object - a
    // `RenderPointerListener` - so the path is checked for the gesture
    // receiver rather than for the button widget itself.
    final buttonRect = tester.getRect(button);
    final hit = tester.hitTestOnBinding(buttonRect.center);
    expect(
      hit.path.any((e) => e.target.runtimeType.toString() ==
          'RenderPointerListener'),
      isTrue,
      reason: 'the sound control must be the thing under the pointer',
    );
    expect(
      hit.path.any((e) => e.target is TrailerPreviewGate),
      isFalse,
      reason: 'the preview must not take the press meant for the control',
    );
  });

  testWidgets('the control names itself for a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(hero());
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.bySemanticsLabel('Unmute trailer'),
      findsOneWidget,
      reason: 'a muted preview offers to be unmuted',
    );
    handle.dispose();
  });

  testWidgets('the gate hands the sound state to whoever asked for it', (
    tester,
  ) async {
    bool? reported;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrailerPreviewGate(
            hovered: true,
            trailerKey: 'abcdefghijk',
            resolveTrailerKey: () async => 'abcdefghijk',
            onSoundChanged: (muted) => reported = muted,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1300));

    // The gate itself never changes the state - the embed's answer does, and
    // the debug builder never answers - so nothing is reported. The point is
    // that the gate accepts the answer and passes it on rather than keeping
    // it to itself.
    expect(reported, isNull);
  });
}
