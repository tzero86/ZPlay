/// The trailer modal: TMDb's YouTube key, played inside the app.
///
/// Every trailer affordance in the app used to hand a `youtube.com/watch` URL
/// to `url_launcher` and leave the app. TMDb resolves a trailer to a YouTube
/// *key*, and nothing here can play one: Media3 and mpv have no extractor for a
/// YouTube watch page, and `services/music/youtube_audio_extractor.dart` is the
/// only thing that talks to InnerTube, for audio. So the key is embedded in a
/// webview instead, in a modal that is a surface of this app rather than a
/// browser window on top of it.
///
/// **The wrapper.** The video is not the webview's top-level document: it is an
/// iframe inside a tiny local HTML document whose origin is
/// [_embedOrigin]. That origin is load-bearing. YouTube's embed refuses to play
/// a request that arrives with no referrer at all - which is what a document
/// loaded from a bare string has, `about:blank` on WebView2 and on Android's
/// `loadData` - so the wrapper is loaded *onto* a real https origin and the
/// iframe carries `referrerpolicy="strict-origin-when-cross-origin"`. Android
/// gets that origin from the platform API's `baseUrl`; WebView2, which has no
/// equivalent, gets it from a virtual host name mapped to the wrapper's folder.
///
/// **Playback without a gesture.** The embed autoplays, which every webview
/// blocks by default; the Android WebView is told not to require a gesture,
/// because the input on a television is a remote and not a tap.
///
/// **The fallback is a real path, not a dead surface.** `show` asks the host
/// whether an embed exists at all - no WebView2 runtime, no federated platform
/// - and hands the key to the browser when it does not, which is exactly what
/// the button did before. When the embed starts and then fails, the video area
/// says so and offers "Watch on YouTube" as a focused control, so the trailer
/// is always one press away.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../../services/theme/design_tokens.dart';
import 'focusable_card.dart';
import 'pill_button.dart';

/// What the modal needs from the platform it is running on.
///
/// Two questions, both of which a widget test has to be able to answer for:
/// whether this build can mount an embed at all, and where a trailer goes when
/// it cannot. `flutter test` has no platform webview and no browser, so the
/// default below is substituted wholesale in tests via [TrailerModal.debugHost].
abstract interface class TrailerHost {
  /// Whether an embed can be mounted. False means the key goes to the browser
  /// instead of into a modal that would have nothing in it.
  Future<bool> get canEmbed;

  /// Hands a YouTube watch URL to whatever the platform has registered for
  /// https - the launch the trailer buttons did before this modal existed.
  Future<bool> launchExternal(Uri uri);
}

/// Everything a trailer control needs: one modal, one entry point.
class TrailerModal extends StatefulWidget {
  /// The YouTube key TMDb returned.
  final String trailerKey;

  /// The title the trailer belongs to, shown so the surface states what it is
  /// playing. Null for a link that carries no title.
  final String? title;

  const TrailerModal({super.key, required this.trailerKey, this.title});

  /// Overrides the platform answers below. Test-only.
  @visibleForTesting
  static TrailerHost? debugHost;

  /// Opens [trailerKey] in the modal over [context], or hands it to YouTube
  /// when this build has no webview to play it in.
  static Future<void> show(
    BuildContext context, {
    required String trailerKey,
    String? title,
  }) async {
    final host = debugHost ?? const _PlatformTrailerHost();
    if (!await host.canEmbed) {
      // No runtime, or no federated platform for this OS (Linux, say). The key
      // still reaches the device's own YouTube - the affordance is unchanged,
      // it just is not this modal.
      await host.launchExternal(_watchUri(trailerKey));
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      // Dismissible by the barrier, by `Escape` (the framework's `DismissIntent`
      // pops a barrier-dismissible route) and by the Android back gesture, which
      // pops the route. The visible close control is the fourth path, and the
      // one a remote uses.
      barrierDismissible: true,
      // One neutral scrim, and no border or shadow under the surface: what
      // separates the modal from the page is this and nothing else.
      barrierColor: ZplayTokens.of(context).bg.withValues(alpha: 0.87),
      builder: (_) => TrailerModal(trailerKey: trailerKey, title: title),
    );
  }

  /// The watch URL a trailer falls back to, unchanged from the launch the
  /// trailer buttons used to do themselves.
  static Uri _watchUri(String trailerKey) =>
      Uri.https('www.youtube.com', '/watch', {'v': trailerKey});

