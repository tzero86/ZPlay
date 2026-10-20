import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../../services/layout/form_factor.dart';
import '../common/trailer_embed.dart';
import '../common/trailer_sound_settle.dart';
import '../common/webview_environment.dart';

/// What a surface outside the preview's own tree can ask of it.
///
/// The preview's layer is `IgnorePointer`ed, because it is a picture on top
/// of a picture and must not eat the click that opens the title. A sound
/// control that has to live *with* the picture therefore cannot be its
/// child: it would inherit the `IgnorePointer` and could not be pressed, and
/// it would be excluded from the semantics tree as well.
///
/// The handle is what the control talks to instead.
abstract interface class TrailerPreviewHandle {
  /// Turns the sound on or off.
  Future<void> toggleSound();
}

/// A muted, chrome-free YouTube trailer for a hovered card.
///
/// The modal owns the full player; this is the same embed stripped to the
/// artwork's rectangle. It is created only after the pointer has rested on a
/// card, and only on platforms with a WebView implementation. A D-pad never
/// mounts one: focus moves while the user is navigating, and an autoplaying
/// video would fight that.
class TrailerPreview extends StatefulWidget {
  const TrailerPreview({
    super.key,
    required this.trailerKey,
    this.onFailed,
    this.cover = false,
    this.onSoundChanged,
  });

  final String trailerKey;
  final VoidCallback? onFailed;

  /// Reports the sound state as the embed answers it.
  ///
  /// The embed owns the truth - it may refuse to unmute, and it may be
  /// muted by something else - so the icon is drawn from the embed's answer
  /// rather than from the press that asked for it.
  final ValueChanged<bool>? onSoundChanged;

  /// Whether the video fills its box instead of letterboxing inside it.
  ///
  /// A YouTube embed is 16:9 and pads itself to fit, so a poster-shaped card
  /// shows black bars above and below the video and a wide band shows them
  /// down the sides. The hero band is wide, so it asks for the cover: the
  /// video is scaled to fill the band and the overflow is cropped, which is
  /// what a still would have done.
  final bool cover;

  /// Test seam; avoids a real WebView in widget tests.
  @visibleForTesting
  static Widget Function(String trailerKey)? debugBuilder;

  /// Whether this platform can play a trailer at all.
  ///
  /// Linux has no WebView implementation, so a preview there is a black
  /// rectangle: the gate must not even start one.
  ///
  /// A [debugBuilder] stands in for the WebView, so a platform without one
  /// can still run the preview's own logic - which is what the widget tests
  /// do, and they run on Linux in CI. Without this the whole gate was
  /// unreachable outside Windows, and the test that pins the dwell passed
  /// only on the machine that happened to be running it.
  static bool get isSupported =>
      debugBuilder != null ||
      (!kIsWeb &&
          (Platform.isWindows ||
              Platform.isMacOS ||
              Platform.isAndroid ||
              Platform.isIOS));

  /// Test seam; stands in for the embed's script runner.
  ///
  /// The command the app sends to the embed is the whole of the sound
  /// control's behaviour, and a test cannot see it without a seam: the
  /// real one needs a WebView. The runner is given the script and answers
  /// with the state the embed reports, which is what the host reads back.
  @visibleForTesting
  static Future<dynamic> Function(String script)? debugRunScript;

  @override
  TrailerPreviewState createState() => TrailerPreviewState();
}

