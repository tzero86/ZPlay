import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/models/iptv/m3u_models.dart';
import 'package:zplay/services/iptv/m3u_store.dart';
import 'package:zplay/services/storage/json_document_store.dart';

const String _key = 'pt_iptv_m3u_playlists_v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('loads legacy bare JSON and rewrites it as an envelope', () async {
    SharedPreferences.setMockInitialValues({
      _key: jsonEncode([
        const M3uPlaylist(
          id: 'legacy',
          name: 'Legacy playlist',
          sourceUrl: 'https://example.test/list.m3u',
          addedAt: 1,
          updatedAt: 2,
          channels: <M3uChannel>[],
        ).toJson(),
      ]),
    });

    final playlists = await M3uStore.loadAll();

    expect(playlists.single.id, 'legacy');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_key), contains(JsonDocumentStore.schemaField));
  });

  test('saveAll writes an envelope that loadAll reads back', () async {
    const playlist = M3uPlaylist(
      id: 'saved',
      name: 'Saved playlist',
      sourceUrl: null,
      addedAt: 3,
      updatedAt: 4,
      channels: <M3uChannel>[],
    );

    await M3uStore.saveAll(const [playlist]);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_key), contains(JsonDocumentStore.schemaField));
    expect(
      jsonDecode(prefs.getString(_key)!) as Map<String, dynamic>,
      contains('data'),
    );

    final playlists = await M3uStore.loadAll();
    expect(playlists.single.id, 'saved');
  });
}
