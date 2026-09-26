import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/addon/addon.dart';
import '../../models/stream/stream_model.dart';
import '../addon/addon_manager.dart';
import '../scraper/stream_scraper.dart';
import '../scraper/sites/knaben.dart';
import '../scraper/sites/torrent_galaxy.dart';
import '../scraper/sites/fourkhdhub.dart';
import '../scraper/sites/xdownloader.dart';
import '../scraper/sites/videasy.dart';
import '../scraper/sites/vidsrc.dart';
import '../scraper/sites/multiembed.dart';
import '../scraper/sites/vidcore.dart';
import '../scraper/sites/flystream.dart';
import '../scraper/sites/movienight.dart';
import '../scraper/sites/downloadeverything.dart';
import '../scraper/sites/movy.dart';
import '../scraper/sites/vuflix.dart';
import '../scraper/sites/rivestream.dart';
import '../scraper/sites/cinejoy.dart';
import '../scraper/sites/dulo.dart';
import '../scraper/sites/vidup.dart';
import '../scraper/sites/flaxmovies.dart';
import '../scraper/sites/vidgod.dart';
import '../scraper/sites/vidfast.dart';
import '../scraper/sites/peestream.dart';
import '../scraper/sites/lookmovie.dart';
import '../scraper/sites/hexa.dart';
import '../scraper/sites/bcine.dart';
import '../scraper/sites/mapple.dart';
import '../scraper/sites/nova.dart';
import '../scraper/sites/megasource.dart';
import '../scraper/sites/purstream.dart';
import '../scraper/sites/vidapi.dart';
import '../scraper/sites/vidrock.dart';
import '../scraper/sites/vidvault.dart';
import '../scraper/sites/vidzee.dart';
import '../scraper/sites/cinesrc.dart';
import '../scraper/sites/cinesu.dart';
import '../scraper/sites/frame.dart';
import '../scraper/sites/fsharetv.dart';
import '../scraper/sites/fsonic.dart';
import '../scraper/sites/fsonline.dart';
import '../scraper/sites/kisskh.dart';
import '../scraper/sites/lmscript.dart';
import '../scraper/sites/meowtv.dart';
import '../scraper/sites/vidlink.dart';
import '../scraper/sites/vixsrc.dart';
import '../scraper/sites/xpass.dart';
import '../scraper/sites/a111477.dart';
import '../scraper/sites/vadapav.dart';
import '../scraper/sites/zxcstream.dart';
import '../scraper/sites/hindmoviez.dart';
import '../anime/anime_scraper_service.dart';
import '../anime_arabic/anime_arabic_service.dart';
import '../anime_arabic/anime_arabic_extractor.dart';
import '../debrid/debrid_service.dart';
import '../p2p/p2p_settings_service.dart';
import '../cloudstream/cloudstream_manager.dart';

/// Service that fetches playback streams from all installed Stremio addons
/// and built-in scrapers.
class StreamService {
  StreamService._();

  static http.Client _stremioClient = http.Client();
  static final List<StreamSubscription> _activeSubscriptions = [];
  static int _streamSessionId = 0;

  /// Stops and cancels all active scrapers (Built-in HTTP, Built-in P2P, CloudStream, and Stremio Addons).
  static void stopAllScrapers() {
    _streamSessionId++;
    debugPrint('[StreamService] stopAllScrapers() called (session: $_streamSessionId)');

    // 1. Cancel tracked subscriptions in StreamService
    for (final sub in _activeSubscriptions) {
      sub.cancel();
    }
    _activeSubscriptions.clear();

    // 2. Abort pending Stremio HTTP requests and renew client
    try {
      _stremioClient.close();
    } catch (_) {}
    _stremioClient = http.Client();

    // 3. Cancel built-in scrapers
    ScraperManager.instance.cancelActiveScrapes();

    // 4. Cancel CloudStream scrapers & Android bridge jobs
    CloudStreamManager.instance.cancelActiveScrapes();
  }

