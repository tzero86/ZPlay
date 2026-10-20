import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/addon/addon_manager.dart';
import 'package:zplay/services/storage/json_document_store.dart';

const String _key = 'installed_addons_v5';

Map<String, dynamic> _entry(String baseUrl, String id) => <String, dynamic>{
  'baseUrl': baseUrl,
  'enabled': true,
  'enableCatalogs': true,
  'enableSearch': true,
  'enableStreams': false,
  'enableSubtitles': false,
  'manifest': <String, dynamic>{
    'id': id,
    'name': id,
    'version': '1.0.0',
    'resources': <String>['catalog'],
    'types': <String>['movie'],
    'idPrefixes': <String>['tt'],
    'catalogs': <Object>[],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(() => AddonManager.readStoredForTesting = null);

  test('loads legacy bare JSON and rewrites it as an envelope', () async {
    SharedPreferences.setMockInitialValues({
      _key: jsonEncode([
        // Built-ins are present so initialize does not try to seed them
        // over the network.
        _entry('builtin:zplay', 'builtin.zplay'),
        _entry('builtin:zplayhttp', 'builtin.zplayhttp'),
        _entry('https://legacy.example.test', 'com.example.legacy'),
      ]),
    });

    await AddonManager.instance.reload();

    expect(
      AddonManager.instance.addons.map((addon) => addon.baseUrl),
      contains('https://legacy.example.test'),
    );

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    expect(stored, contains(JsonDocumentStore.schemaField));
    expect(jsonDecode(stored!) as Map<String, dynamic>, contains('data'));
  });
}
