import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/iptv/iptv_settings.dart';

/// Pins the Boxing bucket's place in the Live TV category list, and the one
/// promise that lets it be added without a migration.
///
/// A fight-night bucket is read next to the combat bucket, so a fresh install
/// gets it there rather than appended to the end of the list. Installs that
/// already saved a category list never see that order, because the load path
/// merges any default the saved list lacks - which is why no migration code
/// exists for this, and why the merge is pinned here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Boxing sits immediately before Combat & Martial Arts', () {
    const categories = IptvSettings.defaultCategories;
    final boxing = categories.indexOf('Boxing');
    expect(boxing, isNonNegative, reason: 'Boxing must be a default category');
    expect(
      categories[boxing + 1],
      'Combat & Martial Arts',
      reason: 'the fight-night bucket belongs beside the combat bucket',
    );
  });

  test('a saved list without Boxing gains it on load, keeping its own order',
      () async {
    const saved = [
      'Movies & Premium Networks',
      'Premier Live Broadcasts',
      'Combat & Martial Arts',
    ];
    SharedPreferences.setMockInitialValues({
      // The persisted category key is a contract of its own: renaming it drops
      // every existing install back to the defaults, so the test spells it out
      // rather than reading it from the class under test.
      'iptv_visible_categories': saved,
    });

    await IptvSettings.initialize();

    final visible = IptvSettings.visibleCategories.value;
    expect(
      visible.contains('Boxing'),
      isTrue,
      reason: 'an existing install must reach the new rail with no migration',
    );
    expect(
      visible.indexOf('Boxing') + 1,
      visible.indexOf('Combat & Martial Arts'),
      reason: 'a new default joins beside the default it is meant to sit next '
          'to, so the rail a user is looking for is not buried at the end',
    );
    expect(
      visible.where(saved.contains).toList(),
      saved,
      reason: 'the merge never reorders the categories the user already had',
    );
    expect(visible.toSet().length, visible.length, reason: 'no duplicates');
    addTearDown(() {
      IptvSettings.visibleCategories.value =
          List.from(IptvSettings.defaultCategories);
    });
  });

  test('an empty saved list still yields the full default line-up', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await IptvSettings.initialize();

    expect(IptvSettings.visibleCategories.value, IptvSettings.defaultCategories);
    addTearDown(() {
      IptvSettings.visibleCategories.value =
          List.from(IptvSettings.defaultCategories);
    });
  });
}