  static void _registerBuiltInScrapers() {
    // Debrid resolves magnets in the cloud, so the BitTorrent indexers stay
    // usable when the local P2P engine is off but a Debrid service is set up.
    final torrentsUsable = P2pSettingsService.isP2pEnabled.value ||
        DebridService.isDebridReady.value;
    if (torrentsUsable) {
      ScraperManager.instance.registerScraper(KnabenScraper());
      ScraperManager.instance.registerScraper(TorrentGalaxyScraper());
    } else {
      ScraperManager.instance.unregisterTorrentScrapers();
    }
    ScraperManager.instance.registerScraper(A111477Scraper());
    ScraperManager.instance.registerScraper(VadapavScraper());
    ScraperManager.instance.registerScraper(FourKHDHubScraper());
    ScraperManager.instance.registerScraper(XDownloaderScraper());
    ScraperManager.instance.registerScraper(VideasyScraper());
    ScraperManager.instance.registerScraper(VidSrcScraper());
    ScraperManager.instance.registerScraper(MultiEmbedScraper());
    ScraperManager.instance.registerScraper(VidCoreScraper());
    ScraperManager.instance.registerScraper(FlyStreamScraper());
    ScraperManager.instance.registerScraper(MovieNightScraper());
    ScraperManager.instance.registerScraper(DownloadEverythingScraper());
    ScraperManager.instance.registerScraper(MovyScraper());
    ScraperManager.instance.registerScraper(VuflixScraper());
    ScraperManager.instance.registerScraper(RiveStreamScraper());
    ScraperManager.instance.registerScraper(CinejoyScraper());
    ScraperManager.instance.registerScraper(DuloScraper());
    ScraperManager.instance.registerScraper(VidUpScraper());
    ScraperManager.instance.registerScraper(FlaxMoviesScraper());
    ScraperManager.instance.registerScraper(VidGodScraper());
    ScraperManager.instance.registerScraper(VidFastScraper());
    ScraperManager.instance.registerScraper(PeeStreamScraper());
    ScraperManager.instance.registerScraper(LookMovieScraper());
    ScraperManager.instance.registerScraper(HexaScraper());
    ScraperManager.instance.registerScraper(BcineScraper());
    ScraperManager.instance.registerScraper(MappleScraper());
    ScraperManager.instance.registerScraper(NovaScraper());
    ScraperManager.instance.registerScraper(MegaSourceScraper());
    ScraperManager.instance.registerScraper(PurstreamScraper());
    ScraperManager.instance.registerScraper(VidApiScraper());
    ScraperManager.instance.registerScraper(VidRockScraper());
    ScraperManager.instance.registerScraper(VidVaultScraper());
    ScraperManager.instance.registerScraper(VidZeeScraper());
    ScraperManager.instance.registerScraper(CineSrcScraper());
    ScraperManager.instance.registerScraper(CineSuScraper());
    ScraperManager.instance.registerScraper(FrameScraper());
    ScraperManager.instance.registerScraper(FshareTvScraper());
    ScraperManager.instance.registerScraper(FSonicScraper());
    ScraperManager.instance.registerScraper(FSOnlineScraper());
    ScraperManager.instance.registerScraper(KissKhScraper());
    ScraperManager.instance.registerScraper(LMScriptScraper());
    ScraperManager.instance.registerScraper(MeowTvScraper());
    ScraperManager.instance.registerScraper(VidLinkScraper());
    ScraperManager.instance.registerScraper(VixSrcScraper());
    ScraperManager.instance.registerScraper(XPassScraper());
    ScraperManager.instance.registerScraper(ZxcStreamScraper());
    ScraperManager.instance.registerScraper(HindMoviezScraper());
  }

