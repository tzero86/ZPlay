/// One band, drawn once, for every settings sub-page.
///
/// Nineteen pages used to hand-roll this `AppBar` under the same comment, and
/// they drifted a line at a time - which is the whole of the report that walking
/// into a settings page feels like entering a different app. They are all this
/// widget now, so what is pinned here is what every one of them draws.
///
/// The two assertions that matter are the visual ones the copies got wrong: the
/// band is flat (one converted page set `elevation: 0` and the rest relied on the
/// theme), and it is **transparent with no hairline**, so the page's own canvas is
/// the band — an opaque strip or a bottom rule here re-creates the seam the
/// shell's blended nav exists to remove. The last is the only *behaviour* it has:
/// the back chevron pops.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/services/theme/design_tokens.dart';
import 'package:zplay/widgets/settings/settings_app_bar.dart';

/// Pushes a page using the shared band, so the back chevron has somewhere to go
/// back to.
Future<void> _pumpPage(WidgetTester tester, {required String title}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: SettingsAppBar(title: title),
                    body: const SizedBox.shrink(),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('draws the one band every settings page used to copy',
      (tester) async {
    await _pumpPage(tester, title: 'Probe Settings');

    final context = tester.element(find.byType(SettingsAppBar));
    final tokens = context.tokens;
    final appBar = tester.widget<AppBar>(find.byType(AppBar));

    expect(
      appBar.elevation,
      0,
      reason: 'flat, and stated rather than inherited: a shadow on some pages '
          'and not others is exactly the drift this removes',
    );
    expect(
      appBar.scrolledUnderElevation,
      0,
      reason: 'no scroll-under band: a strip that tints itself once content '
          'slides under it is the band coming back',
    );
    expect(
      appBar.backgroundColor,
      Colors.transparent,
      reason: 'the page canvas is the band; an opaque fill here is the seam '
          'this widget exists to remove',
    );
    expect(
      appBar.surfaceTintColor,
      Colors.transparent,
      reason: 'no scroll-under tint; the band is transparent instead',
    );
    expect(
      appBar.shape,
      isNull,
      reason: 'no bottom hairline: a page header separated by a line is a page '
          'header that looks like a different app from its own canvas',
    );

    final title = tester.widget<Text>(find.text('Probe Settings'));
    expect(
      title.style,
      ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
      reason: 'one title style for every page, so no page can restyle its own',
    );
  });

  testWidgets('the back chevron pops the page it is on', (tester) async {
    await _pumpPage(tester, title: 'Probe Settings');
    expect(find.text('Probe Settings'), findsOneWidget);

    expect(
      find.byIcon(Icons.arrow_back_ios_rounded),
      findsOneWidget,
      reason: 'the pages that were copied all drew this chevron at size 20',
    );

    await tester.tap(find.byIcon(Icons.arrow_back_ios_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Probe Settings'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
