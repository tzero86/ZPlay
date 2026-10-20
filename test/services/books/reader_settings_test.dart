import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/books/reader_settings.dart';
import 'package:zplay/services/storage/json_document_store.dart';

const String _key = 'zplay_reader_settings_v3';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReaderSettings.settingsNotifier.value = const ReaderSettingsData();
  });

  test(
    'loads legacy bare JSON settings and rewrites them as an envelope',
    () async {
      SharedPreferences.setMockInitialValues({
        _key: jsonEncode(<String, dynamic>{
          'fontSize': 22.0,
          'fontFamily': 'Merriweather',
          'theme': 'sepia',
          'mode': 'paginated',
          'textAlign': 'justify',
        }),
      });

      await ReaderSettings.init();

      expect(ReaderSettings.current.fontSize, 22.0);
      expect(ReaderSettings.current.fontFamily, 'Merriweather');
      expect(ReaderSettings.current.theme, ReaderTheme.sepia);
      expect(ReaderSettings.current.textAlign, TextAlign.justify);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_key), contains(JsonDocumentStore.schemaField));
    },
  );

  test('an update persists an envelope that init reads back', () async {
    await ReaderSettings.init();

    ReaderSettings.updateFontSize(30);
    await Future<void>.delayed(Duration.zero);

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    expect(stored, contains(JsonDocumentStore.schemaField));

    ReaderSettings.settingsNotifier.value = const ReaderSettingsData();
    await ReaderSettings.init();
    expect(ReaderSettings.current.fontSize, 30);
  });
}
