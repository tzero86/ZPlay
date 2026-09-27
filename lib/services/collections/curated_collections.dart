import 'curated_collection.dart';
import 'curated_decades.dart';
import 'curated_eras.dart';
import 'curated_sagas.dart';

/// Every curated pack the app ships, in the order the Home rails and the Browse
/// vertical present them.
///
/// Sagas lead because a franchise is the stronger hook, then the 1990s genre
/// rails, then the decade lanes. The decades come last deliberately: they are
/// the broadest cut and the least surprising, so they read as a natural tail to
/// Memory Lane rather than as a second thing competing with it.
final List<CuratedCollection> curatedCollections = [
  ...curatedSagas,
  ...curatedEras,
  ...curatedDecades,
];
