import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/debrid_error.dart';
import '../models/debrid_file.dart';
import '../utils/debrid_failure_mapper.dart';
import '../utils/debrid_media_matcher.dart';
import '../../config/env_service.dart';

class AllDebridService {
  static const String _key = 'alldebrid_api_key';

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
        Uri.parse(
          'https://api.alldebrid.com/v4/user?agent=${EnvService.alldebridAgent}&apikey=$trimmed',
        ),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['status'] == 'success') {
          return data['data']?['user'] as Map<String, dynamic>?;
        }
      }
    } catch (_) {}
    return null;
  }

  void _flattenAdFiles(
    List<dynamic> nodes,
    String prefix,
    List<Map<String, dynamic>> out,
  ) {
    for (final node in nodes) {
      if (node is! Map) continue;
      final name = (node['n'] as String?) ?? '';
      final children = node['e'];
      if (children is List) {
        _flattenAdFiles(
          children,
          prefix.isEmpty ? name : '$prefix/$name',
          out,
        );
      } else {
        out.add({
          'path': prefix.isEmpty ? name : '$prefix/$name',
          'size': (node['s'] as num?)?.toInt() ?? 0,
          'link': (node['l'] as String?) ?? '',
        });
      }
    }
  }

  Map<String, dynamic> _adDecode(http.Response res) {
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['status'] == 'error') {
      throw classifyHttpFailure(
        service: 'AllDebrid',
        statusCode: res.statusCode,
        body: res.body,
      );
    }
    return (body['data'] as Map).cast<String, dynamic>();
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
        service: 'AllDebrid',
        message: 'AllDebrid API key is missing. Please configure it in Settings.',
      );
    }
    final headers = {'Authorization': 'Bearer $apiKey'};

    // 1. Upload magnet
    final upRes = await http.post(
      Uri.parse('https://api.alldebrid.com/v4/magnet/upload'),
      headers: headers,
      body: {'magnets[]': magnet},
    );
    final upData = _adDecode(upRes);
    final magnets = (upData['magnets'] as List?) ?? const [];
    if (magnets.isEmpty || magnets.first is! Map) {
      throw DebridResolutionException.transient(
        service: 'AllDebrid',
        message: 'AllDebrid answered with an unexpected response, try again.',
        detail: 'AllDebrid: empty magnet upload response',
      );
    }
    final m = (magnets.first as Map).cast<String, dynamic>();
    if (m['error'] != null) {
      final e = (m['error'] as Map).cast<String, dynamic>();
      throw DebridResolutionException.sourceRejected(
        service: 'AllDebrid',
        message: 'AllDebrid refused this magnet.',
        detail: 'AllDebrid: ${e['code']} - ${e['message']}',
        rememberUnusable: false,
      );
    }
    final magnetId = m['id'];
    if (magnetId == null) {
      throw DebridResolutionException.sourceRejected(
        service: 'AllDebrid',
        message: 'AllDebrid refused this magnet.',
        detail: 'AllDebrid: no magnet id returned',
        rememberUnusable: false,
      );
    }

    // 2. Poll status
    int attempts = 0;
    while (attempts < 40) {
      final stRes = await http.post(
        Uri.parse('https://api.alldebrid.com/v4.1/magnet/status'),
        headers: headers,
        body: {'id': magnetId.toString()},
      );
      final stData = _adDecode(stRes);
      final mags = stData['magnets'];
      Map<String, dynamic>? magObj;
      if (mags is List && mags.isNotEmpty && mags.first is Map) {
        magObj = (mags.first as Map).cast<String, dynamic>();
      } else if (mags is Map) {
        magObj = mags.cast<String, dynamic>();
      }
      final code = (magObj?['statusCode'] as num?)?.toInt() ?? -1;
      if (code == 4) break;
      if (code >= 5) {
        final word = (magObj?['status'] as String?) ?? 'error';
        final classified = classifyTorrentStatus(
          service: 'AllDebrid',
          status: word,
        );
        throw DebridResolutionException(
          kind: classified.kind,
          service: classified.service,
          message: classified.message,
          detail: 'AllDebrid magnet failed: $word (code $code)',
          rememberUnusable: classified.rememberUnusable,
        );
      }
      await Future.delayed(const Duration(seconds: 3));
      attempts++;
    }

    // 3. Get files
    final filesRes = await http.post(
      Uri.parse('https://api.alldebrid.com/v4/magnet/files'),
      headers: headers,
      body: {'id[]': magnetId.toString()},
    );
    final filesData = _adDecode(filesRes);
    final filesMagnets = (filesData['magnets'] as List?) ?? const [];
    if (filesMagnets.isEmpty || filesMagnets.first is! Map) {
      throw DebridResolutionException.transient(
        service: 'AllDebrid',
        message: 'AllDebrid answered with an unexpected response, try again.',
        detail: 'AllDebrid: empty files response',
      );
    }
    final filesObj = (filesMagnets.first as Map).cast<String, dynamic>();
    if (filesObj['error'] != null) {
      final e = (filesObj['error'] as Map).cast<String, dynamic>();
      throw DebridResolutionException.sourceRejected(
        service: 'AllDebrid',
        message: 'AllDebrid refused this magnet.',
        detail: 'AllDebrid files: ${e['code']} - ${e['message']}',
        rememberUnusable: false,
      );
    }
    final tree = (filesObj['files'] as List?) ?? const [];
    final flat = <Map<String, dynamic>>[];
    _flattenAdFiles(tree, '', flat);
    if (flat.isEmpty) {
      throw DebridResolutionException.notCached(
        service: 'AllDebrid',
        message: 'AllDebrid has no files for this torrent yet, try again shortly.',
        detail: 'AllDebrid: no files in magnet',
      );
    }

    // 4. Pick file
    final picked = DebridMediaMatcher.pickMediaFile<Map<String, dynamic>>(
      flat,
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
        service: 'AllDebrid',
        message: 'No file in this torrent matches what you asked for.',
        detail: 'AllDebrid: no suitable media file found in torrent',
        rememberUnusable: false,
      );
    }
    final pickedPath = (picked['path'] as String?) ?? '';
    final pickedLink = (picked['link'] as String?) ?? '';
    final pickedSize = (picked['size'] as num?)?.toInt() ?? 0;
    if (pickedLink.isEmpty) {
      throw DebridResolutionException.sourceRejected(
        service: 'AllDebrid',
        message: 'AllDebrid has no playable link for this file.',
        detail: 'AllDebrid: picked file has no unlock link',
        rememberUnusable: false,
      );
    }

    // 5. Unlock link
    final unRes = await http.post(
      Uri.parse('https://api.alldebrid.com/v4/link/unlock'),
      headers: headers,
      body: {'link': pickedLink},
    );
    final unData = _adDecode(unRes);
    final dlLink = unData['link'] as String?;
    if (dlLink == null || dlLink.isEmpty) {
      if (unData['delayed'] != null) {
        throw DebridResolutionException.notCached(
          service: 'AllDebrid',
          message: 'AllDebrid is still unlocking this file, try again shortly.',
          detail: 'AllDebrid returned a delayed link',
        );
      }
      throw DebridResolutionException.sourceRejected(
        service: 'AllDebrid',
        message: 'AllDebrid has no playable link for this file.',
        detail: 'AllDebrid unlock returned no link',
        rememberUnusable: false,
      );
    }
    return [
      DebridFile(
        filename: (unData['filename'] as String?) ?? pickedPath.split('/').last,
        filesize: (unData['filesize'] as num?)?.toInt() ?? pickedSize,
        downloadUrl: dlLink,
      ),
    ];
  }
}
