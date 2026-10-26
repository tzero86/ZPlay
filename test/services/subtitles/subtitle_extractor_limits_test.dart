import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/subtitles/subtitle_extractor.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('accepts a small subtitle and rejects archive bombs', () async {
    final validSrt = utf8.encode('1\n00:00:01,000 --> 00:00:02,000\nHello\n');

    final bombArchive = Archive()
      ..addFile(
        ArchiveFile(
          'movie.srt',
          10 * 1024 * 1024,
          List<int>.filled(10 * 1024 * 1024, 0x41),
        ),
      );
    final zipBomb = ZipEncoder().encode(bombArchive);
    final gzipBomb = gzip.encode(List<int>.filled(10 * 1024 * 1024, 0x41));

    final routes = <String, List<int>>{
      '/ok.srt': validSrt,
      '/bomb.zip': zipBomb,
      '/bomb.gz': gzipBomb,
    };

    server.listen((request) async {
      final body = routes[request.uri.path];
      if (body == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.statusCode = HttpStatus.ok;
        request.response.add(body);
      }
      await request.response.close();
    });

    final origin = 'http://127.0.0.1:${server.port}';

    final okPath = await SubtitleExtractor.downloadAndExtract(
      '$origin/ok.srt',
      providerName: 'limit-test',
    );
    expect(okPath, isNotNull);
    final okFile = File(okPath!);
    expect(await okFile.exists(), isTrue);
    await okFile.parent.delete(recursive: true);

    expect(
      await SubtitleExtractor.downloadAndExtract(
        '$origin/bomb.zip',
        providerName: 'limit-test',
      ),
      isNull,
    );
    expect(
      await SubtitleExtractor.downloadAndExtract(
        '$origin/bomb.gz',
        providerName: 'limit-test',
      ),
      isNull,
    );
  });
}
