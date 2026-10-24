import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/book/book_result.dart';

class BookracyService {
  static const String _baseUrl = 'https://api.bookracy.com/api/books';
  static final BookracyService instance = BookracyService._();
  static final RegExp _md5Pattern = RegExp(r'^[0-9a-fA-F]{32}$');

  BookracyService._();

  final http.Client _client = http.Client();

  final Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
    'Accept': 'application/json',
    'Origin': 'https://bookracy.com',
    'Referer': 'https://bookracy.com/',
  };

  /// Searches books from Bookracy API.
  Future<List<BookResult>> searchBooks({
    required String query,
    String? lang = 'en',
    int page = 1,
    int limit = 100,
    String? formatFilter,
  }) async {
    final cleanQuery = query.trim();
    final effectiveQuery = cleanQuery.isNotEmpty ? cleanQuery : 'fantasy';

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'query': effectiveQuery,
        if (lang != null && lang.isNotEmpty && lang.toLowerCase() != 'all')
          'lang': lang.toLowerCase(),
        'limit': limit.toString(),
        'page': page.toString(),
      },
    );

    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[BookracyService] HTTP ${response.statusCode} for $uri');
        }
        return [];
      }

      final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return [];
      }

      final resultsList = decoded['results'];
      if (resultsList is! List) {
        return [];
      }

      final books = <BookResult>[];
      final seenMd5 = <String>{};

      for (final item in resultsList) {
        if (item is Map<String, dynamic>) {
          final book = BookResult.fromJson(item);
          final ft = book.bookFiletype.toLowerCase();

          // Exclude lit, lrf, and legacy unsupported formats
          if (ft == 'lit' ||
              ft == 'lrf' ||
              ft == 'djvu' ||
              ft == 'rtf' ||
              ft == 'doc' ||
              ft == 'docx') {
            continue;
          }

          if (book.title.isNotEmpty &&
              _md5Pattern.hasMatch(book.md5.trim()) &&
              seenMd5.add(book.md5)) {
            // Apply format filter if specified (e.g. 'epub', 'pdf', 'mobi', 'azw3', 'fb2', 'txt', 'cbz')
            if (formatFilter != null &&
                formatFilter.isNotEmpty &&
                formatFilter.toLowerCase() != 'all') {
              if (book.bookFiletype != formatFilter.toLowerCase()) {
                continue;
              }
            }
            books.add(book);
          }
        }
      }

      return books;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[BookracyService] Error searching books ($effectiveQuery): $e',
        );
      }
      return [];
    }
  }

  /// Fetches popular / trending / curated categories for the Books Home Page.
  Future<Map<String, List<BookResult>>> fetchFeaturedCategories({
    String lang = 'en',
  }) async {
    final categories = <String, String>{
      'Popular Fiction': 'fiction',
      'Sci-Fi & Fantasy': 'fantasy',
      'Mystery & Thriller': 'thriller',
      'Science & History': 'history',
      'Bestsellers': 'novel',
    };

    final results = <String, List<BookResult>>{};

    await Future.wait(
      categories.entries.map((entry) async {
        try {
          final books = await searchBooks(
            query: entry.value,
            lang: lang,
            limit: 40,
            page: 1,
          );
          if (books.isNotEmpty) {
            results[entry.key] = books;
          }
        } catch (_) {}
      }),
    );

    return results;
  }
}
