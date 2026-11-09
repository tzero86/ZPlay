import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';

/// Represents a single video stream extracted from Dulo.
class DuloStream {
  final String url;
  final String title;
  final String type;
  final String quality;

  DuloStream({
    required this.url,
    required this.title,
    required this.type,
    required this.quality,
  });

  factory DuloStream.fromJson(Map<String, dynamic> json) {
    return DuloStream(
      url: json['url']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Source',
      type: json['type']?.toString() ?? 'hls',
      quality: json['quality']?.toString() ?? 'Auto',
    );
  }
}

/// Core client managing session handshake, cookie caching, and SSE stream extraction
/// across Dulo domains (dulo.cx, dulo.gd).
class DuloClient {
  static final DuloClient instance = DuloClient._internal();
  DuloClient._internal();

  static const List<String> _domains = [
    'https://dulo.gd',
    'https://dulo.cx',
  ];

  static const String _ua = kZplayUserAgent;

  String? _cachedSessionCookie;
  DateTime? _sessionExpiry;
  String _activeDomain = _domains.first;

  String get activeDomain => _activeDomain;

  Map<String, String> get playbackHeaders => {
        'User-Agent': _ua,
        'Referer': 'https://d.dulo.gd/',
        'Origin': 'https://d.dulo.gd',
      };

  /// Obtains or reuses an active `__Host-amri_session` cookie from Dulo.
  Future<String?> _getSessionCookie(String domain) async {
    if (_cachedSessionCookie != null &&
        _sessionExpiry != null &&
        DateTime.now().isBefore(_sessionExpiry!)) {
      return _cachedSessionCookie;
    }

    try {
      final uri = Uri.parse('$domain/api/session');
      final res = await http.get(
        uri,
        headers: {
          'User-Agent': _ua,
          'Accept': 'application/json',
          'Referer': '$domain/',
          'Origin': domain,
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final setCookie = res.headers['set-cookie'];
        if (setCookie != null && setCookie.isNotEmpty) {
          final match = RegExp(r'(__Host-amri_session=[^;]+)').firstMatch(setCookie);
          final cookieVal = match != null ? match.group(1) : setCookie.split(';').first;
          _cachedSessionCookie = cookieVal;
          _sessionExpiry = DateTime.now().add(const Duration(hours: 6));
          return _cachedSessionCookie;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[DuloClient] Session fetch error ($domain): $e');
    }

    return null;
  }

  /// Extracts streams progressively via Server-Sent Events (SSE) from `/api/source`.
  Stream<DuloStream> fetchSourcesStream(Map<String, dynamic> payload) async* {
    final seenUrls = <String>{};

    for (final domain in _domains) {
      final client = http.Client();
      bool receivedAny = false;

      try {
        final cookie = await _getSessionCookie(domain);
        final request = http.Request('POST', Uri.parse('$domain/api/source'));
        request.headers.addAll({
          'User-Agent': _ua,
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          'Referer': '$domain/',
          'Origin': domain,
          if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
        });
        request.body = jsonEncode(payload);

        final response = await client.send(request).timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          _activeDomain = domain;

          final lineStream = response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter());

          await for (final line in lineStream) {
            final trimmed = line.trim();
            if (trimmed.startsWith('data:')) {
              final jsonPart = trimmed.substring(5).trim();
              if (jsonPart.isEmpty || !jsonPart.startsWith('{')) continue;

              try {
                final data = jsonDecode(jsonPart);
                if (data is Map<String, dynamic> && data['sources'] is List) {
                  final rawSources = data['sources'] as List;
                  for (final item in rawSources) {
                    if (item is Map<String, dynamic>) {
                      final stream = DuloStream.fromJson(item);
                      if (stream.url.isNotEmpty &&
                          stream.url.startsWith('http') &&
                          seenUrls.add(stream.url)) {
                        receivedAny = true;
                        yield stream;
                      }
                    }
                  }
                }
              } catch (_) {
                // Ignore malformed intermediate progress JSON chunks
              }
            } else if (trimmed.startsWith('event: complete')) {
              break;
            }
          }

          if (receivedAny) {
            client.close();
            return;
          }
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          // Invalidate cookie in case of session expiration
          _cachedSessionCookie = null;
          _sessionExpiry = null;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[DuloClient] SSE extraction error ($domain): $e');
      } finally {
        client.close();
      }

      if (receivedAny) return;
    }
  }

  /// Helper for Movies.
  Stream<DuloStream> getMovieStreams(int tmdbId) {
    return fetchSourcesStream({
      'type': 'movie',
      'tmdbId': tmdbId,
    });
  }

  /// Helper for TV series.
  Stream<DuloStream> getTvStreams(int tmdbId, int season, int episode) {
    return fetchSourcesStream({
      'type': 'tv',
      'tmdbId': tmdbId,
      'season': season,
      'episode': episode,
    });
  }

  /// Helper for Anime.
  Stream<DuloStream> getAnimeStreams(int anilistId, int episode) {
    return fetchSourcesStream({
      'type': 'anime',
      'anilistId': anilistId,
      'episode': episode,
    });
  }
}
