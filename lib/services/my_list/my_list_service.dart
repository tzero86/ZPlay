import 'package:flutter/foundation.dart';
import '../../models/my_list/my_list_item.dart';
import '../anime/anime_library_service.dart';
import '../content/content_settings.dart';
import '../continue_watching/continue_watching_service.dart';
import '../storage/json_document_store.dart';
import '../trakt/trakt_service.dart';
import '../simkl/simkl_service.dart';

abstract final class MyListService {
  static const _storageKey = 'my_list_v1';
  static const int maxItems = 500;
  static void _invalidateSectionCache() {}

  /// The list used to be one bare JSON string decoded at startup; a decode
  /// failure reset it to empty. The store keeps the last valid copy and
  /// migrates the existing string in place.
  static final JsonDocumentStore<List<MyListItem>> _store =
      JsonDocumentStore<List<MyListItem>>(
        key: _storageKey,
        version: 1,
        decode: (value) => (value as List)
            .map((entry) => MyListItem.fromJson(entry as Map<String, dynamic>))
            .toList(),
        encode: (items) => items.map((item) => item.toJson()).toList(),
        migrations: <int, JsonMigration>{0: (value) => value},
      );

  static final ValueNotifier<List<MyListItem>> items =
      ValueNotifier<List<MyListItem>>([]);
  static final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  /// Items the global Adult Content switch allows to render. Storage is never
  /// touched, so entries reappear the moment the switch is turned back on.
  static List<MyListItem> get visibleItems {
    if (ContentSettings.adultEnabled.value) return items.value;
    // Collect adult session ids once: testing each entry via isAdultContent
    // would re-scan the session list per entry (O(N*M)).
    final adultIds = _adultSessionIds();
    return items.value
        .where((i) => !isAdultContent(i, adultSessionIds: adultIds))
        .toList();
  }

  /// Whether [item] is known to come from adult content.
  ///
  /// My List stores no addon provenance or maturity flag, so an entry is only
  /// classified when the app already knows the media is adult: an adult-flagged
  /// Continue Watching session for the same id, or an adult anime in the anime
  /// library with the same title. Anything else stays visible — this adds no
  /// persistence and performs no network lookups. Pass [adultSessionIds] when
  /// classifying a batch so the session list is scanned once, not per item.
  static bool isAdultContent(MyListItem item, {Set<String>? adultSessionIds}) {
    final imdbId = item.imdbId;
    final tmdbId = item.tmdbId;
    final adultIds = adultSessionIds ?? _adultSessionIds();
    final playedFromAdultSource =
        (imdbId != null && imdbId.isNotEmpty && adultIds.contains(imdbId)) ||
        (tmdbId != null && adultIds.contains('tmdb:$tmdbId'));
    if (playedFromAdultSource) return true;

    return AnimeLibraryService.instance.isKnownAdultTitle(item.title);
  }

  static Set<String> _adultSessionIds() {
    final ids = <String>{};
    for (final session in ContinueWatchingService.activeItems.value) {
      if (session.isAdult) ids.add(session.id);
    }
    return ids;
  }

  static Future<void> initialize() async {
    await reloadLocal();
    syncAll();
  }

  /// Re-reads the stored list into [items] without contacting Trakt or Simkl.
  ///
  /// Used after a profile import, which has already written the document the
  /// running app now needs to show.
  static Future<void> reloadLocal() async {
    final stored = await _store.read();
    if (stored != null) {
      items.value = stored;
    }
  }

  static Future<void> syncAll() async {
    if (isSyncing.value) return;

    // Ask about the accounts before showing a sync state. A device with no
    // Trakt or Simkl pairing has nothing to sync, and announcing "Syncing..."
    // while the auth check runs is both untrue and, on a platform where the
    // keystore is slow, a spinner that outlives the page's first frame.
    final hasTrakt = await TraktService.instance.isAuthenticated();
    final hasSimkl = await SimklService.instance.isAuthenticated();
    if (!hasTrakt && !hasSimkl) return;

    isSyncing.value = true;
    try {
      await Future.wait([
        if (hasTrakt) syncWithTrakt(),
        if (hasSimkl) syncWithSimkl(),
      ]);
    } finally {
      isSyncing.value = false;
    }
  }

