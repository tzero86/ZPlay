import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/anime/anime_media.dart';
import '../content/content_settings.dart';
import '../storage/json_document_store.dart';

class AnimeLibraryService extends ChangeNotifier {
  static final AnimeLibraryService instance = AnimeLibraryService._internal();
  AnimeLibraryService._internal() {
    ContentSettings.adultEnabled.addListener(notifyListeners);
  }

  static const String _watchlistKey = 'zplay_anime_watchlist_v2';
  static const String _historyKey = 'zplay_anime_history_v2';
  static const String _legacyWatchlistKey = 'zplay_anime_watchlist_v1';
  static const String _legacyHistoryKey = 'zplay_anime_history_v1';

  /// One item that cannot be decoded is dropped; the rest of the document is
  /// kept. The previous per-entry `StringList` decode had the same tolerance,
  /// and losing a whole watchlist to one damaged entry is worse than losing it.
  static List<AnimeWatchlistItem> _decodeItems(Object? value) {
    final items = <AnimeWatchlistItem>[];
    if (value is! List) return items;
    for (final entry in value) {
      try {
        items.add(
          AnimeWatchlistItem.fromJson(Map<String, dynamic>.from(entry as Map)),
        );
      } catch (_) {}
    }
    return items;
  }

  static final JsonDocumentStore<List<AnimeWatchlistItem>> _watchlistStore =
      JsonDocumentStore<List<AnimeWatchlistItem>>(
        key: _watchlistKey,
        version: 1,
        decode: _decodeItems,
        encode: (items) => items.map((item) => item.toJson()).toList(),
        migrations: <int, JsonMigration>{0: (value) => value},
      );

  static final JsonDocumentStore<List<AnimeWatchlistItem>> _historyStore =
      JsonDocumentStore<List<AnimeWatchlistItem>>(
        key: _historyKey,
        version: 1,
        decode: _decodeItems,
        encode: (items) => items.map((item) => item.toJson()).toList(),
        migrations: <int, JsonMigration>{0: (value) => value},
      );

  final List<AnimeWatchlistItem> _watchlist = [];
  final Map<int, AnimeWatchlistItem> _progressMap = {};

  bool _isInitialized = false;

  /// While the global Adult Content switch is off, adult entries are hidden from
  /// every list the library exposes. Nothing is removed from storage, so they
  /// come back as soon as the switch is turned on.
  bool _isVisible(AnimeWatchlistItem item) =>
      ContentSettings.adultEnabled.value || !item.anime.isAdult;

  List<AnimeWatchlistItem> get watchlist =>
      List.unmodifiable(_watchlist.where(_isVisible));
  List<AnimeWatchlistItem> get watchingList => _watchlist
      .where(
        (item) => item.status == AnimeWatchStatus.watching && _isVisible(item),
      )
      .toList();
  List<AnimeWatchlistItem> get planToWatchList => _watchlist
      .where(
        (item) =>
            item.status == AnimeWatchStatus.planToWatch && _isVisible(item),
      )
      .toList();
  List<AnimeWatchlistItem> get completedList => _watchlist
      .where(
        (item) => item.status == AnimeWatchStatus.completed && _isVisible(item),
      )
      .toList();
  List<AnimeWatchlistItem> get recentHistory => List.unmodifiable(
    _progressMap.values.where(_isVisible).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
  );

  /// Whether the library holds [title] as adult content, regardless of the
  /// switch state. Lets entries saved elsewhere (My List), which carry no
  /// maturity flag of their own, be classified without new persistence.
  bool isKnownAdultTitle(String title) {
    final key = _normalizedTitle(title);
    if (key.isEmpty) return false;
    bool isAdult(AnimeWatchlistItem entry) =>
        entry.anime.isAdult &&
        _normalizedTitle(entry.anime.displayTitle) == key;
    return _watchlist.any(isAdult) || _progressMap.values.any(isAdult);
  }

