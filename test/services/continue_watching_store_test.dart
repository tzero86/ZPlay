import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/continue_watching/continue_watching_service.dart';
import 'package:zplay/services/storage/json_document_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ContinueWatchingService.activeItems.value = [];
  });

  test(
    'loads a legacy bare-JSON session list and upgrades it in place',
    () async {
      final legacy = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'tt1234567',
          'title': 'Legacy Movie',
          'type': 'movie',
          'positionSeconds': 120,
          'totalDurationSeconds': 1000,
          'lastWatchedAt': DateTime(2026, 1, 1).toIso8601String(),
          'isTorrent': false,
        },
      ];
      SharedPreferences.setMockInitialValues({
        'continue_watching_sessions_v1': jsonEncode(legacy),
      });

      await ContinueWatchingService.initialize();

      expect(ContinueWatchingService.activeItems.value, hasLength(1));
      expect(
        ContinueWatchingService.activeItems.value.single.title,
        'Legacy Movie',
      );

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('continue_watching_sessions_v1')!;
      expect(raw, contains(JsonDocumentStore.schemaField));
      expect(raw, contains('Legacy Movie'));
    },
  );

  test('recovers a valid backup when the live document is corrupt', () async {
    final entry = <String, dynamic>{
      'id': 'tt7654321',
      'title': 'Recovered Show',
      'type': 'series',
      'season': 1,
      'episode': 2,
      'positionSeconds': 200,
      'totalDurationSeconds': 2000,
      'lastWatchedAt': DateTime(2026, 2, 1).toIso8601String(),
      'isTorrent': false,
    };
    final backup = jsonEncode(<String, dynamic>{
      JsonDocumentStore.schemaField: 1,
      JsonDocumentStore.checksumField: sha256
          .convert(utf8.encode(jsonEncode(<Map<String, dynamic>>[entry])))
          .toString(),
      JsonDocumentStore.dataField: <Map<String, dynamic>>[entry],
    });
    SharedPreferences.setMockInitialValues({
      'continue_watching_sessions_v1': '{"broken":',
      'continue_watching_sessions_v1__backup': backup,
    });

    await ContinueWatchingService.initialize();

    expect(ContinueWatchingService.activeItems.value, hasLength(1));
    expect(
      ContinueWatchingService.activeItems.value.single.title,
      'Recovered Show',
    );
  });
}
