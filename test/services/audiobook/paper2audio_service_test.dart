import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/audiobook/paper2audio_service.dart';
import 'package:zplay/services/storage/json_document_store.dart';

const String _key = 'p2a_jobs_v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads legacy bare JSON and persists an envelope', () async {
    SharedPreferences.setMockInitialValues({
      _key: jsonEncode([
        <String, dynamic>{
          'runId': 'legacy-run',
          'fileName': 'legacy.epub',
          'voiceId': 'af_heart',
          'createdAt': 1,
          'status': 'completed',
          'progress': 1.0,
        },
      ]),
    });

    final service = Paper2AudioService.instance;
    final jobs = await service.getJobs();

    expect(jobs.single.runId, 'legacy-run');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_key), contains(JsonDocumentStore.schemaField));

    await service.removeJob('legacy-run');

    final stored = prefs.getString(_key);
    expect(stored, contains(JsonDocumentStore.schemaField));
    expect(stored, contains('"data":[]'));
  });
}