  /// Fetches streams from all active stream-capable addons for the given
  /// content type and ID.
  static Stream<StreamSource> fetchStreams({
    required String type,
    required String id,
    required String title,
    int? year,
    int? season,
    int? episode,
    List<String>? genres,
  }) {
    stopAllScrapers();

    final controller = StreamController<StreamSource>();
    final currentSession = _streamSessionId;

    final addons = AddonManager.instance.activeStreamAddons;
    final isHttpActive = AddonManager.instance.isZplayHttpActive;
    final csExtensions = CloudStreamManager.instance.activeExtensions;
    final hasCs = csExtensions.isNotEmpty;

    if (addons.isEmpty && !isHttpActive && !hasCs) {
      controller.close();
      return controller.stream;
    }

    _registerBuiltInScrapers();

    final List<StreamSubscription> sessionSubs = [];

    controller.onCancel = () {
      for (final sub in sessionSubs) {
        sub.cancel();
      }
      _activeSubscriptions.removeWhere((s) => sessionSubs.contains(s));
      sessionSubs.clear();
      if (currentSession == _streamSessionId) {
        stopAllScrapers();
      }
    };

    int pending = addons.length + (isHttpActive ? 1 : 0) + (hasCs ? 1 : 0);

    // Direct CloudStream link resolution if targeting a CloudStream item
    if (hasCs && (id.startsWith('cloudstream_ep:') || id.startsWith('cloudstream:'))) {
      final parts = id.split(':');
      if (parts.length >= 3) {
        final sourceId = parts[1];
        final dataUrl = id.startsWith('cloudstream_ep:')
            ? Uri.decodeComponent(parts[2])
            : Uri.decodeComponent(parts.sublist(2).join(':'));

        final sub = CloudStreamManager.instance.resolveStreamsForDataUrl(
          sourceId: sourceId,
          dataUrl: dataUrl,
          title: title,
        ).listen((source) {
          if (!controller.isClosed && currentSession == _streamSessionId) {
            controller.add(source);
          }
        }, onError: (_) {});
        sessionSubs.add(sub);
        _activeSubscriptions.add(sub);
      }
    }

    // CloudStream extensions (if active)
    if (hasCs) {
      final sub = CloudStreamManager.instance.scrapeStreams(
        type: type,
        title: title,
        year: year,
        season: season,
        episode: episode,
        genres: genres,
      ).listen((source) {
        if (!controller.isClosed && currentSession == _streamSessionId) {
          controller.add(source);
        }
      }, onError: (_) {}, onDone: () {
        pending--;
        if (pending <= 0 && !controller.isClosed) controller.close();
      });
      sessionSubs.add(sub);
      _activeSubscriptions.add(sub);
    }

    // Local ZPlayHTTP scrapers (if active)
    if (isHttpActive) {
      final isImdb = id.startsWith('tt');
      final cleanImdbId = isImdb ? id.split(':')[0] : null;

      final sub = ScraperManager.instance.scrapeAll(
        type: type,
        title: title,
        year: year,
        season: season,
        episode: episode,
        imdbId: cleanImdbId,
      ).listen((source) {
        if (!controller.isClosed && currentSession == _streamSessionId) {
          controller.add(source);
        }
      }, onDone: () {
        pending--;
        if (pending <= 0 && !controller.isClosed) controller.close();
      });
      sessionSubs.add(sub);
      _activeSubscriptions.add(sub);
    }

    for (final addon in addons) {
      _fetchFromAddon(addon, type, id).then((sources) {
        if (!controller.isClosed && currentSession == _streamSessionId) {
          for (final source in sources) {
            controller.add(source);
          }
        }
      }).catchError((_) {}).whenComplete(() {
        pending--;
        if (pending <= 0 && !controller.isClosed) {
          controller.close();
        }
      });
    }

    return controller.stream;
  }

