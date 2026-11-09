import 'package:flutter/material.dart';

// Models ported from PlayTorrio TV IPTV system.
// Pure data classes - no heavy dependencies.

/// Raw scraped Xtream-Codes portal credentials (unverified).
class IptvPortal {
  final String url;
  final String username;
  final String password;
  final String source;

  const IptvPortal({
    required this.url,
    required this.username,
    required this.password,
    this.source = '',
  });

  String get key => '$url|$username|$password'.toLowerCase();

  /// Identity for duplicate-portal checks: ignores URL, since the same
  /// account can be exposed on multiple host names.
  String get credKey => '$username|$password'.toLowerCase();

  Map<String, dynamic> toJson() => {
        'url': url,
        'username': username,
        'password': password,
        'source': source,
      };

  factory IptvPortal.fromJson(Map<String, dynamic> j) => IptvPortal(
        url: j['url'] as String? ?? '',
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
        source: j['source'] as String? ?? '',
      );
}

/// Portal that successfully authenticated against /player_api.php.
class VerifiedPortal {
  final IptvPortal portal;
  final String name;
  final String expiry;
  final String maxConnections;
  final String activeConnections;

  const VerifiedPortal({
    required this.portal,
    required this.name,
    required this.expiry,
    required this.maxConnections,
    required this.activeConnections,
  });

  String get key => portal.key;
  String get credKey => portal.credKey;
}

class IptvCategory {
  final String id;
  final String name;
  const IptvCategory({required this.id, required this.name});
}

enum IptvSection { live, vod, series }

/// Single playable stream entry. `kind` = "live" / "vod" / "series".
class IptvStream {
  final String streamId;
  final String name;
  final String icon;
  final String categoryId;
  final String containerExt;
  final String kind;

  const IptvStream({
    required this.streamId,
    required this.name,
    required this.icon,
    required this.categoryId,
    required this.containerExt,
    required this.kind,
  });
}

/// Single EPG programme entry returned by Xtream `get_short_epg`.
class EpgEntry {
  final String title;
  final String description;
  final DateTime start;
  final DateTime stop;
  const EpgEntry({
    required this.title,
    required this.description,
    required this.start,
    required this.stop,
  });

  bool get isNow {
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(stop);
  }

  /// How far into this programme the wall clock is, `0..1`.
  ///
  /// Three surfaces drew this bar - the browser page's channel rows, the guide
  /// band's progress track and its "N mins elapsed (P% complete)" line - and
  /// each computed the fraction itself. Clamped here, and `0` for a zero-length
  /// entry, because the fraction is read on every rebuild: an unclamped or NaN
  /// value paints outside the track.
  double get progress {
    final total = stop.difference(start).inSeconds;
    if (total <= 0) return 0.0;
    final elapsed = DateTime.now().difference(start).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0).toDouble();
  }
}

class IptvEpisode {
  final String id;
  final String title;
  final String containerExt;
  final int season;
  final int episode;
  final String plot;
  final String image;

  const IptvEpisode({
    required this.id,
    required this.title,
    required this.containerExt,
    required this.season,
    required this.episode,
    required this.plot,
    required this.image,
  });
}

/// Custom user-added quick channel for the Live TV quick channels row.
class QuickChannel {
  final String id;
  final String name;
  final String short;
  final String category;
  final List<String> keywords;
  final List<Color> gradient;
  final String? iconUrl;

  const QuickChannel({
    required this.id,
    required this.name,
    required this.short,
    required this.category,
    required this.keywords,
    required this.gradient,
    this.iconUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'short': short,
        'category': category,
        'keywords': keywords,
        'gradient': gradient.map((c) => '#${c.value.toRadixString(16)}').toList(),
        'iconUrl': iconUrl,
      };

  factory QuickChannel.fromJson(Map<String, dynamic> j) => QuickChannel(
        id: j['id'] as String,
        name: j['name'] as String,
        short: j['short'] as String,
        category: j['category'] as String? ?? 'Quick',
        keywords: (j['keywords'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ?? [],
        gradient: (j['gradient'] as List<dynamic>?)
                ?.map((e) {
                  final hex = e as String;
                   return Color(int.parse('0x${hex.replaceFirst('#', '')}'));
                })
                .toList() ?? [Colors.grey, Colors.black54],
        iconUrl: j['iconUrl'] as String?,
      );
}

/// A single alive stream found while resolving a HardcodedChannel.
class ChannelHit {
  final VerifiedPortal portal;
  final IptvStream stream;
  final String streamUrl;

  const ChannelHit({
    required this.portal,
    required this.stream,
    required this.streamUrl,
  });

  /// The flat, abbreviated shape the channel-results cache has always written:
  /// `pu` portal url, `uu` username, `pp` password, `pn` portal name, `sid`
  /// stream id, `sn` stream name, `si` stream icon, `scid` category id, `sce`
  /// container extension, `sk` stream kind, `url` playable url.
  ///
  /// These key names are the on-disk format of every installed build, so they
  /// are not to be tidied: a hit saved by a previous version is read back
  /// through [ChannelHit.fromJson], and a hit saved by this one has to stay
  /// readable if the app is downgraded.
  ///
  /// The portal's `source`, expiry and connection counts are not part of that
  /// shape, so a restored hit comes back as a `'Saved'` portal - the provenance
  /// tag the cache reader has always stamped on one.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'pu': portal.portal.url,
        'uu': portal.portal.username,
        'pp': portal.portal.password,
        'pn': portal.name,
        'sid': stream.streamId,
        'sn': stream.name,
        'si': stream.icon,
        'scid': stream.categoryId,
        'sce': stream.containerExt,
        'sk': stream.kind,
        'url': streamUrl,
      };

  /// Tolerant the way the cache reader has always been: an absent key reads as
  /// empty (an absent `sk` as `'live'`), while a key of the wrong type throws
  /// and the store drops the cached list.
  factory ChannelHit.fromJson(Map<String, dynamic> o) => ChannelHit(
        portal: VerifiedPortal(
          portal: IptvPortal(
            url: o['pu'] as String? ?? '',
            username: o['uu'] as String? ?? '',
            password: o['pp'] as String? ?? '',
            source: 'Saved',
          ),
          name: o['pn'] as String? ?? '',
          expiry: '',
          maxConnections: '1',
          activeConnections: '0',
        ),
        stream: IptvStream(
          streamId: o['sid'] as String? ?? '',
          name: o['sn'] as String? ?? '',
          icon: o['si'] as String? ?? '',
          categoryId: o['scid'] as String? ?? '',
          containerExt: o['sce'] as String? ?? '',
          kind: o['sk'] as String? ?? 'live',
        ),
        streamUrl: o['url'] as String? ?? '',
      );
}

class ScrapePage {
  final List<IptvPortal> portals;
  final String? nextAfter;
  const ScrapePage({required this.portals, this.nextAfter});
  bool get hasMore => nextAfter != null && nextAfter!.isNotEmpty;
}
