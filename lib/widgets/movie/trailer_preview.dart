import 'dart:async';
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

/// A muted, chrome-free YouTube trailer for a hovered card.
///
/// The modal owns the full player; this is the same embed stripped to the
/// artwork's rectangle. It is created only after the pointer has rested on a
/// card, and only on platforms with a WebView implementation. A D-pad never
/// mounts one: focus moves while the user is navigating, and an autoplaying
/// video would fight that.
class TrailerPreview extends StatefulWidget {
  const TrailerPreview({super.key, required this.trailerKey, this.onFailed});

  final String trailerKey;
  final VoidCallback? onFailed;

  /// Test seam; avoids a real WebView in widget tests.
  @visibleForTesting
  static Widget Function(String trailerKey)? debugBuilder;

  static bool get isSupported =>
      !kIsWeb &&
      (Platform.isWindows ||
          Platform.isMacOS ||
          Platform.isAndroid ||
          Platform.isIOS);

  @override
  State<TrailerPreview> createState() => _TrailerPreviewState();
}

class _TrailerPreviewState extends State<TrailerPreview> {
  WebviewController? _windows;
  Widget? _embed;

  @override
  void initState() {
    super.initState();
    _mount();
  }

  Future<void> _mount() async {
    final debug = TrailerPreview.debugBuilder;
    if (debug != null) {
      setState(() => _embed = debug(widget.trailerKey));
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
      TrailerEmbed.wrapperHtml(widget.trailerKey, muted: true, controls: false),
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
      TrailerEmbed.wrapperHtml(widget.trailerKey, muted: true, controls: false),
      baseUrl: '${TrailerEmbed.origin}/',
    );
    if (!mounted) return;
    setState(() => _embed = WebViewWidget(controller: controller));
  }

  static bool _autoplayPolicyRequested = false;

  Future<void> _applyAutoplayPolicy() async {
    if (_autoplayPolicyRequested) return;
    _autoplayPolicyRequested = true;
    try {
      await WebviewController.initializeEnvironment(
        additionalArguments: '--autoplay-policy=no-user-gesture-required',
      );
    } catch (error) {
      debugPrint('[TrailerPreview] autoplay policy not applied: $error');
    }
  }

  @override
  void dispose() {
    _windows?.dispose();
    super.dispose();
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
  });

  final bool hovered;
  final String? trailerKey;
  final Future<String?> Function()? resolveTrailerKey;

  @override
  State<TrailerPreviewGate> createState() => _TrailerPreviewGateState();
}

class _TrailerPreviewGateState extends State<TrailerPreviewGate> {
  static const Duration _dwell = Duration(milliseconds: 1100);

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
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    if (!_visible && _key == null) return;
    setState(() {
      _visible = false;
      _key = null;
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
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: _visible && key != null && !_failed
              ? TrailerPreview(
                  trailerKey: key,
                  onFailed: () {
                    if (!mounted) return;
                    setState(() {
                      _failed = true;
                      _visible = false;
                    });
                  },
                )
              : const SizedBox.expand(),
        ),
      ),
    );
  }
}