/// The live preview's state.
///
/// Named, not private, because the gate that owns the preview reaches it
/// through a [GlobalKey]: the key's type has to be the preview's own state
/// type, and a private one could not be written down. A key of the wrong
/// type still holds the element, but its `currentState` is read through
/// that type - so a key naming the gate's own state gave the gate's state
/// for a preview, and asking it for the sound control found nothing. The
/// button was drawn, it was pressed, and nothing happened.
class TrailerPreviewState extends State<TrailerPreview>
    implements TrailerPreviewHandle {
  WebviewController? _windows;
  WebViewController? _federated;
  Widget? _embed;

  /// The sound state, as the embed last reported it.
  ///
  /// The app owns the icon, and the embed owns the truth: a preview that
  /// says "mute" over a video that is already silent is a lie the user
  /// acts on. The embed answers, and this holds the answer.
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _mount();
  }

  @override
  void didUpdateWidget(covariant TrailerPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different video is a different embed. The WebView is mounted once
    // and never re-pointed, so without this the preview went on showing the
    // first title's trailer for every title after it.
    if (widget.trailerKey == oldWidget.trailerKey) return;
    _teardown();
    _mount();
  }

  /// Releases the current embed before a new one is mounted.
  void _teardown() {
    _windows?.dispose();
    _windows = null;
    _federated = null;
    if (_embed != null && mounted) {
      setState(() => _embed = null);
    }
  }

  Future<void> _mount() async {
    final debug = TrailerPreview.debugBuilder;
    if (debug != null) {
      setState(() => _embed = debug(widget.trailerKey));
      // The stand-in has no embed of its own, so the state is read from
      // the script runner - which is the same way the real path learns it.
      if (TrailerPreview.debugRunScript != null) {
        unawaited(_awaitSoundState());
      }
      return;
    }
    try {
      if (Platform.isWindows) {
        await _mountWebView2();
      } else {
        await _mountFederated();
      }
    } catch (error) {
      debugPrint('[TrailerPreview] embed failed: $error');
      widget.onFailed?.call();
    }
  }

  Future<void> _mountWebView2() async {
    await _applyAutoplayPolicy();
    final controller = WebviewController();
    await controller.initialize();
    await controller.setBackgroundColor(Colors.black);
    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'trailer_preview'),
    );
    await directory.create(recursive: true);
    await File(p.join(directory.path, TrailerEmbed.wrapperFile)).writeAsString(
      TrailerEmbed.wrapperHtml(
        widget.trailerKey,
        muted: true,
        controls: false,
        cover: widget.cover,
        inert: true,
      ),
    );
    await controller.addVirtualHostNameMapping(
      TrailerEmbed.host,
      directory.path,
      WebviewHostResourceAccessKind.allow,
    );
    await controller.loadUrl(
      '${TrailerEmbed.origin}/${TrailerEmbed.wrapperFile}',
    );
    if (!mounted) {
      await controller.dispose();
      return;
    }
    _windows = controller;
    setState(() => _embed = Webview(controller));
    // The embed answers with the state it ended up in once it is up, and
    // the button is drawn from that answer rather than from the state the
    // app asked for.
    unawaited(_awaitSoundState());
    // The player's own chrome goes away at the same time: it belongs to the
    // embed, and the preview is a picture in the app's surface.
    unawaited(_hideChrome());
  }

  Future<void> _mountFederated() async {
    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(Colors.black);
    if (controller.platform is AndroidWebViewController) {
      await (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    await controller.loadHtmlString(
      TrailerEmbed.wrapperHtml(
        widget.trailerKey,
        muted: true,
        controls: false,
        cover: widget.cover,
        inert: true,
      ),
      baseUrl: '${TrailerEmbed.origin}/',
    );
    if (!mounted) return;
    _federated = controller;
    setState(() => _embed = WebViewWidget(controller: controller));
  }

  /// Applies the WebView2 autoplay policy, and never fatally.
  ///
  /// The environment is process-wide and the trailer modal configures the same
  /// one, so this is [WebviewEnvironment]'s single attempt rather than this
  /// widget's: whichever of the two mounts first configures it, and the other
  /// one must not fail because the environment is already there.
  Future<void> _applyAutoplayPolicy() async {
    await WebviewEnvironment.ensureAutoplayPolicy();
  }

  @override
  void dispose() {
    _windows?.dispose();
    super.dispose();
  }

  /// Turns the sound on or off, and takes the embed's answer for the state.
  ///
  /// Public because the control that asks for it is outside this widget's
  /// tree: the preview layer is `IgnorePointer`ed, so the button cannot be
  /// its own child.
  @override
  Future<void> toggleSound() async {
    // The state the trailer is being asked to take.
    //
    // `_muted` is the state the embed is in now, so the state it is being
    // asked to take is the other one. A muted trailer is being asked to
    // become *unmuted*, which is `false` - and `false` is what has to pick
    // the unmute script. Reading the other way round sent the *mute* script
    // when the trailer was already muted, so the button muted a muted
    // trailer and the unmute was never sent at all.
    final wantedMuted = !_muted;
    try {
      await _runScript(
        wantedMuted ? TrailerEmbed.muteScript : TrailerEmbed.unmuteScript,
      );
    } catch (error) {
      debugPrint('[TrailerPreview] sound toggle failed: $error');
      return;
    }
    // The state is not changed here on the Windows path: the embed answers
    // with the state it actually ended up in, and that is what the button is
    // drawn from, because an embed may refuse to unmute. A button that says
    // "muted" over a video with sound is a lie the user acts on.
    //
    // The federated path cannot read the answer back, so it draws the state
    // it asked for.
    if (_windows == null) {
      if (!mounted) return;
      setState(() => _muted = wantedMuted);
      widget.onSoundChanged?.call(wantedMuted);
      return;
    }
    await _readSettledSoundState(wantedMuted);
  }

  /// Reads the state back until the embed has applied the change.
  ///
  /// The embed applies a mute change asynchronously: the player still
  /// reports the old state for a moment after the command returns. Reading
  /// once, immediately, therefore reads the state *before* the change - and
  /// the button never moves. The state is read until it agrees with what
  /// was asked for, or until the answer has stopped moving, which means the
  /// embed has settled on a state of its own.
  Future<void> _readSettledSoundState(bool wanted) async {
    final settled = await TrailerSoundSettle.settle(
      wanted: wanted,
      read: _readSoundState,
      isCancelled: () => !mounted,
    );
    if (settled == null) return;
  }

  /// Runs a script in the embed, whichever platform it is on.
  Future<dynamic> _runScript(String script) async {
    final seam = TrailerPreview.debugRunScript;
    if (seam != null) return seam(script);
    final windows = _windows;
    if (windows != null) {
      return windows.executeScript(script);
    }
    final controller = _federated;
    if (controller != null) {
      return controller.runJavaScript(script);
    }
    return null;
  }

  /// Takes the embed's own controls away.
  ///
  /// The player object appears once the embed's channel is open, which is
  /// a moment after the frame loads, so the attempt is repeated for a
  /// second or so rather than made once and forgotten.
  Future<void> _hideChrome() async {
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        await _runScript(TrailerEmbed.hideChromeScript);
      } catch (_) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
    }
  }

  /// Waits for the embed to report its state, and adopts it.
  ///
  /// The embed answers a moment after it loads, and the answer is the
  /// truth: an embed that is already muted says so, and the button shows a
  /// muted speaker rather than promising sound.
  Future<void> _awaitSoundState() async {
    for (var attempt = 0; attempt < 12; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      await _readSoundState();
      if (!_muted) return;
    }
  }

  /// Reads the embed's sound state back and adopts it.
  ///
  /// The embed writes its state into the page, and the page is read with a
  /// second script. The answer is the truth: an embed that refused to
  /// unmute says so, and the button shows a muted speaker rather than
  /// promising sound.
  ///
  /// Returns the state it read, so a caller can wait for it to settle.
  Future<bool?> _readSoundState() async {
    dynamic raw;
    try {
      raw = await _runScript(TrailerEmbed.stateScript);
    } catch (error) {
      debugPrint('[TrailerPreview] sound state read failed: $error');
      return null;
    }
    final muted = _mutedFrom(raw);
    if (muted == null) return null;
    if (!mounted) return muted;
    if (muted != _muted) {
      setState(() => _muted = muted);
      widget.onSoundChanged?.call(muted);
    }
    return muted;
  }

  /// The muted flag inside a script's answer, or null when it carries none.
  static bool? _mutedFrom(dynamic raw) {
    if (raw == null) return null;
    Object? decoded = raw;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return null;
      }
    }
    if (decoded is! Map) return null;
    final muted = decoded['muted'];
    return muted is bool ? muted : null;
  }

  @override
  Widget build(BuildContext context) {
    final embed = _embed;
    if (embed == null) return const SizedBox.expand();
    // The preview is an image on top of an image: it must not eat the click
    // that opens the title, and it has nothing to say to a screen reader.
    return IgnorePointer(child: ExcludeSemantics(child: embed));
  }
}