  static String _normalizedTitle(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<void> init() async {
    if (_isInitialized) return;
    await reloadLocal();
  }

  /// Re-reads both documents into memory, without any network or cloud sync.
  ///
  /// Used after a profile import so the restored watchlist and history are
  /// visible immediately instead of on the next launch.
  Future<void> reloadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final watchlist = await _read(
        _watchlistStore,
        _legacyWatchlistKey,
        prefs,
      );
      final history = await _read(_historyStore, _legacyHistoryKey, prefs);

      _watchlist
        ..clear()
        ..addAll(watchlist);
      _progressMap
        ..clear()
        ..addEntries(history.map((item) => MapEntry(item.anime.id, item)));

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('AnimeLibraryService init error: $e');
    }
  }

  /// Reads [store], migrating a legacy `StringList` under [legacyKey] on first
  /// run. A migrated list is written to the new key and the old one removed.
  static Future<List<AnimeWatchlistItem>> _read(
    JsonDocumentStore<List<AnimeWatchlistItem>> store,
    String legacyKey,
    SharedPreferences prefs,
  ) async {
    final stored = await store.read();
    if (stored != null) return stored;

    final legacy = prefs.getStringList(legacyKey);
    if (legacy == null) return const <AnimeWatchlistItem>[];

    final items = <AnimeWatchlistItem>[];
    for (final raw in legacy) {
      try {
        items.add(
          AnimeWatchlistItem.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {}
    }
    await store.write(items);
    await prefs.remove(legacyKey);
    return items;
  }

  bool isAnimeInWatchlist(int anilistId) {
    return _watchlist.any((i) => i.anime.id == anilistId);
  }

  AnimeWatchlistItem? getWatchlistItem(int anilistId) {
    try {
      return _watchlist.firstWhere((i) => i.anime.id == anilistId);
    } catch (_) {
      return null;
    }
  }

  AnimeWatchlistItem? getProgress(int anilistId) {
    return _progressMap[anilistId];
  }

  Future<void> setWatchlistStatus(
    AnimeMedia anime,
    AnimeWatchStatus status,
  ) async {
    final idx = _watchlist.indexWhere((i) => i.anime.id == anime.id);
    final currentProgress = _progressMap[anime.id];

    final newItem = AnimeWatchlistItem(
      anime: anime,
      status: status,
      lastWatchedEpisode: currentProgress?.lastWatchedEpisode ?? 0,
      lastWatchedPositionSeconds:
          currentProgress?.lastWatchedPositionSeconds ?? 0,
      totalDurationSeconds: currentProgress?.totalDurationSeconds ?? 0,
      updatedAt: DateTime.now(),
    );

    if (idx >= 0) {
      _watchlist[idx] = newItem;
    } else {
      _watchlist.insert(0, newItem);
    }

    notifyListeners();
    await _saveWatchlist();
  }

  Future<void> removeFromWatchlist(int anilistId) async {
    _watchlist.removeWhere((i) => i.anime.id == anilistId);
    notifyListeners();
    await _saveWatchlist();
  }

  Future<void> updateProgress({
    required AnimeMedia anime,
    required int episodeNumber,
    required int positionSeconds,
    required int durationSeconds,
  }) async {
    final status = _watchlist
        .firstWhere(
          (i) => i.anime.id == anime.id,
          orElse: () => AnimeWatchlistItem(
            anime: anime,
            status: AnimeWatchStatus.watching,
            updatedAt: DateTime.now(),
          ),
        )
        .status;

    final item = AnimeWatchlistItem(
      anime: anime,
      status: status,
      lastWatchedEpisode: episodeNumber,
      lastWatchedPositionSeconds: positionSeconds,
      totalDurationSeconds: durationSeconds,
      updatedAt: DateTime.now(),
    );

    _progressMap[anime.id] = item;

    // Update watchlist item if present
    final wlIdx = _watchlist.indexWhere((i) => i.anime.id == anime.id);
    if (wlIdx >= 0) {
      _watchlist[wlIdx] = item;
    }

    notifyListeners();
    await _saveHistory();
    if (wlIdx >= 0) {
      await _saveWatchlist();
    }
  }

  Future<void> _saveWatchlist() async {
    try {
      await _watchlistStore.write(List<AnimeWatchlistItem>.of(_watchlist));
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      await _historyStore.write(
        List<AnimeWatchlistItem>.of(_progressMap.values),
      );
    } catch (_) {}
  }
}
