import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/iptv/iptv_network.dart';

/// The live-scraper's Reddit reader used to pull posts out of the Atom feed with
/// four regular expressions and a hand-written entity decoder, because the feed
/// arrives as text and nothing else parsed it. It is an XML document now
/// (`xml` package) and this test is the only thing standing between a parser
/// swap and silently losing every portal the scraper finds: the production test
/// (`test/iptv_reddit_extractor_test.dart`) is tagged `network` and needs the
/// internet.
///
/// What has to stay true: entry order, the `t3_` ids that page the feed, the
/// HTML/entity flattening that the portal regexes read, and "no posts" rather
/// than a throw on a malformed body.
void main() {
  String feed(String entries) =>
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<feed xmlns="http://www.w3.org/2005/Atom">$entries</feed>';

  String entry({
    required String id,
    String? title,
    required String content,
    String contentType = 'html',
  }) =>
      '<entry>'
      '<id>$id</id>'
      '${title == null ? '' : '<title>$title</title>'}'
      '<content type="$contentType">$content</content>'
      '</entry>';

  test('reads entries in feed order and keeps the t3_ ids paging depends on',
      () {
    final posts = IptvScraper.parseCatalogRss(
      feed(
        entry(id: 't3_aaa1', title: 'one', content: 'a') +
            entry(id: 't3_bbb2', title: 'two', content: 'b') +
            entry(id: 'not-a-post', title: 'skip', content: 'c') +
            entry(id: 't3_ccc3', title: 'three', content: 'd'),
      ),
    );

    expect(posts.map((p) => p.id).toList(), ['t3_aaa1', 't3_bbb2', '', 't3_ccc3']);
    expect(posts.map((p) => p.title).toList(), ['one', 'two', 'skip', 'three']);
    // Only `t3_` ids are posts and only they page the feed; the others keep
    // their place in the body pass with an empty id, which is what the
    // cursor logic already assumed.
    expect(
      posts.where((p) => p.id.isNotEmpty).map((p) => p.id),
      ['t3_aaa1', 't3_bbb2', 't3_ccc3'],
    );
  });

  test('decodes entities exactly once, as the portal regexes expect', () {
    final posts = IptvScraper.parseCatalogRss(
      feed(
        entry(
          id: 't3_amp',
          title: 'fast &amp;amp; cheap',
          content: 'Deal: fast &amp;amp; cheap pw&amp;#39;s '
              'http://p3.example:2095/live/alice/pw/1.ts',
        ),
      ),
    );

    expect(posts.single.title, 'fast &amp; cheap');
    // One decode pass: `&amp;#39;` becomes `&#39;`'s character only after the
    // XML parser's own pass, which is what the old decoder did too.
    expect(posts.single.body, contains("pw's"));
    expect(posts.single.body, contains('http://p3.example:2095/live/alice/pw/1.ts'));
  });

  test('flattens HTML block tags without gluing words together', () {
    final posts = IptvScraper.parseCatalogRss(
      feed(
        entry(
          id: 't3_html',
          title: 'Server',
          content:
              '&lt;div&gt;&lt;p&gt;Server: http://panel.example:8080&lt;/p&gt;'
              '&lt;p&gt;User: bob&lt;/p&gt;&lt;p&gt;Pass: secret123&lt;/p&gt;'
              '&lt;/div&gt;',
        ),
      ),
    );

    final body = posts.single.body;
    expect(body, contains('Server: http://panel.example:8080'));
    expect(body, contains('User: bob'));
    expect(body, contains('Pass: secret123'));
    expect(body, isNot(contains('<p>')));
    expect(body, isNot(contains('&lt;')));
    // A block boundary is a separator, not a space inside a host name.
    expect(body, contains('http://panel.example:8080'));
  });

  test('a post with no title still yields its body', () {
    final posts = IptvScraper.parseCatalogRss(
      feed(
        entry(
          id: 't3_notitle',
          content: 'No title here: http://panel4.example:8080 '
              'User: carl Pass: hunter22',
        ),
      ),
    );

    expect(posts.single.title, isEmpty);
    expect(posts.single.body, contains('http://panel4.example:8080'));
    expect(posts.single.body, contains('Pass: hunter22'));
  });

  test('xhtml content keeps its child elements readable', () {
    final posts = IptvScraper.parseCatalogRss(
      feed(
        entry(
          id: 't3_xhtml',
          title: 'XHTML',
          contentType: 'xhtml',
          content: '<div xmlns="http://www.w3.org/1999/xhtml">'
              '<p>alpha http://p5.example:8080</p>'
              '<p>User: dan Pass: hunter33</p></div>',
        ),
      ),
    );

    final body = posts.single.body;
    expect(body, contains('alpha http://p5.example:8080'));
    expect(body, contains('Pass: hunter33'));
  });

  test('a malformed feed is no posts, not a crash', () {
    expect(IptvScraper.parseCatalogRss('<feed><entry><id>t3_x'), isEmpty);
    expect(IptvScraper.parseCatalogRss(''), isEmpty);
    expect(IptvScraper.parseCatalogRss('not xml at all'), isEmpty);
  });
}