import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/storage/json_document_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  JsonDocumentStore<List<int>> intStore({
    int version = 1,
    Map<int, JsonMigration> migrations = const <int, JsonMigration>{
      0: _identity,
    },
  }) {
    return JsonDocumentStore<List<int>>(
      key: 'test_document',
      version: version,
      decode: (value) => (value as List).cast<int>(),
      encode: (value) => value,
      migrations: migrations,
    );
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('writes an envelope and reads it back', () async {
    final store = intStore();
    await store.write([1, 2, 3]);

    expect(await store.read(), [1, 2, 3]);

    final prefs = await SharedPreferences.getInstance();
    final envelope =
        jsonDecode(prefs.getString('test_document')!) as Map<String, dynamic>;
    expect(envelope[JsonDocumentStore.schemaField], 1);
    expect(envelope[JsonDocumentStore.dataField], [1, 2, 3]);
    expect(envelope[JsonDocumentStore.checksumField], isNotEmpty);
  });

  test('reads legacy bare JSON and rewrites it in the envelope format',
      () async {
    SharedPreferences.setMockInitialValues({
      'test_document': jsonEncode([4, 5, 6]),
    });

    expect(await intStore().read(), [4, 5, 6]);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('test_document')!;
    expect(raw, startsWith('{'));
    expect(raw, contains(JsonDocumentStore.schemaField));
  });

  test('recovers a corrupt live copy from the last known good backup',
      () async {
    final store = intStore();
    await store.write([1]);
    await store.write([2]);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('test_document', '{"broken":');

    expect(await store.read(), [1]);
    expect(prefs.getString('test_document'), isNot('{"broken":'));
    expect(prefs.getString(store.quarantineKey), '{"broken":');
  });

  test('migrates an older schema to the current version', () async {
    const envelope = <String, Object?>{
      JsonDocumentStore.schemaField: 1,
      JsonDocumentStore.checksumField: '',
      JsonDocumentStore.dataField: [1, 2],
    };
    // The checksum has to match the data at the version that wrote it.
    final stored = <String, Object?>{
      ...envelope,
      JsonDocumentStore.checksumField: _checksumFor([1, 2]),
    };
    SharedPreferences.setMockInitialValues({
      'test_document': jsonEncode(stored),
    });

    final store = intStore(
      version: 2,
      migrations: <int, JsonMigration>{
        0: _identity,
        1: (value) => (value as List).map((e) => (e as int) + 10).toList(),
      },
    );

    expect(await store.read(), [11, 12]);
    final prefs = await SharedPreferences.getInstance();
    final rewritten = jsonDecode(prefs.getString('test_document')!)
        as Map<String, dynamic>;
    expect(rewritten[JsonDocumentStore.schemaField], 2);
    expect(rewritten[JsonDocumentStore.dataField], [11, 12]);
  });

  test('quarantines an unreadable payload instead of silently dropping it',
      () async {
    SharedPreferences.setMockInitialValues({
      'test_document': 'not json',
      'test_document__backup': 'also not json',
    });

    expect(await intStore().read(), isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('test_document__corrupt'), isNotNull);
  });

  test('rejects a payload whose checksum does not match', () async {
    SharedPreferences.setMockInitialValues({
      'test_document': jsonEncode(<String, Object?>{
        JsonDocumentStore.schemaField: 1,
        JsonDocumentStore.checksumField: 'deadbeef',
        JsonDocumentStore.dataField: [1, 2],
      }),
    });

    expect(await intStore().read(), isNull);
  });

  test('a newer schema is left untouched instead of overwritten', () async {
    final newer = jsonEncode(<String, Object?>{
      JsonDocumentStore.schemaField: 2,
      JsonDocumentStore.checksumField: _checksumFor([9, 9]),
      JsonDocumentStore.dataField: [9, 9],
    });
    SharedPreferences.setMockInitialValues({
      'test_document': newer,
      'test_document__backup': jsonEncode([1]),
    });

    final store = intStore();
    expect(await store.read(), isNull);
    await store.write([7]);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('test_document'), newer);
  });
}

Object? _identity(Object? value) => value;

String _checksumFor(Object? data) =>
    sha256.convert(utf8.encode(jsonEncode(data))).toString();
