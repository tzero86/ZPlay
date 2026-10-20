import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/models/book/reading_progress.dart';
import 'package:zplay/services/books/continue_reading_service.dart';
import 'package:zplay/services/storage/json_document_store.dart';

const String _key = 'continue_reading_sessions_v1';

ReadingProgress _progress(String md5, DateTime lastReadAt) => ReadingProgress(
  md5: md5,
  title: 'Title $md5',
  author: 'Author',
  coverUrl: '',
  filePath: '/books/$md5.epub',
  fileType: 'epub',
  lastReadAt: lastReadAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ContinueReadingService.activeItems.value = [];
  });

  test('loads legacy bare JSON and rewrites it as an envelope', () async {
    SharedPreferences.setMockInitialValues({
      _key: jsonEncode([_progress('b1', DateTime.utc(2026, 1, 1)).toJson()]),
    });

    await ContinueReadingService.initialize();

    expect(ContinueReadingService.activeItems.value.single.md5, 'b1');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_key), contains(JsonDocumentStore.schemaField));
  });

  test('saveProgress writes an envelope that initialize reads back', () async {
    await ContinueReadingService.initialize();

    await ContinueReadingService.saveProgress(
      _progress('b2', DateTime.utc(2026, 1, 2)),
    );

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    expect(stored, contains(JsonDocumentStore.schemaField));
    expect(jsonDecode(stored!) as Map<String, dynamic>, contains('data'));

    ContinueReadingService.activeItems.value = [];
    await ContinueReadingService.initialize();
    expect(ContinueReadingService.activeItems.value.single.md5, 'b2');
  });
}
