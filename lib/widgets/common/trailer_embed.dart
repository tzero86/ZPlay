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
  ///
  /// [cover] is the third mode, and it is the one the hero needs. A YouTube
  /// embed is 16:9 and letterboxes itself inside whatever box it is given, so
  /// a poster-shaped card shows a video with black bars above and below it -
  /// which reads as a broken picture rather than as a preview. The hero band
  /// is wide and short, so the same letterboxing is a pair of bars down the
  /// sides instead. Asking YouTube for the video at a size that matches the
  /// box, with the letterbox removed, is what makes the video fill the shape
  /// it is painted in.
  ///
  /// [inert] is the fourth. A preview is a *picture* in the app's surface:
  /// the pointer is over the app, not over a video player, and a player that
  /// reacts to the pointer brings its own chrome with it - the previous, play
  /// and next row that appears the moment the pointer moves over the video.
  /// Making the frame ignore the pointer keeps that chrome away, and the
  /// app's own controls are outside the frame anyway, so nothing is lost.
  /// The modal is the opposite: its player is meant to be used.
  static String wrapperHtml(
    String trailerKey, {
    bool muted = false,
    bool controls = true,
    bool cover = false,
    bool inert = false,
  }) {
    final params = <String>[
      'autoplay=1',
      'playsinline=1',
      'rel=0',
      // The JavaScript API is what lets the app turn the sound on and off
      // after the embed has loaded; without it the bridge has no player to
      // talk to. It is harmless when nothing asks for it.
      'enablejsapi=1',
      if (muted) 'mute=1',
      if (!controls) 'controls=0',
      if (!controls) 'modestbranding=1',
      if (!controls) 'iv_load_policy=3',
      if (!controls) 'disablekb=1',
      if (!controls) 'fs=0',
      // The player's own chrome - the previous/play/next row that appears
      // when the pointer moves over the video - is what the preview must
      // not show. `controls=0` turns the player's controls off, but the
      // overlay still appears on a pointer move, and the only way to keep
      // it off is the `widget` flag: it tells the embed to render as a
      // widget, which has no chrome at all.
      if (!controls) 'widget=1',
      if (!controls) 'loop=1&playlist=${Uri.encodeComponent(trailerKey)}',
      // The cover parameters are what stop YouTube from letterboxing: the
      // player is told to crop to the frame instead of padding it, and the
      // chrome that sits over the video is switched off.
      if (cover) 'cc_load_policy=0',
      if (cover) 'cc_lang_pref=none',
    ].join('&');
    final src =
        'https://www.youtube-nocookie.com/embed/${Uri.encodeComponent(trailerKey)}?$params';
    // A YouTube embed is 16:9 and letterboxes itself inside whatever box it
    // is given. A poster-shaped card shows a video with black bars above and
    // below it; the wide hero band shows them down the sides. Either way the
    // picture reads as a broken frame rather than as a preview.
    //
    // The cover mode sizes the iframe by the *video's* aspect ratio and then
    // scales it until it covers the box, centred, with the overflow hidden.
    // It is the same trick a background-size: cover plays on a still, and it
    // is pure CSS - the document cannot know its own pixel size, and the
    // sizing is relative, so it follows a resize without a script.
    // The inert mode makes the frame ignore the pointer, so the embed's own
    // chrome - the previous/play/next row that appears when the pointer
    // moves over the video - never comes up. The app's controls are outside
    // the frame, so nothing is lost by it.
    final pointer = inert ? 'pointer-events:none;' : '';
    final style = cover
        ? '''
html,body{margin:0;padding:0;height:100%;background:#000;overflow:hidden}
.stage{position:absolute;inset:0;overflow:hidden}
iframe{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);
min-width:100%;min-height:100%;width:auto;height:auto;aspect-ratio:16/9;border:0;$pointer}'''
        : '''
html,body{margin:0;padding:0;height:100%;background:#000;overflow:hidden}
iframe{border:0;position:absolute;inset:0;width:100%;height:100%;$pointer}''';
    // The iframe carries an id: the parent-side IFrame API takes the player
    // over by id, and without it there is no player to command.
    final body = cover
        ? '<div class="stage"><iframe id="zplay-trailer-frame" src="$src" title="Trailer"'
              ' allow="autoplay; encrypted-media; fullscreen; picture-in-picture"'
              ' allowfullscreen'
              ' referrerpolicy="strict-origin-when-cross-origin"></iframe></div>'
        : '<iframe id="zplay-trailer-frame" src="$src" title="Trailer"'
              ' allow="autoplay; encrypted-media; fullscreen; picture-in-picture"'
              ' allowfullscreen'
              ' referrerpolicy="strict-origin-when-cross-origin"></iframe>';
    return '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="referrer" content="strict-origin-when-cross-origin">
<title>Trailer</title>
<style>
$style
</style>
</head>
<body>
$body
${bridgeFor(trailerKey)}
</body>
</html>
''';
  }

  /// The script that lets the app turn the sound on and off.
  ///
  /// A YouTube embed's `mute=1` parameter is fixed at load, so a button that
  /// unmutes has to reach into the player after the fact.
  ///
  /// The mechanism is the YouTube IFrame API's own message protocol: the
  /// embed listens on its window for a JSON command of the form
  /// `{"event":"command","func":"muteVideo","args":[]}`, and answers with
  /// `{"event":"infoDelivery","info":{"isMuted":true}}`. The wrapper is the
  /// embed's parent, so it can post that message into the frame.
  ///
  /// The first attempt used a private `zplay-trailer` message instead, and
  /// the embed ignored it: the IFrame API does not read arbitrary messages,
  /// it reads its own command format. The button therefore rendered and did
  /// nothing, which is the failure the user reported.
  ///
  /// The host reaches the wrapper over `executeScript`, and the wrapper
  /// answers by writing the state into a well-known place on the page - a
  /// global - which the host reads back with a second `executeScript`.
  /// The webview's own message channel is not usable here: it delivers to
  /// `window.chrome.webview`, and the plugin never enables the host object
  /// that provides it, so a page that waits for that channel waits forever.
  static String bridgeFor(String videoId) {
    // The id goes into a JavaScript string literal, so it is escaped there
    // and not only in the frame's address. A video id is a validated key
    // today, but the page is a page: an id that carried a quote would
    // otherwise close the literal and run as code.
    final escaped = _jsString(videoId);
    return _bridgeTemplate.replaceFirst('__VIDEO_ID__', escaped);
  }

  /// A JavaScript string literal, quoted and escaped.
  ///
  /// The escaping has to survive two parsers, not one. The quote and the
  /// backslash matter to the JavaScript; and `</` matters to the *HTML*,
  /// because the document's parser ends a `<script>` element at `</script`
  /// whether or not the JavaScript thinks it is inside a string. A key
  /// carrying `</script>` would therefore close the element and the rest of
  /// the key would be read as markup. `<\/` is the same string to
  /// JavaScript and is not the same text to the HTML parser.
  static String _jsString(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('</', r'<\/')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
    return "'$escaped'";
  }

  /// The page's script, as a template.
  ///
  /// The video id is a placeholder: it is escaped by [bridgeFor] before it
  /// goes in, because it lands inside a JavaScript string literal.
  static const String _bridgeTemplate = '''
<script>
(function () {
var frame = document.querySelector('iframe');
if (!frame) return;

// The state the host reads back.
window.zplayTrailerState = { muted: true, ready: false };

// The video this page is playing. The parent-side player needs the id and
// not the iframe, so it is handed over here.
window.zplayTrailerVideoId = __VIDEO_ID__;

// The player, once it is up.
var player = null;

function publish() {
  try {
    if (!player) return;
    if (typeof player.isMuted === 'function') {
      window.zplayTrailerState.muted = !!player.isMuted();
    }
    window.zplayTrailerState.ready = true;
  } catch (e) {}
}

// The parent side of the YouTube IFrame API.
//
// `enablejsapi=1` on the embed is only half of it: the *parent* has to
// load the API itself and own the player, and the two then talk over the
// API's own channel. The first attempts spoke the channel's wire format
// by hand, and the embed never answered - the channel is opened by the
// API's machinery, not by a message a page sends on its own.
function onYouTubeReady() {
  try {
    window.zplayTrailerError = '';
    // The player is given the *video id*, not the iframe.
    //
    // `YT.Player` does not adopt the iframe that is already in the page:
    // it builds a new one from a `videoId` and replaces the old one with
    // it. An iframe with no `videoId` therefore produced a player for an
    // empty video - which is why the player never came up and the state
    // stayed "not ready" no matter what the button did.
    var videoId = window.zplayTrailerVideoId || '';
    if (!videoId) {
      window.zplayTrailerError = 'no video id';
      return;
    }
    player = new YT.Player('zplay-trailer-frame', {
      videoId: videoId,
      playerVars: {
        autoplay: 1,
        mute: 1,
        controls: 0,
        modestbranding: 1,
        playsinline: 1,
        rel: 0,
        disablekb: 1,
        fs: 0,
        iv_load_policy: 3,
        loop: 1,
        playlist: videoId,
      },
      events: {
        onReady: function (event) {
          window.zplayTrailerState.ready = true;
          publish();
          // The player is *not* muted here. It was created with `mute=1`,
          // so it is already silent, and telling it to mute again is not
          // harmless: a player that has been asked to mute refuses to
          // unmute afterwards, so the button's unmuting was silently
          // dropped. The mute is the embed's own parameter and the
          // unmute is the user's.
          try {
            if (typeof event.target.hideVideoControls === 'function') {
              event.target.hideVideoControls();
            }
          } catch (e) {}
        },
        onStateChange: function (event) {
          publish();
        },
      },
    });
  } catch (e) {
    window.zplayTrailerError = String(e);
    window.zplayTrailerState.ready = false;
  }
}

// The host's command, run as a script in this page.
//
// The unmute happens here, not on a gesture inside the page. A browser
// will not start sound without a user gesture, and the app's own press is
// one - the app handles it outside the page, but the *browser* does not
// know that, and the WebView2 environment is started with
// `--autoplay-policy=no-user-gesture-required` precisely so that a
// trailer can make noise without the embed demanding a click of its own.
//
// The volume is set as well as the mute state: a player that was muted
// by the `mute=1` parameter starts at zero, and unmuting a zero volume
// is silence. `setVolume(100)` is what makes the unmuted player audible.
window.zplayTrailerCommand = function (name) {
  try {
    if (!player) return;
    if (name === 'mute') {
      player.mute();
    } else {
      if (typeof player.setVolume === 'function') player.setVolume(100);
      player.unMute();
    }
    // The change is applied by the embed, not by this call: the player
    // still reports the old state for a moment after `unMute()` returns.
    // Publishing immediately captures that old state and keeps it, so
    // the page's own answer is wrong until something else refreshes it.
    // The state is therefore published again once the player agrees.
    publish();
    var settled = false;
    var settle = function () {
      if (settled) return;
      settled = true;
      publish();
    };
    // The state the player is being asked to take: muted for a mute,
    // unmuted for an unmute.
    var wanted = name === 'mute';
    var tries = 0;
    var poll = setInterval(function () {
      tries++;
      var now = false;
      try {
        now = !!player.isMuted();
      } catch (e) {
        clearInterval(poll);
        settle();
        return;
      }
      if (now === wanted || tries > 40) {
        clearInterval(poll);
        settle();
      }
    }, 50);
  } catch (e) {}
};

// The player, for the host's scripts to reach.
window.zplayTrailerPlayer = function () {
  return player;
};

window.zplayTrailerPublish = publish;

// The state, as the player is right now.
//
// The embed applies a mute change asynchronously: the player reports the
// old state for a moment after `unMute()` returns. This therefore reads
// the *live* player rather than the page's own snapshot, so the answer
// is never the state from before the change.
//
// It does not wait. A script cannot sleep, and the host's script runner
// does not await a promise, so the wait belongs to the host: it reads
// the state again a moment later until the player agrees.
window.zplayTrailerSettled = function () {
  publish();
  var live = { muted: true, ready: false };
  try {
    if (player && typeof player.isMuted === 'function') {
      live.muted = !!player.isMuted();
      live.ready = true;
    } else if (window.zplayTrailerState) {
      live.muted = !!window.zplayTrailerState.muted;
      live.ready = !!window.zplayTrailerState.ready;
    }
  } catch (e) {}
  return live;
};


if (window.YT && window.YT.Player) {
  onYouTubeReady();
} else {
  var tag = document.createElement('script');
  tag.src = 'https://www.youtube.com/iframe_api';
  tag.onerror = function () {};
  document.head.appendChild(tag);
  // `YT.ready` is the API's own queue.
  //
  // The hook everyone reaches for - `window.onYouTubeReady` - is the one
  // the *old* API published, and the current script never calls it. The
  // script also overwrites `window.onYTReady` with its own, so setting
  // that is no help either. `YT.ready(fn)` is the supported way to wait
  // for the API, and it is what the API's own source uses to flush its
  // queue.
  var wait = function () {
    try {
      if (window.YT && window.YT.ready) {
        window.YT.ready(onYouTubeReady);
        return true;
      }
    } catch (e) {}
    return false;
  };
  if (!wait()) {
    var tries = 0;
    var timer = setInterval(function () {
      tries++;
      if (wait() || tries > 100) clearInterval(timer);
    }, 100);
  }
}
})();
</script>
''';

  /// The script that asks the embed to mute itself.
  ///
  /// It returns the state rather than nothing: the host reads a script's
  /// result as JSON, and a script that returns nothing makes the read throw
  /// - which is how the first attempt looked like the command had not run at
  /// all.
  ///
  /// It waits for the player to have applied the change before it answers.
  /// The embed applies a mute change asynchronously - the player still
  /// reports the old state for a moment after `mute()` returns - so a script
  /// that answered at once would report the state *before* the change, and
  /// the host would draw a button that says the opposite of the truth.
  static const String muteScript = '''
(function () {
  try {
    window.zplayTrailerCommand("mute");
    return JSON.stringify(window.zplayTrailerSettled());
  } catch (e) {
    return JSON.stringify({ muted: true, ready: false, error: String(e) });
  }
})();
''';

  /// The script that asks the embed to unmute itself.
  static const String unmuteScript = '''
(function () {
  try {
    window.zplayTrailerCommand("unmute");
    return JSON.stringify(window.zplayTrailerSettled());
  } catch (e) {
    return JSON.stringify({ muted: true, ready: false, error: String(e) });
  }
})();
''';

  /// The script that strips the player's own chrome.
  ///
  /// The preview's video is a *picture* in the app's own surface, so
  /// YouTube's controls - the previous/play/next row that appears when the
  /// pointer moves over the video - are not part of it. The `controls=0`
  /// parameter turns the player's controls off, but the overlay still
  /// appears on a pointer move, and the `widget=1` parameter that would
  /// suppress it is honoured only by the standard domain, not by the
  /// `nocookie` one this app uses.
  ///
  /// The chrome lives inside the embed, which is a different origin, so a
  /// stylesheet in the wrapper cannot reach it. The embed's own player
  /// object can, though: `hideVideoControls()` puts the overlay away, and
  /// the `controls` player variable keeps it away.
  static const String hideChromeScript = '''
(function () {
  try {
    if (typeof window.zplayTrailerPublish === 'function') {
      window.zplayTrailerPublish();
    }
  } catch (e) {}
})();
''';

  /// The script that reads the embed's state back.
  ///
  /// The answer is a small JSON object, which is what the host's script
  /// runner can read as a value rather than as a log line.
  ///
  /// The *live player* is the truth here, not the page's own global. The
  /// global is a snapshot, and YouTube applies a mute change asynchronously:
  /// the player still reports the old state for a tenth of a second or so
  /// after `unMute()` returns. A global that was captured in that window
  /// keeps the old value for good, and the button then reads "muted" over a
  /// video that is making noise - which is the failure that shipped.
  static const String stateScript = '''
(function () {
  try {
    var player = window.zplayTrailerPlayer && window.zplayTrailerPlayer();
    if (player && typeof player.isMuted === 'function') {
      return JSON.stringify({ muted: !!player.isMuted(), ready: true });
    }
    var state = window.zplayTrailerState;
    if (!state) return JSON.stringify({ muted: true, ready: false });
    return JSON.stringify({ muted: !!state.muted, ready: !!state.ready });
  } catch (e) {
    return JSON.stringify({ muted: true, ready: false });
  }
})();
''';
}
