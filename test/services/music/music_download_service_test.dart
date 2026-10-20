import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// Tests drive the platform interface directly; these are path_provider's own
// dependencies and the pubspec is owned elsewhere, so they cannot be declared.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/music/music_download_service.dart';
import 'package:zplay/services/storage/json_document_store.dart';

const String _key = 'music_downloaded_tracks_v3';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

Map<String, dynamic> _trackJson(String id, String audioPath) =>
    <String, dynamic>{
      'id': id,
      'title': 'Title $id',
      'artist': 'Artist',
      'album': 'Album',
      'coverUrl': '',
      'durationSeconds': 120,
      'localAudioPath': audioPath,
      'localCoverPath': '',
      'format': 'm4a',
      'quality': 'HQ Audio',
      'fileSizeBytes': 200,
      'downloadedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('zplay_music_storage_test');
    PathProviderPlatform.instance = _FakePathProvider(temp.path);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test(
    'loads legacy bare JSON, verifies files, and persists an envelope',
    () async {
      final audio = File('${temp.path}/track.m4a')
        ..writeAsBytesSync(List<int>.filled(200, 0));
      final missing = '${temp.path}/missing.m4a';

      SharedPreferences.setMockInitialValues({
        _key: jsonEncode([
          _trackJson('present', audio.path),
          _trackJson('missing', missing),
        ]),
      });

      final service = MusicDownloadService.instance;
      await service.init();

      expect(service.downloadedTracks.map((t) => t.id), [
        'present',
      ], reason: 'tracks whose file is gone must still be dropped');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_key), contains(JsonDocumentStore.schemaField));

      await service.deleteDownloadedTrack('present');

      final stored = prefs.getString(_key);
      expect(stored, contains(JsonDocumentStore.schemaField));
      expect(stored, contains('"data":[]'));
    },
  );
}
