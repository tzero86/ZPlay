/// A profile import replaces `installed_addons_v5` while the app is running,
/// and the startup read may still be in flight when it does: the import fires
/// from the shell's first frame, which the deferred service warm-up is still
/// painting behind.
///
/// Before the reload existed, an imported list never reached the running app.
/// Before it shared the in-flight read, the two could land in either order and
/// the older list could be the one left in memory. This pins the second half
/// down, and it fails on a timeout rather than hanging the suite if a future
/// reload ever waits on itself.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/addon/addon_manager.dart';

const String _beforeImport = 'https://before-import.example.test';
const String _afterImport = 'https://after-import.example.test';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AddonManager.readStoredForTesting = null);

  test('a reload concurrent with an in-flight read waits for it and re-reads',
      () async {
    SharedPreferences.setMockInitialValues({});

    var reads = 0;
    final startupRead = Completer<void>();
    AddonManager.readStoredForTesting = () async {
      reads++;
      if (reads == 1) {
        // The startup read. It is held open across the import, which is the
        // window the reload has to respect.
        await startupRead.future;
        return jsonEncode([_entry(_beforeImport)]);
      }
      return jsonEncode([_entry(_afterImport)]);
    };

    final startup = AddonManager.instance.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1, reason: 'the startup read is in flight');

    // The import has replaced the store by the time this is called. The
    // startup read applied the list from before it.
    final reload = AddonManager.instance.reload();
    await Future<void>.delayed(Duration.zero);
    expect(
      reads,
      1,
      reason: 'a reload must wait on the read already running, not start a '
          'second one alongside it: which list ends up in memory would then '
          'depend on which read finished last',
    );

    startupRead.complete();
    // A timeout, so a reload that waited on itself fails this test instead of
    // hanging the suite.
    await startup.timeout(const Duration(seconds: 5));
    await reload.timeout(const Duration(seconds: 5));

    expect(reads, 2, reason: 'the reload reads the store again once it is free');
    final urls = AddonManager.instance.addons.map((a) => a.baseUrl).toList();
    expect(urls, contains(_afterImport));
    expect(
      urls,
      isNot(contains(_beforeImport)),
      reason: 'the list the import wrote is the one left in memory',
    );
  });
}

Map<String, dynamic> _entry(String url) => {
      'baseUrl': url,
      'enabled': true,
      'enableCatalogs': true,
      'enableSearch': true,
      'enableStreams': true,
      'enableSubtitles': false,
      'manifest': {
        'id': 'com.example.${Uri.parse(url).host.replaceAll('.', '-')}',
        'name': 'Test addon',
        'version': '1.0.0',
        'resources': ['stream'],
        'types': ['movie'],
        'idPrefixes': ['tt'],
        'catalogs': <Object>[],
      },
    };