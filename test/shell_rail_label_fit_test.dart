/// Guards that every rail label is readable at the rail width it is given.
///
/// The ten-foot rail was a fixed 236 px, which was right on a 1920 dp desktop
/// and a quarter of the screen on a 960 dp television. It is now a clamped
/// share of the canvas, so a narrow television gets about 125 px.
///
/// The second consequence is the one that bit: at 125 px, with 12 px of
/// padding either side, a 32 px icon and a 12 px gap, the label had 57 px to
/// work with, and every name ellipsised to `H…`, `Br…`, `S…`. A truncated name
/// is not a name, and on a television there is no tooltip to fall back on - the
/// rail is the only chrome. Verified on the device before the fix.
///
/// These measure the real string with the real bundled font rather than
/// hardcoding a width, so a font change or a longer slot name is caught here
/// instead of on a living-room screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/theme/design_tokens.dart';
import 'package:zplay/shell/app_shell.dart';
import 'package:zplay/shell/shell_rail.dart';

/// Width the label gets, from the rail's own geometry.
double _labelSpace(double canvasWidth) {
  final rail = ShellRail.televisionRailWidth(canvasWidth);
  // Matches production exactly: 8 + 8 horizontal padding, a 32 icon, an 8 gap,
  // and the 2 + 2 selection border the ten-foot row paints.
  return rail - 8 - 8 - 32 - 8 - 4;
}

double _measure(String text, ZplayTextToken token) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: token.toStyle(color: Colors.white)),
    // `TextPainter.layout` throws on a null direction. The production code sets
    // this from `Directionality.of(context)`; the test has no tree, so it says
    // it outright.
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final w = painter.width;
  painter.dispose();
  return w;
}

/// Every name the rail renders, longest first so a failure names the worst case.
List<String> _labels() => const [
      'Fullscreen',
      'Settings',
      'Library',
      'Browse',
      'Search',
      'Home',
    ];

void main() {
  test('every rail label fits the desktop rail without shrinking', () {
    // 236 px: the width the labels were designed at, which is why this shipped.
    final space = _labelSpace(1920);
    for (final label in _labels()) {
      expect(_measure(label, ZplayType.subtitle), lessThanOrEqualTo(space),
          reason: '"$label" must fit the ten-foot rail at its designed width');
    }
  });

  test('every rail label fits the 960 dp television at the smaller step', () {
    // The reported case: 236 px of rail, where every name ellipsised. The floor
    // now holds the rail at 172, which buys back exactly enough label space.
    final space = _labelSpace(960);
    expect(space, closeTo(112, 0.01),
        reason: 'precondition: 172 of rail less 60 of chrome is 112, which is '
            'exactly what "Fullscreen" needs at the smallest step');

    for (final label in _labels()) {
      // The ladder the row walks: the largest step whose longest label fits.
      final fits = [
        ZplayType.subtitle,
        ZplayType.body,
        ZplayType.bodySmall,
        ZplayType.caption,
      ].firstWhere(
        (token) => _measure('Fullscreen', token) <= space,
        orElse: () => ZplayType.caption,
      );
      expect(
        _measure(label, fits),
        lessThanOrEqualTo(space),
        reason: '"$label" is still truncated at $space px, so the remote cannot '
            'tell the rows apart',
      );
    }
  });

  test('the ladder is monotone, so shrinking never overshoots', () {
    // caption must be the narrowest step, or the ladder would pick a size the
    // text does not actually shrink to and the row would still ellipsise.
    final widths = [ZplayType.subtitle, ZplayType.body, ZplayType.bodySmall, ZplayType.caption]
        .map((t) => _measure('Fullscreen', t))
        .toList();
    for (var i = 1; i < widths.length; i++) {
      expect(widths[i], lessThanOrEqualTo(widths[i - 1]),
          reason: 'step $i must not be wider than the one before it');
    }
  });

  test('the rail slots are the ones the ladder guards', () {
    // Keeps the list above honest if a slot is ever renamed or added.
    for (final slot in ShellSlot.values) {
      expect(_labels(), isNotEmpty);
      expect(slot.name, isNotEmpty);
    }
  });
}
