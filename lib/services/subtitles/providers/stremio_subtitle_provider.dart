import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../models/subtitle/subtitle_model.dart';
import '../../addon/addon_manager.dart';
import '../../addon/addon_url_resolver.dart';
import '../../../utils/language_names.dart';
import '../../../utils/security/log_redaction.dart';
import '../subtitle_provider.dart';
import '../subtitle_extractor.dart';

class StremioSubtitleProvider extends SubtitleProvider {
  @override
  String get name => 'Stremio Addon';

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json',
  };

  @override
  Future<List<SubtitleVariant>> search(
    String movieName, {
    String? imdbId,
    int? season,
    int? episode,
    int? year,
  }) async {
    String? cleanImdbId = imdbId;
    if (cleanImdbId == null || cleanImdbId.isEmpty) {
      final match = RegExp(r'\b(tt\d{7,8})\b').firstMatch(movieName);
      if (match != null) cleanImdbId = match.group(1);
    }

    if (cleanImdbId == null || cleanImdbId.isEmpty) {
      return [];
    }

    if (!cleanImdbId.startsWith('tt')) {
      cleanImdbId = 'tt$cleanImdbId';
    }

    final isEpisode = season != null && episode != null;
    final type = isEpisode ? 'series' : 'movie';
    final id = isEpisode ? '$cleanImdbId:$season:$episode' : cleanImdbId;

    final List<SubtitleVariant> results = [];
    final activeAddons = AddonManager.instance.activeSubtitleAddons;

    for (final addon in activeAddons) {
      try {
        final resolvedBaseUrl = await AddonUrlResolver.resolve(addon.baseUrl);
        final url = '$resolvedBaseUrl/subtitles/$type/$id.json';
        print(
          '[StremioSubtitleProvider] Querying ${addon.manifest.name}: ${redactUrl(url)}',
        );
        final res = await http
            .get(Uri.parse(url), headers: _headers)
            .timeout(const Duration(seconds: 6));

        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          final subsList = data['subtitles'] as List?;
          if (subsList == null || subsList.isEmpty) continue;

          int idx = 0;
          for (final item in subsList) {
            if (item is! Map) continue;
            final map = Map<String, dynamic>.from(item);
            final subUrl = map['url']?.toString();
            if (subUrl == null || subUrl.isEmpty) continue;

            idx++;
            final rawLang = (map['lang'] ?? 'en').toString();
            final language = subtitleLanguageName(rawLang);

            final fileTitle =
                map['subtitleFileName']?.toString() ??
                map['movieReleaseName']?.toString() ??
                map['title']?.toString();
            final title = fileTitle?.isNotEmpty == true
                ? fileTitle!
                : '${addon.manifest.name} #$idx';

            final format =
                (map['SubFormat']?.toString() ??
                        (title.toLowerCase().endsWith('.vtt') ? 'vtt' : 'srt'))
                    .toLowerCase();

            results.add(
              SubtitleVariant(
                providerName: addon.manifest.name,
                language: language,
                title: title,
                downloadUrl: subUrl,
                format: format,
                extraData: {
                  'id': map['id'],
                  'subEncoding': map['SubEncoding'],
                  'fpsMilli': map['fpsMilli'],
                  'releaseGroup': map['releaseGroup'],
                },
              ),
            );
          }
          print(
            '[StremioSubtitleProvider] ${addon.manifest.name} returned $idx subtitles',
          );
        }
      } catch (e) {
        print(
          '[StremioSubtitleProvider] Error querying ${addon.manifest.name}: $e',
        );
      }
    }

    return results;
  }

  @override
  Future<String?> download(SubtitleVariant variant) async {
    final reqHeaders = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': '*/*',
    };
    if (variant.extraData['headers'] is Map) {
      reqHeaders.addAll(
        (variant.extraData['headers'] as Map).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
      );
    }
    return SubtitleExtractor.downloadAndExtract(
      variant.downloadUrl,
      headers: reqHeaders,
      providerName: variant.providerName,
    );
  }
}
