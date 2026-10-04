import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/addon/addon.dart';
import '../../models/continue_watching/continue_watching_item.dart';
import '../../models/movie/movie.dart';
import '../../models/movie/movie_section.dart';
import '../../models/my_list/my_list_item.dart';
import '../../models/stremio/stremio_meta.dart';
import '../continue_watching/continue_watching_service.dart';
import '../content/content_settings.dart';
import '../metadata/bestsimilar_scraper.dart';
import '../my_list/my_list_service.dart';
import '../simkl/simkl_list_source.dart';
import '../simkl/simkl_service.dart';
import '../trakt/trakt_list_source.dart';
import '../trakt/trakt_service.dart';

enum SimilarSectionPosition {
  top('Top (Below Hero Banner)'),
  underCinemeta('Under Cinemeta Addon'),
  middle('Middle of Catalog'),
  bottom('Bottom of Page');

  final String label;
  const SimilarSectionPosition(this.label);
}

enum HeroStyle {
  immersive('Immersive Cinematic Carousel'),
  compact('Compact Spotlight'),
  minimalist('Minimalist Header');

  final String label;
  const HeroStyle(this.label);
}

enum AmbientLightPattern {
  dualOrbs('Dual Floating Orbs'),
  topAurora('Top Aurora Horizon'),
  fullMesh('Full Deep Ambient Mesh'),
  centerPulse('Pulsing Core');

  final String label;
  const AmbientLightPattern(this.label);
}

enum CardDensity {
  compact('Compact (Dense Grid)'),
  standard('Standard Balanced'),
  cinematic('Cinematic (Large Posters)');

  final String label;
  const CardDensity(this.label);
}

abstract final class HomePageSettings {
  static const _keyEnableSpotlight = 'home_enable_spotlight';
  static const _keyEnableSimilar = 'home_enable_similar';
  static const _keyEnableWatchingSimilar = 'home_enable_watching_similar';
  static const _keyEnableTraktRec = 'home_enable_trakt_rec';
  static const _keyEnableSimklRec = 'home_enable_simkl_rec';
  static const _keySimilarPosition = 'home_similar_position';
  static const _keyHeroStyle = 'home_hero_style';
  static const _keyHeroAutoRotate = 'home_hero_auto_rotate';
  static const _keyHeroRotateSeconds = 'home_hero_rotate_seconds';
  static const _keyCardDensity = 'home_card_density';
  static const _keyShowRating = 'home_show_rating';
  static const _keyAmbientGlow = 'home_ambient_glow';
  static const _keyCardHoverZoom = 'home_card_hover_zoom';
  static const _keyEnableAmbientLights = 'home_enable_ambient_lights';
  static const _keyAmbientPattern = 'home_ambient_pattern';
  static const _keyAmbientIntensity = 'home_ambient_intensity';
  static const _keyAmbientSpeed = 'home_ambient_speed';
  static const _keyEnableCalendar = 'app_enable_calendar';
  static const _keyEnableAiQuiz = 'app_enable_ai_quiz';
  static const _keyHideArtlessRails = 'home_hide_artless_rails';

  static final ValueNotifier<bool> enableSpotlight = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> enableSimilar = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> enableWatchingSimilar = ValueNotifier<bool>(
    true,
  );
  static final ValueNotifier<bool> enableTraktRecommendations =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> enableSimklRecommendations =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> enableCalendar = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> enableAiQuiz = ValueNotifier<bool>(true);

