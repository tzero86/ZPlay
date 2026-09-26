import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/services/debrid/debrid_rejection_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DebridRejectionStore', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DebridRejectionStore.instance.initialize();
    });

    test('remembers a refusal for lowercase and uppercase hashes', () async {
      final store = DebridRejectionStore.instance;
      expect(store.isRejected('ABCDEF0123456789'), isFalse);

      await store.remember(
        infoHash: 'abcdef0123456789',
        service: 'Real-Debrid',
        reason: 'Blocked for copyright',
        permanent: true,
      );

      expect(store.isRejected('abcdef0123456789'), isTrue);
      expect(store.isRejected('ABCDEF0123456789'), isTrue);
      expect(store.isRejected('  AbCdEf0123456789 '), isTrue);
    });

    test('reason lookup returns what was stored', () async {
      final store = DebridRejectionStore.instance;
      await store.remember(
        infoHash: 'aaaabbbbccccdddd',
        service: 'TorBox',
        reason: 'Dead torrent',
        permanent: true,
      );

      expect(store.reasonFor('AAAABBBBCCCCDDDD'), 'Dead torrent');
      expect(store.reasonFor('0000000000000000'), isNull);
    });

    test('expires non permanent refusals after 14 days', () async {
      final old = DateTime.now().subtract(const Duration(days: 15));
      SharedPreferences.setMockInitialValues({
        'debrid_rejections': jsonEncode({
          'aaaaaaaaaaaaaaaa': {
            'service': 'Real-Debrid',
            'reason': 'Still converting',
            'at': old.toIso8601String(),
            'permanent': false,
          },
          'bbbbbbbbbbbbbbbb': {
            'service': 'Real-Debrid',
            'reason': 'Blocked for copyright',
            'at': old.toIso8601String(),
            'permanent': true,
          },
        }),
      });

      final store = DebridRejectionStore.instance;
      await store.initialize();

      expect(store.isRejected('aaaaaaaaaaaaaaaa'), isFalse);
      expect(store.reasonFor('aaaaaaaaaaaaaaaa'), isNull);
      expect(store.isRejected('bbbbbbbbbbbbbbbb'), isTrue);
      expect(store.reasonFor('bbbbbbbbbbbbbbbb'), 'Blocked for copyright');
    });

    test('a recent non permanent refusal is still rejected', () async {
      final store = DebridRejectionStore.instance;
      await store.remember(
        infoHash: 'cccccccccccccccc',
        service: 'Premiumize',
        reason: 'Still converting',
        permanent: false,
      );

      expect(store.isRejected('cccccccccccccccc'), isTrue);
    });

    test('null and empty hashes are never rejected', () async {
      final store = DebridRejectionStore.instance;
      await store.remember(
        infoHash: 'dddddddddddddddd',
        service: 'Real-Debrid',
        reason: 'Blocked for copyright',
        permanent: true,
      );

      expect(store.isRejected(null), isFalse);
      expect(store.isRejected(''), isFalse);
      expect(store.isRejected('   '), isFalse);
      expect(store.reasonFor(null), isNull);
      expect(store.reasonFor(''), isNull);
    });

    test('refusals survive a reload', () async {
      final store = DebridRejectionStore.instance;
      await store.remember(
        infoHash: 'eeeeeeeeeeeeeeee',
        service: 'AllDebrid',
        reason: 'Dead torrent',
        permanent: false,
      );

      await store.initialize();

      expect(store.isRejected('EEEEEEEEEEEEEEEE'), isTrue);
      expect(store.reasonFor('eeeeeeeeeeeeeeee'), 'Dead torrent');
    });

    test('forgetAll clears everything', () async {
      final store = DebridRejectionStore.instance;
      await store.remember(
        infoHash: 'ffffffffffffffff',
        service: 'Real-Debrid',
        reason: 'Blocked for copyright',
        permanent: true,
      );
      expect(store.isRejected('ffffffffffffffff'), isTrue);

      await store.forgetAll();

      expect(store.isRejected('ffffffffffffffff'), isFalse);
      expect(store.reasonFor('ffffffffffffffff'), isNull);
    });

    test('revision increments on every change', () async {
      final store = DebridRejectionStore.instance;
      final start = DebridRejectionStore.revision.value;

      await store.remember(
        infoHash: '1111111111111111',
        service: 'Real-Debrid',
        reason: 'Blocked for copyright',
        permanent: true,
      );
      expect(DebridRejectionStore.revision.value, start + 1);

      await store.remember(
        infoHash: '2222222222222222',
        service: 'TorBox',
        reason: 'Dead torrent',
        permanent: false,
      );
      expect(DebridRejectionStore.revision.value, start + 2);

      await store.forgetAll();
      expect(DebridRejectionStore.revision.value, start + 3);

      await store.initialize();
      expect(DebridRejectionStore.revision.value, start + 4);
    });
  });
}
