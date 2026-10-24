import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/utils/download/download_path_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('records prior custom download roots without duplicates', () async {
    final first = p.join(Directory.systemTemp.path, 'zplay-downloads-one');
    final second = p.join(Directory.systemTemp.path, 'zplay-downloads-two');

    await DownloadPathHelper.setCustomDownloadsDirectoryPath(first);
    await DownloadPathHelper.setCustomDownloadsDirectoryPath(second);
    await DownloadPathHelper.setCustomDownloadsDirectoryPath(first);

    final prefs = await SharedPreferences.getInstance();
    final history =
        prefs.getStringList('custom_downloads_directory_history') ?? const [];

    expect(history.first, p.normalize(p.absolute(first)));
    expect(history, contains(p.normalize(p.absolute(second))));
    expect(history.toSet().length, history.length);
    expect(history.length, lessThanOrEqualTo(10));
  });
}
