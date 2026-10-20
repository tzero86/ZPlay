/// Guards the resolver that finds a trailer for a title that arrives without
/// one.
///
/// The order matters and is the whole point: a title's own key wins, the
/// addon's info response is the credential-free source, TMDb is only
/// consulted when a credential is configured, and the title itself is the
/// last resort for a rail whose ids no addon can answer for.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/services/metadata/metadata_service.dart';
import 'package:zplay/services/metadata/trailer_resolver.dart';

/// A client that answers the two addon endpoints the resolver uses.
class _FakeClient extends http.BaseClient {
  _FakeClient(this.responses);

  final Map<String, String> responses;

  /// Every URL this client was asked for, in order.
  final List<String> requests = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();
    requests.add(url);
    for (final entry in responses.entries) {
      if (url.contains(entry.key)) {
        return http.StreamedResponse(
          Stream.value(utf8.encode(entry.value)),
          200,
        );
      }
    }
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 404);
  }
}

void main() {
  late http.Client original;

  setUp(() {
    original = MetadataService.client;
    TrailerResolver.clearCache();
    MetadataService.clearCache();
  });

  tearDown(() {
    MetadataService.client = original;
    TrailerResolver.clearCache();
    MetadataService.clearCache();
  });

  test('a title with its own key is not looked up at all', () async {
    final client = _FakeClient({'meta/': '{"meta": {"id": "tt1"}}'});
    MetadataService.client = client;

    final movie = Movie(
      id: 'tt1',
      name: 'Has A Trailer',
      type: 'movie',
      addonBaseUrl: 'https://example.test',
      trailerKey: 'HzGx48E64Xg',
    );

    expect(await TrailerResolver.resolve(movie), 'HzGx48E64Xg');
    expect(client.requests, isEmpty);
  });

  test(
    'the addon info response names the trailer, with no credential',
    () async {
      MetadataService.client = _FakeClient({
        'meta/movie/tt3458254.json': jsonEncode({
          'meta': {
            'id': 'tt3458254',
            'name': 'Patient Zero',
            'type': 'movie',
            'trailers': [
              {'source': 'W9uddyaqAPE', 'type': 'Trailer'},
            ],
          },
        }),
      });

      final movie = Movie(
        id: 'tt3458254',
        name: 'Patient Zero',
        type: 'movie',
        addonBaseUrl: 'https://example.test',
      );

      expect(await TrailerResolver.resolve(movie), 'W9uddyaqAPE');
    },
  );

  test('a title with no usable id is found by its name and year', () async {
    // The "because you watched" recommendations carry `bestsimilar_<n>`,
    // which no info resource can answer for. The search finds the title and
    // its IMDb id; the info response is where the trailer is named.
    MetadataService.client = _FakeClient({
      'search=Patient%20Zero.json': jsonEncode({
        'metas': [
          {
            'id': 'tt3458254',
            'name': 'Patient Zero',
            'type': 'movie',
            'releaseInfo': '2018',
          },
          {
            'id': 'tt2102496',
            'name': 'Cabin Fever 3: Patient Zero',
            'type': 'movie',
            'releaseInfo': '2014',
          },
        ],
      }),
      'meta/movie/tt3458254.json': jsonEncode({
        'meta': {
          'id': 'tt3458254',
          'name': 'Patient Zero',
          'type': 'movie',
          'trailers': [
            {'source': 'W9uddyaqAPE', 'type': 'Trailer'},
          ],
        },
      }),
    });

    final movie = Movie(
      id: 'bestsimilar_12345',
      name: 'Patient Zero',
      year: '2018',
      type: 'movie',
      addonBaseUrl: 'https://example.test',
    );

    expect(await TrailerResolver.resolve(movie), 'W9uddyaqAPE');
  });

  test('a title with no trailer anywhere resolves to null', () async {
    MetadataService.client = _FakeClient({
      'meta/': jsonEncode({
        'meta': {'id': 'tt1', 'name': 'Nothing'},
      }),
    });

    final movie = Movie(
      id: 'tt1',
      name: 'Nothing',
      type: 'movie',
      addonBaseUrl: 'https://example.test',
    );

    expect(await TrailerResolver.resolve(movie), isNull);
  });
}
