/// The shape an artwork URL is used at, so a size upgrade knows what is
/// actually being drawn rather than guessing from the filename.
enum ArtKind { poster, backdrop }

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
/// px at DPR 2 - and the focused card grows a 1.35x copy of itself, so 500 px
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

  /// TMDb's size segment. Catalogues and detail responses carry whichever step
  /// the upstream addon chose, commonly `w500` for a poster that is then drawn
  /// at 400 physical pixels and upscaled by the focused card.
  static final RegExp _tmdbSize = RegExp(
    r'^(https?://image\.tmdb\.org/t/p/)(w\d+|original)/',
  );

  /// The largest still worth the bytes for [kind]; [url] itself for anything
  /// else.
  ///
  /// A metahub poster goes to `large` (780 x 1170) and a backdrop to `large`
  /// (1920 x 1080). A TMDb poster goes to `w780` and a backdrop to `w1280`;
  /// `original` is left alone because a 4K still would only be decoded down
  /// again. Null and empty pass through as they came.
  static String? upgrade(String? url, {ArtKind kind = ArtKind.poster}) {
    if (url == null || url.isEmpty) return url;

    final metahub = url.replaceFirstMapped(
      _metahubSize,
      (match) => '${match[1]}large/',
    );
    if (metahub != url) return metahub;

    return url.replaceFirstMapped(_tmdbSize, (match) {
      final current = match[2]!;
      if (current == 'original') return match[0]!;
      final currentWidth = int.tryParse(current.substring(1)) ?? 0;
      final target = kind == ArtKind.poster ? 780 : 1280;
      if (currentWidth >= target) return match[0]!;
      return '${match[1]}w$target/';
    });
  }
}
