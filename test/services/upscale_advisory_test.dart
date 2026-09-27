import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/player/player_settings.dart';

/// The advisory is what tells a user that upscaling a source they do not need
/// upscaled will probably not help, so the boundaries matter more than the
/// wording: a mode wrongly called "not recommended" gets ignored, and a mode
/// wrongly called beneficial makes a stream look worse than it needed to.
void main() {
  // A 4K panel, which is the case the advisory exists for.
  const panelW = 3840.0;
  const panelH = 2160.0;

  UpscaleAdvisory advise(
    Anime4KPreset preset,
    int w,
    int h, {
    double? dw,
    double? dh,
  }) {
    return adviseForUpscaling(
      preset: preset,
      sourceWidth: w,
      sourceHeight: h,
      displayWidth: dw ?? panelW,
      displayHeight: dh ?? panelH,
    );
  }

  group('adviseForUpscaling', () {
    test('off is never applicable', () {
      expect(advise(Anime4KPreset.off, 480, 270), UpscaleAdvisory.notApplicable);
    });

    test('a 480p source on a 4K panel is beneficial', () {
      expect(advise(Anime4KPreset.fsrEasu, 854, 480), UpscaleAdvisory.beneficial);
    });

    test('1080p on a 4K panel is beneficial', () {
      expect(advise(Anime4KPreset.fsrEasu, 1920, 1080), UpscaleAdvisory.beneficial);
    });

    test('a 4K source on a 4K panel is not recommended', () {
      // The case the rule was written for: an exact match is a scale of 1.0,
      // so warning only above 1.0 let the commonest case through unflagged.
      expect(advise(Anime4KPreset.fsrEasu, 3840, 2160), UpscaleAdvisory.notRecommended);
      expect(advise(Anime4KPreset.fsrEasuRcas, 3840, 2160), UpscaleAdvisory.notRecommended);
    });

    test('a source larger than the panel is not recommended', () {
      expect(advise(Anime4KPreset.fsrEasu, 7680, 4320), UpscaleAdvisory.notRecommended);
    });

    test('a marginal enlargement is beneficial past the threshold', () {
      expect(
        advise(Anime4KPreset.fsrEasu, 1920, 1080, dw: 2400, dh: 1350),
        UpscaleAdvisory.beneficial,
      );
    });

    // The only band where the two FSR modes differ. Both are harmless and
    // pointless once the source fills the panel; between a match and a real
    // enlargement, smoothing still has a little to add and sharpening mostly
    // has ringing to amplify.
    test('just above a match, sharpening is flagged and smoothing is not', () {
      expect(
        advise(Anime4KPreset.fsrEasuRcas, 1920, 1080, dw: 1980, dh: 1113),
        UpscaleAdvisory.notRecommended,
      );
      expect(
        advise(Anime4KPreset.fsrEasu, 1920, 1080, dw: 1980, dh: 1113),
        UpscaleAdvisory.neutral,
      );
    });

    // A film is letterboxed, so the comparison has to use the fitted scale
    // rather than raw width: 1920x800 in a 16:9 panel is not "at or above" it.
    test('a letterboxed film is judged on the fitted scale, not raw width', () {
      expect(advise(Anime4KPreset.fsrEasu, 1920, 800), UpscaleAdvisory.beneficial);
    });

    test('an unknown source reports neutral rather than guessing', () {
      expect(advise(Anime4KPreset.fsrEasu, 0, 0), UpscaleAdvisory.neutral);
    });

    test('an unmeasured panel reports neutral rather than guessing', () {
      expect(
        advise(Anime4KPreset.fsrEasu, 1920, 1080, dw: 0, dh: 0),
        UpscaleAdvisory.neutral,
      );
    });
  });

  group('preset classification', () {
    test('the two FSR modes are FSR and nothing else is', () {
      for (final preset in Anime4KPreset.values) {
        final expected =
            preset == Anime4KPreset.fsrEasu || preset == Anime4KPreset.fsrEasuRcas;
        expect(preset.isFsr, expected, reason: '${preset.name} misclassified');
      }
    });

    test('the Anime4K modes are Anime4K and neither FSR mode is', () {
      for (final preset in Anime4KPreset.values) {
        final expected = preset != Anime4KPreset.off && !preset.isFsr;
        expect(preset.isAnime4k, expected, reason: '${preset.name} misclassified');
      }
    });

    test('no preset claims both families at once', () {
      for (final preset in Anime4KPreset.values) {
        expect(preset.isFsr && preset.isAnime4k, isFalse,
            reason: '${preset.name} claims both families');
      }
    });
  });

  group('shader chains', () {
    test('off ships no shaders', () {
      expect(Anime4KPreset.off.shaderFiles, isEmpty);
    });

    // Stacking both families would scale the same pixels twice, so no chain may
    // reference an Anime4K file while claiming to be FSR.
    test('an FSR chain contains no Anime4K shader', () {
      for (final preset in [Anime4KPreset.fsrEasu, Anime4KPreset.fsrEasuRcas]) {
        expect(preset.shaderFiles, isNotEmpty, reason: '${preset.name} ships nothing');
        for (final file in preset.shaderFiles) {
          expect(file, isNot(contains('Anime4K')),
              reason: '${preset.name} mixes in $file');
        }
      }
    });

    test('the smooth FSR mode is EASU only', () {
      expect(Anime4KPreset.fsrEasu.shaderFiles, isNot(contains('FSR_RCAS.glsl')));
    });

    test('the sharp FSR mode adds RCAS on top of the smoothing pass', () {
      expect(Anime4KPreset.fsrEasuRcas.shaderFiles,
          containsAll(Anime4KPreset.fsrEasu.shaderFiles));
      expect(Anime4KPreset.fsrEasuRcas.shaderFiles, contains('FSR_RCAS.glsl'));
    });
  });

  group('describeUpscaleAdvisory', () {
    test('not applicable produces no copy', () {
      expect(describeUpscaleAdvisory(UpscaleAdvisory.notApplicable, 1920, 1080), isEmpty);
    });

    test('the not-recommended copy names the source and warns', () {
      final text = describeUpscaleAdvisory(UpscaleAdvisory.notRecommended, 3840, 2160);
      expect(text, contains('3840x2160'));
      expect(text.toLowerCase(), contains('worse'));
    });

    test('an unknown source is described without inventing a resolution', () {
      final text = describeUpscaleAdvisory(UpscaleAdvisory.neutral, 0, 0);
      expect(text, contains('this source'));
      expect(text, isNot(contains('0x0')));
    });
  });
}
