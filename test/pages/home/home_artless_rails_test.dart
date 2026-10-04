/// A Home rail that cannot draw is a row of blank rectangles, so it is dropped.
///
/// The rule is a fact about the layout rather than a taste about content. Home's
/// rails are [CardArtwork.landscape] tiles, and a landscape tile carries no name
/// text at all - the row's heading is the only label and the picture is the
/// identification. A tile that resolves no art is therefore not a card with an
/// empty placeholder in it; it is an empty rectangle. That is what a Debrid
/// addon's torrent catalogue looked like on the shelf: "lots of stuff without any
/// images, no idea what they are".
///
/// Both directions are asserted, because the guard is only correct if it is
/// *narrow*: one item that can draw has to keep the whole rail, and an item with
/// only an IMDb id has to count as drawable, since metahub is where most
/// catalogue art comes from. A guard that dropped either would delete real rows.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:zplay/models/addon/addon.dart';
import 'package:zplay/models/movie/movie.dart';
import 'package:zplay/models/movie/movie_section.dart';
import 'package:zplay/pages/home/home_page.dart';

Movie _movie(String id, {String? poster, String? backdrop}) => Movie(
  id: id,
  name: 'Title $id',
  poster: poster,
  backdrop: backdrop,
  year: '2024',
  type: 'movie',
  addonBaseUrl: 'test',
);

MovieSection _section(String title, List<Movie> movies) => MovieSection(
  title: title,
  subtitle: '',
  contentType: 'movie',
  addonBaseUrl: 'test',
  catalog: AddonCatalog(type: 'movie', id: title),
  movies: movies,
);

void main() {
  group('visibleHomeSections', () {
    test('drops a rail no item of which can draw', () {
      final sections = [
        _section('Torrents', [_movie('torrentio:abc'), _movie('bits:def')]),
      ];

      expect(
        visibleHomeSections(sections, hideArtless: true),
        isEmpty,
        reason: 'the rail would render as blank tiles with nothing to read',
      );
    });

    test('keeps a rail when one item can draw and the rest cannot', () {
      final sections = [
        _section('Mixed', [
          _movie('torrentio:abc'),
          _movie('bits:def'),
          _movie('tt0468569', poster: 'https://cdn.example/p.jpg'),
        ]),
      ];

      expect(
        visibleHomeSections(sections, hideArtless: true),
        hasLength(1),
        reason: 'the rail is droppable only when *nothing* in it can draw',
      );
    });

    test('an IMDb id is enough on its own, because metahub is the art', () {
      final sections = [
        _section('Addon rail', [_movie('tt0468569')]),
      ];

      expect(
        visibleHomeSections(sections, hideArtless: true),
        hasLength(1),
        reason: 'most catalogue items carry no poster and rely on this fallback',
      );
    });

    test('a backdrop is art too', () {
      final sections = [
        _section('Wide rail', [
          _movie('addon:1', backdrop: 'https://cdn.example/wide.jpg'),
        ]),
      ];

      expect(visibleHomeSections(sections, hideArtless: true), hasLength(1));
    });

    test('a blank or whitespace URL is not art', () {
      final sections = [
        _section('Blank', [_movie('addon:1', poster: '   ', backdrop: '')]),
      ];

      expect(
        visibleHomeSections(sections, hideArtless: true),
        isEmpty,
        reason: 'a blank URL is what an addon sends when it has no picture',
      );
    });

    test('turning the setting off keeps every rail that has any item', () {
      final sections = [
        _section('Torrents', [_movie('torrentio:abc')]),
        _section('Real', [_movie('tt0468569')]),
      ];

      expect(
        visibleHomeSections(sections, hideArtless: false),
        hasLength(2),
        reason: 'the setting is the escape hatch, so it must actually disable '
            'the rule',
      );
    });

    test('an empty rail is dropped whichever way the setting is set', () {
      final sections = [_section('Empty', const [])];

      expect(visibleHomeSections(sections, hideArtless: true), isEmpty);
      expect(visibleHomeSections(sections, hideArtless: false), isEmpty);
    });
  });
}
