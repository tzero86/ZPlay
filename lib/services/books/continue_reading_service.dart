import 'package:flutter/material.dart';
import '../../models/book/reading_progress.dart';
import '../storage/json_document_store.dart';

class ContinueReadingService {
  static const _storageKey = 'continue_reading_sessions_v1';

  static final JsonDocumentStore<List<ReadingProgress>> _store =
      JsonDocumentStore<List<ReadingProgress>>(
        key: _storageKey,
        version: 1,
        decode: (value) => (value as List)
            .whereType<Map<String, dynamic>>()
            .map(ReadingProgress.fromJson)
            .toList(),
        encode: (items) => items.map((item) => item.toJson()).toList(),
        migrations: <int, JsonMigration>{0: (value) => value},
      );

  static final ValueNotifier<List<ReadingProgress>> activeItems =
      ValueNotifier<List<ReadingProgress>>([]);

  static Future<void> initialize() => reload();

  /// Re-reads the stored reading list into [activeItems], replacing the
  /// in-memory copy. Used after a profile import.
  static Future<void> reload() async {
    try {
      final stored = await _store.read();
      if (stored != null) {
        final rawItems = stored.where((item) => item.md5.isNotEmpty).toList();

        rawItems.sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));

        // Deduplicate by book md5
        final deduped = <String, ReadingProgress>{};
        for (final item in rawItems) {
          if (!deduped.containsKey(item.md5)) {
            deduped[item.md5] = item;
          }
        }

        final items = deduped.values.toList();
        items.sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
        activeItems.value = items;
      }
    } catch (e) {
      debugPrint('[ContinueReadingService] Init error: $e');
    }
  }

  static Future<void> saveProgress(ReadingProgress progress) async {
    try {
      final current = List<ReadingProgress>.from(activeItems.value);
      current.removeWhere((i) => i.md5 == progress.md5);
      current.insert(0, progress);

      // Keep top 50 recent books
      if (current.length > 50) {
        current.removeRange(50, current.length);
      }

      activeItems.value = current;

      await _store.write(current);
    } catch (e) {
      debugPrint('[ContinueReadingService] Save progress error: $e');
    }
  }

  static ReadingProgress? getProgress(String md5) {
    try {
      return activeItems.value.firstWhere((i) => i.md5 == md5);
    } catch (_) {
      return null;
    }
  }

  static Future<void> removeProgress(String md5) async {
    try {
      final current = List<ReadingProgress>.from(activeItems.value);
      current.removeWhere((i) => i.md5 == md5);
      activeItems.value = current;

      await _store.write(current);
    } catch (e) {
      debugPrint('[ContinueReadingService] Remove progress error: $e');
    }
  }
}
