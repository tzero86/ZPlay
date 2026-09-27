import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/models/iptv/m3u_models.dart';
import 'package:zplay/services/iptv/m3u_parser.dart';

/// The smallest useful playlist: one `#EXTINF` line, one URL line.
const List<String> _twoLine = [
  '#EXTINF:-1 tvg-id="bbc.example" tvg-logo="http://logo/l.png" '
      'group-title="News",BBC One',
  'http://example.com/live/user/pass/1.m3u8',
];

/// Joins fixture lines with a chosen line ending so the CRLF / bare-CR
/// cases can reuse the exact same playlist text as the LF case.
String _playlist(List<String> lines, {String eol = '\n'}) => lines.join(eol);

/// Every field of every channel as one comparable string, so a parsed
/// playlist can be diffed against its CRLF/CR twin field by field.
List<String> _digest(List<M3uChannel> channels) => [
      for (final c in channels)
        '${c.name}|${c.url}|${c.logo}|${c.group}|${c.tvgId}|${c.tvgName}',
    ];

void main() {
  group('M3uParser.parse', () {
    group('a minimal playlist', () {
      test('reads the name after the comma and the following URL', () {
        final channels = M3uParser.parse(_playlist(_twoLine));

        expect(channels.length, 1);
        expect(channels.first.name, 'BBC One');
        expect(channels.first.url, 'http://example.com/live/user/pass/1.m3u8');
      });

      test('reads tvg-id, tvg-logo and group-title off the EXTINF line', () {
        final channels = M3uParser.parse(_playlist(_twoLine));

        expect(channels.first.tvgId, 'bbc.example');
        expect(channels.first.logo, 'http://logo/l.png');
        expect(channels.first.group, 'News');
        // No tvg-name in the fixture, and an absent attribute is empty —
        // not null, and not the literal text of the attribute.
        expect(channels.first.tvgName, '');
      });
    });

    group('attribute forms', () {
      test('accepts single-quoted attribute values', () {
        final channels = M3uParser.parse(_playlist([
          "#EXTINF:123 tvg-id='news.bbc' group-title='UK Sports',BBC News HD",
          'https://example.com/live/bbcnews.m3u8',
        ]));

        expect(channels.length, 1);
        expect(channels.first.tvgId, 'news.bbc');
        expect(channels.first.group, 'UK Sports');
        expect(channels.first.logo, '');
        expect(channels.first.name, 'BBC News HD');
      });

      test('accepts unquoted attribute values and stops at the comma', () {
        final channels = M3uParser.parse(_playlist([
          '#EXTINF:0 group-title=Sports tvg-id=espn.example '
              'tvg-logo=http://logo/e.png,ESPN',
          'https://example.com/live/espn.m3u8',
        ]));

        expect(channels.first.group, 'Sports');
        expect(channels.first.tvgId, 'espn.example');
        // The unquoted branch is `[^\s,]+`, so the value ends at the comma
        // that separates the attributes from the display name.
        expect(channels.first.logo, 'http://logo/e.png');
        expect(channels.first.name, 'ESPN');
      });

      test('reads all three quoting styles on one EXTINF line', () {
        final channels = M3uParser.parse(_playlist([
          '#EXTINF:-1 tvg-id="sky.example" group-title=Sports '
              "tvg-logo='http://logo/s.png',Sky Sports",
          'https://example.com/live/sky.m3u8',
        ]));

        expect(channels.length, 1);
        expect(channels.first.tvgId, 'sky.example');
        expect(channels.first.group, 'Sports');
        expect(channels.first.logo, 'http://logo/s.png');
        expect(channels.first.name, 'Sky Sports');
      });

      test('reads tvg-name and falls back to it when the name is blank', () {
        final channels = M3uParser.parse(_playlist([
          '#EXTINF:-1 tvg-id="cnn.example" tvg-name="CNN International HD",'
              'CNN Intl',
          'https://example.com/live/cnn.m3u8',
          '#EXTINF:-1 tvg-name="Fallback Name",',
          'https://example.com/live/cnn2.m3u8',
        ]));

        expect(channels[0].tvgName, 'CNN International HD');
        expect(channels[0].name, 'CNN Intl');
        // Blank display name after the comma: tvg-name stands in for it.
        expect(channels[1].tvgName, 'Fallback Name');
        expect(channels[1].name, 'Fallback Name');
      });
    });

    group('leading duration', () {
      test('strips -1 and leaves the first attribute intact', () {
        final channels = M3uParser.parse(_playlist(_twoLine));

        expect(channels.first.tvgId, 'bbc.example');
        expect(channels.first.logo, 'http://logo/l.png');
        expect(channels.first.group, 'News');
        expect(channels.first.name, 'BBC One');
      });

      test('strips a fractional -1.000 without leaking into any field', () {
        final channels = M3uParser.parse(_playlist([
          '#EXTINF:-1.000 tvg-id="f1.example" tvg-logo="http://logo/f1.png" '
              'group-title="Movies",Film One',
          'https://example.com/live/f1.m3u8',
        ]));

        expect(channels.first.tvgId, 'f1.example');
        expect(channels.first.logo, 'http://logo/f1.png');
        expect(channels.first.group, 'Movies');
        expect(channels.first.name, 'Film One');
        // The duration must not survive as a stray token anywhere. The
        // `isFalse` alone would also pass if the duration were simply
        // dropped, so the exact two leading fields are pinned as well:
        // a partial duration strip would corrupt them.
        expect(
          _digest(channels).first,
          'Film One|https://example.com/live/f1.m3u8|'
          'http://logo/f1.png|Movies|f1.example|',
        );
        for (final field in _digest(channels)) {
          expect(field.contains('-1'), isFalse);
        }
      });
    });

    group('URL schemes', () {
      test('accepts every scheme the parser advertises', () {
        const urls = [
          'http://a.example.com/live/1.m3u8',
          'https://a.example.com/live/2.m3u8',
          'rtmp://a.example.com/live/key3',
          'rtmps://a.example.com/live/key4',
          'rtsp://a.example.com/live/5',
          'udp://@239.255.0.1:1234',
          'rtp://239.255.0.1:5678',
          'mms://a.example.com/stream7',
          'mmsh://a.example.com/stream8',
        ];
        final channels = M3uParser.parse(_playlist([
          for (var i = 0; i < urls.length; i++) ...[
            '#EXTINF:-1 tvg-id="ch$i.example",Channel $i',
            urls[i],
          ],
        ]));

        expect(channels.map((c) => c.url).toList(), urls);
        expect(
          channels.map((c) => c.name).toList(),
          [for (var i = 0; i < urls.length; i++) 'Channel $i'],
        );
      });

      test('accepts an uppercase scheme prefix', () {
        final channels = M3uParser.parse(_playlist([
          '#EXTINF:-1,Upper Case',
          'HTTPS://a.example.com/live/upper.m3u8',
        ]));

        expect(channels.length, 1);
        // The URL is stored verbatim; only the scheme *test* is lowercased.
        expect(channels.first.url, 'HTTPS://a.example.com/live/upper.m3u8');
      });

      test('drops a bare host that carries no scheme', () {
        // The only URL in the playlist is scheme-less, so once it is
        // skipped nothing is left and the "no channels" guard fires.
        expect(
          () => M3uParser.parse(_playlist([
            '#EXTINF:-1,No Scheme',
            'a.example.com/live/1.m3u8',
          ])),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('line endings', () {
      test('parses a CRLF playlist exactly like the LF original', () {
        final lf = M3uParser.parse(_playlist(_twoLine));
        final crlf = M3uParser.parse(_playlist(_twoLine, eol: '\r\n'));

        expect(_digest(crlf), _digest(lf));
        expect(crlf.length, 1);
        expect(crlf.first.name, 'BBC One');
        expect(crlf.first.url, 'http://example.com/live/user/pass/1.m3u8');
        expect(crlf.first.tvgId, 'bbc.example');
      });

      test('parses a bare-CR playlist exactly like the LF original', () {
        final lf = M3uParser.parse(_playlist(_twoLine));
        final cr = M3uParser.parse(_playlist(_twoLine, eol: '\r'));

        expect(_digest(cr), _digest(lf));
        expect(cr.length, 1);
        expect(cr.first.name, 'BBC One');
        expect(cr.first.url, 'http://example.com/live/user/pass/1.m3u8');
        expect(cr.first.tvgId, 'bbc.example');
      });
    });

    group('non-attribute lines', () {
      test('skips #EXTVLCOPT and #EXTGRP without turning them into channels',
          () {
        final channels = M3uParser.parse(_playlist([
          '#EXTINF:-1 tvg-id="vlc.example" group-title="UK",Channel A',
          '#EXTVLCOPT:http-client=ffmpeg,http-user-agent=ZPlay',
          '#EXTVLCOPT:network-caching=1000',
          '#EXTGRP:UK Extended',
          'https://example.com/live/a.m3u8',
        ]));

        expect(channels.length, 1);
        expect(channels.first.name, 'Channel A');
        expect(channels.first.url, 'https://example.com/live/a.m3u8');
        expect(channels.first.tvgId, 'vlc.example');
        // `#EXTGRP` after the EXTINF overwrites group-title, it does not
        // append to it.
        expect(channels.first.group, 'UK Extended');
      });

      test('keeps a query string intact and never reads it as attributes', () {
        final channels = M3uParser.parse(_playlist([
          '#EXTINF:-1 tvg-id="sky.example" group-title="Sports",'
              'Sky Sports Main Event',
          'https://cdn.example.com/live/stream.m3u8'
              '?token=abc123&user=bob&type=hd',
        ]));

        expect(channels.length, 1);
        expect(
          channels.first.url,
          'https://cdn.example.com/live/stream.m3u8'
          '?token=abc123&user=bob&type=hd',
        );
        expect(channels.first.name, 'Sky Sports Main Event');
        expect(channels.first.tvgId, 'sky.example');
        expect(channels.first.group, 'Sports');
      });

      test('does not leak EXTINF attributes into the next channel', () {
        final channels = M3uParser.parse(_playlist([
          '#EXTINF:-1 tvg-id="one.example" tvg-logo="http://logo/1.png" '
              'group-title="News",Channel One',
          'http://example.com/live/1.m3u8',
          '#EXTINF:-1 tvg-id="two.example",Channel Two',
          'http://example.com/live/2.m3u8',
        ]));

        expect(channels.length, 2);
        expect(channels[1].tvgId, 'two.example');
        expect(channels[1].name, 'Channel Two');
        // The second EXTINF sets no logo or group, so the first one's
        // values must have been cleared, not inherited.
        expect(channels[1].logo, '');
        expect(channels[1].group, '');
      });

      test('does not leak attributes onto a URL line with no EXTINF', () {
        // A playlist where the last EXTINF is followed by a bare URL has no
        // following EXTINF to clear the pending fields, so the attributes of
        // the previous channel must not bleed onto this URL's channel.
        final channels = M3uParser.parse(_playlist([
          '#EXTINF:-1 tvg-id="x1.example" tvg-logo="http://logo/1.png" '
              'group-title="News",Channel One',
          'http://example.com/live/1.m3u8',
          'http://example.com/live/2.m3u8',
        ]));

        expect(channels.length, 2);
        expect(channels[1].url, 'http://example.com/live/2.m3u8');
        expect(channels[1].name, 'http://example.com/live/2.m3u8');
        expect(channels[1].tvgId, '');
        expect(channels[1].logo, '');
        expect(channels[1].group, '');
      });

      test('names a URL line that has no EXTINF after it by its own URL', () {
        final channels = M3uParser.parse(
          'http://example.com/live/orphan.m3u8',
        );

        expect(channels.length, 1);
        expect(channels.first.url, 'http://example.com/live/orphan.m3u8');
        expect(channels.first.name, 'http://example.com/live/orphan.m3u8');
        expect(channels.first.group, '');
      });
    });

    group('error contract', () {
      test('throws on empty content before the no-channels guard can run',
          () {
        // Asserting the specific message pins the *empty* guard at :9-11.
        // Without it the same input would still throw, but with the
        // "No channels found" message from :81-84 instead.
        expect(
          () => M3uParser.parse(''),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('Playlist is empty'),
            ),
          ),
        );
      });

      test('throws FormatException when the text holds no channel', () {
        expect(
          () => M3uParser.parse('this is just a sentence, not a playlist'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws FormatException on a playlist that is only a header', () {
        expect(
          () => M3uParser.parse('#EXTM3U\n'),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });
}
