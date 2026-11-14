import 'trailer_key.dart';

class Movie {
  final String id;
  final String name;
  final String? poster;
  final String? year;
  final String type;
  final String addonBaseUrl;
  final String? imdbRating;

  /// Wide artwork for the hero band, when the catalog supplied one.
  ///
  /// A poster is 2:3 and a hero is roughly 16:9, so stretching one to fill the
  /// band crops a title out of the picture. Catalog responses carry a
  /// `background` on some resources and not on others, hence nullable and
  /// resolved lazily rather than assumed.
  final String? backdrop;

  /// Muted trailer for the hero band, when one is known.
  ///
  /// Not serialised into caches: a trailer is a large remote URL resolved
  /// after the catalog response arrives, and a stale cached catalog must not
  /// pin a dead trailer URL into a rail.
  final String? trailerKey;

  /// When the title was released, from the catalog's `released` field - what
  /// a film's "New release" tag is read from. Null when the catalog omits it.
  final DateTime? releasedAt;

  /// When the most recent episode that has already aired went out, from the
  /// catalog's `videos` list (Cinemeta sends it with every series). Null for a
  /// film or a catalog that sends no episodes.
  final DateTime? latestEpisodeAt;

  /// Whether that latest aired episode is the first of its season - the
  /// difference between a "New season" tag and a "New episode" one.
  final bool latestEpisodeIsPremiere;

  Movie({
    required this.id,
    required this.name,
    this.poster,
    this.year,
    required this.type,
    required this.addonBaseUrl,
    this.imdbRating,
    this.backdrop,
    this.trailerKey,
    this.releasedAt,
    this.latestEpisodeAt,
    this.latestEpisodeIsPremiere = false,
  });

  /// Whether this movie represents a collection or franchise item.
  bool get isCollection =>
      type == 'collections' ||
      type == 'collection' ||
      id.startsWith('ctmdb.') ||
      name.toLowerCase().endsWith('collection');

  factory Movie.fromJson(Map<String, dynamic> json, String addonBaseUrl) {
    String? ratingStr;
    if (json['imdbRating'] != null) {
      ratingStr = json['imdbRating'].toString();
    } else if (json['rating'] != null) {
      ratingStr = json['rating'].toString();
    } else if (json['imdb_rating'] != null) {
      ratingStr = json['imdb_rating'].toString();
    } else if (json['vote_average'] != null) {
      ratingStr = json['vote_average'].toString();
    }

    final latest = _latestAiredEpisode(json['videos']);

    return Movie(
      releasedAt: _parseDate(json['released']),
      latestEpisodeAt: latest?.at,
      latestEpisodeIsPremiere: latest?.premiere ?? false,
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown',
      poster: json['poster']?.toString(),
      year: json['releaseInfo']?.toString() ?? json['year']?.toString(),
      type: json['type']?.toString() ?? 'movie',
      addonBaseUrl: addonBaseUrl,
      imdbRating: ratingStr,
      backdrop: json['background']?.toString(),
      // The catalog names the trailer itself, in `trailerStreams` or
      // `trailers`. Reading it here is what gives every card a trailer
      // without a TMDb credential and without a second request.
      trailerKey: trailerKeyFromPayload(json),
    );
  }

  /// The same title with its hero media filled in, leaving everything else
  /// alone. Lets a resolver enrich one item without rebuilding its siblings.
  Movie withHeroMedia({String? backdrop, String? trailerKey}) => Movie(
    id: id,
    name: name,
    poster: poster,
    year: year,
    type: type,
    addonBaseUrl: addonBaseUrl,
    imdbRating: imdbRating,
    backdrop: backdrop ?? this.backdrop,
    trailerKey: trailerKey ?? this.trailerKey,
    releasedAt: releasedAt,
    latestEpisodeAt: latestEpisodeAt,
    latestEpisodeIsPremiere: latestEpisodeIsPremiere,
  );

  static DateTime? _parseDate(Object? raw) =>
      raw == null ? null : DateTime.tryParse(raw.toString());

  /// The newest episode in [videos] that has already aired, and whether it
  /// opens its season. Specials (season 0) are ignored.
  static ({DateTime at, bool premiere})? _latestAiredEpisode(Object? videos) {
    if (videos is! List) return null;
    final now = DateTime.now();
    ({DateTime at, bool premiere})? best;
    for (final v in videos) {
      if (v is! Map) continue;
      final season = int.tryParse('${v['season'] ?? ''}') ?? 0;
      if (season <= 0) continue;
      final at = _parseDate(v['released'] ?? v['firstAired']);
      if (at == null || at.isAfter(now)) continue;
      if (best == null || at.isAfter(best.at)) {
        final number = int.tryParse('${v['episode'] ?? v['number'] ?? ''}');
        best = (at: at, premiere: number == 1);
      }
    }
    return best;
  }
}

/// The small status tag a card can carry, read from the catalog's own dates.
enum CardFreshness {
  newSeason('New season'),
  newEpisode('New episode'),
  newRelease('New release');

  const CardFreshness(this.label);
  final String label;

  /// How recent a season premiere has to be to earn "New season".
  static const Duration seasonWindow = Duration(days: 21);

  /// How recent an ordinary episode has to be to earn "New episode". Short on
  /// purpose: most popular series air weekly, so a longer window tagged nearly
  /// every one of them and the tag stopped meaning anything.
  static const Duration episodeWindow = Duration(days: 3);

  /// How recent a film's release has to be to earn the film tag.
  static const Duration releaseWindow = Duration(days: 30);

  /// The tag [movie] earns at [now], or null. Sparse on purpose: a tag on
  /// every card is noise, so only a real, recent date earns one.
  static CardFreshness? of(Movie movie, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final episode = movie.latestEpisodeAt;
    if (episode != null) {
      final age = at.difference(episode);
      if (movie.latestEpisodeIsPremiere && age <= seasonWindow) {
        return newSeason;
      }
      if (age <= episodeWindow) return newEpisode;
    }
    final released = movie.releasedAt;
    if (movie.type == 'movie' &&
        released != null &&
        !released.isAfter(at) &&
        at.difference(released) <= releaseWindow) {
      return newRelease;
    }
    return null;
  }
}
