/// Artwork sizing: asks the CDN for the largest still that is worth the bytes.
///
/// The sizes here are measured, not guessed (probed 2026-10-04 against
/// `images.metahub.space`, the CDN every poster in this app resolves through -
/// Cinemeta, the Trakt/Simkl transformers, the list sources and My List all
/// build `poster/medium` URLs by hand):
///
///   poster/small       480 x 270
///   poster/medium      500 x 750
///   poster/large       780 x 1170
///   background/medium 1920 x 1080
///   background/large  1920 x 1080, and 3038 x 1707 on newer titles
///
/// A poster card on the television draws roughly 200 logical dp - 400 physical
/// px at DPR 2 - and the focused card paints a 1.15x copy of itself, so 500 px
/// is close enough to look acceptable in a static mock and just small enough to
/// soften on the panel. 780 px costs about 70 KB more per poster in the shared
/// 30-day cache (see [AppImageCache]) and is the difference between a poster
/// and a smudge.
///
/// Only the size segment is rewritten. A URL the CDN does not own is returned
/// untouched, because guessing at another host's sizing scheme is how a working
/// image turns into a 404.
abstract final class ArtQuality {
  /// Matches the size segment of a metahub still, and nothing else: the host is
  /// anchored so a URL that merely *mentions* the domain in a query string is
  /// left alone.
  static final RegExp _metahubSize = RegExp(
    r'^(https?://images\.metahub\.space/(?:poster|background|logo)/)'
    r'(?:small|medium)/',
  );

  /// The `large` variant of a metahub still; [url] itself for anything else.
  ///
  /// Null and empty pass through as they came, so a caller can hand this a
  /// nullable `movie.poster` without a second guard. Null stays null: the
  /// difference between "no art" and "art" is the caller's to render, and a
  /// blank string is the one value that would reach the image as a request for
  /// the current page.
  static String? upgrade(String? url) {
    if (url == null || url.isEmpty) return url;
    return url.replaceFirstMapped(
      _metahubSize,
      (match) => '${match[1]}large/',
    );
  }
}
