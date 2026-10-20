import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/layout/device_profile.dart';
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

  Widget gate({bool hovered = true}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 200,
          height: 300,
          child: TrailerPreviewGate(
            hovered: hovered,
            trailerKey: 'abcdefghijk',
            resolveTrailerKey: () async => 'abcdefghijk',
          ),
        ),
      ),
    ),
  );

  testWidgets('a pointer previews a trailer only after the dwell', (
    tester,
  ) async {
    await tester.pumpWidget(gate());

    expect(
      find.byKey(const ValueKey<String>('trailer-preview-abcdefghijk')),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(const ValueKey<String>('trailer-preview-abcdefghijk')),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 700));
    expect(
      find.byKey(const ValueKey<String>('trailer-preview-abcdefghijk')),
      findsOneWidget,
    );
  });

  testWidgets('leaving before the dwell never mounts a preview', (
    tester,
  ) async {
    await tester.pumpWidget(gate());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(gate(hovered: false));
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.byKey(const ValueKey<String>('trailer-preview-abcdefghijk')),
      findsNothing,
    );
  });

  testWidgets('a television never autoplays a trailer', (tester) async {
    DeviceProfile.debugSetTelevision(value: true);
    await tester.pumpWidget(gate());
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.byKey(const ValueKey<String>('trailer-preview-abcdefghijk')),
      findsNothing,
    );
  });

  testWidgets('the preview is reachable on a platform with no webview', (
    tester,
  ) async {
    // Linux has no WebView implementation, so the gate refuses to start a
    // preview there - and CI runs on Linux. The stand-in builder is what
    // makes the gate's own logic testable there at all: without it this
    // file's dwell test only ever passed on the machine that happened to
    // be running it, and the release build shipped a preview that never
    // started.
    expect(TrailerPreview.isSupported, isTrue);
  });
}