  /// Drop Home rails no item of which can draw a picture.
  ///
  /// On by default, because a landscape rail is identified by its picture and a
  /// tile that draws nothing is an empty rectangle - see `visibleHomeSections`,
  /// which is where the rule lives. It is a setting rather than an unconditional
  /// rule so a rail that is genuinely useful without art can be brought back
  /// without a code change.
  static final ValueNotifier<bool> hideArtlessRails = ValueNotifier<bool>(true);
  static final ValueNotifier<SimilarSectionPosition> similarPosition =
      ValueNotifier<SimilarSectionPosition>(SimilarSectionPosition.top);
  static final ValueNotifier<HeroStyle> heroStyle = ValueNotifier<HeroStyle>(
    HeroStyle.immersive,
  );
  static final ValueNotifier<bool> heroAutoRotate = ValueNotifier<bool>(true);
  static final ValueNotifier<int> heroRotateSeconds = ValueNotifier<int>(6);
  static final ValueNotifier<CardDensity> cardDensity =
      ValueNotifier<CardDensity>(CardDensity.standard);
  static final ValueNotifier<bool> showRating = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> ambientGlow = ValueNotifier<bool>(true);
  static final ValueNotifier<double> cardHoverZoom = ValueNotifier<double>(
    1.08,
  );
  static final ValueNotifier<bool> enableAmbientLights = ValueNotifier<bool>(
    true,
  );
  static final ValueNotifier<AmbientLightPattern> ambientLightPattern =
      ValueNotifier<AmbientLightPattern>(AmbientLightPattern.dualOrbs);
  static final ValueNotifier<double> ambientLightIntensity =
      ValueNotifier<double>(0.22);
  static final ValueNotifier<double> ambientLightSpeed = ValueNotifier<double>(
    1.0,
  );

  static final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  // Cached recommendation sections to avoid scraping on every scroll
  static MovieSection? _cachedSimilarSection;
  static MovieSection? _cachedWatchingSimilarSection;
  static MovieSection? _cachedTraktSection;
  static MovieSection? _cachedSimklSection;
  static final Map<TraktSeeAllList, MovieSection> _cachedTraktPublicSections = {};
  static String? lastListSourceTitle;

  /// Drop cached recommendation sections (e.g. when the adult switch flips:
  /// the cached seed was picked under the old switch value).
  static void clearRecommendationCache() {
    _cachedSimilarSection = null;
    _cachedWatchingSimilarSection = null;
    _cachedTraktSection = null;
    _cachedSimklSection = null;
    _cachedTraktPublicSections.clear();
  }

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    enableSpotlight.value = prefs.getBool(_keyEnableSpotlight) ?? true;
    enableSimilar.value = prefs.getBool(_keyEnableSimilar) ?? true;
    enableWatchingSimilar.value =
        prefs.getBool(_keyEnableWatchingSimilar) ?? true;
    enableTraktRecommendations.value =
        prefs.getBool(_keyEnableTraktRec) ?? true;
    enableSimklRecommendations.value =
        prefs.getBool(_keyEnableSimklRec) ?? true;
    enableCalendar.value = prefs.getBool(_keyEnableCalendar) ?? true;
    enableAiQuiz.value = prefs.getBool(_keyEnableAiQuiz) ?? true;
    hideArtlessRails.value = prefs.getBool(_keyHideArtlessRails) ?? true;

    final posStr = prefs.getString(_keySimilarPosition);
    similarPosition.value = SimilarSectionPosition.values.firstWhere(
      (p) => p.name == posStr,
      orElse: () => SimilarSectionPosition.top,
    );

    final heroStr = prefs.getString(_keyHeroStyle);
    heroStyle.value = HeroStyle.values.firstWhere(
      (h) => h.name == heroStr,
      orElse: () => HeroStyle.immersive,
    );

    heroAutoRotate.value = prefs.getBool(_keyHeroAutoRotate) ?? true;
    heroRotateSeconds.value = prefs.getInt(_keyHeroRotateSeconds) ?? 6;

    final densityStr = prefs.getString(_keyCardDensity);
    cardDensity.value = CardDensity.values.firstWhere(
      (d) => d.name == densityStr,
      orElse: () => CardDensity.standard,
    );

    showRating.value = prefs.getBool(_keyShowRating) ?? true;
    ambientGlow.value = prefs.getBool(_keyAmbientGlow) ?? true;
    cardHoverZoom.value = prefs.getDouble(_keyCardHoverZoom) ?? 1.08;

