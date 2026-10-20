/// The Settings diagnostics page: it has to render the collected report and
/// both actions must go through [DiagnosticsExport], not around it.
///
/// The page is verified against an injected fake, so no clipboard plugin and no
/// filesystem is touched - the same rule the service's own tests follow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/pages/settings/diagnostics_page.dart';
import 'package:zplay/services/diagnostics/diagnostics_export.dart';

class _FakeDiagnostics extends DiagnosticsExport {
  int copyCalls = 0;
  int saveCalls = 0;

  @override
  Future<Map<String, Object?>> collect() async => <String, Object?>{
    'schemaVersion': 1,
    'app': <String, Object?>{'version': '9.9.9', 'build': '4242'},
    'device': <String, Object?>{'formFactor': 'television'},
    'player': <String, Object?>{'engine': 'media3'},
    'streamEngine': <String, Object?>{'torrentEngine': 'stopped'},
    'breadcrumbs': <String, Object?>{
      'count': 2,
      'limit': 50,
      'entries': <Object?>[
        <String, Object?>{
          'at': '2026-10-19T10:00:00.000Z',
          'category': 'route',
          'message': 'push DetailsPage',
        },
        <String, Object?>{
          'at': '2026-10-19T10:00:01.000Z',
          'category': 'stream',
          'message': 'stream.open',
        },
      ],
    },
  };

  @override
  Future<String> copyText() async {
    copyCalls++;
    return '{"fake":true}';
  }

  @override
  Future<String?> saveReport() async {
    saveCalls++;
    return '/tmp/zplay-diagnostics.json';
  }
}

Future<void> _pumpPage(WidgetTester tester, _FakeDiagnostics fake) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(960, 720);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(home: DiagnosticsPage(export: fake)));
  // The page's own state, not a settled tree: the ambient background repeats
  // forever, so `pumpAndSettle` never returns here.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('renders the report summary and the breadcrumb tail', (
    tester,
  ) async {
    await _pumpPage(tester, _FakeDiagnostics());

    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('9.9.9'), findsOneWidget);
    expect(find.text('television'), findsOneWidget);
    expect(find.text('media3'), findsOneWidget);
    expect(find.text('stopped'), findsOneWidget);
    expect(find.textContaining('2 recorded'), findsOneWidget);
    expect(find.textContaining('stream.open'), findsOneWidget);
    expect(find.text('Copy report'), findsOneWidget);
    expect(find.text('Save report'), findsOneWidget);
  });

  testWidgets('Copy report goes through the service seam', (tester) async {
    final fake = _FakeDiagnostics();
    await _pumpPage(tester, fake);

    await tester.tap(find.text('Copy report'));
    await tester.pump();
    await tester.pump();

    expect(fake.copyCalls, 1);
    expect(fake.saveCalls, 0);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Save report shows the path the service returned', (
    tester,
  ) async {
    final fake = _FakeDiagnostics();
    await _pumpPage(tester, fake);

    await tester.tap(find.text('Save report'));
    await tester.pump();
    await tester.pump();

    expect(fake.saveCalls, 1);
    expect(fake.copyCalls, 0);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            (widget.data ?? '').contains('/tmp/zplay-diagnostics.json'),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
  });
}
