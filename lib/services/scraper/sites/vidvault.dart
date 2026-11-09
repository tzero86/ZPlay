import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import 'tmdb_helper.dart';

/// Pure-Dart VidVault Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla VidVault provider.
/// Resolves direct high-speed MP4 & MKV files from vidvault.ru.
class VidVaultScraper extends HttpScraper {
  static const _baseUrl = 'https://vidvault.ru';
  static const _ua = kZplayUserAgent;

  static const _headers = {
    'Referer': '$_baseUrl/',
    'Origin': _baseUrl,
    'User-Agent': _ua,
  };

  Future<String?> _getToken(http.Client client) async {
    try {
      final res = await client.get(
        Uri.parse('$_baseUrl/api/get-token'),
        headers: _headers,
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['t'] != null) {
          return data['t'].toString();
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
    final isTv = (type == 'tv' || type == 'series');
    final mediaType = isTv ? 'tv' : 'movie';

    try {
      final tmdbId = await TmdbHelper.resolveTmdbId(
        imdbId: imdbId,
        title: title,
        type: mediaType,
        year: year,
      );

      if (tmdbId == null) {
        if (kDebugMode) debugPrint('[VidVaultScraper] Could not resolve TMDB ID for "$title"');
        return;
      }

      final client = http.Client();
      try {
        final token = await _getToken(client);
        if (token == null || token.isEmpty) return;

        final payload = <String, dynamic>{
          'type': mediaType,
          'tmdbId': tmdbId.toString(),
          if (isTv) 'season': (season ?? 1).toString(),
          if (isTv) 'episode': (episode ?? 1).toString(),
        };

        final res = await client.post(
          Uri.parse('$_baseUrl/api/download-proxy'),
          headers: {
            ..._headers,
            'Content-Type': 'application/json',
            'x-request-token': token,
          },
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 10));

        if (res.statusCode != 200) return;
        final data = jsonDecode(res.body);
        if (data is! Map) return;

        final mp4 = data['mp4Data'];
        if (mp4 is Map) {
          final lanName = mp4['lanName']?.toString().trim() ?? '';
          final country = mp4['country']?.toString().trim() ?? '';
          final detailPath = mp4['detailPath']?.toString().trim() ?? '';

          final downloads = mp4['downloadInfo']?['data']?['downloads'];
          if (downloads is List) {
            for (final d in downloads) {
              if (d is! Map) continue;
              final dUrl = d['url']?.toString();
              if (dUrl == null || dUrl.isEmpty) continue;

              final resLabel = d['resolution']?.toString() ?? '1080';
              final titleParts = [
                'VidVault',
                'MP4',
                if (lanName.isNotEmpty) lanName,
                if (country.isNotEmpty && country != lanName) country,
                '${resLabel}p',
              ];

              final descParts = [
                'VidVault Direct MP4',
                if (lanName.isNotEmpty) lanName,
                if (country.isNotEmpty) country,
                if (detailPath.isNotEmpty) detailPath,
              ];

              yield StreamSource.zplayHttp(
                title: titleParts.join(' · '),
                description: descParts.join(' · '),
                url: dUrl,
                headers: _headers,
              );
            }
          }
        }

        final mkvFiles = data['mkvData']?['files'];
        if (mkvFiles is List) {
          for (final f in mkvFiles) {
            if (f is! Map) continue;
            final fUrl = f['url']?.toString();
            if (fUrl == null || fUrl.isEmpty) continue;

            final size = f['size']?.toString() ?? '';
            final label = size.isNotEmpty ? 'MKV · $size' : 'MKV';

            yield StreamSource.zplayHttp(
              title: 'VidVault · $label',
              description: 'VidVault Direct File',
              url: fUrl,
              headers: _headers,
            );
          }
        }

        // Additional mkvV2Data and mkvV3Data sources with explicit backend language tags
        for (final key in ['mkvV2Data', 'mkvV3Data']) {
          final mkvExtra = data[key];
          if (mkvExtra is Map) {
            final eUrl = mkvExtra['url']?.toString();
            if (eUrl != null && eUrl.isNotEmpty) {
              final eQuality = mkvExtra['quality']?.toString().trim() ?? '';
              final eLang = mkvExtra['language']?.toString().trim() ?? '';
              final eCountry = mkvExtra['country']?.toString().trim() ?? '';
              final eSize = mkvExtra['size']?.toString().trim() ?? '';

              final parts = [
                'VidVault',
                'MKV',
                if (eLang.isNotEmpty) eLang,
                if (eCountry.isNotEmpty && eCountry != eLang) eCountry,
                if (eQuality.isNotEmpty) eQuality,
                if (eSize.isNotEmpty) eSize,
              ];

              yield StreamSource.zplayHttp(
                title: parts.join(' · '),
                description: 'VidVault Direct MKV · $eLang $eCountry $eSize'.trim(),
                url: eUrl,
                headers: _headers,
              );
            }
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[VidVaultScraper] error: $e');
    }
  }
}