/// The dwell gate in front of [TrailerPreview].
///
/// A rail is scanned, not stared at: starting a video the moment a pointer
/// touches a card would flicker through half the row. The timer is cancelled by
/// the first frame the pointer leaves, so only a deliberate rest pays for a
/// WebView. Television and touch input never schedule one.
class TrailerPreviewGate extends StatefulWidget {
  const TrailerPreviewGate({
    super.key,
    required this.hovered,
    required this.trailerKey,
    required this.resolveTrailerKey,
    this.cover = false,
    this.onSoundChanged,
    this.onPreviewUp,
  });

  final bool hovered;
  final String? trailerKey;
  final Future<String?> Function()? resolveTrailerKey;

  /// Whether the video fills its box instead of letterboxing inside it. See
  /// [TrailerPreview.cover].
  final bool cover;

  /// Reports the sound state as the embed answers it.
  ///
  /// The control that shows it lives outside this widget - in the surface's
  /// own control row - so the answer has to travel up here and out again.
  final ValueChanged<bool>? onSoundChanged;

  /// Reports that the preview has started, or stopped.
  ///
  /// The control that acts on the video lives outside this widget, and it
  /// appears only while there is a video to act on - so the surface has to
  /// be told when there is one.
  ///
  /// The report is deferred by a frame: the gate starts the preview from a
  /// timer, but the *stop* can be reported while the surface is building,
  /// and a `setState` during the build is the "setState() or
  /// markNeedsBuild() called during build" exception.
  final ValueChanged<bool>? onPreviewUp;

