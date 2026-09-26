import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/debrid_error.dart';
import '../models/debrid_file.dart';
import '../utils/debrid_failure_mapper.dart';
import '../utils/debrid_media_matcher.dart';

class DebridLinkService {
  static const String _key = 'debridlink_api_key';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<String?> getKey() async {
    final prefs = await _prefs;
    return prefs.getString(_key);
  }

  Future<void> saveKey(String key) async {
    final prefs = await _prefs;
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, trimmed);
    }
  }

  Future<bool> hasKey() async {
    final key = await getKey();
    return key != null && key.isNotEmpty;
  }

  Future<Map<String, dynamic>?> verifyKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return null;
    try {
      final res = await http.get(
        Uri.parse('https://debrid-link.com/api/v2/account/infos'),
        headers: {'Authorization': 'Bearer $trimmed'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['success'] == true) {
          return data['value'] as Map<String, dynamic>?;
        }
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> _dlDecode(http.Response res) {
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw classifyHttpFailure(
        service: 'Debrid-Link',
        statusCode: res.statusCode,
        body: res.body,
      );
    }
    return body;
  }

  List<Map<String, dynamic>> _dlExtractFiles(dynamic torrentValue) {
    final out = <Map<String, dynamic>>[];
    if (torrentValue is! Map) return out;
    final files = torrentValue['files'];
    if (files is! List) return out;
    for (final raw in files) {
      if (raw is! Map) continue;
      out.add({
        'path': (raw['name'] as String?) ?? '',
        'size': (raw['size'] as num?)?.toInt() ?? 0,
        'link': (raw['downloadUrl'] as String?) ?? '',
        'percent': (raw['downloadPercent'] as num?)?.toDouble() ?? 0.0,
      });
    }
    return out;
  }

  Future<List<DebridFile>> resolveMagnet(
    String magnet, {
    int? fileIndex,
    String? filename,
    int? season,
    int? episode,
    String? episodeTitle,
  }) async {
    final apiKey = await getKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw DebridResolutionException.account(
        service: 'Debrid-Link',
        message:
            'Debrid-Link API key is missing. Please configure it in Settings.',
      );
    }
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };

    final addRes = await http.post(
      Uri.parse('https://debrid-link.com/api/v2/seedbox/add'),
      headers: headers,
      body: json.encode({'url': magnet, 'async': true}),
    );
    final addBody = _dlDecode(addRes);
    final torrent = addBody['value'];
    if (torrent is! Map || torrent['id'] == null) {
      throw DebridResolutionException.sourceRejected(
        service: 'Debrid-Link',
        message: 'Debrid-Link refused this magnet.',
        detail: 'Debrid-Link: no torrent id returned',
        rememberUnusable: false,
      );
    }
    final torrentId = torrent['id'] as String;

    var files = _dlExtractFiles(torrent);
    bool ready = files.isNotEmpty &&
        files.every((f) => (f['link'] as String).isNotEmpty);

    int attempts = 0;
    while (!ready && attempts < 40) {
      await Future.delayed(const Duration(seconds: 3));
      final stRes = await http.get(
        Uri.parse('https://debrid-link.com/api/v2/seedbox/list?ids=$torrentId'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );
      final stBody = _dlDecode(stRes);
      final list = stBody['value'];
      if (list is List && list.isNotEmpty) {
        files = _dlExtractFiles(list.first);
        ready = files.isNotEmpty &&
            files.every((f) => (f['link'] as String).isNotEmpty);
      }
      attempts++;
    }
    if (files.isEmpty) {
      throw DebridResolutionException.notCached(
        service: 'Debrid-Link',
        message: 'Debrid-Link has no files for this torrent yet, try again shortly.',
        detail: 'Debrid-Link: no files in torrent',
      );
    }
    if (!ready) {
      throw DebridResolutionException.notCached(
        service: 'Debrid-Link',
        message: 'Debrid-Link is still preparing this torrent, try again shortly.',
        detail: 'Debrid-Link: torrent not ready after 120s',
      );
    }

    final picked = DebridMediaMatcher.pickMediaFile<Map<String, dynamic>>(
      files,
      fileIndex: fileIndex,
      filename: filename,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
      name: (f) => (f['path'] as String?) ?? '',
      size: (f) => (f['size'] as num?)?.toInt() ?? 0,
    );
    if (picked == null) {
      throw DebridResolutionException.sourceRejected(
        service: 'Debrid-Link',
        message: 'No file in this torrent matches what you asked for.',
        detail: 'Debrid-Link: no suitable media file found in torrent',
        rememberUnusable: false,
      );
    }
    final pickedPath = (picked['path'] as String?) ?? '';
    final pickedLink = (picked['link'] as String?) ?? '';
    if (pickedLink.isEmpty) {
      throw DebridResolutionException.sourceRejected(
        service: 'Debrid-Link',
        message: 'Debrid-Link has no playable link for this file.',
        detail: 'Debrid-Link: picked file has no download link',
        rememberUnusable: false,
      );
    }

    return [
      DebridFile(
        filename: pickedPath.split('/').last,
        filesize: (picked['size'] as num?)?.toInt() ?? 0,
        downloadUrl: pickedLink,
      ),
    ];
  }
}
