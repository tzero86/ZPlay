/// The shell and settings chrome in Arabic.
///
/// Two things are being guarded here, and only one of them is copy: the shell
/// has to say its destinations in the app's language, and the app has to lay
/// itself out right-to-left when that language is Arabic. The second is the
/// one a translated string cannot prove on its own, so the direction is read
/// off the live element rather than inferred from the locale.
///
/// The English case is asserted too, because the fallback used by every widget
/// pumped without the app's delegates must keep the words the rest of the suite
/// searches for.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/l10n/generated/app_localizations.dart';
import 'package:zplay/l10n/l10n.dart';
import 'package:zplay/pages/settings/diagnostics_page.dart';
import 'package:zplay/services/diagnostics/diagnostics_export.dart';
import 'package:zplay/services/layout/device_profile.dart';
import 'package:zplay/services/settings/locale_settings.dart';
import 'package:zplay/shell/app_shell.dart';
import 'package:zplay/shell/shell_rail.dart';

const _ar = Locale('ar');

Widget _app(Locale locale, Widget home) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

Widget _rail() => Scaffold(
  body: ShellRail(
    current: ShellSlot.home,
    onSelect: (_) {},
    onLiveTv: () {},
  ),
);

/// A page that reports the bundle it sees, for asserting the delegate wiring
/// itself rather than a widget's rendering.
class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Directionality.of(context),
      child: Text(l10nOf(context).navHome),
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocaleSettings.locale.value = null;
    DeviceProfile.debugSetTelevision(value: false);
  });

  tearDown(() {
    LocaleSettings.locale.value = null;
    DeviceProfile.debugSetTelevision(value: false);
  });

  testWidgets('Arabic shell is RTL and names every destination in Arabic', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_ar, _rail()));
    await tester.pump();

    final context = tester.element(find.byType(ShellRail));
    expect(
      Directionality.of(context),
      TextDirection.rtl,
      reason: 'an Arabic MaterialApp has to lay the shell out right-to-left',
    );

    for (final label in <String>[
      'الرئيسية',
      'تصفح',
      'بحث',
      'المكتبة',
      'الإعدادات',
      'البث المباشر',
    ]) {
      expect(
        find.text(label),
        findsOneWidget,
        reason: 'the shell must draw "$label" in Arabic',
      );
    }
  });

  testWidgets('English stays the default copy', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(const Locale('en'), _rail()));
    await tester.pump();

    final context = tester.element(find.byType(ShellRail));
    expect(Directionality.of(context), TextDirection.ltr);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Live TV'), findsOneWidget);
  });

  testWidgets('a plain MaterialApp still sees English through l10nOf', (
    tester,
  ) async {
    // No delegates: the situation every older widget test is in.
    await tester.pumpWidget(const MaterialApp(home: _Probe()));
    await tester.pump();

    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('diagnostics page renders its Arabic chrome', (tester) async {
    await tester.pumpWidget(
      _app(
        _ar,
        Scaffold(body: DiagnosticsPage(export: _FakeDiagnostics())),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('التشخيص'), findsOneWidget);
    expect(find.text('نسخ التقرير'), findsOneWidget);
    expect(find.text('حفظ التقرير'), findsOneWidget);
    expect(find.textContaining('2 مسجّل'), findsOneWidget);
  });

  test('LocaleSettings persists Arabic and initialize restores it', () async {
    await LocaleSettings.setLocale('ar');
    expect(LocaleSettings.locale.value, _ar);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('zplay_locale'), 'ar');

    // A fresh launch reads the stored choice rather than defaulting to system.
    LocaleSettings.locale.value = null;
    await LocaleSettings.initialize();
    expect(LocaleSettings.locale.value, _ar);

    // And the system choice is stored as an absence, not the word "system".
    await LocaleSettings.setLocale(LocaleSettings.systemCode);
    expect(LocaleSettings.locale.value, isNull);
    expect(prefs.getString('zplay_locale'), isNull);
  });
}

class _FakeDiagnostics extends DiagnosticsExport {
  @override
  Future<Map<String, Object?>> collect() async => <String, Object?>{
    'app': <String, Object?>{'version': '9.9.9'},
    'device': <String, Object?>{'formFactor': 'television'},
    'player': <String, Object?>{'engine': 'media3'},
    'breadcrumbs': <String, Object?>{
      'count': 2,
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
  Future<String> copyText() async => '{"fake":true}';

  @override
  Future<String?> saveReport() async => null;
}