  static Future<void> syncWithTrakt() async {
    try {
      if (!await TraktService.instance.isAuthenticated()) return;
      final movieItems = await TraktService.instance.fetchList(
        'watchlist',
        'movies',
      );
      final showItems = await TraktService.instance.fetchList(
        'watchlist',
        'shows',
      );

      final combined = [...movieItems, ...showItems];
      if (combined.isEmpty) return;

      final current = List<MyListItem>.from(items.value);
      for (final raw in combined) {
        if (raw is! Map<String, dynamic>) continue;
        final item = MyListItem.fromTraktJson(raw);
        final idx = current.indexWhere(
          (i) => i.uniqueKey == item.uniqueKey || i.matches(item),
        );
        if (idx == -1) {
          current.insert(0, item);
        } else {
          current[idx] = current[idx].mergeWith(item);
        }
      }
      current.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      items.value = current.take(maxItems).toList();
      await _persist();
    } catch (e) {
      debugPrint('MyListService: Trakt sync error: $e');
    }
  }

  static Future<void> syncWithSimkl() async {
    try {
      if (!await SimklService.instance.isAuthenticated()) return;
      final lib = await SimklService.instance.fetchLibrarySnapshotOrNull();
      if (lib == null) return;

      final current = List<MyListItem>.from(items.value);
      for (final bucket in ['movies', 'shows', 'anime']) {
        final list = lib[bucket];
        if (list is! List) continue;
        for (final raw in list) {
          if (raw is! Map<String, dynamic>) continue;
          final status = raw['status'];
          if (status == 'plantowatch' || status == 'watching') {
            final item = MyListItem.fromSimklJson(raw);
            final idx = current.indexWhere(
              (i) => i.uniqueKey == item.uniqueKey || i.matches(item),
            );
            if (idx == -1) {
              current.insert(0, item);
            } else {
              current[idx] = current[idx].mergeWith(item);
            }
          }
        }
      }
      current.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      items.value = current.take(maxItems).toList();
      await _persist();
    } catch (e) {
      debugPrint('MyListService: Simkl sync error: $e');
    }
  }

  static Future<void> _persist() async {
    await _store.write(items.value);
  }

  static bool isInList(MyListItem item) {
    return items.value.any(
      (i) => i.uniqueKey == item.uniqueKey || i.matches(item),
    );
  }

  static void add(MyListItem item) {
    if (isInList(item)) return;

    final newList = <MyListItem>[...items.value, item];
    newList.sort((a, b) => b.addedAt.compareTo(a.addedAt));

    if (newList.length > maxItems) {
      newList.removeRange(maxItems, newList.length);
    }

    items.value = newList;
    _invalidateSectionCache();
    _persist();

    // Push to cloud services if logged in
    _syncCloudAdd(item);
  }

  static void _syncCloudAdd(MyListItem item) async {
    final imdb = item.imdbId;
    final tmdb = item.tmdbId;
    final trakt = item.traktId;
    final simkl = item.simklId;

    if (await TraktService.instance.isAuthenticated()) {
      TraktService.instance.addToWatchlist(
        imdb ?? '',
        item.type,
        tmdbId: tmdb,
        traktId: trakt,
      );
    }
    if (await SimklService.instance.isAuthenticated()) {
      SimklService.instance.addToList(
        imdb ?? '',
        item.type,
        'plantowatch',
        tmdbId: tmdb,
        simklId: simkl,
      );
    }
  }

  static void remove(MyListItem item) {
    items.value = items.value
        .where((i) => i.uniqueKey != item.uniqueKey && !i.matches(item))
        .toList();
    _invalidateSectionCache();
    _persist();

    _syncCloudRemove(item);
  }

  static void _syncCloudRemove(MyListItem item) async {
    final imdb = item.imdbId;
    final tmdb = item.tmdbId;
    final trakt = item.traktId;
    final simkl = item.simklId;

    if (await TraktService.instance.isAuthenticated()) {
      TraktService.instance.removeFromWatchlist(
        imdb ?? '',
        item.type,
        tmdbId: tmdb,
        traktId: trakt,
      );
    }
    if (await SimklService.instance.isAuthenticated()) {
      SimklService.instance.addToList(
        imdb ?? '',
        item.type,
        'dropped',
        tmdbId: tmdb,
        simklId: simkl,
      );
    }
  }

  static void toggle(MyListItem item) {
    if (isInList(item)) {
      remove(item);
    } else {
      add(item);
    }
  }
}
