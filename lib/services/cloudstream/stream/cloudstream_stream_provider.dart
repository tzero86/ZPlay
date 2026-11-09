import '../../../models/stream/stream_model.dart';
import '../../../models/subtitle/subtitle_model.dart';
import '../../../utils/language_names.dart';

class CloudStreamStreamProvider {
  /// Transforms a raw link Map emitted by CloudStream into ZPlay's StreamSource.
  static StreamSource? toStreamSource(
    Map<String, dynamic> data, {
    required String extensionName,
    String? mediaTitle,
  }) {
    var rawUrl = data['url']?.toString().trim();
    if (rawUrl == null || rawUrl.isEmpty) return null;

    final magnetIdx = rawUrl.indexOf('magnet:?xt=urn:');
    if (magnetIdx != -1) {
      rawUrl = rawUrl.substring(magnetIdx);
    }

    final qualityStr = (data['quality']?.toString().trim() ?? '').isNotEmpty
        ? data['quality'].toString().trim()
        : (data['qualityInt'] != null ? '${data['qualityInt']}p' : 'HD');

    final name = data['name']?.toString().trim() ??
        data['title']?.toString().trim() ??
        extensionName;

    // Resolve and fix headers
    Map<String, String>? headersMap;
    if (data['headers'] is Map) {
      headersMap = (data['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
    } else if (data['extraData'] is Map && (data['extraData'] as Map)['allHeaders'] is Map) {
      headersMap = ((data['extraData'] as Map)['allHeaders'] as Map)
          .map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    if (headersMap != null) {
      final referer = data['referer']?.toString();
      if (referer != null && referer.isNotEmpty && !headersMap.containsKey('Referer')) {
        headersMap['Referer'] = referer.endsWith('/') ? referer : '$referer/';
      }
    }

    // Extract, normalize, and parse all subtitles
    final List<SubtitleVariant> parsedSubtitles = [];
    final rawSubs = data['subtitles'] as List?;
    if (rawSubs != null && rawSubs.isNotEmpty) {
      final seenUrls = <String>{};
      for (final s in rawSubs) {
        if (s is Map) {
          final file = s['file']?.toString() ?? s['url']?.toString();
          if (file == null || file.trim().isEmpty) continue;
          final cleanUrl = file.trim();
          if (!seenUrls.add(cleanUrl.toLowerCase())) continue;
          final rawLabel = (s['label'] ?? s['lang'] ?? s['language'] ?? 'English').toString().trim();
          final lang = subtitleLanguageName(rawLabel);

          // Detect subtitle format
          String format = (s['format'] ?? s['subFormat'] ?? '').toString().trim().toLowerCase();
          if (format.isEmpty) {
            final lowerUrl = cleanUrl.toLowerCase();
            if (lowerUrl.contains('.vtt')) {
              format = 'vtt';
            } else if (lowerUrl.contains('.ass')) {
              format = 'ass';
            } else {
              format = 'srt';
            }
          }

          // Headers for downloading subtitle
          Map<String, String>? subHeaders;
          if (s['headers'] is Map) {
            subHeaders = (s['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
          } else if (headersMap != null) {
            subHeaders = Map<String, String>.from(headersMap);
          }

          final displayTitle = rawLabel.isNotEmpty && rawLabel.toLowerCase() != lang.toLowerCase()
              ? '$rawLabel ($extensionName)'
              : '$lang ($extensionName)';

          parsedSubtitles.add(
            SubtitleVariant(
              providerName: extensionName,
              language: lang,
              title: displayTitle,
              downloadUrl: cleanUrl,
              format: format,
              extraData: {
                if (subHeaders != null) 'headers': subHeaders,
                if (data['referer'] != null) 'referer': data['referer'],
                'source': 'cloudstream',
                'isForced': s['isForced'] == true || rawLabel.toLowerCase().contains('forced'),
                'isHearingImpaired': s['isHearingImpaired'] == true ||
                    rawLabel.contains('[CC]') ||
                    rawLabel.toLowerCase().contains('sdh'),
              },
            ),
          );
        }
      }
    }

    final isDub = data['isDub'] == true ||
        data['type']?.toString().toLowerCase() == 'dub' ||
        name.toLowerCase().contains('dub') ||
        (data['extra']?.toString().toLowerCase().contains('dub') ?? false) ||
        (data['description']?.toString().toLowerCase().contains('dub') ?? false);

    final isSub = data['type']?.toString().toLowerCase() == 'sub' ||
        name.toLowerCase().contains('sub') ||
        (data['extra']?.toString().toLowerCase().contains('sub') ?? false);

    final catLabel = isDub ? 'Dub' : (isSub ? 'Sub' : null);
    final desc = catLabel != null
        ? 'CloudStream • $extensionName • $catLabel'
        : 'CloudStream • $extensionName';

    return StreamSource(
      name: '[$qualityStr] $name',
      title: mediaTitle != null && mediaTitle.isNotEmpty ? '$mediaTitle ($extensionName)' : name,
      url: rawUrl,
      headers: headersMap,
      addonName: extensionName,
      description: desc,
      subtitles: parsedSubtitles.isNotEmpty ? parsedSubtitles : null,
      behaviorHints: {
        if (parsedSubtitles.isNotEmpty) 'subtitles': rawSubs,
      },
    );
  }
}
