import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/pages/settings/palette_picker.dart';
import 'package:zplay/services/theme/app_theme_service.dart';
import 'package:zplay/widgets/common/focusable_card.dart';

/// The theme picker has to be reachable from a sofa.
///
/// It was three identical copies of a grid built from a bare `InkWell` -
/// pointer-only, because `InkWell` is not a `Focus` widget. Eleven swatches a
/// television could show and no remote could touch, in three settings pages, so
/// the duplication is what made the bug survive: fixing one copy would have left
/// two of them broken.
void main() {
  setUp(() {
    AppThemeService.currentPalette.value = AppThemeService.palettes.first;
  });

  testWidgets('every palette is a focus target a remote can reach', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PalettePicker())),
    );
    await tester.pump();

    final cards = find.byType(FocusableCard);
    expect(cards, findsNWidgets(AppThemeService.palettes.length),
        reason: 'one focusable row per palette');

    // A `FocusableActionDetector` is what makes each row reachable; a bare
    // `InkWell` renders the same pixels and answers none of these.
    expect(
      find.descendant(of: cards, matching: find.byType(FocusableActionDetector)),
      findsNWidgets(AppThemeService.palettes.length),
      reason: 'each row must install a real focus node, or it is pointer-only',
    );
  });

  testWidgets('the centre key applies the palette a row is focused on',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PalettePicker())),
    );
    await tester.pump();

    final target = AppThemeService.palettes.last;
    final initial = AppThemeService.currentPalette.value.id;

    // Focus the last row by traversal, then activate it the way a remote does.
    final rows = find.byType(FocusableCard);
    final last = rows.last;
    tester.widget<FocusableCard>(last).onTap?.call();
    await tester.pump();

    expect(AppThemeService.currentPalette.value.id, target.id,
        reason: 'activating a row must apply that palette');
    expect(initial, isNot(target.id),
        reason: 'precondition: the last palette is not already active');
  });
}