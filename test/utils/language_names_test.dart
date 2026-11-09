import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/utils/language_names.dart';

/// The subtitle rows are labelled by these strings, and the player groups
/// subtitles by them, so a provider's raw tag (`fre`, `pob`, `English [CC]`)
/// has to resolve to exactly one display name.
void main() {
  test('names the ISO codes the providers actually send', () {
    expect(subtitleLanguageName('fre'), 'French');
    expect(subtitleLanguageName('bul'), 'Bulgarian');
    expect(subtitleLanguageName('pob'), 'Portuguese (BR)');
    expect(subtitleLanguageName('eng'), 'English');
    expect(subtitleLanguageName('ara'), 'Arabic');
  });

  test('strips qualifiers and region suffixes', () {
    expect(subtitleLanguageName('English [CC]'), 'English');
    expect(subtitleLanguageName('Spanish (SDH)'), 'Spanish');
    expect(subtitleLanguageName('pt-BR'), 'Portuguese');
  });

  test('keeps the uppercase convention for unknown codes', () {
    // A code is not a word: the old per-provider fallbacks showed `XX`, and a
    // track tagged with an unknown code still has to look like a code.
    expect(subtitleLanguageName('xx'), 'XX');
    expect(subtitleLanguageName('klingon'), 'Klingon');
  });

  test('never returns an empty label', () {
    expect(subtitleLanguageName(''), 'English');
    expect(subtitleLanguageName('   '), 'English');
  });
}