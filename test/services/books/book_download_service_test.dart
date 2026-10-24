import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/books/book_download_service.dart';

void main() {
  group('BookDownloadService.getBookFile', () {
    test('rejects a traversal-shaped id before touching storage', () async {
      await expectLater(
        BookDownloadService.instance.getBookFile('../../evil', 'epub'),
        throwsArgumentError,
      );
    });

    test('rejects short ids', () async {
      await expectLater(
        BookDownloadService.instance.getBookFile('abc123', 'epub'),
        throwsArgumentError,
      );
    });
  });

  group('BookDownloadService download queries', () {
    test('treat a malformed id as not downloaded', () async {
      expect(
        await BookDownloadService.instance.getDownloadedBook(
          '../../evil',
          'epub',
        ),
        isNull,
      );
      expect(
        await BookDownloadService.instance.isBookDownloaded('abc123', 'epub'),
        isFalse,
      );
    });
  });
}
