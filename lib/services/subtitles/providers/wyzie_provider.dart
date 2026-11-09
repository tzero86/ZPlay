import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../models/subtitle/subtitle_model.dart';
import '../../../utils/language_names.dart';
import '../../config/service_credentials.dart';
import '../subtitle_provider.dart';

class WyzieProvider extends SubtitleProvider {
  @override
  String get name => 'Wyzie';

  static const String _endpoint = 'https://sub.wyzie.io/search';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static Map<String, String> get _headers {
    final key = ServiceCredentials.value(ServiceCredential.wyzie);
    return {
      'User-Agent': _userAgent,
      'Accept': 'application/json',
      'x-api-key': key,
      'Authorization': 'Bearer $key',
    };
  }

  @override
  Future<List<SubtitleVariant>> search(
    String movieName, {
    String? imdbId,
    int? season,
    int? episode,
    int? year,
  }) async {
    final List<SubtitleVariant> results = [];

    try {
      final queryParams = <String, String>{
        'source': 'all',
        'key': ServiceCredentials.value(ServiceCredential.wyzie),
      };

      if (imdbId != null && imdbId.isNotEmpty) {
        queryParams['id'] = imdbId.startsWith('tt') ? imdbId : 'tt$imdbId';
      } else {
        queryParams['query'] = movieName;
      }

      if (season != null) queryParams['season'] = season.toString();
      if (episode != null) queryParams['episode'] = episode.toString();

      final uri = Uri.parse(_endpoint).replace(queryParameters: queryParams);
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));

      if (res.statusCode != 200) return [];

      final dynamic data = jsonDecode(utf8.decode(res.bodyBytes));
      final list = data is List ? data : [];

      for (final item in list) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);

        final url = map['url']?.toString();
        if (url == null || url.isEmpty) continue;

        final rawLang = (map['language'] ?? map['lang'] ?? 'en').toString();
        final display = map['display']?.toString();
        final language = display?.isNotEmpty == true
            ? display!
            : subtitleLanguageName(rawLang);

        final release = map['release']?.toString();
        final format = (map['format']?.toString() ?? 'srt').toLowerCase();
        final isHi = map['isHearingImpaired'] == true || map['hi'] == true;

        String title = release?.isNotEmpty == true ? release! : 'Wyzie Subtitle';
        if (isHi) {
          title = '$title [CC]';
        }

        results.add(
          SubtitleVariant(
            providerName: name,
            language: language,
            title: title,
            downloadUrl: url,
            format: format,
            extraData: {
              'encoding': map['encoding'],
              'fps': map['fps'],
              'downloads': map['downloads'],
            },
          ),
        );
      }
    } catch (e) {
      print('[WyzieProvider] search error: $e');
    }

    return results;
  }

  @override
  Future<String?> download(SubtitleVariant variant) async {
    try {
      final res = await http
          .get(Uri.parse(variant.downloadUrl), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return null;

      final dir = await getTemporaryDirectory();
      final ext = variant.format.toLowerCase() == 'vtt' ? 'vtt' : 'srt';
      final outPath = '${dir.path}/wyzie_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final file = File(outPath);
      await file.writeAsBytes(res.bodyBytes, flush: true);
      return outPath;
    } catch (e) {
      print('[WyzieProvider] download error: $e');
      return null;
    }
  }
}
