/// Ready-made Stremio addon templates that take the Debrid key in the URL.
///
/// Each template stores one base URL per Debrid service, with the key left as a
/// placeholder such as `{realdebrid}`. The addon URL resolver swaps the
/// placeholder for the user's own saved key at request time, so the installed
/// addon record never holds a copy of the key.
class DebridAddonTemplate {
  final String id;
  final String name;
  final String description;

  /// Debrid service name -> base URL template containing a {placeholder}.
  final Map<String, String> baseUrlByService;

  /// URL without any Debrid parameter, used to revert a connected addon.
  final String plainUrl;

  const DebridAddonTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.baseUrlByService,
    required this.plainUrl,
  });

  List<String> get services => baseUrlByService.keys.toList();

  String? baseUrlFor(String service) => baseUrlByService[service];
}

class DebridAddonCatalog {
  static const List<DebridAddonTemplate> templates = [
    DebridAddonTemplate(
      id: 'torrentio',
      name: 'Torrentio',
      description:
          'Stremio addon that searches BitTorrent indexers and flags which results are already cached on the connected Debrid service.',
      baseUrlByService: {
        'Real-Debrid': 'https://torrentio.strem.fun/realdebrid={realdebrid}',
        'AllDebrid': 'https://torrentio.strem.fun/alldebrid={alldebrid}',
        'Premiumize': 'https://torrentio.strem.fun/premiumize={premiumize}',
        'Debrid-Link': 'https://torrentio.strem.fun/debridlink={debridlink}',
        'TorBox': 'https://torrentio.strem.fun/torbox={torbox}',
      },
      plainUrl: 'https://torrentio.strem.fun',
    ),
  ];

  static DebridAddonTemplate? byId(String id) {
    for (final template in templates) {
      if (template.id == id) return template;
    }
    return null;
  }
}
