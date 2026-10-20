import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/models/audiobook/audiobook_model.dart';
import 'package:zplay/services/audiobook/audiobook_progress_service.dart';
import 'package:zplay/services/storage/json_document_store.dart';

const String _storageKey = 'audiobook_continue_listening_v2';
const String _legacyStorageKey = 'audiobook_continue_listening_v1';

Audiobook _audiobook({String uuid = 'book-1', String title = 'Book'}) {
  return Audiobook(
    uuid: uuid,
    audioBookId: 'id-1',
    dynamicSlugId: 'slug-1',
    title: title,
    coverImage: '',
    source: 'source',
    pageUrl: 'https://example/audio',
  );
}

AudiobookProgress _progress({
  String uuid = 'book-1',
  String title = 'Book',
  int timestamp = 1000,
}) {
  return AudiobookProgress(
    audiobook: _audiobook(uuid: uuid, title: title),
    chapters: [AudiobookChapter(title: 'Chapter 1', url: 'https://example/1')],
    chapterIndex: 2,
    positionMs: 4200,
    durationMs: 60000,
    lastListenedTimestamp: timestamp,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('migrates the legacy StringList into a durable document', () async {
    SharedPreferences.setMockInitialValues({
      _legacyStorageKey: <String>[
        jsonEncode(_progress(timestamp: 500).toJson()),
        'not json at all',
        jsonEncode(_progress(uuid: 'book-2', title: 'Book 2', timestamp: 900).toJson()),
      ],
    });

    final all = await AudiobookProgressService.instance.getAllProgress();

    expect(
      all.map((p) => p.key),
      <String>['book-2', 'book-1'],
      reason: 'unreadable entries are dropped and the rest sort newest first',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_storageKey), contains(JsonDocumentStore.schemaField));
    expect(
      prefs.containsKey(_legacyStorageKey),
      isFalse,
      reason: 'a migrated legacy list is removed once it is in the store',
    );
  });

  test('saves progress as an envelope with the 20-entry cap and order', () async {
    final service = AudiobookProgressService.instance;

    for (var i = 0; i < 25; i++) {
      await service.saveProgress(
        audiobook: _audiobook(uuid: 'book-$i', title: 'Book $i'),
        chapters: [AudiobookChapter(title: 'Chapter', url: 'https://example/$i')],
        chapterIndex: 0,
        position: Duration(seconds: i),
        duration: const Duration(minutes: 10),
      );
    }

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_storageKey), contains(JsonDocumentStore.schemaField));
    expect(prefs.containsKey(_legacyStorageKey), isFalse);

    final all = await service.getAllProgress();
    expect(all, hasLength(20));
    final keys = all.map((p) => p.key).toList();
    expect(keys, contains('book-24'));
    expect(keys, isNot(contains('book-0')));
    for (var i = 1; i < all.length; i++) {
      expect(
        all[i - 1].lastListenedTimestamp,
        greaterThanOrEqualTo(all[i].lastListenedTimestamp),
        reason: 'entries stay sorted newest first',
      );
    }
    final newest = all.firstWhere((p) => p.key == 'book-24');
    expect(newest.chapterIndex, 0);
    expect(newest.positionMs, 24000);
  });
}
