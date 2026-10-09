import 'dart:convert';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import '../../config/service_credentials.dart';

/// Scraper for All Movies Downloader (Films365) producing direct MP4 stream sources.
class XDownloaderScraper extends StreamScraper {
  @override
  String get name => 'ZPlayHTTP';

  static const String _baseUrl = 'https://www.films365.org';
  static Map<String, String> get _headers => {
    'Authorization':
        'Bearer ${ServiceCredentials.value(ServiceCredential.xdownloader)}',
    'Content-Type': 'application/json',
    'User-Agent': 'MovieDownloader/1.0',
  };

  @override
  Future<List<StreamSource>> scrape({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async {
    final sources = <StreamSource>[];

    try {
      // 1. Perform Search Query
      final searchUri = Uri.parse('$_baseUrl/api/mobile/search');
      final searchResponse = await http.post(
        searchUri,
        headers: _headers,
        body: jsonEncode({'query': title}),
      );

      if (searchResponse.statusCode != 200) return sources;

      final searchJson = jsonDecode(searchResponse.body);
      final resultsObj = searchJson['results'];
      if (resultsObj == null) return sources;

      final List items = (resultsObj['all'] as List?) ??
          (resultsObj['movies'] as List?) ??
          (resultsObj['tvs'] as List?) ??
          [];

      if (items.isEmpty) return sources;

      // Normalize target type ('movie' vs 'tv'/'series')
      final targetType = (type == 'series' || type == 'tv') ? 'tv' : 'movie';

      dynamic matchedItem;
      final cleanSearchTitle = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

      for (final item in items) {
        final itemType = item['type']?.toString();
        if (itemType != null && itemType != targetType) continue;

        final itemTitle = item['title']?.toString() ?? '';
        final cleanItemTitle = itemTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

        if (cleanItemTitle == cleanSearchTitle || cleanItemTitle.contains(cleanSearchTitle)) {
          matchedItem = item;
          break;
        }
      }

      matchedItem ??= items.firstWhere(
        (i) => (i['type']?.toString() == targetType),
        orElse: () => null,
      );

      if (matchedItem == null) return sources;

      final itemId = matchedItem['id']?.toString() ?? matchedItem['tmdbId']?.toString();
      if (itemId == null) return sources;

      // 2. Fetch Media Details by ID
      final detailsUri = Uri.parse('$_baseUrl/api/mobile/details?id=$itemId&type=$targetType');
      final detailsResponse = await http.get(detailsUri, headers: _headers);

      if (detailsResponse.statusCode != 200) return sources;

      final detailsJson = jsonDecode(detailsResponse.body);
      final data = detailsJson['data'];
      if (data == null) return sources;

      final spoken = (data['spokenLanguages'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          [];
      final langSuffix = spoken.isNotEmpty ? ' · ${spoken.join(', ')}' : '';

      if (targetType == 'movie') {
        final downloadUrl = data['downloadUrl']?.toString();
        final videoUrl = data['videoUrl']?.toString();

        final streamUrl = (downloadUrl != null && downloadUrl.isNotEmpty) ? downloadUrl : videoUrl;

        if (streamUrl != null && streamUrl.isNotEmpty) {
          final safeUrl = Uri.parse(streamUrl).toString();
          sources.add(StreamSource(
            name: 'ZPlayHTTP',
            addonName: 'ZPlayHTTP',
            title: 'X-Downloader$langSuffix',
            description: 'X-Downloader Direct MP4 Stream$langSuffix',
            url: safeUrl,
          ));
        }
      } else {
        // TV Series
        final seasons = data['seasons'] as List?;
        if (seasons != null && season != null) {
          final targetSeason = seasons.firstWhere(
            (s) => s['seasonNumber'] == season,
            orElse: () => null,
          );

          if (targetSeason != null) {
            final episodes = targetSeason['episodes'] as List?;
            if (episodes != null && episode != null) {
              final targetEpisode = episodes.firstWhere(
                (e) => e['episodeNumber'] == episode,
                orElse: () => null,
              );

              if (targetEpisode != null) {
                final epDownloadUrl = targetEpisode['downloadUrl']?.toString();
                final epVideoUrl = targetEpisode['videoUrl']?.toString();

                final streamUrl = (epDownloadUrl != null && epDownloadUrl.isNotEmpty)
                    ? epDownloadUrl
                    : epVideoUrl;

                if (streamUrl != null && streamUrl.isNotEmpty) {
                  final safeUrl = Uri.parse(streamUrl).toString();
                  sources.add(StreamSource(
                    name: 'ZPlayHTTP',
                    addonName: 'ZPlayHTTP',
                    title: 'X-Downloader$langSuffix',
                    description: 'X-Downloader Direct MP4 Stream (S${season}E$episode)$langSuffix',
                    url: safeUrl,
                  ));
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('XDownloaderScraper error: $e');
    }

    return sources;
  }
}
