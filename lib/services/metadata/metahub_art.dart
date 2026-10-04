/// Keyless artwork by IMDb id.
///
/// Metahub serves a still, a logo and a poster for a well-formed IMDb id with
/// no API key and no account, so artwork stops being a thing the user has to
/// configure. An id metahub does not know returns HTTP 404 and the caller
/// shows its own fallback - this class never throws and never returns null.
abstract final class MetahubArt {
  /// Matches `tt` followed by digits - the only shape metahub knows.
  static final RegExp _imdbId = RegExp(r'^tt[0-9]+$');

  /// True for a syntactically usable IMDb id. Real ids are `tt` followed by
  /// digits; metahub 404s on anything else, so a caller should skip the
  /// request entirely rather than spend a round trip on it.
  static bool isUsableId(String imdbId) => _imdbId.hasMatch(imdbId);

  /// 16:9 still for a hero band or a landscape card.
  static String backdropUrl(String imdbId, {String size = 'large'}) =>
      _url('background', size, imdbId);

  /// Transparent title treatment, or null when the caller prefers text.
  static String logoUrl(String imdbId, {String size = 'large'}) =>
      _url('logo', size, imdbId);

  /// 2:3 poster. `large` by default, because the two sizes below it are too
  /// small for a card on a television — see [ArtQuality] for the measurements
  /// and for the upgrade applied to posters that arrive already sized.
  static String posterUrl(String imdbId, {String size = 'large'}) =>
      _url('poster', size, imdbId);

  static String _url(String kind, String size, String imdbId) =>
      'https://images.metahub.space/$kind/$size/$imdbId/img';
}