  /// Fetches streams specifically for a targeted provider/addon that was previously used by the user.
  ///
  /// - If [targetAddonName] == 'ZPlayHTTP': Only scrapes built-in alive HTTP scrapers.
  /// - If [targetAddonName] == 'ZPlay': Only scrapes built-in torrent scrapers.
  /// - If [targetAddonName] matches a Stremio addon (e.g. 'Torrentio', 'CyberFlix'): Only calls that specific addon.
  static Stream<StreamSource> fetchStreamsForTargetAddon({
    required String targetAddonName,
    required String type,
    required String id,
    required String title,
    int? year,
    int? season,
    int? episode,
    List<String>? genres,
  }) {
    final controller = StreamController<StreamSource>();
    final normalizedTarget = targetAddonName.trim().toLowerCase();

    final isArabicAnime = id.startsWith('arabic_anime:') ||
        normalizedTarget == 'arabicanime' ||
        normalizedTarget.contains('arabic');

    if (isArabicAnime) {
      () async {
        try {
          String slug = '';
          if (id.startsWith('arabic_anime:')) {
            final parts = id.split(':');
            if (parts.length >= 2) slug = parts[1];
          } else if (id.isNotEmpty) {
            slug = id;
          }
          if (slug.isEmpty && title.isNotEmpty) {
            final searchResults = await AnimeArabicService.instance.search(title);
            if (searchResults.isNotEmpty) {
              slug = searchResults.first.slug;
            }
          }
          final epNum = episode ?? 1;
          if (slug.isNotEmpty) {
            final details = await AnimeArabicService.instance.getDetails(slug);
            final targetEp = details.episodes.firstWhere(
              (e) => e.number == epNum,
              orElse: () => ArabicEpisode(
                number: epNum,
                title: 'الحلقة $epNum',
                encodedHref: '',
                watchPath: '/e/$slug-$epNum#tok',
              ),
            );
            final hits = await AnimeArabicExtractor.instance.resolveEpisode(targetEp);
            final sources = AnimeArabicExtractor.toSources(
              hits,
              animeTitle: details.title,
              episodeNumber: epNum,
            );
            for (final s in sources) {
              if (!controller.isClosed) controller.add(s);
            }
          }
        } catch (_) {}
        if (!controller.isClosed) controller.close();
      }();
      return controller.stream;
    }

    // Check if targeting general anime providers
    final isAnime = type == 'anime' ||
        id.startsWith('anilist:') ||
        normalizedTarget == 'megaplay' ||
        normalizedTarget == 'anidb' ||
        normalizedTarget == 'watchhentai' ||
        normalizedTarget == 'hentaini' ||
        normalizedTarget == 'anime';

    if (isAnime) {
      int? anilistId;
      if (id.startsWith('anilist:')) {
        final parts = id.split(':');
        if (parts.length >= 2) {
          anilistId = int.tryParse(parts[1]);
        }
      }
      return AnimeScraperService.instance.scrapeStreamsByDetails(
        title: title,
        anilistId: anilistId,
        episodeNumber: episode ?? 1,
      );
    }

    // Check if targeting built-in ZPlayHTTP / ZPlay
    final isLocalZplay = normalizedTarget == 'zplayhttp' ||
        normalizedTarget == 'zplay' ||
        normalizedTarget.contains('zplay');

    if (isLocalZplay) {
      _registerBuiltInScrapers();

      final isImdb = id.startsWith('tt');
      final cleanImdbId = isImdb ? id.split(':')[0] : null;

      ScraperManager.instance.scrapeAll(
        type: type,
        title: title,
        year: year,
        season: season,
        episode: episode,
        imdbId: cleanImdbId,
      ).listen(
        (source) {
          if (!controller.isClosed) {
            // If target was specifically ZPlayHTTP, only yield HTTP streams
            if (normalizedTarget == 'zplayhttp' &&
                (source.infoHash != null && source.infoHash!.isNotEmpty)) {
              return;
            }
            // If target was specifically ZPlay (torrent), only yield torrent streams
            if (normalizedTarget == 'zplay' &&
                (source.infoHash == null || source.infoHash!.isEmpty)) {
              return;
            }
            controller.add(source);
          }
        },
        onError: (_) {},
        onDone: () {
          if (!controller.isClosed) controller.close();
        },
      );

      return controller.stream;
    }

    // Check if targeting a CloudStream extension
    final matchingCs = CloudStreamManager.instance.activeExtensions.where(
      (e) =>
          e.name.toLowerCase() == normalizedTarget ||
          (e.internalName != null && e.internalName!.toLowerCase() == normalizedTarget) ||
          e.name.toLowerCase().contains(normalizedTarget) ||
          normalizedTarget.contains(e.name.toLowerCase()),
    ).toList();

    if (matchingCs.isNotEmpty) {
      return CloudStreamManager.instance.scrapeStreams(
        type: type,
        title: title,
        year: year,
        season: season,
        episode: episode,
        genres: genres,
      );
    }

    // Otherwise, find the matching Stremio addon
    final matchingAddons = AddonManager.instance.activeStreamAddons.where(
      (a) =>
          a.manifest.name.toLowerCase() == normalizedTarget ||
          a.manifest.name.toLowerCase().contains(normalizedTarget) ||
          normalizedTarget.contains(a.manifest.name.toLowerCase()),
    ).toList();

    if (matchingAddons.isNotEmpty) {
      final matchingAddon = matchingAddons.first;
      _fetchFromAddon(matchingAddon, type, id).then((sources) {
        if (!controller.isClosed) {
          for (final source in sources) {
            controller.add(source);
          }
        }
      }).catchError((_) {}).whenComplete(() {
        if (!controller.isClosed) controller.close();
      });
    } else {
      // Fallback: If no exact addon match found, run general fetch
      return fetchStreams(
        type: type,
        id: id,
        title: title,
        year: year,
        season: season,
        episode: episode,
        genres: genres,
      );
    }

    return controller.stream;
  }

  static Future<List<StreamSource>> _fetchFromAddon(
    InstalledAddon addon,
    String type,
    String id,
  ) async {
    try {
      // Check idPrefixes filtering if declared by addon
      if (addon.manifest.idPrefixes.isNotEmpty) {
        final matchesPrefix = addon.manifest.idPrefixes.any((p) => id.startsWith(p));
        if (!matchesPrefix) return [];
      }

      // Check types filtering if declared by addon
      if (addon.manifest.types.isNotEmpty) {
        final matchesType = addon.manifest.types.contains(type);
        if (!matchesType) return [];
      }

      final pathId = Uri.encodeComponent(id);
      final url = '${addon.baseUrl}/stream/$type/$pathId.json';

      final response = await _stremioClient.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final streams = data['streams'] as List<dynamic>?;

      if (streams == null || streams.isEmpty) return [];

      return streams
          .whereType<Map>()
          .map((json) => StreamSource.fromJson(Map<String, dynamic>.from(json), addon.manifest.name))
          .where((s) => s.url != null || s.infoHash != null || s.externalUrl != null)
          .toList();
    } catch (e) {
      debugPrint('Addon ${addon.manifest.name} stream fetch failed: $e');
      return [];
    }
  }
}
