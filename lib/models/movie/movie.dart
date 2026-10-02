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

    return Movie(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown',
      poster: json['poster']?.toString(),
      year: json['releaseInfo']?.toString() ?? json['year']?.toString(),
      type: json['type']?.toString() ?? 'movie',
      addonBaseUrl: addonBaseUrl,
      imdbRating: ratingStr,
      backdrop: json['background']?.toString(),
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
      );
}
