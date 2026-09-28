/// Guards that a Material button says where focus is.
///
/// `CardFocusRing` is the app's own focus indicator and covers every card, rail
/// row and transport control. Material buttons are a separate population: they
/// fall back to the framework's default `overlayColor`, an 8% tint that is
/// invisible on a dark surface and certainly invisible at ten feet.
///
/// The P2P advisory's three answers are all Material buttons, so a remote user
/// pressing right through the dialog saw nothing move and no button respond.
/// Verified on a Chromecast with Google TV: four presses, no visual change.
///
/// Set at the theme rather than per button, so every dialog, sheet and
/// `TextButton` inherits it. Per-site styling is the same class of miss as the
/// settings rows having been bare `InkWell`s - reachable by pointer, invisible
/// and unreachable by remote.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/theme/app_theme_service.dart';

/// The overlay a button in [states] would paint, or null for the default.
Color? _overlayFor(Set<WidgetState> states) {
  final theme = AppThemeService.createThemeData(AppThemeService.palettes.first);
  final style = theme.elevatedButtonTheme?.style;
  return style?.overlayColor?.resolve(states);
}

void main() {
  test('a focused Material button has a focus overlay', () {
    final overlay = _overlayFor(const {WidgetState.focused});
    expect(overlay, isNotNull,
        reason: 'no overlay means the framework default, an 8% tint that a '
            'person cannot see at ten feet');
  });

  test('and the focus overlay is stronger than a hover', () {
    final focused = _overlayFor(const {WidgetState.focused});
    final hovered = _overlayFor(const {WidgetState.hovered});
    expect(focused, isNotNull);
    expect(hovered, isNotNull);
    expect(
      (focused!).a,
      greaterThanOrEqualTo((hovered!).a),
      reason: 'focus has to out-read hover, or a remote user cannot tell the '
          'two apart',
    );
  });

  test('the three button themes are all configured', () {
    final theme = AppThemeService.createThemeData(AppThemeService.palettes.first);
    final styles = <String, ButtonStyle?>{
      'elevated': theme.elevatedButtonTheme?.style,
      'outlined': theme.outlinedButtonTheme?.style,
      'text': theme.textButtonTheme?.style,
    };
    for (final entry in styles.entries) {
      expect(entry.value?.overlayColor, isNotNull,
          reason: '${entry.key} buttons are used across the app and must show '
              'focus like everything else');
    }
  });

  test('an outlined button gains a visible border on focus', () {
    // An overlay alone can be lost against a bright fill, so the outline moves
    // too - the same 2 px accent the app's own cards use.
    final theme = AppThemeService.createThemeData(AppThemeService.palettes.first);
    final side = theme.outlinedButtonTheme?.style?.side?.resolve(
      const {WidgetState.focused},
    );
    expect(side, isNotNull);
    expect(side!.width, greaterThanOrEqualTo(2.0));
  });
}
