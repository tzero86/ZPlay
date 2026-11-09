// Persistence for the M3U playlists the user imported. Downloading lives in
// `sources/m3u_remote_source.dart`, which is also what the scan path reads.
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/iptv/m3u_models.dart';
import '../storage/json_document_store.dart';

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
