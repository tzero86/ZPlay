import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/music/music_track.dart';
import '../storage/secret_keys.dart';
import '../storage/secure_store.dart';

class QobuzTrack {
  final String id;
  final String title;
  final String artist;
  final String album;
  final int durationSeconds;
  final String? isrc;
  final String? audioQuality;
  final String? artworkUrl;
  final String? format;

  const QobuzTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationSeconds,
    this.isrc,
    this.audioQuality,
    this.artworkUrl,
    this.format,
  });

  factory QobuzTrack.fromJson(Map<String, dynamic> json) {
    return QobuzTrack(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown Track',
      artist: json['artist']?.toString() ?? 'Unknown Artist',
      album: json['album']?.toString() ?? 'Single',
      durationSeconds: int.tryParse(json['duration']?.toString() ?? '') ?? 0,
      isrc: json['isrc']?.toString(),
      audioQuality:
          json['audioQuality']?.toString() ?? json['quality']?.toString(),
      artworkUrl:
          json['artworkURL']?.toString() ?? json['artworkUrl']?.toString(),
      format: json['format']?.toString() ?? 'flac',
    );
  }
}

class QobuzMusicService {
  static final QobuzMusicService instance = QobuzMusicService._internal();
  QobuzMusicService._internal();

  /// Default fallback Eclipse Qobuz endpoint
  static const String defaultEndpoint =
      'https://qobuz-tidal-eclipse.cyrusna29.workers.dev/u/4opn823jmxs6yee60au24sse15kp';

  static const String generateUrl =
      'https://qobuz-tidal-eclipse.cyrusna29.workers.dev/generate';

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36';

  String? _activeEndpoint;
  String? _token;
  String? _manifestUrl;
  String? _quality;

  String get activeEndpoint => _activeEndpoint ?? defaultEndpoint;
  String? get currentToken => _token;
  String? get currentManifestUrl => _manifestUrl;
  String? get currentQuality => _quality;

  final Map<
    String,
    ({String url, Map<String, String> headers, String quality, String format})
  >
  _cache = {};

  /// Generates a fresh Eclipse token and manifestUrl dynamically on app launch
  Future<void> initialize() async {
    // Load previously cached endpoint first for immediate responsiveness.
    // The manifest URL embeds the session token, so all three live in the
    // keystore rather than the plaintext preferences file.
    try {
      _activeEndpoint = await SecureStore.read(SecretKeys.qobuzEclipseEndpoint);
      _token = await SecureStore.read(SecretKeys.qobuzEclipseToken);
      _manifestUrl = await SecureStore.read(SecretKeys.qobuzEclipseManifestUrl);
    } catch (_) {}

    // Request new dynamic token and manifest from /generate
    await refreshEndpoint();
  }

  /// Performs POST https://qobuz-tidal-eclipse.cyrusna29.workers.dev/generate
  Future<bool> refreshEndpoint() async {
    try {
      debugPrint(
        '[QobuzMusicService] Generating fresh FLAC Eclipse session on app launch...',
      );
      final uri = Uri.parse(generateUrl);
      final headers = {
        'Content-Type': 'application/json',
        'Origin': 'https://qobuz-tidal-eclipse.cyrusna29.workers.dev',
        'Referer': 'https://qobuz-tidal-eclipse.cyrusna29.workers.dev/',
        'User-Agent': userAgent,
        'sec-ch-ua':
            '"Not=A?Brand";v="99", "Brave";v="151", "Chromium";v="151"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'sec-fetch-dest': 'empty',
        'sec-fetch-mode': 'cors',
        'sec-fetch-site': 'same-origin',
        'sec-gpc': '1',
        'Accept': '*/*',
      };

      final response = await http
          .post(uri, headers: headers, body: '{}')
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = data['token']?.toString();
        final quality = data['quality']?.toString();
        final manifestUrl = data['manifestUrl']?.toString();

        if (manifestUrl != null && manifestUrl.isNotEmpty) {
          _manifestUrl = manifestUrl;
          _token = token;
          _quality = quality;
          _activeEndpoint = manifestUrl.replaceAll('/manifest.json', '');

          debugPrint(
            '[QobuzMusicService] Successfully generated fresh FLAC endpoint: $_activeEndpoint (Quality: $_quality)',
          );

          // Cache in the platform keystore
          try {
            await SecureStore.write(
              SecretKeys.qobuzEclipseEndpoint,
              _activeEndpoint!,
            );
            if (_token != null) {
              await SecureStore.write(SecretKeys.qobuzEclipseToken, _token!);
            }
            await SecureStore.write(
              SecretKeys.qobuzEclipseManifestUrl,
              _manifestUrl!,
            );
          } catch (_) {}

          return true;
        }
      } else {
        debugPrint(
          '[QobuzMusicService] Generate request returned status code ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint(
        '[QobuzMusicService] Failed to generate fresh FLAC endpoint: $e',
      );
    }
    return false;
  }

