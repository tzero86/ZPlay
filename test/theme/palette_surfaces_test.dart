import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/theme/app_theme_service.dart';

/// Pins the single background ramp.
///
/// [ZplaySurfaces] owns the page, card and bar colours; a preset is an accent
/// choice only. Without this guard a palette could quietly grow its own
/// background again and repaint the whole app behind the picker, so both the
/// palette getters and the [ThemeData] the service builds from them are
/// asserted against the same three constants.
void main() {
  test('every palette reports the shared ZplaySurfaces ramp', () {
    expect(AppThemeService.palettes, isNotEmpty);

    for (final palette in AppThemeService.palettes) {
      expect(
        palette.scaffoldBackgroundColor,
        ZplaySurfaces.bg,
        reason:
            'palette "${palette.id}" must not carry its own page background',
      );
      expect(
        palette.cardBackgroundColor,
        ZplaySurfaces.surface,
        reason:
            'palette "${palette.id}" must not carry its own card background',
      );
      expect(
        palette.appBarBackgroundColor,
        ZplaySurfaces.raised,
        reason:
            'palette "${palette.id}" must not carry its own app bar background',
      );
    }
  });

  test('palette ids are unique', () {
    final ids = AppThemeService.palettes.map((palette) => palette.id).toList();

    expect(
      ids.toSet(),
      hasLength(ids.length),
      reason:
          'stored palette ids must keep resolving to exactly one palette, '
          'got ${ids.join(', ')}',
    );
  });

  test('createThemeData paints the shared ZplaySurfaces ramp', () {
    for (final palette in AppThemeService.palettes) {
      final theme = AppThemeService.createThemeData(palette);

      expect(
        theme.scaffoldBackgroundColor,
        ZplaySurfaces.bg,
        reason: 'theme for "${palette.id}" must use the shared page background',
      );
      expect(
        theme.appBarTheme.backgroundColor,
        ZplaySurfaces.raised,
        reason:
            'theme for "${palette.id}" must use the shared app bar background',
      );
      expect(
        theme.cardTheme.color,
        ZplaySurfaces.surface,
        reason: 'theme for "${palette.id}" must use the shared card background',
      );
    }
  });
}
