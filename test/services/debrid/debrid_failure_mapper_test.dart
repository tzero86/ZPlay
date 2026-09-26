import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/debrid/models/debrid_error.dart';
import 'package:zplay/services/debrid/utils/debrid_failure_mapper.dart';

/// Bodies captured verbatim from the live Real-Debrid API.
const String rdInfringing = '{"error": "infringing_file", "error_code": 35}';
const String rdInvalidTorrent =
    '{"error": "torrent_file_invalid", "error_code": 30}';
const String rdBadToken = '{"error": "bad_token", "error_code": 8}';

/// Every message is shown to the user, so it has to stay a single line of
/// prose with no JSON, no braces and no status codes in it.
void expectShowable(DebridResolutionException e) {
  expect(e.message, isNotEmpty);
  expect(e.message.trim(), e.message);
  expect(e.message.contains('\n'), isFalse);
  expect(e.message.contains('{'), isFalse);
  expect(e.message.contains('}'), isFalse);
  expect(e.message.contains('error_code'), isFalse);
  expect(RegExp(r'\b\d{3}\b').hasMatch(e.message), isFalse);
}

void main() {
  group('classifyHttpFailure', () {
    test('Live Real-Debrid 451 copyright refusal', () {
      final e = classifyHttpFailure(
        service: 'Real-Debrid',
        statusCode: 451,
        body: rdInfringing,
      );

      expect(e.kind, DebridFailureKind.sourceRejected);
      expect(e.rememberUnusable, isTrue);
      expect(e.canTryAnotherSource, isTrue);
      expect(e.service, 'Real-Debrid');
      expect(
        e.message,
        'Real-Debrid blocked this torrent over a copyright claim.',
      );
      expectShowable(e);
    });

    test('Live Real-Debrid 451 refusal keeps the raw body in detail', () {
      final e = classifyHttpFailure(
        service: 'Real-Debrid',
        statusCode: 451,
        body: rdInfringing,
      );

      expect(e.detail, contains('451'));
      expect(e.detail, contains('infringing_file'));
      expect(e.toString(), e.message);
    });

    test('Live Real-Debrid 400 unreadable torrent refusal', () {
      final e = classifyHttpFailure(
        service: 'Real-Debrid',
        statusCode: 400,
        body: rdInvalidTorrent,
      );

      expect(e.kind, DebridFailureKind.sourceRejected);
      expect(e.rememberUnusable, isTrue);
      expect(e.message, 'Real-Debrid could not read that torrent file.');
      expectShowable(e);
    });

    test('Live Real-Debrid 401 bad token is an account problem', () {
      final e = classifyHttpFailure(
        service: 'Real-Debrid',
        statusCode: 401,
        body: rdBadToken,
      );

      expect(e.kind, DebridFailureKind.account);
      expect(e.rememberUnusable, isFalse);
      expect(e.canTryAnotherSource, isFalse);
      expect(e.message.toLowerCase(), contains('api key'));
      expect(e.message.toLowerCase(), contains('settings'));
      expectShowable(e);
    });

    test('Known numeric codes classify when the body has no error string', () {
      final refused = classifyHttpFailure(
        service: 'Real-Debrid',
        statusCode: 451,
        body: '{"error_code": 35}',
      );
      expect(refused.kind, DebridFailureKind.sourceRejected);
      expect(refused.rememberUnusable, isTrue);
      expectShowable(refused);

      final account = classifyHttpFailure(
        service: 'Real-Debrid',
        statusCode: 403,
        body: '{"error_code": 8}',
      );
      expect(account.kind, DebridFailureKind.account);
      expectShowable(account);
    });

    test('unavailable_file is a rejected source but not remembered', () {
      final e = classifyHttpFailure(
        service: 'Real-Debrid',
        statusCode: 404,
        body: '{"error": "unavailable_file", "error_code": 29}',
      );

      expect(e.kind, DebridFailureKind.sourceRejected);
      expect(e.rememberUnusable, isFalse);
      expectShowable(e);
    });

    test('Unknown 4xx is a rejected source', () {
      final e = classifyHttpFailure(
        service: 'TorBox',
        statusCode: 418,
        body: '{"error": "some_new_thing"}',
      );

      expect(e.kind, DebridFailureKind.sourceRejected);
      expect(e.rememberUnusable, isFalse);
      expectShowable(e);
    });

    test('401 and 403 are account problems', () {
      for (final status in <int>[401, 403]) {
        final e = classifyHttpFailure(
          service: 'Premiumize',
          statusCode: status,
          body: '{"error": "nope"}',
        );
        expect(e.kind, DebridFailureKind.account, reason: 'status $status');
        expect(e.canTryAnotherSource, isFalse);
        expectShowable(e);
      }
    });

    test('429 is transient', () {
      final e = classifyHttpFailure(
        service: 'AllDebrid',
        statusCode: 429,
        body: '{"error": "too_many_requests"}',
      );

      expect(e.kind, DebridFailureKind.transient);
      expect(e.rememberUnusable, isFalse);
      expect(e.canTryAnotherSource, isTrue);
      expectShowable(e);
    });

    test('5xx is transient', () {
      for (final status in <int>[500, 502, 503]) {
        final e = classifyHttpFailure(
          service: 'Debrid-Link',
          statusCode: status,
          body: 'gateway is down',
        );
        expect(e.kind, DebridFailureKind.transient, reason: 'status $status');
        expectShowable(e);
      }
    });

    test('A 451 with an unparseable body is still a legal block', () {
      final e = classifyHttpFailure(
        service: 'Real-Debrid',
        statusCode: 451,
        body: '<html>unavailable for legal reasons</html>',
      );

      expect(e.kind, DebridFailureKind.sourceRejected);
      expect(e.rememberUnusable, isTrue);
      expectShowable(e);
    });

    test('A 200 body that reports failure is a rejected source', () {
      final e = classifyHttpFailure(
        service: 'TorBox',
        statusCode: 200,
        body: '{"success": false, "detail": "download not available"}',
      );

      expect(e.kind, DebridFailureKind.sourceRejected);
      expect(e.rememberUnusable, isFalse);
      expectShowable(e);
    });

    test('A non JSON body falls back to the status rule', () {
      final transient = classifyHttpFailure(
        service: 'TorBox',
        statusCode: 504,
        body: '',
      );
      expect(transient.kind, DebridFailureKind.transient);

      final refused = classifyHttpFailure(
        service: 'TorBox',
        statusCode: 404,
        body: '',
      );
      expect(refused.kind, DebridFailureKind.sourceRejected);
      expect(refused.rememberUnusable, isFalse);
      expectShowable(refused);
    });

    test('detail always carries the raw status and body', () {
      final e = classifyHttpFailure(
        service: 'AllDebrid',
        statusCode: 404,
        body: '{"error": "unknown", "error_code": 3}',
      );

      expect(e.detail, contains('404'));
      expect(e.detail, contains('"error_code": 3'));
    });
  });

  group('classifyTorrentStatus', () {
    test('Unservable torrent words are rejected and remembered', () {
      for (final word in <String>['magnet_error', 'virus', 'dead']) {
        final e = classifyTorrentStatus(service: 'Real-Debrid', status: word);
        expect(e.kind, DebridFailureKind.sourceRejected, reason: word);
        expect(e.rememberUnusable, isTrue, reason: word);
        expect(e.detail, contains(word));
        expectShowable(e);
      }
    });

    test('error is transient', () {
      final e = classifyTorrentStatus(service: 'TorBox', status: 'error');

      expect(e.kind, DebridFailureKind.transient);
      expect(e.rememberUnusable, isFalse);
      expect(e.canTryAnotherSource, isTrue);
      expectShowable(e);
    });

    test('Unknown status words are transient', () {
      final e = classifyTorrentStatus(
        service: 'Debrid-Link',
        status: 'some_future_state',
      );

      expect(e.kind, DebridFailureKind.transient);
      expect(e.rememberUnusable, isFalse);
      expect(e.detail, contains('some_future_state'));
      expectShowable(e);
    });
  });
}
