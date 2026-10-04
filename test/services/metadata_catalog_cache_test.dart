/// Catalog cache freshness: a cached catalog/search response must expire, so a
/// Home reload actually refetches instead of replaying whatever the process
/// first fetched. The un-TTL'd cache held one snapshot for the whole life of
/// the process, which is how the hero kept replaying 2012-era titles.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/services/metadata/metadata_service.dart';

void main() {
  late int hits;
  final t0 = DateTime(2026, 10, 4, 9);

  setUp(() {
    hits = 0;
    MetadataService.clock = () => t0;
    MetadataService.client = MockClient((request) async {
      hits++;
      return http.Response(
        jsonEncode({
          'metas': [
            {'id': 'tt1', 'name': 'Fresh', 'type': 'movie'},
          ],
        }),
        200,
      );
    });
    MetadataService.clearCache();
  });

  tearDown(() {
    MetadataService.client = http.Client();
    MetadataService.clock = DateTime.now;
    MetadataService.clearCache();
  });

  Future<List<Movie>> fetch() => MetadataService.fetchCatalog(
        baseUrl: 'https://addon.example.com',
        type: 'movie',
        catalogId: 'top',
      );

  test('a cached catalog is served inside the TTL and refetched after it',
      () async {
    await fetch();

    MetadataService.clock =
        () => t0.add(MetadataService.catalogCacheTtl - const Duration(seconds: 1));
    await fetch();
    expect(hits, 1, reason: 'inside the TTL the response is served from cache');

    MetadataService.clock = () => t0.add(MetadataService.catalogCacheTtl);
    final third = await fetch();
    expect(hits, 2, reason: 'at the TTL the entry expires and is refetched');
    expect(third.single.name, 'Fresh');
  });

  test('searches expire on the same clock', () async {
    Future<List<Movie>> search() => MetadataService.search(
          baseUrl: 'https://addon.example.com',
          type: 'movie',
          catalogId: 'top',
          query: 'Dredd',
        );

    await search();
    MetadataService.clock = () => t0.add(MetadataService.catalogCacheTtl);
    await search();
    expect(hits, 2);
  });

  test('clearCatalogCache still drops entries before the TTL does', () async {
    await fetch();
    MetadataService.clearCatalogCache();
    await fetch();
    expect(hits, 2);

    MetadataService.clearCache();
    await fetch();
    expect(hits, 3);
  });
}
