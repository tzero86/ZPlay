import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/audiobook/custom_audiobook_service.dart';
import 'package:zplay/services/storage/json_document_store.dart';

const String _key = 'custom_audiobooks_v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads legacy bare JSON and persists an envelope', () async {
    SharedPreferences.setMockInitialValues({
      _key: jsonEncode([
        <String, dynamic>{
          'id': 'legacy',
          'title': 'Legacy book',
          'author': 'Author',
          'coverPath': null,
          'audioFilePaths': <String>[],
          'createdAt': 1,
          'totalBytes': 0,
        },
      ]),
    });

    final service = CustomAudiobookService.instance;
    final books = await service.getAll();

    expect(books.single.id, 'legacy');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_key), contains(JsonDocumentStore.schemaField));

    await service.deleteAudiobook('legacy');

    final stored = prefs.getString(_key);
    expect(stored, contains(JsonDocumentStore.schemaField));
    expect(stored, contains('"data":[]'));
  });
}
