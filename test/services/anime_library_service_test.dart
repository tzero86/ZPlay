import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/models/anime/anime_media.dart';
import 'package:zplay/services/anime/anime_library_service.dart';
import 'package:zplay/services/storage/json_document_store.dart';

const String _watchlistKey = 'zplay_anime_watchlist_v2';
const String _historyKey = 'zplay_anime_history_v2';
const String _legacyWatchlistKey = 'zplay_anime_watchlist_v1';
const String _legacyHistoryKey = 'zplay_anime_history_v1';

AnimeWatchlistItem _item(
  int id, {
  AnimeWatchStatus status = AnimeWatchStatus.watching,
  int episode = 0,
  DateTime? updatedAt,
}) {
  return AnimeWatchlistItem(
    anime: AnimeMedia(id: id, titleEnglish: 'Anime $id'),
    status: status,
    lastWatchedEpisode: episode,
    updatedAt: updatedAt ?? DateTime(2026, 1, 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('migrates legacy StringList entries into both documents', () async {
    final legacyWatch = _item(1, status: AnimeWatchStatus.planToWatch);
    final legacyHistory = _item(2, episode: 5);
    SharedPreferences.setMockInitialValues({
      _legacyWatchlistKey: <String>[
        jsonEncode(legacyWatch.toJson()),
        'not json at all',
      ],
      _legacyHistoryKey: <String>[jsonEncode(legacyHistory.toJson())],
    });

    final service = AnimeLibraryService.instance;
    await service.reloadLocal();

    expect(
      service.watchlist.single.anime.id,
      1,
      reason: 'the one unreadable legacy entry must not drop the valid one',
    );
    expect(service.watchlist.single.status, AnimeWatchStatus.planToWatch);
    expect(service.recentHistory.single.anime.id, 2);
    expect(service.recentHistory.single.lastWatchedEpisode, 5);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(_watchlistKey),
      contains(JsonDocumentStore.schemaField),
    );
    expect(
      prefs.getString(_historyKey),
      contains(JsonDocumentStore.schemaField),
    );
    expect(
      prefs.containsKey(_legacyWatchlistKey),
      isFalse,
      reason: 'a migrated legacy list is removed once it is in the store',
    );
    expect(prefs.containsKey(_legacyHistoryKey), isFalse);
  });

  test('saves both documents as envelopes that reload', () async {
    final service = AnimeLibraryService.instance;
    await service.reloadLocal();

    await service.setWatchlistStatus(
      const AnimeMedia(id: 10, titleEnglish: 'Saved Anime'),
      AnimeWatchStatus.completed,
    );
    await service.updateProgress(
      anime: const AnimeMedia(id: 10, titleEnglish: 'Saved Anime'),
      episodeNumber: 3,
      positionSeconds: 120,
      durationSeconds: 1440,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(_watchlistKey),
      contains(JsonDocumentStore.schemaField),
    );
    expect(
      prefs.getString(_historyKey),
      contains(JsonDocumentStore.schemaField),
    );
    expect(prefs.containsKey(_legacyWatchlistKey), isFalse);
    expect(prefs.containsKey(_legacyHistoryKey), isFalse);

    await service.reloadLocal();
    expect(service.watchlist.single.status, AnimeWatchStatus.completed);
    expect(service.recentHistory.single.lastWatchedEpisode, 3);
    expect(service.recentHistory.single.lastWatchedPositionSeconds, 120);
  });
}
