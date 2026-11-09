import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/home/home_page_settings.dart';

/// The page's settings are one table now, read by [HomePageSettings.initialize]
/// and written by one generic setter. Two things have to stay true: a stored
/// value loads back into its notifier, and a write still lands under the key
/// that build has always used.
///
/// The enum row is the one that matters most: it persists a name and maps it
/// back through the enum's `values`, which is the only place a removed or
/// renamed value could throw on startup.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a stored value loads back into its notifier', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'home_show_rating': false,
    });
    await HomePageSettings.initialize();
    expect(HomePageSettings.showRating.value, isFalse);
  });

  test('an enum setting persists its name and loads it back', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await HomePageSettings.initialize();

    final original = HomePageSettings.similarPosition.value;
    final other = SimilarSectionPosition.values.firstWhere(
      (value) => value != original,
    );
    await HomePageSettings.setSimilarPosition(other);

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('home_similar_position'), other.name);

    // Reloading must come back as the enum, not the name, and must not throw.
    await HomePageSettings.initialize();
    expect(HomePageSettings.similarPosition.value, other);
  });

  test('a name the enum no longer has falls back instead of throwing', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'home_similar_position': 'aRemovedPosition',
    });
    await HomePageSettings.initialize();
    expect(
      HomePageSettings.similarPosition.value,
      isA<SimilarSectionPosition>(),
    );
  });
}