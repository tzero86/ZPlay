import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/audiobook/audiobook_model.dart';
import '../storage/json_document_store.dart';

class AudiobookProgress {
  final Audiobook audiobook;
  final List<AudiobookChapter> chapters;
  final int chapterIndex;
  final int positionMs;
  final int durationMs;
  final int lastListenedTimestamp;

  AudiobookProgress({
    required this.audiobook,
    required this.chapters,
    required this.chapterIndex,
    required this.positionMs,
    required this.durationMs,
    required this.lastListenedTimestamp,
  });

  String get key =>
      audiobook.uuid.isNotEmpty ? audiobook.uuid : audiobook.title;

  Map<String, dynamic> toJson() => {
    'audiobook': audiobook.toJson(),
    'chapters': chapters.map((c) => c.toJson()).toList(),
    'chapterIndex': chapterIndex,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'lastListenedTimestamp': lastListenedTimestamp,
  };

  factory AudiobookProgress.fromJson(Map<String, dynamic> json) =>
      AudiobookProgress(
        audiobook: Audiobook.fromJson(json['audiobook']),
        chapters: (json['chapters'] as List)
            .map((c) => AudiobookChapter.fromJson(c))
            .toList(),
        chapterIndex: json['chapterIndex'] ?? 0,
        positionMs: json['positionMs'] ?? 0,
        durationMs: json['durationMs'] ?? 0,
        lastListenedTimestamp: json['lastListenedTimestamp'] ?? 0,
      );
}

class AudiobookProgressService {
  static final AudiobookProgressService instance =
      AudiobookProgressService._internal();
  AudiobookProgressService._internal();

  static const String _storageKey = 'audiobook_continue_listening_v2';
  static const String _legacyStorageKey = 'audiobook_continue_listening_v1';

  /// Keeps the old per-entry tolerance: a single undecodable entry is dropped
  /// rather than costing the whole continue-listening list.
  static List<AudiobookProgress> _decode(Object? value) {
    final result = <AudiobookProgress>[];
    if (value is! List) return result;
    for (final entry in value) {
      try {
        result.add(
          AudiobookProgress.fromJson(Map<String, dynamic>.from(entry as Map)),
        );
      } catch (_) {}
    }
    return result;
  }

  static final JsonDocumentStore<List<AudiobookProgress>> _store =
      JsonDocumentStore<List<AudiobookProgress>>(
        key: _storageKey,
        version: 1,
        decode: _decode,
        encode: (all) => all.map((p) => p.toJson()).toList(),
        migrations: <int, JsonMigration>{0: (value) => value},
      );

  Future<void> saveProgress({
    required Audiobook audiobook,
    required List<AudiobookChapter> chapters,
    required int chapterIndex,
    required Duration position,
    required Duration duration,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = await _readAll(prefs);

      final key = audiobook.uuid.isNotEmpty ? audiobook.uuid : audiobook.title;
      all.removeWhere((p) => p.key == key);

      final newEntry = AudiobookProgress(
        audiobook: audiobook,
        chapters: chapters,
        chapterIndex: chapterIndex,
        positionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
        lastListenedTimestamp: DateTime.now().millisecondsSinceEpoch,
      );

      all.insert(0, newEntry);

      if (all.length > 20) {
        all.removeRange(20, all.length);
      }

      await _store.write(all);
    } catch (e) {
      print('[AudiobookProgressService] Error saving progress: $e');
    }
  }

  Future<List<AudiobookProgress>> getAllProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await _readAll(prefs);
    } catch (e) {
      print('[AudiobookProgressService] Error loading progress: $e');
      return [];
    }
  }

  /// Reads the durable document, migrating the legacy `StringList` on first
  /// run: each entry is decoded on its own, the result is written to the new
  /// key, and the old key is removed.
  Future<List<AudiobookProgress>> _readAll(SharedPreferences prefs) async {
    final stored = await _store.read();
    final List<AudiobookProgress> result;
    if (stored != null) {
      result = List<AudiobookProgress>.of(stored);
    } else {
      final legacy = prefs.getStringList(_legacyStorageKey);
      result = <AudiobookProgress>[];
      if (legacy != null) {
        for (final raw in legacy) {
          try {
            result.add(
              AudiobookProgress.fromJson(
                jsonDecode(raw) as Map<String, dynamic>,
              ),
            );
          } catch (_) {}
        }
        await _store.write(result);
        await prefs.remove(_legacyStorageKey);
      }
    }

    result.sort(
      (a, b) => b.lastListenedTimestamp.compareTo(a.lastListenedTimestamp),
    );
    return result;
  }

  Future<void> removeProgress(String audiobookKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = await _readAll(prefs);
      all.removeWhere((p) => p.key == audiobookKey);
      await _store.write(all);
    } catch (e) {
      print('[AudiobookProgressService] Error removing progress: $e');
    }
  }
}
