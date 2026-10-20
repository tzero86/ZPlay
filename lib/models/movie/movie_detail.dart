import 'link.dart';
import 'trailer_key.dart';
import 'video.dart';

class MovieDetail {
  final String id;
  final String type;
  final String name;
  final String? poster;
  final String? background;
  final String? logo;
  final String? description;
  final String? year;
  final String? imdbRating;
  final List<String> genres;
  final List<String> cast;
  final List<String> director;
  final String? runtime;
  final List<Link> links;
  final List<Video> videos;
  final String? tmdbId;

  /// The title's trailer, when the info response named one.
  ///
  /// The same payload that carries the description carries the trailer, in
  /// `trailers` or `trailerStreams`; a title whose catalog row had no
  /// trailer still usually has one here.
  final String? trailerKey;

  MovieDetail({
    required this.id,
    required this.type,
    required this.name,
    this.poster,
    this.background,
    this.logo,
    this.description,
    this.year,
    this.imdbRating,
    this.genres = const [],
    this.cast = const [],
    this.director = const [],
    this.runtime,
    this.links = const [],
    this.videos = const [],
    this.tmdbId,
    this.trailerKey,
  });

  /// Whether this detail represents a collection or franchise item.
  bool get isCollection =>
      type == 'collections' ||
      type == 'collection' ||
      id.startsWith('ctmdb.') ||
      name.toLowerCase().endsWith('collection');

  MovieDetail copyWith({
    String? id,
    String? type,
    String? name,
    String? poster,
    String? background,
    String? logo,
    String? description,
    String? year,
    String? imdbRating,
    List<String>? genres,
    List<String>? cast,
    List<String>? director,
    String? runtime,
    List<Link>? links,
    List<Video>? videos,
    String? tmdbId,
    String? trailerKey,
  }) {
    return MovieDetail(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      poster: poster ?? this.poster,
      background: background ?? this.background,
      logo: logo ?? this.logo,
      description: description ?? this.description,
      year: year ?? this.year,
      imdbRating: imdbRating ?? this.imdbRating,
      genres: genres ?? this.genres,
      cast: cast ?? this.cast,
      director: director ?? this.director,
      runtime: runtime ?? this.runtime,
      links: links ?? this.links,
      videos: videos ?? this.videos,
      tmdbId: tmdbId ?? this.tmdbId,
      trailerKey: trailerKey ?? this.trailerKey,
    );
  }

  factory MovieDetail.fromJson(Map<String, dynamic> json) {
    return MovieDetail(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'movie',
      name: json['name']?.toString() ?? 'Unknown',
      poster: json['poster']?.toString(),
      background: json['background']?.toString(),
      logo: json['logo']?.toString(),
      description: json['description']?.toString(),
      year: json['releaseInfo']?.toString() ?? json['year']?.toString(),
      imdbRating: json['imdbRating']?.toString(),
      genres: _parseStringList(json['genres']),
      cast: _parseStringList(json['cast']),
      director: _parseStringList(json['director']),
      runtime: json['runtime']?.toString(),
      links:
          (json['links'] as List<dynamic>?)
              ?.map((e) => Link.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      videos:
          (json['videos'] as List<dynamic>?)
              ?.map((e) => Video.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tmdbId: json['moviedb_id']?.toString(),
      // The info response names the trailer in the same two rows the
      // catalog uses - see [trailerKeyFromPayload].
      trailerKey: trailerKeyFromPayload(json),
    );
  }
}

List<String> _parseStringList(dynamic value) {
  if (value == null) return [];
  if (value is String) return [value];
  if (value is List) return value.map((e) => e.toString()).toList();
  return [];
}