  /// The YouTube key inside a trailer *link*, or null when [url] is not a
  /// YouTube video.
  ///
  /// Stremio's meta links are the case this serves: a trailer link is a
  /// category, not a type, so the same row can carry `watch?v=…`, a `youtu.be`
  /// share link, an embed or a `ytsearch:` query. Only the first three are a
  /// key this modal can play; a search belongs to the browser, which is what
  /// the caller does with a null.
  static String? youtubeKeyFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host == 'youtu.be') {
      return _key(uri.pathSegments.isEmpty ? null : uri.pathSegments.first);
    }
    if (host != 'youtube.com' &&
        host != 'youtube-nocookie.com' &&
        !host.endsWith('.youtube.com') &&
        !host.endsWith('.youtube-nocookie.com')) {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.length >= 2 &&
        (segments[0] == 'embed' || segments[0] == 'shorts' || segments[0] == 'v')) {
      return _key(segments[1]);
    }
    return _key(uri.queryParameters['v']);
  }

  /// A video key is exactly eleven characters of `[A-Za-z0-9_-]`; anything else
  /// is a playlist, a channel or a search, and none of those are a trailer.
  static String? _key(String? value) =>
      value != null && _keyPattern.hasMatch(value) ? value : null;

  static final RegExp _keyPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Where the video actually comes from. Kept apart from the wrapper's own
  /// origin on purpose: the wrapper is local and the embed is remote, and an
  /// iframe rooted at the wrapper asks the local host mapping for a file that
  /// is not there - which is a page-load error inside the stage, not a video.
  static const String _youtubeOrigin = 'https://www.youtube-nocookie.com';

  /// The wrapper document, exposed so a test can pin the one thing no widget
  /// test can observe without a real webview: that the iframe points at
  /// YouTube. This shipped pointing at its own origin once and rendered the
  /// mapping's "file not found" page inside the modal.
  @visibleForTesting
  static String debugWrapperHtml(String trailerKey) => _wrapperHtml(trailerKey);

  /// The local document the embed lives in. See the library doc for why it
  /// exists at all.
  static String _wrapperHtml(String trailerKey) {
    final src = '$_youtubeOrigin/embed/${Uri.encodeComponent(trailerKey)}'
        '?autoplay=1&playsinline=1&rel=0';
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

  @override
  State<TrailerModal> createState() => _TrailerModalState();
}

