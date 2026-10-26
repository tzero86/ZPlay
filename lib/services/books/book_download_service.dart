import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/book/book_result.dart';

import '../../utils/security/safe_paths.dart';
import '../../utils/network/bounded_response.dart';

class BookDownloadService {
  static final BookDownloadService instance = BookDownloadService._();
  BookDownloadService._();

  final Map<String, double> _progressMap = {};
  final ValueNotifier<Map<String, double>> progressNotifier =
      ValueNotifier<Map<String, double>>({});

  static final RegExp _md5Pattern = RegExp(r'^[0-9a-fA-F]{32}$');

  Directory? _booksDirectory;

  Future<Directory> getBooksDirectory() async {
    if (_booksDirectory != null && await _booksDirectory!.exists()) {
      return _booksDirectory!;
    }
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(appDocDir.path, 'ZPlay', 'Books'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _booksDirectory = dir;
      return dir;
    } catch (_) {
      final temp = Directory(
        p.join(Directory.systemTemp.path, 'ZPlay', 'Books'),
      );
      if (!await temp.exists()) {
        await temp.create(recursive: true);
      }
      _booksDirectory = temp;
      return temp;
    }
  }

  /// Returns the expected local file path for a book by its md5 and filetype.
  Future<File> getBookFile(String md5, String filetype) async {
    final normalizedMd5 = md5.trim();
    if (!_md5Pattern.hasMatch(normalizedMd5)) {
      throw ArgumentError.value(md5, 'md5', 'Expected a 32-character hex id');
    }
    final dir = await getBooksDirectory();
    final ext = sanitizeFileComponent(
      filetype.replaceAll('.', '').toLowerCase(),
      fallback: 'bin',
    );
    return File(p.join(dir.path, '$normalizedMd5.$ext'));
  }

  /// Checks if the book is already downloaded and exists on disk.
  Future<bool> isBookDownloaded(String md5, String filetype) async {
    if (!_md5Pattern.hasMatch(md5.trim())) return false;
    final file = await getBookFile(md5, filetype);
    if (await file.exists()) {
      final len = await file.length();
      return len > 100;
    }
    return false;
  }

  /// Gets the local file if downloaded, or null if not yet downloaded.
  Future<File?> getDownloadedBook(String md5, String filetype) async {
    if (!_md5Pattern.hasMatch(md5.trim())) return null;
    final file = await getBookFile(md5, filetype);
    if (await file.exists() && await file.length() > 100) {
      return file;
    }
    return null;
  }

  /// Downloads any book file (EPUB, PDF, MOBI, AZW3, FB2, TXT, CBZ, LIT, LRF).
  Future<File?> downloadBook(
    BookResult book, {
    void Function(double progress)? onProgress,
  }) async {
    final md5 = book.md5.trim();
    if (!_md5Pattern.hasMatch(md5)) {
      debugPrint('[BookDownloadService] Refusing book with invalid md5');
      return null;
    }

    final targetFile = await getBookFile(md5, book.bookFiletype);

    // If already downloaded and valid, return immediately
    if (await targetFile.exists() && await targetFile.length() > 100) {
      onProgress?.call(1.0);
      return targetFile;
    }

    _updateProgress(md5, 0.01);
    onProgress?.call(0.01);

    // Try primary URL, then fallback clean URL
    final candidateUrls = <String>[
      if (book.downloadUrl.isNotEmpty) book.downloadUrl,
      'https://api.bookracy.com/download/$md5/book.${book.bookFiletype}',
      if (book.link.isNotEmpty && book.link != book.downloadUrl) book.link,
    ];

    Exception? lastException;
    final client = HttpClient();

    for (final urlStr in candidateUrls) {
      try {
        final uri = Uri.parse(urlStr);
        final request = await client.getUrl(uri);
        request.headers.set(
          'User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
        );
        request.headers.set('Accept', '*/*');
        request.headers.set('Referer', 'https://bookracy.com/');
        request.headers.set('Origin', 'https://bookracy.com');
        request.headers.set(
          'sec-ch-ua',
          '"Not(A:Brand";v="99", "Google Chrome";v="133", "Chromium";v="133"',
        );

        final response = await request.close();

        if (response.statusCode != 200 && response.statusCode != 206) {
          lastException = Exception('HTTP ${response.statusCode} from $urlStr');
          continue;
        }

        final contentLength = response.contentLength;
        if (contentLength > BoundedResponse.bookMaxBytes) {
          await BoundedResponse.discard(response);
          lastException = Exception('Book is larger than the download limit');
          continue;
        }

        int receivedBytes = 0;

        final tempFile = File('${targetFile.path}.tmp');
        if (await tempFile.exists()) {
          await tempFile.delete();
        }

        final sink = tempFile.openWrite();
        try {
          await for (final chunk in response) {
            if (receivedBytes + chunk.length > BoundedResponse.bookMaxBytes) {
              throw const ResponseTooLargeException(
                BoundedResponse.bookMaxBytes,
              );
            }
            sink.add(chunk);
            receivedBytes += chunk.length;
            if (contentLength > 0) {
              final progress = (receivedBytes / contentLength).clamp(0.0, 1.0);
              _updateProgress(md5, progress);
              onProgress?.call(progress);
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }

        final tempLen = await tempFile.length();
        if (tempLen < 10) {
          await tempFile.delete();
          lastException = Exception('Downloaded file is empty');
          continue;
        }

        // Verify not an HTML error page
        final headerBytes = await tempFile.openRead(0, 120).first;
        final headerStr = String.fromCharCodes(headerBytes).toLowerCase();
        if (headerStr.contains('<!doctype html') ||
            headerStr.contains('<html') ||
            headerStr.contains('{"error":')) {
          await tempFile.delete();
          lastException = Exception('Downloaded file is an error page');
          continue;
        }

        // Rename temp to target
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await tempFile.rename(targetFile.path);

        _updateProgress(md5, 1.0);
        onProgress?.call(1.0);

        Future.delayed(const Duration(seconds: 2), () {
          _removeProgress(md5);
        });

        return targetFile;
      } catch (e) {
        try {
          final temp = File('${targetFile.path}.tmp');
          if (await temp.exists()) await temp.delete();
        } catch (_) {}
        lastException = Exception('Error downloading from $urlStr: $e');
      }
    }

    _removeProgress(md5);
    throw lastException ??
        Exception('Failed to download book after trying all sources');
  }

  /// Deletes a downloaded book from local storage.
  Future<bool> deleteBook(String md5, String filetype) async {
    try {
      final file = await getBookFile(md5, filetype);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BookDownloadService] Error deleting book ($md5): $e');
      }
    }
    return false;
  }

  void _updateProgress(String md5, double progress) {
    _progressMap[md5] = progress;
    progressNotifier.value = Map<String, double>.from(_progressMap);
  }

  void _removeProgress(String md5) {
    _progressMap.remove(md5);
    progressNotifier.value = Map<String, double>.from(_progressMap);
  }
}
