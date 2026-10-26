import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/utils/network/bounded_response.dart';

void main() {
  group('BoundedResponse.readBytes', () {
    test('reads a body below the limit', () async {
      final bytes = await BoundedResponse.readBytes(
        Stream.fromIterable([utf8.encode('abc'), utf8.encode('def')]),
        maxBytes: 16,
      );

      expect(utf8.decode(bytes), 'abcdef');
    });

    test('rejects an advertised body above the limit before reading', () async {
      expect(
        () => BoundedResponse.readBytes(
          Stream.fromIterable([utf8.encode('abc')]),
          maxBytes: 4,
          contentLength: 5,
        ),
        throwsA(isA<ResponseTooLargeException>()),
      );
    });

    test(
      'cancels an oversized advertised body instead of draining it',
      () async {
        var cancelled = false;
        final controller = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );

        await expectLater(
          BoundedResponse.readBytes(
            controller.stream,
            maxBytes: 4,
            contentLength: 5,
          ),
          throwsA(isA<ResponseTooLargeException>()),
        );

        expect(cancelled, isTrue);
        await controller.close();
      },
    );

    test('discard cancels the body without reading it', () async {
      var cancelled = false;
      final controller = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );

      await BoundedResponse.discard(controller.stream);

      expect(cancelled, isTrue);
      await controller.close();
    });

    test('stops a streamed body that crosses the limit', () async {
      expect(
        () => BoundedResponse.readBytes(
          Stream.fromIterable([List<int>.filled(4, 0), List<int>.filled(4, 0)]),
          maxBytes: 5,
        ),
        throwsA(isA<ResponseTooLargeException>()),
      );
    });

    test('reads text under the same limit', () async {
      final text = await BoundedResponse.readString(
        Stream.fromIterable([utf8.encode('hello')]),
        maxBytes: 16,
      );

      expect(text, 'hello');
    });
  });

  group('BoundedResponse decompression', () {
    test('decodes a gzip payload below the limit', () {
      final compressed = gzip.encode(utf8.encode('hello'));

      final bytes = BoundedResponse.decodeGzip(compressed, maxBytes: 64);

      expect(utf8.decode(bytes), 'hello');
    });

    test('rejects a gzip payload that expands past the limit', () {
      final compressed = gzip.encode(List<int>.filled(64 * 1024, 0x41));

      expect(
        () => BoundedResponse.decodeGzip(compressed, maxBytes: 1024),
        throwsA(isA<ResponseTooLargeException>()),
      );
    });

    test('decodes raw deflate below the limit', () {
      final compressed = ZLibEncoder(raw: true).convert(utf8.encode('hello'));

      final bytes = BoundedResponse.decodeDeflate(compressed, maxBytes: 64);

      expect(utf8.decode(bytes), 'hello');
    });

    test('rejects raw deflate that expands past the limit', () {
      final compressed = ZLibEncoder(
        raw: true,
      ).convert(List<int>.filled(64 * 1024, 0x41));

      expect(
        () => BoundedResponse.decodeDeflate(compressed, maxBytes: 1024),
        throwsA(isA<ResponseTooLargeException>()),
      );
    });
  });
}
