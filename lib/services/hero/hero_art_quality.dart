import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../storage/app_image_cache.dart';

/// Reads an artwork URL's real pixel size, or null when it cannot be read.
typedef HeroArtProbe = Future<ui.Size?> Function(String url);

/// The hero's resolution gate: no still reaches the band unless its *source*
/// is big enough to fill it without visible upscaling.
///
/// A URL says nothing about the picture behind it. Addons hand out stills at
/// whatever size they found - 300 px thumbnails, poster-sized crops, a 780 px
/// fanart - and the band is the window's width. Requesting a bigger decode
/// cannot add detail that is not in the file, so a small source stretched to
/// 1920+ px is exactly the "pixelated hero" that was reported. The only fix is
/// to look at the file before painting it.
///
/// The probe downloads through [AppImageCache.manager] (the same disk cache the
/// band paints from, so the bytes are fetched once) and reads only the image
/// header via [ui.ImageDescriptor] - no full decode, no bitmap in memory.
/// Results are memoized per URL for the session.
abstract final class HeroArtQuality {
  /// The narrowest source the hero accepts, in pixels. TMDb's `w1280` is the
  /// smallest still that holds up on a 1080p band; metahub's `background`
  /// stills are 1920 and up. Anything below this is a thumbnail or a poster
  /// crop, and is what painted the blurry slides.
  static const int minWidth = 1280;

  /// Minimum width/height ratio. The band is wider than 16:9, so a 2:3 poster
  /// (or a square) cropped into it is both upscaled and cut to a sliver.
  static const double minAspect = 1.3;

  static final Map<String, Future<ui.Size?>> _sizes = {};

  /// Whether a still of [size] is sharp enough for the hero band.
  static bool isSharp(ui.Size? size) {
    if (size == null || size.height <= 0) return false;
    return size.width >= minWidth && size.width / size.height >= minAspect;
  }

  /// Replaces the network probe in tests, where no image host answers.
  @visibleForTesting
  static HeroArtProbe? debugProbe;

  /// [url]'s real dimensions, fetched once per session.
  static Future<ui.Size?> probe(String url, {BaseCacheManager? cacheManager}) {
    final override = debugProbe;
    if (override != null) {
      return override(url).then((size) {
        if (size != null) _known[url] = isSharp(size);
        return size;
      });
    }
    return _sizes.putIfAbsent(
      url,
      () => _read(url, cacheManager ?? AppImageCache.manager),
    );
  }

  /// The answer for [url] if it has already been probed: true/false, or null
  /// while unknown. Lets a synchronous caller avoid reporting an unverified URL.
  static bool? known(String url) => _known[url];
  static final Map<String, bool> _known = {};

  @visibleForTesting
  static void clear() {
    _sizes.clear();
    _known.clear();
    debugProbe = null;
  }

  static Future<ui.Size?> _read(String url, BaseCacheManager manager) async {
    ui.Size? size;
    try {
      final file = await manager.getSingleFile(url);
      final bytes = await file.readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      size = ui.Size(descriptor.width.toDouble(), descriptor.height.toDouble());
      descriptor.dispose();
      buffer.dispose();
    } catch (e) {
      debugPrint('[HeroArtQuality] probe failed for $url: $e');
      // A failed probe is not cached as a final answer: a transient network
      // error must not blacklist good art for the whole session.
      _sizes.remove(url);
      return null;
    }
    _known[url] = isSharp(size);
    if (_known[url] == false) {
      debugPrint(
        '[HeroArtQuality] rejected ${size.width.toInt()}x'
        '${size.height.toInt()} still: $url',
      );
    }
    return size;
  }
}
