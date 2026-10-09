import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// Pure-Dart KissKH Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla KissKH provider.
/// Resolves Asian dramas and shows from kisskh.do via enc-dec.app decryption.
class KissKhScraper extends StreamScraper {
  @override
  String get name => 'ZPlayHTTP';

  static const _encApi = 'https://enc-dec.app/api';
  static const _base = 'https://kisskh.do';
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static const _headers = {
    'User-Agent': _ua,
    'Accept': 'application/json',
  };

  static String _cleanTitle(String t) {
    return t.toLowerCase().replaceAll(RegExp(r'\(\d{4}\)'), '').replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// How strongly [itemTitle] identifies [title]; 0 means it names nothing the
  /// caller asked for. Kept at 0 rather than -1 so a result list that scores
  /// all zeros resolves to nothing instead of handing back whichever drama
  /// the search happened to rank first.
  static int _scoreTitleMatch(String target, String itemTitle) {
    final targetClean = _cleanTitle(target);
    final parts = itemTitle.split(RegExp(r'\s*-\s*')).map(_cleanTitle);

    if (parts.any((p) => p == targetClean)) return 5;
    if (parts.any((p) => p.contains(targetClean) || targetClean.contains(p))) return 3;
    return 0;
  }

  /// The best-scoring drama for [title], or null when no result names it.
  static Map? pickBestDrama(List<dynamic> results, String title) {
    Map? drama;
    var bestScore = 0;

    for (final item in results) {
      if (item is! Map) continue;
      final score = _scoreTitleMatch(title, item['title']?.toString() ?? '');
      if (score > bestScore) {
        bestScore = score;
        drama = item;
      }
    }

    return drama;
  }

  Future<String?> _encKey(http.Client client, dynamic episodeId, String type) async {
    try {
      final res = await client.get(
        Uri.parse('$_encApi/enc-kisskh?text=$episodeId&type=$type'),
        headers: {'User-Agent': _ua, 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['status'] == 200) {
          return data['result']?.toString();
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Stream<StreamSource> scrapeStream({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async* {
    try {
      final client = http.Client();
      try {
        final searchRes = await client.get(
          Uri.parse('$_base/api/DramaList/Search?q=${Uri.encodeComponent(title)}'),
          headers: _headers,
        ).timeout(const Duration(seconds: 6));

        if (searchRes.statusCode != 200) return;
        final results = jsonDecode(searchRes.body);
        if (results is! List || results.isEmpty) return;

        final drama = pickBestDrama(results, title);
        if (drama == null || drama['id'] == null) return;
        final dramaId = drama['id'];

        final detailRes = await client.get(
          Uri.parse('$_base/api/DramaList/Drama/$dramaId'),
          headers: _headers,
        ).timeout(const Duration(seconds: 8));

        if (detailRes.statusCode != 200) return;
        final detail = jsonDecode(detailRes.body);
        if (detail is! Map || detail['episodes'] is! List) return;

        final targetEpNum = episode ?? 1;
        final episodes = detail['episodes'] as List;

        final epMatch = episodes.firstWhere(
          (ep) => ep is Map && (ep['number'] as num?)?.toInt() == targetEpNum,
          orElse: () => episodes.first,
        );

        if (epMatch == null || epMatch['id'] == null) return;
        final episodeId = epMatch['id'];

        final vidKey = await _encKey(client, episodeId, 'vid');
        if (vidKey == null || vidKey.isEmpty) return;

        final videoRes = await client.get(
          Uri.parse('$_base/api/DramaList/Episode/$episodeId.png?err=false&ts=&time=&kkey=$vidKey'),
          headers: _headers,
        ).timeout(const Duration(seconds: 10));

        if (videoRes.statusCode != 200) return;
        final videoData = jsonDecode(videoRes.body);
        if (videoData is! Map || videoData['Video'] == null) return;

        final streamUrl = videoData['Video'].toString();
        if (streamUrl.isEmpty) return;

        final isHls = streamUrl.contains('.m3u8');
        final reqHeaders = {
          'User-Agent': _ua,
          'Referer': '$_base/',
        };

        yield StreamSource(
          name: 'ZPlayHTTP',
          addonName: 'ZPlayHTTP',
          title: 'KissKH · Drama · 1080p',
          description: 'KissKH Stream · ${isHls ? 'HLS' : 'MP4'}',
          url: streamUrl,
          headers: reqHeaders,
          behaviorHints: {
            'notWebReady': false,
            'proxyHeaders': {
              'request': reqHeaders,
            },
          },
        );
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[KissKhScraper] error: $e');
    }
  }
}
