import 'curated_collection.dart';

/// Decade lanes: one rail per decade, hand-picked the same way
/// `curated_eras.dart` is.
///
/// The 1990s rails are six GENRES inside one decade, not six decades, so the
/// year dimension was never actually offered. These lanes are that dimension.
///
/// Every id, title and year here was resolved through Cinemeta, the same source
/// the 1990s rails were authored against, and checked to fall inside its own
/// decade. Two earlier drafts of this file carried ids that resolved to a
/// different film than intended, and two picks came back with a year outside
/// their lane, so the lists below are verified rather than remembered.
///
/// Why bundled and not generated: TMDb discover can rank by decade, but it needs
/// a user-supplied key and returns nothing without one, so a network-built lane
/// would be invisible to most of the audience. A curated lane is the only version
/// that works for everyone, and it is what the existing rails already are.
///
/// Movies only. The whole collections surface is built on `contentType:
/// 'movie'`, so a series lane is a separate data problem rather than another
/// list to add here.
const List<CuratedCollection> curatedDecades = [
  CuratedCollection(
    id: 'era_70s',
    title: 'The 1970s',
    subtitle: '10 picks from 1970 to 1979',
    kind: CuratedKind.era,
    items: [
      CuratedItem(imdbId: 'tt0068646', title: 'The Godfather', year: 1972),
      CuratedItem(imdbId: 'tt0073486', title: 'One Flew Over the Cuckoo\'s Nest', year: 1975),
      CuratedItem(imdbId: 'tt0076759', title: 'Star Wars: Episode IV - A New Hope', year: 1977),
      CuratedItem(imdbId: 'tt0073195', title: 'Jaws', year: 1975),
      CuratedItem(imdbId: 'tt0078748', title: 'Alien', year: 1979),
      CuratedItem(imdbId: 'tt0071562', title: 'The Godfather Part II', year: 1974),
      CuratedItem(imdbId: 'tt0075148', title: 'Rocky', year: 1976),
      CuratedItem(imdbId: 'tt0075686', title: 'Annie Hall', year: 1977),
      CuratedItem(imdbId: 'tt0078788', title: 'Apocalypse Now', year: 1979),
      CuratedItem(imdbId: 'tt0075314', title: 'Taxi Driver', year: 1976),
    ],
  ),
  CuratedCollection(
    id: 'era_80s',
    title: 'The 1980s',
    subtitle: '10 picks from 1980 to 1989',
    kind: CuratedKind.era,
    items: [
      CuratedItem(imdbId: 'tt0080684', title: 'Star Wars: Episode V - The Empire Strikes Back', year: 1980),
      CuratedItem(imdbId: 'tt0088763', title: 'Back to the Future', year: 1985),
      CuratedItem(imdbId: 'tt0081505', title: 'The Shining', year: 1980),
      CuratedItem(imdbId: 'tt0083658', title: 'Blade Runner', year: 1982),
      CuratedItem(imdbId: 'tt0082971', title: 'Raiders of the Lost Ark', year: 1981),
      CuratedItem(imdbId: 'tt0093779', title: 'The Princess Bride', year: 1987),
      CuratedItem(imdbId: 'tt0087332', title: 'Ghostbusters', year: 1984),
      CuratedItem(imdbId: 'tt0084787', title: 'The Thing', year: 1982),
      CuratedItem(imdbId: 'tt0095016', title: 'Die Hard', year: 1988),
      CuratedItem(imdbId: 'tt0094226', title: 'The Untouchables', year: 1987),
    ],
  ),
  CuratedCollection(
    id: 'era_00s',
    title: 'The 2000s',
    subtitle: '10 picks from 2000 to 2009',
    kind: CuratedKind.era,
    items: [
      CuratedItem(imdbId: 'tt0120737', title: 'The Lord of the Rings: The Fellowship of the Ring', year: 2001),
      CuratedItem(imdbId: 'tt0245429', title: 'Spirited Away', year: 2003),
      CuratedItem(imdbId: 'tt0209144', title: 'Memento', year: 2001),
      CuratedItem(imdbId: 'tt0482571', title: 'The Prestige', year: 2006),
      CuratedItem(imdbId: 'tt0477348', title: 'No Country for Old Men', year: 2007),
      CuratedItem(imdbId: 'tt0317248', title: 'City of God', year: 2004),
      CuratedItem(imdbId: 'tt0469494', title: 'There Will Be Blood', year: 2007),
      CuratedItem(imdbId: 'tt0407887', title: 'The Departed', year: 2006),
      CuratedItem(imdbId: 'tt0457430', title: 'Pan\'s Labyrinth', year: 2007),
      CuratedItem(imdbId: 'tt0382932', title: 'Ratatouille', year: 2007),
    ],
  ),
  CuratedCollection(
    id: 'era_10s',
    title: 'The 2010s',
    subtitle: '10 picks from 2010 to 2019',
    kind: CuratedKind.era,
    items: [
      CuratedItem(imdbId: 'tt1375666', title: 'Inception', year: 2010),
      CuratedItem(imdbId: 'tt1853728', title: 'Django Unchained', year: 2012),
      CuratedItem(imdbId: 'tt2582802', title: 'Whiplash', year: 2014),
      CuratedItem(imdbId: 'tt1392190', title: 'Mad Max: Fury Road', year: 2015),
      CuratedItem(imdbId: 'tt6751668', title: 'Parasite', year: 2019),
      CuratedItem(imdbId: 'tt5052448', title: 'Get Out', year: 2017),
      CuratedItem(imdbId: 'tt2543164', title: 'Arrival', year: 2016),
      CuratedItem(imdbId: 'tt1392214', title: 'Prisoners', year: 2013),
      CuratedItem(imdbId: 'tt1856101', title: 'Blade Runner 2049', year: 2017),
      CuratedItem(imdbId: 'tt3783958', title: 'La La Land', year: 2016),
    ],
  ),
];