  /// Searches Qobuz tracks by query string using Eclipse /search endpoint
  Future<List<QobuzTrack>> searchTracks(
    String query, {
    String? endpoint,
  }) async {
    if (query.trim().isEmpty) return [];
    final base = endpoint ?? activeEndpoint;

    try {
      final url = Uri.parse(
        '$base/search?q=${Uri.encodeComponent(query.trim())}',
      );
      final res = await http
          .get(
            url,
            headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final tracksList =
            (data['tracks'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map((json) => QobuzTrack.fromJson(json))
                .where((t) => t.id.isNotEmpty)
                .toList() ??
            [];
        return tracksList;
      } else {
        debugPrint('Qobuz search HTTP error ${res.statusCode} for "$query"');
      }
    } catch (e) {
      debugPrint('Failed to search Qobuz tracks for "$query": $e');
    }
    return [];
  }

  /// Resolves direct audio stream URL from Qobuz Eclipse /stream/{id} endpoint
  Future<({String url, String format, String quality})?> getAudioStream(
    String trackId, {
    String? endpoint,
  }) async {
    final base = endpoint ?? activeEndpoint;
    try {
      final url = Uri.parse('$base/stream/$trackId');
      final res = await http
          .get(
            url,
            headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final streamUrl = data['url']?.toString();
        if (streamUrl != null && streamUrl.isNotEmpty) {
          final format = data['format']?.toString() ?? 'flac';
          final quality = data['quality']?.toString() ?? 'FLAC Hi-Res';
          return (url: streamUrl, format: format, quality: quality);
        }
      } else {
        debugPrint(
          'Qobuz stream HTTP error ${res.statusCode} for track $trackId',
        );
      }
    } catch (e) {
      debugPrint('Failed to get Qobuz stream for track $trackId: $e');
    }
    return null;
  }

  /// Matches a MusicTrack with Qobuz and returns the resolved FLAC stream URL & headers
  Future<
    ({String url, Map<String, String> headers, String quality, String format})?
  >
  resolveLosslessUrl(MusicTrack track, {String? endpoint}) async {
    if (_cache.containsKey(track.id)) {
      return _cache[track.id];
    }

    try {
      final title = track.title;
      final artist = track.artist;
      final query = '$title $artist'.trim();

      debugPrint(
        'Resolving FLAC lossless track on Qobuz for "$query" using endpoint $activeEndpoint...',
      );
      var results = await searchTracks(query, endpoint: endpoint);

      // Fallback search with cleaned title if no results found
      if (results.isEmpty) {
        final cleanTitle = _cleanTitle(title);
        if (cleanTitle != title) {
          final fallbackQuery = '$cleanTitle $artist'.trim();
          debugPrint(
            'Retrying Qobuz search with cleaned query "$fallbackQuery"...',
          );
          results = await searchTracks(fallbackQuery, endpoint: endpoint);
        }
      }

      if (results.isEmpty) {
        debugPrint('No Qobuz search results found for "$query"');
        return null;
      }

      final matchedTrack = _pickBestMatch(track, results);
      if (matchedTrack == null) return null;

      final streamResult = await getAudioStream(
        matchedTrack.id,
        endpoint: endpoint,
      );
      if (streamResult != null && streamResult.url.isNotEmpty) {
        debugPrint(
          'Resolved Qobuz Lossless stream (${streamResult.quality}) for ${track.title} (ID: ${matchedTrack.id})',
        );
        final result = (
          url: streamResult.url,
          headers: <String, String>{'User-Agent': userAgent},
          quality: streamResult.quality,
          format: streamResult.format,
        );
        _cache[track.id] = result;
        return result;
      }
    } catch (e) {
      debugPrint('Qobuz resolution error for ${track.title}: $e');
    }
    return null;
  }

  String _cleanTitle(String raw) {
    return raw
        .replaceAll(RegExp(r'\(feat\.[^)]+\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(ft\.[^)]+\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[feat\.[^\]]+\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[ft\.[^\]]+\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(Radio Edit\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(Remastered[^)]*\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[Remastered[^\]]*\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  QobuzTrack? _pickBestMatch(MusicTrack track, List<QobuzTrack> candidates) {
    if (candidates.isEmpty) return null;

    final normTitle = _normalizeString(track.title);
    final normArtist = _normalizeString(track.artist);
    final trackDuration = track.durationSeconds;

    QobuzTrack? bestTrack;
    var bestScore = -1;

    for (final c in candidates) {
      var score = 0;
      final cTitle = _normalizeString(c.title);
      final cArtist = _normalizeString(c.artist);

      // Title matching
      if (cTitle == normTitle) {
        score += 50;
      } else if (cTitle.contains(normTitle) || normTitle.contains(cTitle)) {
        score += 35;
      }

      // Artist matching
      if (normArtist.isNotEmpty) {
        if (cArtist == normArtist) {
          score += 40;
        } else if (cArtist.contains(normArtist) ||
            normArtist.contains(cArtist)) {
          score += 25;
        }
      } else {
        score += 20;
      }

      // Duration matching (bonus for close length within 4 seconds)
      if (trackDuration > 0 && c.durationSeconds > 0) {
        final diff = (trackDuration - c.durationSeconds).abs();
        if (diff <= 2) {
          score += 20;
        } else if (diff <= 5) {
          score += 10;
        } else if (diff <= 10) {
          score += 5;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        bestTrack = c;
      }
    }

    return bestTrack ?? candidates.first;
  }

  String _normalizeString(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }
}
