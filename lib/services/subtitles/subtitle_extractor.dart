import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../../utils/network/bounded_response.dart';
import '../../utils/security/log_redaction.dart';
import 'subtitle_parser.dart';

class SubtitleExtractor {
  /// Downloads a file (ZIP, GZ, SRT, VTT, ASS) and extracts/cleans the subtitle on the fly.
  /// Converts legacy encodings (Windows-1256, CP1252, Latin-1, UTF-16) to standard UTF-8.
  /// Returns the absolute path to the local .srt, .vtt, or .ass file.
  static Future<String?> downloadAndExtract(
    String url, {
    Map<String, String>? headers,
    required String providerName,
  }) async {
    final client = http.Client();
    try {
      final reqHeaders = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': '*/*',
      };
      if (headers != null) {
        reqHeaders.addAll(headers);
      }
      if (!reqHeaders.containsKey('Referer') && url.contains('subdl.com')) {
        reqHeaders['Referer'] = 'https://subdl.com/';
      }

      final request = http.Request('GET', Uri.parse(url))
        ..headers.addAll(reqHeaders);
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        print(
          '[SubtitleExtractor] Download failed for ${redactUrl(url)} (Status: ${response.statusCode})',
        );
        await BoundedResponse.discard(response.stream);
        return null;
      }

      final bytes = await BoundedResponse.readHttpBytes(
        response,
        maxBytes: BoundedResponse.subtitleMaxBytes,
      ).timeout(const Duration(seconds: 15));
      if (bytes.isEmpty) return null;

      // Determine temp directory reliably
      String tempDirPath;
      try {
        final dir = await getTemporaryDirectory();
        tempDirPath = dir.path;
      } catch (_) {
        tempDirPath = Directory.systemTemp.path;
      }

      final targetDir = Directory('$tempDirPath/subtitles/$providerName');
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final fileName = '${DateTime.now().millisecondsSinceEpoch}';

      // 1. Check if response is a ZIP archive
      // Magic bytes: PK\x03\x04 (0x50 0x4B 0x03 0x04) or PK\x05\x06 or PK\x07\x08
      final isZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;

      // 2. Check if response is GZIP
      // Magic bytes: 0x1F 0x8B
      final isGzip = bytes.length > 2 && bytes[0] == 0x1F && bytes[1] == 0x8B;

      List<int>? extractedRawBytes;
      String targetExt = 'srt';

      if (isZip) {
        try {
          final archive = ZipDecoder().decodeBytes(bytes);
          ArchiveFile? bestFile;
          int bestSize = -1;

          for (final file in archive) {
            if (!file.isFile) continue;
            final lowerName = file.name.toLowerCase();

            // Skip macOS metadata & junk files
            if (lowerName.contains('__macosx') ||
                lowerName.split('/').last.startsWith('._') ||
                lowerName.endsWith('.ds_store')) {
              continue;
            }

            final isSub =
                lowerName.endsWith('.srt') ||
                lowerName.endsWith('.vtt') ||
                lowerName.endsWith('.ass') ||
                lowerName.endsWith('.sub');

            if (isSub && file.size > bestSize) {
              bestSize = file.size;
              bestFile = file;
            }
          }

          if (bestFile == null) return null;

          final lowerName = bestFile.name.toLowerCase();
          if (lowerName.endsWith('.vtt')) {
            targetExt = 'vtt';
          } else if (lowerName.endsWith('.ass')) {
            targetExt = 'ass';
          } else {
            targetExt = 'srt';
          }
          extractedRawBytes = _decodeZipSubtitle(bestFile);
          if (extractedRawBytes == null) return null;
        } catch (e) {
          print('[SubtitleExtractor] Zip decoding error: $e');
          return null;
        }
      } else if (isGzip) {
        try {
          extractedRawBytes = BoundedResponse.decodeGzip(
            bytes,
            maxBytes: BoundedResponse.subtitleDecompressedMaxBytes,
          );
          targetExt = url.toLowerCase().contains('.vtt') ? 'vtt' : 'srt';
        } catch (e) {
          print('[SubtitleExtractor] GZip decoding error: $e');
          return null;
        }
      } else {
        extractedRawBytes = bytes;
      }

      if (extractedRawBytes.length >
          BoundedResponse.subtitleDecompressedMaxBytes) {
        return null;
      }

      if (url.toLowerCase().endsWith('.vtt')) {
        targetExt = 'vtt';
      } else if (url.toLowerCase().endsWith('.ass')) {
        targetExt = 'ass';
      }

      // 3. Convert character encoding to clean UTF-8
      final decodedString = SubtitleParser.decodeBytesWithFallback(
        extractedRawBytes,
      );
      final utf8Bytes = utf8.encode(decodedString);
      if (utf8Bytes.length > BoundedResponse.subtitleOutputMaxBytes) {
        return null;
      }

      final savePath = '${targetDir.path}/$fileName.$targetExt';
      final localFile = File(savePath);
      await localFile.writeAsBytes(utf8Bytes, flush: true);

      print(
        '[SubtitleExtractor SUCCESS] Extracted subtitle to $savePath (${utf8Bytes.length} bytes)',
      );
      return savePath;
    } catch (e, st) {
      print(
        '[SubtitleExtractor ERROR] Subtitle extraction error ($providerName): ${redactTextUrls('$e')}\n${redactTextUrls('$st')}',
      );
    } finally {
      client.close();
    }
    return null;
  }

  /// Extracts one ZIP entry with a hard output limit.
  ///
  /// `ArchiveFile.content` decompresses without a budget, which is exactly the
  /// compression-bomb path this guards. Read the raw entry and inflate it
  /// through the bounded decoder instead.
  static List<int>? _decodeZipSubtitle(ArchiveFile file) {
    if (file.size > BoundedResponse.subtitleDecompressedMaxBytes) return null;

    final raw = file.rawContent?.getStream(decompress: false).toUint8List();
    if (raw == null) return null;

    final compression = file.compression;
    if (compression == null || compression == CompressionType.none) {
      return raw.length <= BoundedResponse.subtitleDecompressedMaxBytes
          ? raw
          : null;
    }
    if (compression == CompressionType.deflate) {
      try {
        return BoundedResponse.decodeDeflate(
          raw,
          maxBytes: BoundedResponse.subtitleDecompressedMaxBytes,
        );
      } catch (_) {
        return null;
      }
    }
    // bzip2 and unknown methods are not used by subtitle providers. Refuse
    // them rather than falling back to an unbounded decoder.
    return null;
  }
}
