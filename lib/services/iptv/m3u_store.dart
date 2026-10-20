// Persistence + network fetch for M3U playlists.
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/iptv/m3u_models.dart';
import '../storage/json_document_store.dart';
import 'm3u_parser.dart';

class M3uStore {
  static const _key = 'pt_iptv_m3u_playlists_v1';

  static final JsonDocumentStore<List<M3uPlaylist>> _store =
      JsonDocumentStore<List<M3uPlaylist>>(
        key: _key,
        version: 1,
        decode: (value) => (value as List)
            .map((entry) => M3uPlaylist.fromJson(entry as Map<String, dynamic>))
            .toList(),
        encode: (playlists) =>
            playlists.map((playlist) => playlist.toJson()).toList(),
        migrations: <int, JsonMigration>{0: (value) => value},
      );

  static Future<List<M3uPlaylist>> loadAll() async {
    try {
      return await _store.read() ?? <M3uPlaylist>[];
    } catch (e) {
      debugPrint('M3uStore.loadAll failed: $e');
      return [];
    }
  }

  static Future<void> saveAll(List<M3uPlaylist> list) async {
    await _store.write(List<M3uPlaylist>.from(list));
  }

  static String newId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final r = Random.secure().nextInt(1 << 32).toRadixString(16);
    return '${ts.toRadixString(16)}_$r';
  }
}

class M3uFetcher {
  static const _ua = 'VLC/3.0.20 LibVLC/3.0.20';

  static Future<String> fetch(String url) async {
    final uri = Uri.parse(url);
    final res = await http
        .get(uri, headers: const {'User-Agent': _ua})
        .timeout(const Duration(seconds: 25));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException(
        'HTTP ${res.statusCode} while fetching playlist',
        uri: uri,
      );
    }
    final body = res.body;
    if (body.trim().isEmpty) {
      throw const FormatException('Empty response body');
    }
    return body;
  }

  static Future<List<M3uChannel>> fetchAndParse(String url) async {
    final body = await fetch(url);
    return M3uParser.parse(body);
  }
}
