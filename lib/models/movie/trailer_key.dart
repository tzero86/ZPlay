/// Where a title's trailer comes from, and how to recognise a playable one.
///
/// **The addon payload already carries the trailer.** A Stremio-style
/// catalog or meta response names it twice:
///
/// ```json
/// "trailers":       [{"source": "HzGx48E64Xg", "type": "Trailer"}]
/// "trailerStreams": [{"title": "Love of Your Life", "ytId": "HzGx48E64Xg"}]
/// ```
///
/// Measured over a live `catalog/movie/top` response: 49 of 49 items
/// carried a `trailers` entry, and 105 of the 106 entries were a single
/// video. The app read none of it, so every card asked for a trailer it
/// already had and got nothing - which is why the hover preview never
/// appeared.
///
/// A YouTube *video id* is exactly eleven characters of `[A-Za-z0-9_-]`.
/// A playlist id (`PL…`, `UU…`, `RD…`, `OL…`, `FL…`, `LL…`) is the same
/// length and the same alphabet, and one in a hundred catalog entries is
/// exactly that: `PLl99DlL6b4` is a playlist, not a video, and embedding it
/// plays a whole playlist instead of the trailer. The prefixes are what
/// separate them, so they are checked rather than assumed.
library;

/// A YouTube video id, or null when [source] is not one.
///
/// [source] is a raw id (`HzGx48E64Xg`) or a URL
/// (`https://www.youtube.com/watch?v=HzGx48E64Xg`); both are accepted,
/// because a link row and a `trailers` row spell the same video differently.
String? parseTrailerKey(Object? source) {
  if (source is! String) return null;
  final trimmed = source.trim();
  if (trimmed.isEmpty) return null;

  // A bare id is the common case and needs no parsing.
  if (_isVideoId(trimmed)) return trimmed;

  // Anything with a scheme is a URL: hand it to the same reader the
  // trailer modal uses, so a link row and a `trailers` row agree on what
  // a key is.
  if (trimmed.contains('://') || trimmed.startsWith('youtu.be/')) {
    return _keyFromUrl(trimmed);
  }
  return null;
}

/// The first playable trailer key in a catalog or meta payload.
///
/// The payload offers several rows and not all of them are a trailer: a
/// title's meta can list a teaser, a behind-the-scenes clip and the
/// official trailer, and the `type` field says which is which. The order
/// of preference is therefore:
///
/// 1. an official trailer,
/// 2. any trailer,
/// 3. an official video of any type,
/// 4. any video at all.
///
/// A teaser beats an empty card; a playlist is never a trailer, so it is
/// dropped rather than embedded.
///
/// Reads [trailerStreams] first - it is the row that names the video
/// explicitly - and falls back to [trailers], which carries the same id
/// under `source`.
String? trailerKeyFromPayload(Map<String, dynamic> json) {
  final streams = json['trailerStreams'];
  if (streams is List) {
    for (final entry in streams) {
      if (entry is! Map) continue;
      final key = parseTrailerKey(entry['ytId'] ?? entry['source']);
      if (key != null) return key;
    }
  }

  final trailers = json['trailers'];
  if (trailers is List) {
    String? anyTrailer;
    String? anyVideo;
    for (final entry in trailers) {
      if (entry is! Map) continue;
      final key = parseTrailerKey(entry['source'] ?? entry['ytId']);
      if (key == null) continue;
      final type = entry['type']?.toString();
      if (type == null || type.toLowerCase().contains('trailer')) {
        if (type?.toLowerCase() == 'trailer') return key;
        anyTrailer ??= key;
      }
      anyVideo ??= key;
    }
    return anyTrailer ?? anyVideo;
  }

  return null;
}

/// Whether [value] is a YouTube video id rather than a playlist id.
bool _isVideoId(String value) {
  if (value.length != 11) return false;
  for (final unit in value.codeUnits) {
    final isAllowed =
        (unit >= 0x30 && unit <= 0x39) || // 0-9
        (unit >= 0x41 && unit <= 0x5A) || // A-Z
        (unit >= 0x61 && unit <= 0x7A) || // a-z
        unit == 0x2D || // -
        unit == 0x5F; // _
    if (!isAllowed) return false;
  }
  return !_isPlaylistId(value);
}

/// Whether [value] is a YouTube playlist id.
///
/// A playlist id has the same shape as a video id, so length and alphabet
/// cannot tell them apart. The prefix can: YouTube mints playlists as
/// `PL…` (a playlist), `UU…` (a channel's uploads), `RD…` (a mix), `OL…`
/// (a channel's albums) and `FL…`/`LL…` (a channel's favourites or
/// likes), and a video id never starts with one of those two-letter
/// prefixes.
bool _isPlaylistId(String value) {
  if (value.length < 2) return false;
  const playlistPrefixes = <String>{'PL', 'UU', 'RD', 'OL', 'FL', 'LL'};
  return playlistPrefixes.contains(value.substring(0, 2));
}

/// The video id inside a YouTube URL, or null when there is none.
String? _keyFromUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host == 'youtu.be') {
    return _valid(uri.pathSegments.isEmpty ? null : uri.pathSegments.first);
  }
  if (host != 'youtube.com' &&
      host != 'youtube-nocookie.com' &&
      !host.endsWith('.youtube.com') &&
      !host.endsWith('.youtube-nocookie.com')) {
    return null;
  }
  final segments = uri.pathSegments;
  if (segments.length >= 2 &&
      (segments[0] == 'embed' ||
          segments[0] == 'shorts' ||
          segments[0] == 'v')) {
    return _valid(segments[1]);
  }
  return _valid(uri.queryParameters['v']);
}

String? _valid(String? value) {
  if (value == null) return null;
  return _isVideoId(value) ? value : null;
}
