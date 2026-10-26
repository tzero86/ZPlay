import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Thrown when a response or decompressed payload exceeds its budget.
class ResponseTooLargeException implements Exception {
  final int maxBytes;

  const ResponseTooLargeException(this.maxBytes);

  @override
  String toString() => 'Response exceeded the $maxBytes byte limit';
}

/// Size-bounded response and decompression helpers.
///
/// Timeouts stop a stalled peer, but they do not stop a peer that keeps
/// sending. These limits make the read fail closed before a hostile body can
/// exhaust memory.
class BoundedResponse {
  BoundedResponse._();

  static const int addonJsonMaxBytes = 8 * 1024 * 1024;
  static const int iptvJsonMaxBytes = 16 * 1024 * 1024;
  static const int subtitleMaxBytes = 16 * 1024 * 1024;
  static const int subtitleDecompressedMaxBytes = 8 * 1024 * 1024;
  static const int subtitleOutputMaxBytes = 16 * 1024 * 1024;
  static const int bookMaxBytes = 256 * 1024 * 1024;
  static const int hlsManifestMaxBytes = 4 * 1024 * 1024;
  static const int hlsSegmentMaxBytes = 64 * 1024 * 1024;
  static const int hlsKeyMaxBytes = 4 * 1024;

  /// Reads a stream into memory, failing once [maxBytes] is exceeded.
  static Future<Uint8List> readBytes(
    Stream<List<int>> stream, {
    required int maxBytes,
    int? contentLength,
  }) async {
    if (contentLength != null && contentLength > maxBytes) {
      await discard(stream);
      throw ResponseTooLargeException(maxBytes);
    }

    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in stream) {
      total += chunk.length;
      if (total > maxBytes) {
        throw ResponseTooLargeException(maxBytes);
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// Releases a response body without reading it.
  ///
  /// Cancelling aborts the underlying connection instead of downloading a body
  /// the caller is going to ignore. Draining would let a hostile error response
  /// keep sending data.
  static Future<void> discard(Stream<List<int>> stream) async {
    final subscription = stream.listen((_) {}, onError: (_) {});
    await subscription.cancel();
  }

  /// Reads a stream as text under the same byte budget.
  static Future<String> readString(
    Stream<List<int>> stream, {
    required int maxBytes,
    int? contentLength,
    Encoding encoding = utf8,
  }) async {
    final bytes = await readBytes(
      stream,
      maxBytes: maxBytes,
      contentLength: contentLength,
    );
    return encoding.decode(bytes);
  }

  /// Reads an `http` streamed response under [maxBytes].
  static Future<Uint8List> readHttpBytes(
    http.StreamedResponse response, {
    required int maxBytes,
  }) {
    return readBytes(
      response.stream,
      maxBytes: maxBytes,
      contentLength: response.contentLength,
    );
  }

  /// Decodes a gzip payload while bounding the decompressed output.
  static Uint8List decodeGzip(List<int> bytes, {required int maxBytes}) {
    return _decodeZlib(bytes, maxBytes: maxBytes, gzip: true);
  }

  /// Decodes a raw deflate payload (the compression used inside ZIP entries).
  static Uint8List decodeDeflate(List<int> bytes, {required int maxBytes}) {
    return _decodeZlib(bytes, maxBytes: maxBytes, raw: true);
  }

  static Uint8List _decodeZlib(
    List<int> bytes, {
    required int maxBytes,
    bool gzip = false,
    bool raw = false,
  }) {
    final builder = BytesBuilder(copy: false);
    final sink = _BoundedSink(builder, maxBytes);
    final conversion = ZLibDecoder(
      gzip: gzip,
      raw: raw,
    ).startChunkedConversion(sink);
    conversion.add(bytes);
    conversion.close();
    return builder.takeBytes();
  }
}

class _BoundedSink implements Sink<List<int>> {
  final BytesBuilder _builder;
  final int _maxBytes;
  int _length = 0;

  _BoundedSink(this._builder, this._maxBytes);

  @override
  void add(List<int> data) {
    _length += data.length;
    if (_length > _maxBytes) {
      throw ResponseTooLargeException(_maxBytes);
    }
    _builder.add(data);
  }

  @override
  void close() {}
}
