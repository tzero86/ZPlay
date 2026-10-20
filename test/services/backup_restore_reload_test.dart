import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/models/anime/anime_media.dart';
import 'package:zplay/models/my_list/my_list_item.dart';
import 'package:zplay/services/anime/anime_library_service.dart';
import 'package:zplay/services/backup/backup_restore_service.dart';
import 'package:zplay/services/my_list/my_list_service.dart';
import 'package:zplay/services/storage/json_document_store.dart';

const String _myListKey = 'my_list_v1';
const String _animeWatchlistKey = 'zplay_anime_watchlist_v2';

/// The same shape the services declare, so a document written here is a
/// document they can read.
JsonDocumentStore<List<MyListItem>> _myListStore() {
  return JsonDocumentStore<List<MyListItem>>(
    key: _myListKey,
    version: 1,
    decode: (value) => (value as List)
        .map((entry) => MyListItem.fromJson(entry as Map<String, dynamic>))
        .toList(),
    encode: (items) => items.map((item) => item.toJson()).toList(),
    migrations: <int, JsonMigration>{0: (value) => value},
  );
}

JsonDocumentStore<List<AnimeWatchlistItem>> _animeStore() {
  return JsonDocumentStore<List<AnimeWatchlistItem>>(
    key: _animeWatchlistKey,
    version: 1,
    decode: (value) => (value as List)
        .map(
          (entry) => AnimeWatchlistItem.fromJson(entry as Map<String, dynamic>),
        )
        .toList(),
    encode: (items) => items.map((item) => item.toJson()).toList(),
    migrations: <int, JsonMigration>{0: (value) => value},
  );
}

MyListItem _myListItem(String title) => MyListItem(
  traktId: 1,
  title: title,
  year: 2024,
  type: 'movie',
  addedAt: DateTime(2026),
);

AnimeWatchlistItem _animeItem(int id) => AnimeWatchlistItem(
  anime: AnimeMedia(id: id, titleEnglish: 'Anime $id'),
  status: AnimeWatchStatus.watching,
  updatedAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MyListService.items.value = [];
  });

  test(
    'an imported profile updates the running services without restart',
    () async {
      final myList = _myListStore();
      final anime = _animeStore();

      // The state the app booted with.
      SharedPreferences.setMockInitialValues({});
      await myList.write([_myListItem('Old Item')]);
      await anime.write([_animeItem(1)]);
      await MyListService.reloadLocal();
      await AnimeLibraryService.instance.reloadLocal();

      expect(MyListService.items.value.single.title, 'Old Item');
      expect(AnimeLibraryService.instance.watchlist.single.anime.id, 1);

      // A profile produced elsewhere, carrying durable documents.
      await myList.write([_myListItem('Restored Item')]);
      await anime.write([_animeItem(99)]);
      final profile = await BackupRestoreService.exportSettingsJson();

      // The running services still hold the pre-restore state until the import
      // applies the documents and reloads them.
      expect(MyListService.items.value.single.title, 'Old Item');
      expect(AnimeLibraryService.instance.watchlist.single.anime.id, 1);

      await BackupRestoreService.importSettingsJson(profile);

      expect(
        MyListService.items.value.single.title,
        'Restored Item',
        reason: 'the restored My List must be live without a restart',
      );
      expect(
        AnimeLibraryService.instance.watchlist.single.anime.id,
        99,
        reason: 'the restored anime watchlist must be live without a restart',
      );
    },
  );
}