class _TrailerModalState extends State<TrailerModal> {
  /// Holds focus inside the modal for as long as it is up.
  ///
  /// A dialog is an overlay entry, and the page underneath is still in the
  /// tree, so directional traversal from the modal's controls walks out to the
  /// shell rail behind it - the same defect [P2pWarningDialog] records. A
  /// [FocusScope] with its own node keeps traversal between its descendants,
  /// and `autofocus` puts the user on the close control instead of wherever the
  /// page behind happened to leave the ring.
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'TrailerModalScope');

  /// The mounted embed, or null while it loads or once it has failed.
  Widget? _embed;

  /// Released in [dispose]; the WebView2 branch owns a native view.
  WebviewController? _windows;

  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _mount();
  }

  @override
  void dispose() {
    // Fire and forget: the widget is already leaving the tree, and the
    // controller releases the native view itself.
    _windows?.dispose();
    _scope.dispose();
    super.dispose();
  }

  Future<void> _mount() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        await _mountWebView2();
      } else {
        await _mountFederated();
      }
    } catch (error) {
      // A machine with no WebView2 runtime, a platform whose plugin is missing,
      // a key the embed rejects at load: one answer for all of them, and the
      // answer is on screen rather than in a log.
      debugPrint('[TrailerModal] trailer embed failed: $error');
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  /// Windows: `webview_windows`' successor, driven directly.
  ///
  /// It is not part of the `webview_flutter` federation - it has its own
  /// controller and widget - so this branch is not an implementation detail
  /// that could be hidden behind the federated API.
  Future<void> _mountWebView2() async {
    await _applyAutoplayPolicy();
    final controller = WebviewController();
    await controller.initialize();
    await controller.setBackgroundColor(Colors.black);
    // The wrapper needs an origin before anything navigates to it. WebView2's
    // `loadStringContent` navigates to `about:blank` and takes no base URL, so
    // the document is served from a folder mapping instead: the same end that
    // Android reaches with `baseUrl`, by a different mechanism.
    await controller.addVirtualHostNameMapping(
      _embedHost,
      await _servedWrapperDirectory(),
      WebviewHostResourceAccessKind.allow,
    );
    await controller.loadUrl('$_embedOrigin/$_wrapperFile');
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _windows = controller;
      _embed = Webview(controller);
    });
  }

  /// Whether the WebView2 environment has been asked for the autoplay policy.
  ///
  /// One attempt per process: the environment is shared and is configured
  /// before the first controller exists, which is the only moment the call is
  /// allowed - it throws while any controller is alive.
  static bool _autoplayPolicyRequested = false;

  /// Chromium's own switch, passed through to the browser process by WebView2.
  ///
  /// Chromium refuses to start an unmuted video without a user gesture, and a
  /// remote is not a gesture; without this the embed opens on YouTube's play
  /// button instead of playing. Verified on the shipped release build: before
  /// the switch the modal showed the trailer's poster and a play button.
  static const String _autoplayArgument =
      '--autoplay-policy=no-user-gesture-required';

  /// Applies [_autoplayArgument], and never fatally.
  ///
  /// A runtime that will not take the configuration is still a runtime that can
  /// play the trailer once the user presses play, so a failure here is a
  /// fallback to YouTube's own control rather than a failed modal.
  Future<void> _applyAutoplayPolicy() async {
    if (_autoplayPolicyRequested) return;
    _autoplayPolicyRequested = true;
    try {
      await WebviewController.initializeEnvironment(
        additionalArguments: _autoplayArgument,
      );
    } catch (error) {
      debugPrint('[TrailerModal] WebView2 autoplay policy not applied: $error');
    }
  }

  /// Everything else: the federated API, with `baseUrl` doing the work.
  Future<void> _mountFederated() async {
    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(Colors.black);
    if (controller.platform is AndroidWebViewController) {
      // Autoplay is blocked in an Android WebView until the user interacts with
      // the page, and a remote is not an interaction. Without this the trailer
      // opens on a paused player.
      await (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    await controller.loadHtmlString(
      TrailerModal._wrapperHtml(widget.trailerKey),
      baseUrl: '$_embedOrigin/',
    );
    if (!mounted) return;
    setState(() => _embed = WebViewWidget(controller: controller));
  }

  /// Writes the wrapper and returns the folder to map [_embedHost] onto.
  ///
  /// One fixed path, rewritten per open: the document is a few hundred bytes,
  /// and a per-key file would leave one behind for every trailer ever watched.
  Future<String> _servedWrapperDirectory() async {
    final directory = Directory(p.join((await getTemporaryDirectory()).path, 'trailer'));
    await directory.create(recursive: true);
    await File(p.join(directory.path, _wrapperFile))
        .writeAsString(TrailerModal._wrapperHtml(widget.trailerKey));
    return directory.path;
  }

  /// The origin the wrapper is served from.
  ///
  /// It is a name, not a server: on Android it is the document's base URL and
  /// is never requested, and on Windows the virtual host mapping answers for it
  /// locally. YouTube only has to see *an* origin.
  static const String _embedHost = 'trailer.zplay.local';
  static const String _embedOrigin = 'https://$_embedHost';
  static const String _wrapperFile = 'index.html';

  /// The header row: what is playing, and the way out.
  ///
  /// `ZplayType.subtitle` for the name and `caption` for the role, so the
  /// hierarchy is weight and size rather than a box around either. The close
  /// control is the modal's only always-present focusable, so it takes the
  /// autofocus the scope hands out.
  Widget _header(ZplayTokens tokens) {
    final title = widget.title;
    final hasTitle = title != null && title.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZplaySpacing.s20,
        ZplaySpacing.s8,
        ZplaySpacing.s8,
        ZplaySpacing.s8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasTitle ? title : 'Trailer',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                ),
                if (hasTitle)
                  Text(
                    'Trailer',
                    style: ZplayType.caption.toStyle(color: tokens.textMuted),
                  ),
              ],
            ),
          ),
          _CloseButton(onPressed: () => Navigator.of(context).maybePop()),
        ],
      ),
    );
  }

  /// The 16:9 area: the embed, its loading state, or the way out of it.
  Widget _stage(ZplayTokens tokens) {
    if (_failed) return _unavailable(tokens);
    final embed = _embed;
    if (embed == null) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: tokens.textMuted,
        ),
      );
    }
    return embed;
  }

  /// The failure state, and the reason it is not a message alone.
  ///
  /// The embed can be absent for reasons the user cannot fix from here (a
  /// machine without the WebView2 runtime), so the modal still has to be able
  /// to produce the video. "Watch on YouTube" is the same launch the button
  /// used to perform, now one press after the trailer was asked for.
  Widget _unavailable(ZplayTokens tokens) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZplaySpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Trailer unavailable',
              textAlign: TextAlign.center,
              style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
            ),
            const SizedBox(height: ZplaySpacing.s4),
            Text(
              'This trailer could not be played in the app.',
              textAlign: TextAlign.center,
              style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
            ),
            const SizedBox(height: ZplaySpacing.s16),
            PillButton(
              label: 'Watch on YouTube',
              icon: Icons.open_in_new_rounded,
              variant: PillVariant.secondary,
              onPressed: _openExternal,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openExternal() async {
    final host = TrailerModal.debugHost ?? const _PlatformTrailerHost();
    await host.launchExternal(TrailerModal._watchUri(widget.trailerKey));
  }

  /// 78% of the window wide, and never taller than 84% of it once the header is
  /// counted. On a 960x540 television the height is the constraint that binds,
  /// which is the point of taking the smaller of the two: the video stays 16:9
  /// and the surface keeps a margin on all four edges (~43 dp above and below at
  /// that size) rather than being squashed or cropped to fit the width.
  static const double _widthFactor = 0.78;
  static const double _heightFactor = 0.84;

  /// The header's own height: [ZplaySpacing.s8] either side of a 40 dp control.
  static const double _headerHeight =
      ZplaySpacing.s8 + _CloseButton.size + ZplaySpacing.s8;

  static double _surfaceWidth(Size window) => math.min(
    window.width * _widthFactor,
    (window.height * _heightFactor - _headerHeight) * 16 / 9,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final window = MediaQuery.sizeOf(context);

    return FocusScope(
      node: _scope,
      autofocus: true,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(ZplaySpacing.s24),
        child: SizedBox(
          width: _surfaceWidth(window),
          child: DecoratedBox(
            // One surface, one radius, no border and no shadow. `ClipRRect`
            // under it is what lets the video area's own corners be the
            // surface's corners rather than a second, smaller round rectangle
            // inside the first.
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              borderRadius: ZplayRadius.lgAll,
            ),
            child: ClipRRect(
              borderRadius: ZplayRadius.lgAll,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _header(tokens),
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    // Black, and neutral by design: it is the letterbox the
                    // video sits in, not a colour of this app's chrome.
                    child: ColoredBox(
                      color: Colors.black,
                      child: _stage(tokens),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The real answers to [TrailerHost], and the only place the platform packages
/// are touched.
class _PlatformTrailerHost implements TrailerHost {
  const _PlatformTrailerHost();

  @override
  Future<bool> get canEmbed async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      // WebView2 is a runtime the machine may not have, and this answers that
      // without mounting anything: the plugin returns a null version when
      // `GetAvailableCoreWebView2BrowserVersionString` fails. An unregistered
      // plugin throws instead, which is the same answer.
      try {
        return await WebviewController.getWebViewVersion() != null;
      } catch (error) {
        debugPrint('[TrailerModal] WebView2 runtime unavailable: $error');
        return false;
      }
    }
    // The federated platforms register themselves; a target with no
    // implementation leaves this null, and there is nothing to embed.
    return WebViewPlatform.instance != null;
  }

  @override
  Future<bool> launchExternal(Uri uri) async {
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (error) {
      // A device with no browser and no YouTube, or a key the platform
      // rejects. There is nothing to recover and nothing worth interrupting
      // the user with.
      debugPrint('[TrailerModal] external trailer launch failed: $error');
    }
    return false;
  }
}

/// The modal's way out: one 40 dp target, the app's single focus ring.
///
/// The same control [ShortcutsSheet] uses, for the same reason - a close
/// affordance that a remote can reach is not the same thing as a gesture on the
/// barrier.
class _CloseButton extends StatelessWidget {
  static const double size = 40;

  final VoidCallback onPressed;

  const _CloseButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      label: 'Close trailer',
      child: FocusableCard(
        onTap: onPressed,
        builder: (context, state) => CardFocusRing(
          focused: state.focused,
          radius: ZplayRadius.smAll,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: state.highlighted
                  ? tokens.surfaceRaised
                  : Colors.transparent,
              borderRadius: ZplayRadius.smAll,
            ),
            child: Icon(
              Icons.close_rounded,
              size: 20,
              color: state.highlighted
                  ? tokens.textPrimary
                  : tokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
