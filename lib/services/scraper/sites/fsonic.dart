import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// Pure-Dart FSonic Stream Scraper for ZPlayHTTP.
///
/// Ported 1-to-1 from Vyla FSonic provider.
/// Resolves movies from fsonic.net and fsharetv.co.
class FSonicScraper extends HttpScraper {
  static const _baseUrl = 'https://www.fsonic.net';
  static const _fshareBase = 'https://fsharetv.co';
  static const _ua = kZplayUserAgent;

  static const _headers = {
    'User-Agent': _ua,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  @override
  Stream<StreamSource> scrapeStream({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async* {
    if (type == 'tv' || type == 'series' || season != null) return;

    try {
      final client = http.Client();
      try {
        final sRes = await client.get(
          Uri.parse('$_baseUrl/movie/search/${Uri.encodeComponent(title)}'),
          headers: _headers,
        ).timeout(const Duration(seconds: 8));

        if (sRes.statusCode != 200) return;
        final sHtml = sRes.body;

        String? watchSlug;
        var idx = 0;
        final yearStr = year?.toString() ?? '';

        while ((idx = sHtml.indexOf('href="/watch/', idx)) != -1) {
          final start = idx + 6;
          final end = sHtml.indexOf('"', start);
          if (end == -1) break;
          final link = sHtml.substring(start, end);
          watchSlug ??= link;
          if (yearStr.isNotEmpty && link.contains(yearStr)) {
            watchSlug = link;
            break;
          }
          idx = end;
        }

        if (watchSlug == null) return;

        final wRes = await client.get(
          Uri.parse('$_baseUrl$watchSlug'),
          headers: _headers,
        ).timeout(const Duration(seconds: 8));

        if (wRes.statusCode != 200) return;
        final wHtml = wRes.body;

        final match = RegExp(r'''init\('([^']+)',\s*(?:'[^']*',\s*)?'([^']+)'\)''').firstMatch(wHtml);
        if (match == null || match.group(1) == null) return;

        final token = match.group(1)!;
        final trailer = match.group(2) ?? '';

        final jsonRes = await client.get(
          Uri.parse('$_baseUrl/api/source/$token?trailer=$trailer&type=watch'),
          headers: {
            ..._headers,
            'Accept': 'application/json, text/plain, */*',
            'Referer': '$_baseUrl$watchSlug',
          },
        ).timeout(const Duration(seconds: 8));

        if (jsonRes.statusCode != 200) return;
        final json = jsonDecode(jsonRes.body);
        if (json is! Map || json['status'] != 'ok') return;

        final allGroups = <List>[];
        if (json['data']?['file']?['sources'] is List) {
          allGroups.add(json['data']['file']['sources'] as List);
        }
        if (json['data']?['file']?['alternatives'] is List) {
          for (final g in json['data']['file']['alternatives'] as List) {
            if (g is List) allGroups.add(g);
          }
        }

        final seen = <String>{};
        for (final group in allGroups) {
          for (final item in group) {
            if (item is! Map || item['src'] == null) continue;
            final rawSrc = item['src'].toString();
            final srcUrl = rawSrc.startsWith('http') ? rawSrc : '$_fshareBase$rawSrc';

            if (seen.add(srcUrl)) {
              final quality = item['quality']?.toString() ?? '1080';
              final label = item['label']?.toString().trim() ?? '';
              final isHls = srcUrl.contains('.m3u8');

              final titleParts = [
                'FSonic',
                if (label.isNotEmpty) label,
                '${quality}p',
              ];

              final descParts = [
                'FSonic Stream',
                if (label.isNotEmpty) label,
                isHls ? 'HLS' : 'MP4',
              ];

              final reqHeaders = {
                ..._headers,
                'Referer': '$_fshareBase/',
              };

              yield StreamSource.zplayHttp(
                title: titleParts.join(' · '),
                description: descParts.join(' · '),
                url: srcUrl,
                headers: reqHeaders,
              );
            }
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FSonicScraper] error: $e');
    }
  }
}
