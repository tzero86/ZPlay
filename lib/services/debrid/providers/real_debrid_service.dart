import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/debrid_error.dart';
import '../models/debrid_file.dart';
import '../utils/debrid_failure_mapper.dart';
import '../utils/debrid_media_matcher.dart';

class RealDebridService {
  static const String _rdTokenKey = 'rd_access_token';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<String?> getToken() async {
    final prefs = await _prefs;
    return prefs.getString(_rdTokenKey);
  }

  Future<void> saveToken(String key) async {
    final prefs = await _prefs;
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(_rdTokenKey);
    } else {
      await prefs.setString(_rdTokenKey, trimmed);
    }
  }

  Future<bool> hasKey() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<Map<String, dynamic>?> verifyToken(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return null;
    try {
      final res = await http.get(
        Uri.parse('https://api.real-debrid.com/rest/1.0/user'),
        headers: {'Authorization': 'Bearer $trimmed'},
      );
      if (res.statusCode == 200) {
        return json.decode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[RealDebrid] verifyToken error: $e');
    }
    return null;
  }

  Future<List<DebridFile>> resolveMagnet(
    String magnet, {
    int? fileIndex,
    String? filename,
    int? season,
    int? episode,
    String? episodeTitle,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      throw DebridResolutionException.account(
        service: 'Real-Debrid',
        message:
            'Real-Debrid API token is missing. Please configure it in Settings.',
      );
    }

    final headers = {'Authorization': 'Bearer $token'};

    // 1. Add the magnet
    final addRes = await http.post(
      Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/addMagnet'),
      headers: headers,
      body: {'magnet': magnet},
    );

    if (addRes.statusCode != 201) {
      throw classifyHttpFailure(
        service: 'Real-Debrid',
        statusCode: addRes.statusCode,
        body: addRes.body,
      );
    }

    final addData = json.decode(addRes.body) as Map<String, dynamic>;
    final torrentId = addData['id'] as String;

    // 2. Poll info for file list
    Map<String, dynamic>? info;
    List<dynamic>? rdFiles;
    int attempts = 0;

    while (attempts < 20) {
      final infoRes = await http.get(
        Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/info/$torrentId'),
        headers: headers,
      );
      if (infoRes.statusCode == 200) {
        info = json.decode(infoRes.body) as Map<String, dynamic>;
        final status = info['status'] as String?;
        if (status != null &&
            (status == 'magnet_error' ||
                status == 'error' ||
                status == 'dead' ||
                status == 'virus')) {
          throw classifyTorrentStatus(service: 'Real-Debrid', status: status);
        }
        rdFiles = (info['files'] as List?) ?? const [];
        if (rdFiles.isNotEmpty) break;
      }
      await Future.delayed(const Duration(seconds: 2));
      attempts++;
    }

    if (rdFiles == null || rdFiles.isEmpty) {
      throw DebridResolutionException.notCached(
        service: 'Real-Debrid',
        message: 'Real-Debrid is still preparing this torrent, try again shortly.',
        detail: 'Real-Debrid never returned a file list for torrent $torrentId.',
      );
    }

    // 3. Pick matching file
    final picked = DebridMediaMatcher.pickMediaFile<dynamic>(
      rdFiles,
      fileIndex: fileIndex,
      filename: filename,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
      name: (f) => (f['path'] as String?) ?? '',
      size: (f) => (f['bytes'] as num?)?.toInt() ?? 0,
    );

    if (picked == null) {
      throw DebridResolutionException.sourceRejected(
        service: 'Real-Debrid',
        message: 'No file in this torrent matches what you asked for.',
        detail: 'No suitable media file found in Real-Debrid torrent.',
        rememberUnusable: false,
      );
    }

    final pickedId = picked['id'].toString();
    final pickedPath = (picked['path'] as String?) ?? '';
    final pickedSize = (picked['bytes'] as num?)?.toInt() ?? 0;

    final selRes = await http.post(
      Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/selectFiles/$torrentId'),
      headers: headers,
      body: {'files': pickedId},
    );

    if (selRes.statusCode != 204 && selRes.statusCode != 202) {
      await http.post(
        Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/selectFiles/$torrentId'),
        headers: headers,
        body: {'files': 'all'},
      );
    }

    // 4. Poll until downloaded / ready in cloud
    attempts = 0;
    while (attempts < 40) {
      final infoRes = await http.get(
        Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/info/$torrentId'),
        headers: headers,
      );
      if (infoRes.statusCode == 200) {
        info = json.decode(infoRes.body) as Map<String, dynamic>;
        final status = info['status'] as String?;
        if (status == 'downloaded') break;
        if (status != null &&
            (status == 'error' || status == 'dead' || status == 'virus')) {
          throw classifyTorrentStatus(service: 'Real-Debrid', status: status);
        }
      }
      await Future.delayed(const Duration(seconds: 3));
      attempts++;
    }

    if (info == null || info['status'] != 'downloaded') {
      throw DebridResolutionException.notCached(
        service: 'Real-Debrid',
        message: 'Real-Debrid has not cached this torrent yet, try again shortly.',
        detail: 'Real-Debrid download timed out. Torrent not cached on RD.',
      );
    }

    // 5. Unrestrict link
    final links = (info['links'] as List?) ?? const [];
    if (links.isEmpty) {
      throw DebridResolutionException.sourceRejected(
        service: 'Real-Debrid',
        message: 'Real-Debrid returned no playable link for this torrent.',
        detail: 'Real-Debrid returned no download links.',
        rememberUnusable: false,
      );
    }

    String? targetLink;
    if (links.length == 1) {
      targetLink = links.first as String;
    } else {
      final selectedFiles = (info['files'] as List)
          .where((f) => (f['selected'] as int?) == 1)
          .toList();
      final idx = selectedFiles.indexWhere((f) => f['id'].toString() == pickedId);
      if (idx >= 0 && idx < links.length) {
        targetLink = links[idx] as String;
      } else {
        targetLink = links.first as String;
      }
    }

    final unRes = await http.post(
      Uri.parse('https://api.real-debrid.com/rest/1.0/unrestrict/link'),
      headers: headers,
      body: {'link': targetLink},
    );

    if (unRes.statusCode != 200) {
      throw classifyHttpFailure(
        service: 'Real-Debrid',
        statusCode: unRes.statusCode,
        body: unRes.body,
      );
    }

    final data = json.decode(unRes.body) as Map<String, dynamic>;
    return [
      DebridFile(
        filename: (data['filename'] as String?) ?? pickedPath.split('/').last,
        filesize: (data['filesize'] as num?)?.toInt() ?? pickedSize,
        downloadUrl: data['download'] as String,
      ),
    ];
  }
}