    enableAmbientLights.value = prefs.getBool(_keyEnableAmbientLights) ?? true;
    final patternStr = prefs.getString(_keyAmbientPattern);
    ambientLightPattern.value = AmbientLightPattern.values.firstWhere(
      (p) => p.name == patternStr,
      orElse: () => AmbientLightPattern.dualOrbs,
    );
    ambientLightIntensity.value = prefs.getDouble(_keyAmbientIntensity) ?? 0.22;
    ambientLightSpeed.value = prefs.getDouble(_keyAmbientSpeed) ?? 1.0;
  }

  static Future<void> setEnableAmbientLights(bool val) async {
    enableAmbientLights.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableAmbientLights, val);
    changeNotifier.value++;
  }

  static Future<void> setAmbientLightPattern(
    AmbientLightPattern pattern,
  ) async {
    ambientLightPattern.value = pattern;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAmbientPattern, pattern.name);
    changeNotifier.value++;
  }

  static Future<void> setAmbientLightIntensity(double val) async {
    ambientLightIntensity.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyAmbientIntensity, val);
    changeNotifier.value++;
  }

  static Future<void> setAmbientLightSpeed(double val) async {
    ambientLightSpeed.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyAmbientSpeed, val);
    changeNotifier.value++;
  }

  static Future<void> setEnableSpotlight(bool val) async {
    enableSpotlight.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableSpotlight, val);
    changeNotifier.value++;
  }

  static Future<void> setEnableSimilar(bool val) async {
    enableSimilar.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableSimilar, val);
    changeNotifier.value++;
  }

  static Future<void> setEnableWatchingSimilar(bool val) async {
    enableWatchingSimilar.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableWatchingSimilar, val);
    changeNotifier.value++;
  }

  static Future<void> setEnableTraktRecommendations(bool val) async {
    enableTraktRecommendations.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableTraktRec, val);
    changeNotifier.value++;
  }

  static Future<void> setEnableSimklRecommendations(bool val) async {
    enableSimklRecommendations.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableSimklRec, val);
    changeNotifier.value++;
  }

  static Future<void> setEnableCalendar(bool val) async {
    enableCalendar.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableCalendar, val);
    changeNotifier.value++;
  }

  static Future<void> setEnableAiQuiz(bool val) async {
    enableAiQuiz.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableAiQuiz, val);
    changeNotifier.value++;
  }

  /// Toggling this changes which rails Home builds, so it bumps the same
  /// [changeNotifier] every other content switch does and the page rebuilds.
  static Future<void> setHideArtlessRails(bool val) async {
    hideArtlessRails.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHideArtlessRails, val);
    changeNotifier.value++;
  }

  static Future<void> setSimilarPosition(SimilarSectionPosition pos) async {
    similarPosition.value = pos;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySimilarPosition, pos.name);
    changeNotifier.value++;
  }

  static Future<void> setHeroStyle(HeroStyle style) async {
    heroStyle.value = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHeroStyle, style.name);
    changeNotifier.value++;
  }

  static Future<void> setHeroAutoRotate(bool val) async {
    heroAutoRotate.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHeroAutoRotate, val);
    changeNotifier.value++;
  }

  static Future<void> setHeroRotateSeconds(int seconds) async {
    heroRotateSeconds.value = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyHeroRotateSeconds, seconds);
    changeNotifier.value++;
  }

  static Future<void> setCardDensity(CardDensity density) async {
    cardDensity.value = density;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCardDensity, density.name);
    changeNotifier.value++;
  }

  static Future<void> setShowRating(bool val) async {
    showRating.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowRating, val);
    changeNotifier.value++;
  }

  static Future<void> setAmbientGlow(bool val) async {
    ambientGlow.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAmbientGlow, val);
    changeNotifier.value++;
  }

  static Future<void> setCardHoverZoom(double zoom) async {
    cardHoverZoom.value = zoom;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyCardHoverZoom, zoom);
    changeNotifier.value++;
  }

  /// The Home row one BestSimilar recommendation becomes.
  ///
  /// BestSimilar publishes no IMDb id for its titles (verified against the
  /// live pages: no `tt` id, no imdb link, nothing), so the row keeps the
  /// scraper's own id under a `bestsimilar_` prefix the details page
  /// recognises as "resolve this title before fetching meta". The poster is
  /// the scraper's own thumb and the addon is Cinemeta, a real meta server:
  /// the row is a normal catalogue item in every respect but its id.
  @visibleForTesting
  static Movie movieFromBestsimilarItem(BSItem sim) {
    return Movie(
      id: 'bestsimilar_${sim.id}',
      type: sim.isTv ? 'series' : 'movie',
      name: sim.title,
      poster: sim.thumbUrl,
      year: sim.year?.toString(),
      addonBaseUrl: 'https://v3-cinemeta.strem.io',
    );
  }

  /// Shared helper to build a BestSimilar recommendation MovieSection
  static Future<MovieSection?> _buildBestSimilarSection({
    required String sourceTitle,
    required int? year,
    required String type,
    required String sectionTitle,
    required String catalogId,
  }) async {
    final isTv = (type == 'series' || type == 'tv');
    try {
      final hit = await BestSimilarScraper.findBest(
        title: sourceTitle,
        year: year,
        isTv: isTv,
      );

      if (hit == null) return null;

      final details = await BestSimilarScraper.fetchDetails(
        id: hit.id,
        slug: hit.slug,
      );

      if (details == null || details.similar.isEmpty) return null;

      // Safety Guard: If source title is live-action, don't allow anime details
      final isAnimeSource =
          type == 'anime' || sourceTitle.toLowerCase().contains('anime');
      final isAnimeMatched =
          (details.genre?.toLowerCase().contains('animation') == true ||
              details.genre?.toLowerCase().contains('anime') == true) &&
          details.plotTags.any(
            (t) =>
                t.toLowerCase() == 'anime' ||
                t.toLowerCase() == 'japanese animation' ||
                t.toLowerCase() == 'manga adaptation',
          );

      if (!isAnimeSource && isAnimeMatched) {
        debugPrint(
          '[HomePageSettings] Skipping anime match for live-action: $sourceTitle',
        );
        return null;
      }

      final movies = <Movie>[];
      for (final sim in details.similar.take(24)) {
        movies.add(movieFromBestsimilarItem(sim));
      }

      if (movies.isEmpty) return null;

      return MovieSection(
        title: sectionTitle,
        subtitle: 'Recommendations based on $sourceTitle',
        contentType: type,
        addonBaseUrl: 'https://v3-cinemeta.strem.io',
        catalog: AddonCatalog(
          type: type,
          id: catalogId,
          name: 'Similar to $sourceTitle',
          genres: const [],
          supportsSearch: false,
          supportsSkip: false,
        ),
        movies: movies,
      );
    } catch (e) {
      debugPrint(
        '[HomePageSettings] Failed to build similar section for "$sourceTitle": $e',
      );
      return null;
    }
  }

  /// Fetches a dynamic "Because you have [Title] on your list" section using BestSimilar
  static Future<MovieSection?> fetchBestSimilarSection({
    bool forceRefresh = false,
  }) async {
    if (!enableSimilar.value) return null;

    // visibleItems already drops adult entries while the 18+ switch is off.
    final myList = MyListService.visibleItems;
    if (myList.isEmpty) return null;

    if (!forceRefresh && _cachedSimilarSection != null) {
      return _cachedSimilarSection;
    }

    // Try candidates from My List (latest added first, with fallback to others).
    // Each attempt fires up to two network lookups, so only try the latest
    // few entries instead of the whole list.
    final candidates = List<MyListItem>.from(myList.reversed);

    for (final sourceItem in candidates.take(3)) {
      final section = await _buildBestSimilarSection(
        sourceTitle: sourceItem.title,
        year: sourceItem.year,
        type: sourceItem.type,
        sectionTitle: 'Because you have "${sourceItem.title}" on your list',
        catalogId: 'bestsimilar_list',
      );

      if (section != null) {
        _cachedSimilarSection = section;
        lastListSourceTitle = sourceItem.title;
        return section;
      }
    }

    return null;
  }

  /// Fetches a dynamic "Because you're watching [Title]" section from Continue Watching using BestSimilar
  static Future<MovieSection?> fetchContinueWatchingSimilarSection({
    bool forceRefresh = false,
    String? excludeTitle,
  }) async {
    if (!enableWatchingSimilar.value) return null;

    var active = ContinueWatchingService.activeItems.value;
    if (active.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final rawJson = prefs.getString('continue_watching_sessions_v1');
        if (rawJson != null && rawJson.isNotEmpty) {
          final list = jsonDecode(rawJson) as List<dynamic>;
          active = list
              .whereType<Map<String, dynamic>>()
              .map((j) => ContinueWatchingItem.fromJson(j))
              .toList();
        }
      } catch (_) {}
    }

    // Hoist an adult title out of the poll while the 18+ switch is off, so it
    // cannot become a section header ("Because you're watching …") or the seed
    // for its recommendations.
    if (!ContentSettings.adultEnabled.value) {
      // One addon scan for the whole batch, shared across per-item checks.
      final nsfwKeys = ContinueWatchingService.buildNsfwAddonKeys();
      final filtered = active
          .where(
            (item) =>
                !item.isAdult &&
                !ContinueWatchingService.isAdultSession(
                  id: item.id,
                  type: item.type,
                  addonName: item.addonName,
                  nsfwAddonKeys: nsfwKeys,
                ),
          )
          .toList();
      if (filtered.isEmpty) return null;
      active = filtered;
    }

    if (active.isEmpty) return null;

    if (!forceRefresh && _cachedWatchingSimilarSection != null) {
      return _cachedWatchingSimilarSection;
    }

    // Pick a random item from Continue Watching
    final candidates = List<ContinueWatchingItem>.from(active)
      ..shuffle(Random());
    final excluded = (excludeTitle ?? lastListSourceTitle ?? '')
        .trim()
        .toLowerCase();
    var attempts = 0;
    for (final item in candidates) {
      if (excluded.isNotEmpty && item.title.trim().toLowerCase() == excluded) {
        continue;
      }
      // Each attempt below fires up to two network lookups; bound the burst.
      if (attempts >= 3) break;
      attempts++;
      final yearInt = item.year != null ? int.tryParse(item.year!) : null;
      final section = await _buildBestSimilarSection(
        sourceTitle: item.title,
        year: yearInt,
        type: item.type,
        sectionTitle: 'Because you\'re watching "${item.title}"',
        catalogId: 'bestsimilar_watching',
      );

      if (section != null) {
        _cachedWatchingSimilarSection = section;
        return section;
      }
    }

    return null;
  }

  /// Fetches Trakt personalized recommendations if Trakt is authenticated and enabled
  static Future<MovieSection?> fetchTraktRecommendationsSection({
    bool forceRefresh = false,
  }) async {
    if (!enableTraktRecommendations.value) return null;
    if (!await TraktService.instance.isAuthenticated()) return null;

    if (!forceRefresh && _cachedTraktSection != null) {
      return _cachedTraktSection;
    }

    try {
      final res = await TraktListSource.instance.loadList(
        const TraktListChoice.builtin(TraktSeeAllList.recommendations),
      );

      if (res.items.isEmpty) return null;

      final movies = <Movie>[];
      for (final item in res.items.take(24)) {
        movies.add(
          Movie(
            id: item.id,
            type: item.type,
            name: item.name,
            poster: item.poster,
            year: item.year,
            addonBaseUrl: 'https://v3-cinemeta.strem.io',
          ),
        );
      }

      if (movies.isEmpty) return null;

      final section = MovieSection(
        title: 'Recommended for You (Trakt)',
        subtitle: 'Personalized based on your Trakt watch history',
        contentType: 'mixed',
        addonBaseUrl: 'https://v3-cinemeta.strem.io',
        catalog: AddonCatalog(
          type: 'mixed',
          id: 'trakt_recommendations',
          name: 'Trakt Recommendations',
          genres: const [],
          supportsSearch: false,
          supportsSkip: false,
        ),
        movies: movies,
      );

      _cachedTraktSection = section;
      return section;
    } catch (e) {
      debugPrint('[HomePageSettings] Trakt recommendations failed: $e');
      return null;
    }
  }

  /// Home rail heading and sub-line for a Trakt public list. The See-All labels
  /// are too vague to stand alone on Home ("Trending" reads as trending on the
  /// platform; here it means trending this week).
  static ({String title, String subtitle}) _publicSectionText(
    TraktSeeAllList list,
  ) {
    switch (list) {
      case TraktSeeAllList.trending:
        return (
          title: 'Trending This Week',
          subtitle: 'What Trakt viewers are watching right now',
        );
      case TraktSeeAllList.popular:
        return (
          title: 'Popular Now',
          subtitle: 'Most-watched titles across Trakt',
        );
      case TraktSeeAllList.anticipated:
        return (
          title: 'Coming Soon',
          subtitle: 'Most anticipated upcoming releases',
        );
      case TraktSeeAllList.continueWatching:
      case TraktSeeAllList.watchlist:
      case TraktSeeAllList.history:
      case TraktSeeAllList.collection:
      case TraktSeeAllList.ratings:
      case TraktSeeAllList.recommendations:
        return (title: list.label, subtitle: 'From Trakt');
    }
  }

  /// Builds a Home rail from one of Trakt's public lists — trending, popular or
  /// anticipated.
  ///
  /// These three need no OAuth token ([TraktService] routes them through the
  /// api-key-only public endpoint), so unlike [fetchTraktRecommendationsSection]
  /// this works with Trakt signed out. Returns null for a non-public [list] or
  /// when the fetch failed or came back empty, so callers skip the rail
  /// instead of rendering an empty one.
  static Future<MovieSection?> fetchTraktPublicSection(
    TraktSeeAllList list, {
    bool forceRefresh = false,
  }) async {
    if (!list.isPublic) return null;

    final cached = _cachedTraktPublicSections[list];
    if (!forceRefresh && cached != null) return cached;

    try {
      final res = await TraktListSource.instance.loadList(
        TraktListChoice.builtin(list),
      );
      if (res.items.isEmpty) return null;

      final movies = <Movie>[];
      for (final item in res.items.take(24)) {
        movies.add(_movieFromStremioMeta(item));
      }

      if (movies.isEmpty) return null;

      final text = _publicSectionText(list);

      final section = MovieSection(
        title: text.title,
        subtitle: text.subtitle,
        contentType: 'mixed',
        addonBaseUrl: 'https://v3-cinemeta.strem.io',
        catalog: AddonCatalog(
          type: 'mixed',
          id: 'trakt_${list.apiValue}',
          name: text.title,
          genres: const [],
          supportsSearch: false,
          supportsSkip: false,
        ),
        movies: movies,
      );

      _cachedTraktPublicSections[list] = section;
      return section;
    } catch (e) {
      debugPrint('[HomePageSettings] Trakt ${list.apiValue} failed: $e');
      return null;
    }
  }

  static Movie _movieFromStremioMeta(StremioMeta meta) => Movie(
        id: meta.id,
        type: meta.type,
        name: meta.name,
        poster: meta.poster,
        year: meta.year,
        addonBaseUrl: 'https://v3-cinemeta.strem.io',
      );

  /// Fetches Simkl recommendations if Simkl is authenticated and enabled
  static Future<MovieSection?> fetchSimklRecommendationsSection({
    bool forceRefresh = false,
  }) async {
    if (!enableSimklRecommendations.value) return null;
    if (!await SimklService.instance.isAuthenticated()) return null;

    if (!forceRefresh && _cachedSimklSection != null) {
      return _cachedSimklSection;
    }

    try {
      final res = await SimklListSource.instance.loadList(
        SimklSeeAllList.topRated,
      );

      if (res.items.isEmpty) return null;

      final movies = <Movie>[];
      for (final item in res.items.take(24)) {
        movies.add(
          Movie(
            id: item.id,
            type: item.type,
            name: item.name,
            poster: item.poster,
            year: item.year,
            addonBaseUrl: 'https://v3-cinemeta.strem.io',
          ),
        );
      }

      if (movies.isEmpty) return null;

      final section = MovieSection(
        title: 'Recommended for You (Simkl)',
        subtitle: 'Top-rated & personalized suggestions from Simkl',
        contentType: 'mixed',
        addonBaseUrl: 'https://v3-cinemeta.strem.io',
        catalog: AddonCatalog(
          type: 'mixed',
          id: 'simkl_recommendations',
          name: 'Simkl Recommendations',
          genres: const [],
          supportsSearch: false,
          supportsSkip: false,
        ),
        movies: movies,
      );

      _cachedSimklSection = section;
      return section;
    } catch (e) {
      debugPrint('[HomePageSettings] Simkl recommendations failed: $e');
      return null;
    }
  }
}
