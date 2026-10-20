/// The YouTube embed used by the trailer modal and the hover preview.
///
/// YouTube refuses an embed that arrives with no referrer, so the video is an
/// iframe inside a tiny local document loaded onto a real https origin. Android
/// gets that origin from `loadHtmlString`'s `baseUrl`; WebView2, which has no
/// equivalent, serves the document from a virtual host mapping. Both paths use
/// the constants below, so the host and the document cannot drift apart.
abstract final class TrailerEmbed {
  static const String host = 'trailer.zplay.local';
  static const String origin = 'https://$host';
  static const String wrapperFile = 'index.html';

  /// The wrapper document for [trailerKey].
  ///
  /// [muted] and [controls] exist for the inline card preview: it must start
  /// without a gesture and must not put YouTube's chrome on top of a poster.
  /// The modal keeps the default (sound and controls).
  static String wrapperHtml(
    String trailerKey, {
    bool muted = false,
    bool controls = true,
  }) {
    final params = <String>[
      'autoplay=1',
      'playsinline=1',
      'rel=0',
      if (muted) 'mute=1',
      if (!controls) 'controls=0',
      if (!controls) 'modestbranding=1',
      if (!controls) 'iv_load_policy=3',
      if (!controls) 'disablekb=1',
      if (!controls) 'fs=0',
      if (!controls) 'loop=1&playlist=${Uri.encodeComponent(trailerKey)}',
    ].join('&');
    final src =
        'https://www.youtube-nocookie.com/embed/${Uri.encodeComponent(trailerKey)}?$params';
    return '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="referrer" content="strict-origin-when-cross-origin">
<title>Trailer</title>
<style>
html,body{margin:0;padding:0;height:100%;background:#000;overflow:hidden}
iframe{border:0;position:absolute;inset:0;width:100%;height:100%}
</style>
</head>
<body>
<iframe src="$src" title="Trailer"
 allow="autoplay; encrypted-media; fullscreen; picture-in-picture"
 allowfullscreen
 referrerpolicy="strict-origin-when-cross-origin"></iframe>
</body>
</html>
''';
  }
}