  @override
  State<TrailerPreviewGate> createState() => TrailerPreviewGateState();
}

class TrailerPreviewGateState extends State<TrailerPreviewGate>
    implements TrailerPreviewHandle {
  static const Duration _dwell = Duration(milliseconds: 1100);

  /// The live preview, so the sound control can ask it to turn the sound on
  /// or off. The button is outside the preview's own tree - it has to be, so
  /// that it can be pressed - so the two are joined by a key.
  ///
  /// The key's type has to be the *preview's* state, not the gate's own.
  /// A key of the wrong type still holds the element, but its `currentState`
  /// is read through that type: a `GlobalKey<TrailerPreviewGateState>` on a
  /// `TrailerPreview` gave a state that was not the gate's, and asking it
  /// for the sound control found nothing. The button was drawn, it was
  /// pressed, and nothing happened - which is exactly what it looked like.
  final GlobalKey<TrailerPreviewState> _previewKey =
      GlobalKey<TrailerPreviewState>();

  Timer? _timer;
  String? _key;
  bool _visible = false;
  bool _failed = false;

  bool get _canPreview =>
      TrailerPreview.isSupported && !FormFactorService.hasRemoteInput;

  @override
  void initState() {
    super.initState();
    if (widget.hovered) _schedule();
  }

  @override
  void didUpdateWidget(covariant TrailerPreviewGate oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A new title is a new video. The gate kept the old one: the slide
    // changed under the pointer, the gate's key was already set, and the
    // preview went on playing the *previous* title's trailer over the new
    // title's artwork. The reported "it was still playing the trailer" on a
    // title that has none.
    if (widget.trailerKey != oldWidget.trailerKey) {
      _cancel();
      _failed = false;
      // And the new one has to start: cancelling without rescheduling left
      // the gate idle for the rest of the hover, so the new title showed no
      // preview at all.
      if (widget.hovered) _schedule();
      return;
    }

    if (widget.hovered == oldWidget.hovered) return;
    if (widget.hovered) {
      _failed = false;
      _schedule();
    } else {
      _cancel();
    }
  }

  void _schedule() {
    if (!_canPreview) return;
    _timer?.cancel();
    _timer = Timer(_dwell, _start);
  }

  Future<void> _start() async {
    if (!mounted || !widget.hovered) return;
    var key = widget.trailerKey;
    if (key == null || key.isEmpty) {
      key = await widget.resolveTrailerKey?.call();
    }
    if (!mounted || !widget.hovered || key == null || key.isEmpty) return;
    setState(() {
      _key = key;
      _visible = true;
    });
    _reportPreviewUp(true);
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    if (!_visible && _key == null) return;
    setState(() {
      _visible = false;
      _key = null;
    });
    _reportPreviewUp(false);
  }

  /// Reports the preview's state to the surface, off the build.
  ///
  /// The surface answers the report with a `setState`, and the report can
  /// arrive while the surface is building - which is the "setState() or
  /// markNeedsBuild() called during build" exception. A frame's delay puts
  /// it after the build.
  void _reportPreviewUp(bool up) {
    final report = widget.onPreviewUp;
    if (report == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      report(up);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    final preview = AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: _visible && key != null && !_failed
          ? TrailerPreview(
              key: _previewKey,
              trailerKey: key,
              cover: widget.cover,
              onFailed: () {
                if (!mounted) return;
                setState(() {
                  _failed = true;
                  _visible = false;
                });
              },
              onSoundChanged: widget.onSoundChanged,
            )
          : const SizedBox.expand(),
    );

    // The preview is a picture on top of a picture: it must not eat the
    // click that opens the title, and it has nothing to say to a screen
    // reader.
    //
    // The sound control is deliberately *not* here. It has to live in the
    // surface's own control row, beside the other actions, where it is at
    // the same level as everything else the user can press - a control
    // floating over the picture is under the surface's own layer, and the
    // click never reaches it.
    return IgnorePointer(child: ExcludeSemantics(child: preview));
  }

  /// Asks the preview to turn the sound on or off.
  ///
  /// Public because the control that asks for it is outside this widget's
  /// tree: the preview layer is `IgnorePointer`ed, so the button cannot be
  /// its own child.
  @override
  Future<void> toggleSound() async {
    final preview = _previewKey.currentState;
    if (preview == null) return;
    await preview.toggleSound();
  }
}
