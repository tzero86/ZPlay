import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/addon/addon.dart';
import '../../models/movie/movie.dart';
import '../../models/movie/movie_section.dart';
import '../../models/stream/stream_model.dart';
import '../../services/addon/addon_manager.dart';
import '../../services/cloudstream/cloudstream_manager.dart';
import '../../services/home/home_page_settings.dart';
import '../../services/metadata/metadata_service.dart';
import '../../services/layout/form_factor.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/movie/movie_slider_section.dart';
import '../../widgets/search/magnet_files_view.dart';
import '../ai/wewatch_quiz_page.dart';
import '../player/player_screen.dart';

/// What a finished search should show.
enum SearchOutcome {
  /// Every source answered and none of them matched the query.
  noResults,

  /// Every source answered and at least one matched.
  complete,

  /// Some sources answered and some threw: the list is real but partial.
  incomplete,

  /// Nothing came back because sources threw. The catalog is not proven empty.
  failed,
}

/// What a finished search should show, given what came back and what threw.
/// Top level and pure so the three-way split is decided in exactly one place
/// and can be exercised without a widget tree, a network, or an addon install.
SearchOutcome classifySearchResult({
  required int resultCount,
  required int failureCount,
}) {
  if (failureCount == 0) {
    return resultCount == 0 ? SearchOutcome.noResults : SearchOutcome.complete;
  }
  return resultCount == 0 ? SearchOutcome.failed : SearchOutcome.incomplete;
}

/// Which legs of a search died, and how many sources the run expected to hear
/// back from. The page used to throw all of this away, so a dead addon, an
/// expired CloudStream runtime and being offline all rendered the same screen
/// as a title that does not exist. Search is the only route to a title the
/// user already has in mind, so that silence cost far more than the failure.
class SearchFailureLedger {
  /// Leg names in the order they threw, for the error copy.
  final List<String> sourceErrors = [];

  /// How many sources this run queried, the denominator in "X of Y".
  int searchedSourceCount = 0;

  int get failedSources => sourceErrors.length;

  /// Clearing the field abandons the query, so its failures must not survive
  /// into the next search and be blamed on the next title.
  void reset() {
    sourceErrors.clear();
    searchedSourceCount = 0;
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounce;
  bool _isLoading = false;
  List<MovieSection> _results = [];
  String _lastQuery = '';

  /// Synthetic catalog id for the keyless title rail. There is no addon
  /// catalog behind it, so its slider hides See All.
  static const String _titleRailCatalogId = 'imdb_titles';

  /// Each leg is one source the user believes is answering. The addon leg
  /// fans out internally, so a dead addon surfaces as one failure here.
  static const int _addonSearchSourceCount = 1;
  static const int _cloudStreamSearchSourceCount = 1;
  static const int _titleSearchSourceCount = 1;

  final SearchFailureLedger _ledger = SearchFailureLedger();

  bool _isMagnetMode = false;
  String _magnetQuery = '';

  /// The legs a run can hit, and so the denominator the user is shown. A leg
  /// with nothing to search (no CloudStream extension enabled) is not a source
  /// anyone expects an answer from, so it stays out of the count.
  static int _searchedSourceTotalFor({required String query}) {
    if (query.isEmpty) return 0;
    return _titleSearchSourceCount +
        _addonSearchSourceCount +
        (CloudStreamManager.instance.activeExtensions.isNotEmpty
            ? _cloudStreamSearchSourceCount
            : 0);
  }

  SearchOutcome get _outcome => classifySearchResult(
    resultCount: _results.length,
    failureCount: _ledger.failedSources,
  );

  void _recordSourceFailure(String source, Object error) {
    debugPrint('[SearchPage] $source search error: $error');
    // A leg that fails late must not resurrect a query the user has moved on
    // from, and setState after dispose throws.
    if (!mounted) return;
    setState(() {
      _ledger.sourceErrors.add(source);
    });
  }

  /// The service callbacks fire from code that knows nothing about the current
  /// query, so a failure arriving after the user has moved on would be blamed
  /// on the new title. Each leg gets a recorder pinned to its own query.
  void Function(String source, Object error) _sourceErrorRecorderFor(
    String query,
  ) {
    return (source, error) {
      if (!mounted || _lastQuery != query) return;
      _recordSourceFailure(source, error);
    };
  }

  List<String> _searchHistory = [];
  List<MovieSection> _suggestedSections = [];
  bool _isLoadingSuggestions = true;

  /// How far the body has scrolled, as 0..1 for the search band's tint.
  ///
  /// The band carries the field and nothing else, so at the top of the page it
  /// is transparent and the canvas shows through. Results scroll *under* it, so
  /// past a nudge it has to paint or a rail heading would draw across the field
  /// unreadably - the same failure Home's glass bar tints its way out of, and
  /// deliberately the same distance (`AppShell._navBlendThreshold`), so the
  /// shell's own bar and this one settle together.
  ///
  /// A value, not an animation, and it rebuilds the band's decoration only: the
  /// field inside is built once and handed to the [ValueListenableBuilder] as
  /// its `child`, so typing is never rebuilt by scrolling and nothing moves.
  static const double _bandBlendThreshold = 32.0;
  final ValueNotifier<double> _bandTint = ValueNotifier<double>(0);

  /// The body's own scroll feeds the band, because the band is inside the
  /// `appBar` slot and cannot listen to it from there.
  bool _onBodyScroll(ScrollNotification notification) {
    // Vertical only. The rails inside the results are horizontal scrollables
    // whose offset says nothing about how far the page has travelled under the
    // band - a rail nudged one poster to the right would otherwise drag the
    // band's tint to full as if the page had scrolled a whole screen.
    if (notification.metrics.axis != Axis.vertical) return false;
    final t = (notification.metrics.pixels / _bandBlendThreshold)
        .clamp(0.0, 1.0);
    if ((_bandTint.value - t).abs() > 0.01) _bandTint.value = t;
    // Nobody else's business: the field is the only consumer.
    return false;
  }

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
    _loadSuggestions();
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('search_history') ?? [];
    if (mounted) {
      setState(() {
        _searchHistory = history;
      });
    }
  }

  Future<void> _saveSearchHistory(String query) async {
    if (query.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('search_history') ?? [];
    history.remove(query);
    history.insert(0, query);
    if (history.length > 10) history.removeLast();
    await prefs.setStringList('search_history', history);
    if (mounted) {
      setState(() {
        _searchHistory = history;
      });
    }
  }

  Future<void> _removeSearchHistory(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('search_history') ?? [];
    history.remove(query);
    await prefs.setStringList('search_history', history);
    if (mounted) {
      setState(() {
        _searchHistory = history;
      });
    }
  }

  Future<void> _clearSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('search_history');
    if (mounted) {
      setState(() {
        _searchHistory = [];
      });
    }
  }

  Future<void> _loadSuggestions() async {
    try {
      final sections = await AddonManager.instance.fetchAllHomeSections();
      if (mounted) {
        setState(() {
          _suggestedSections = sections.take(4).toList();
          _isLoadingSuggestions = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingSuggestions = false;
        });
      }
    }
  }

  static bool _isMagnetLink(String text) {
    final trimmed = text.trim();
    if (trimmed.toLowerCase().startsWith('magnet:')) return true;
    if (RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(trimmed)) return true;
    if (RegExp(r'^[a-zA-Z2-7]{32}$').hasMatch(trimmed)) return true;
    return false;
  }

  static bool _isStreamLink(String text) {
    final trimmed = text.trim();
    final lower = trimmed.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return false;
    }
    return true;
  }

  void _playDirectStream(String url) {
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    String title = 'Direct Stream';
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last;
      if (last.isNotEmpty) {
        title = Uri.decodeComponent(last);
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          source: StreamSource(
            name: 'Direct Stream',
            title: title,
            url: trimmed,
            addonName: 'Direct Stream',
          ),
          title: title,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    _bandTint.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results.clear();
        _isLoading = false;
        _lastQuery = '';
        _isMagnetMode = false;
        _magnetQuery = '';
        // Clearing the field abandons the query, so its failures must not
        // survive to be shown against the next one.
        _ledger.reset();
      });
      return;
    }

    if (_isStreamLink(trimmed)) {
      _playDirectStream(trimmed);
      return;
    }

    if (_isMagnetLink(trimmed)) {
      setState(() {
        _isMagnetMode = true;
        _magnetQuery = trimmed;
        _isLoading = false;
        _results.clear();
      });
      return;
    } else if (_isMagnetMode) {
      setState(() {
        _isMagnetMode = false;
        _magnetQuery = '';
      });
    }

    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (trimmed != _lastQuery) {
        _performSearch(trimmed);
      }
    });
  }

  void _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    if (_isStreamLink(trimmed)) {
      _playDirectStream(trimmed);
      return;
    }

    if (_isMagnetLink(trimmed)) {
      setState(() {
        _isMagnetMode = true;
        _magnetQuery = trimmed;
        _isLoading = false;
        _results.clear();
      });
      return;
    }

    _saveSearchHistory(trimmed);

    setState(() {
      _isLoading = true;
      _lastQuery = trimmed;
      _isMagnetMode = false;
      _results = [];
      // Failures belong to the query that produced them; carrying them into
      // the next search would blame the new query for the old outage.
      _ledger.reset();
      _ledger.searchedSourceCount = _searchedSourceTotalFor(query: trimmed);
    });

    final currentQuery = trimmed;

    void addSection(MovieSection section, {bool isCloudStream = false}) {
      if (!mounted || _lastQuery != currentQuery) return;
      if (section.movies.isEmpty) return;

      // Prevent duplicate sections
      final exists = _results.any(
        (s) =>
            s.title == section.title &&
            s.subtitle == section.subtitle &&
            s.addonBaseUrl == section.addonBaseUrl,
      );
      if (exists) return;

      setState(() {
        if (!isCloudStream &&
            (section.addonBaseUrl.contains('cinemeta') ||
                section.subtitle.toLowerCase().contains('cinemeta'))) {
          // Prioritize Cinemeta at the top
          _results.insert(0, section);
        } else {
          _results.add(section);
        }
      });
    }

    try {
      // 1. Search Stremio Addons with dynamic streaming
      final addonSearch = AddonManager.instance
          .searchAll(
            currentQuery,
            onSectionResult: (section) {
              addSection(section, isCloudStream: false);
            },
            onSourceError: _sourceErrorRecorderFor(currentQuery),
          )
          .catchError((e) {
            _recordSourceFailure('Addons', e);
            return <MovieSection>[];
          });

      // 2. Search CloudStream Extensions with dynamic streaming
      final csSearch =
          (CloudStreamManager.instance.activeExtensions.isNotEmpty
                  ? CloudStreamManager.instance.searchAcrossExtensions(
                      currentQuery,
                      onProviderResult: (providerName, items) {
                        if (!mounted || _lastQuery != currentQuery) return;
                        if (items.isEmpty) return;

                        final movies = <Movie>[];
                        for (final item in items) {
                          final title =
                              item['title']?.toString() ??
                              item['name']?.toString() ??
                              'Unknown';
                          final rawUrl = item['url']?.toString() ?? '';
                          final sourceId =
                              item['_sourceId']?.toString() ??
                              'cs_${providerName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}';
                          final cover =
                              item['cover']?.toString() ??
                              item['poster']?.toString() ??
                              item['image']?.toString();
                          final isSeries =
                              item['type'] == 1 ||
                              item['type']?.toString().toLowerCase().contains(
                                    'series',
                                  ) ==
                                  true ||
                              item['type']?.toString().toLowerCase().contains(
                                    'tv',
                                  ) ==
                                  true ||
                              (item['extraData'] is Map &&
                                  (item['extraData'] as Map)['type']
                                          ?.toString()
                                          .toLowerCase()
                                          .contains('series') ==
                                      true);

                          movies.add(
                            Movie(
                              id: 'cloudstream:$sourceId:${Uri.encodeComponent(rawUrl)}',
                              name: title,
                              poster: cover,
                              year:
                                  item['year']?.toString() ??
                                  (item['extraData'] is Map
                                      ? (item['extraData'] as Map)['year']
                                            ?.toString()
                                      : null),
                              type: isSeries ? 'series' : 'movie',
                              addonBaseUrl: 'cloudstream',
                            ),
                          );
                        }

                        if (movies.isNotEmpty) {
                          final section = MovieSection(
                            title: 'CloudStream • $providerName',
                            subtitle: 'CloudStream Extension',
                            contentType: 'movie',
                            addonBaseUrl: 'cloudstream',
                            catalog: AddonCatalog(
                              type: 'movie',
                              id: 'cs_$providerName',
                              name: providerName,
                            ),
                            movies: movies,
                          );
                          addSection(section, isCloudStream: true);
                        }
                      },
                      onSourceError: _sourceErrorRecorderFor(currentQuery),
                    )
                  : Future.value(<String, List<Map<String, dynamic>>>{}))
              .catchError((e) {
                _recordSourceFailure('CloudStream', e);
                return <String, List<Map<String, dynamic>>>{};
              });

      // 3. Keyless title lookup. An install whose only installed addon is
      // Cinemeta has no search catalog left, so without this the page would
      // report no results for every query.
      final titleSearch =
          MetadataService.suggestionSearch(
                query: currentQuery,
                onSourceError: _sourceErrorRecorderFor(currentQuery),
              )
              .then((movies) {
                addSection(
                  MovieSection(
                    title: 'Titles',
                    subtitle: 'IMDb suggestions',
                    contentType: 'movie',
                    addonBaseUrl: 'https://v3-cinemeta.strem.io',
                    catalog: AddonCatalog(
                      type: 'movie',
                      id: _titleRailCatalogId,
                      name: 'Titles',
                    ),
                    movies: movies,
                  ),
                );
              })
              .catchError((e) {
                _recordSourceFailure('Title lookup', e);
              });

      await Future.wait([addonSearch, csSearch, titleSearch]);
    } catch (e) {
      // A leg that throws synchronously, or a Future.wait rejection that
      // outran the handlers above, is still a source that did not answer.
      _recordSourceFailure('Search', e);
    }

    if (mounted && _lastQuery == currentQuery) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      _searchController.text = text;
      _onSearchChanged(text);
      if (!_isMagnetLink(text) && !_isStreamLink(text)) {
        _performSearch(text);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.bg,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 10),
        // The band is **transparent at rest and tinted once results scroll
        // under it** - no opaque `tokens.bg` fill and no bottom hairline.
        //
        // An opaque band pinned above the content is the "different app" seam:
        // the shell's nav bar blends into whatever the page paints beneath it,
        // and a page that draws its own surface across the top re-creates the
        // boundary the bar just stopped drawing. The field itself is a
        // `tokens.surface` box, so it stays legible over the canvas; the tint
        // exists for the gutter beside it, where a scrolling rail would
        // otherwise slide past the field's edge.
        //
        // `Material`'s `AppBar` is deliberately not used here. It is a
        // `Focus`-hosting widget whose toolbar is excluded from directional
        // traversal, so a `TextField` placed in `appBar` is never a candidate for
        // a D-pad press: the field renders, the user can see it, and a remote
        // cannot reach it. Verified on a Chromecast with Google TV - the focus
        // tree listed 21 focusables and the field was not one of them, so
        // neither `right` nor the centre button could put a cursor in it and a
        // television user could not search at all. `PreferredSize` is a plain
        // layout contract and imposes nothing on focus.
        child: ValueListenableBuilder<double>(
          valueListenable: _bandTint,
          // Fades the fill in behind the field over the first
          // [_bandBlendThreshold] of scroll and leaves the field itself alone:
          // it is the `child`, built once, so no scroll pixel rebuilds it.
          builder: (context, tint, child) => DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.bg.withValues(alpha: 0.82 * tint),
            ),
            child: child,
          ),
          child: Padding(
            padding: EdgeInsets.only(top: topPadding, bottom: ZplaySpacing.s8),
            child: Row(
              children: [
                const SizedBox(width: ZplaySpacing.s8),
                // Search is a shell slot, so it usually has nothing to pop back to
                // and popping would dismiss the shell itself. Keeping the gate means a
                // pushed SearchPage still shows the button and neither state shifts
                // the field, since the inset above is unconditional.
                if (Navigator.of(context).canPop())
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
                    color: tokens.textPrimary,
                    onPressed: () => Navigator.pop(context),
                  ),
                Expanded(
                  // The prototype caps the field at 540 dp rather than letting it
                  // run the full width of the canvas: a search box that wide on a
                  // 960 dp television reads as a banner, and the caret ends up a
                  // screen away from the icon it belongs to.
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 540),
                      child: Container(
                        width: double.infinity,
                        height: 42,
                        decoration: BoxDecoration(
                          color: tokens.surface,
                          borderRadius: ZplayRadius.smAll,
                          border: Border.fromBorderSide(tokens.hairline),
                        ),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _focusNode,
                          // Never on a television.
                          //
                          // A focused text field installs
                          // `DirectionalFocusAction.forTextField()` (editable_text.dart),
                          // which deliberately ignores arrow intents and keeps them
                          // for caret movement inside the field. So a field that takes
                          // focus on arrival is a trap: the remote can type, but every
                          // arrow press is consumed moving a caret through empty text
                          // and focus never leaves, so the whole catalogue behind the
                          // field is unreachable without a pointer. Verified on a
                          // Chromecast with Google TV - down and up did nothing at all.
                          //
                          // On a pointer device autofocus is the expected behaviour,
                          // so it is kept there. The rail's own autofocus means the
                          // remote still starts from a visible, ringed row, and the
                          // user reaches the field by selecting Search or by pressing
                          // right from it.
                          autofocus:
                              FormFactorService.of(context) !=
                              FormFactor.television,
                          style: ZplayType.subtitle.toStyle(
                            color: tokens.textPrimary,
                          ),
                          textInputAction: TextInputAction.search,
                          onChanged: _onSearchChanged,
                          onSubmitted: _performSearch,
                          decoration: InputDecoration(
                            // "or paste links" is advice for a keyboard. A
                            // television has no clipboard on the remote, so it
                            // names an action the viewer cannot take.
                            hintText: DeviceProfile.isTelevision
                                ? 'Search for a movie or series'
                                : 'Search movies, series, or paste links',
                            hintStyle: ZplayType.body.toStyle(
                              color: tokens.textDisabled,
                            ),
                            border: InputBorder.none,
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 19,
                              color: tokens.textMuted,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: ZplaySpacing.s12,
                              vertical: ZplaySpacing.s12,
                            ),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_searchController.text.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                    color: tokens.textSecondary,
                                    splashRadius: 18,
                                    onPressed: () {
                                      _searchController.clear();
                                      _onSearchChanged('');
                                    },
                                  )
                                else ...[
                                  ValueListenableBuilder<bool>(
                                    valueListenable:
                                        HomePageSettings.enableAiQuiz,
                                    builder: (context, aiQuizEnabled, _) {
                                      if (!aiQuizEnabled) {
                                        return const SizedBox.shrink();
                                      }
                                      return IconButton(
                                        icon: Icon(
                                          Icons.auto_awesome_rounded,
                                          size: 17,
                                          color: AppThemeService
                                              .currentPalette
                                              .value
                                              .primaryColor,
                                        ),
                                        tooltip: 'AI Taste Quiz',
                                        splashRadius: 18,
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const WeWatchQuizPage(),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.content_paste_rounded,
                                      size: 17,
                                    ),
                                    tooltip: 'Paste from clipboard',
                                    color: tokens.textSecondary,
                                    splashRadius: 18,
                                    onPressed: _pasteFromClipboard,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // The body sits on Home's canvas - the shared ambient background - instead
      // of a flat `tokens.bg` surface, and it feeds the band's tint from its own
      // scroll. The listener has to be here rather than in the band: the two are
      // different slots of this `Scaffold`, and the band cannot see a
      // notification raised by a scrollable it is not an ancestor of.
      body: NotificationListener<ScrollNotification>(
        onNotification: _onBodyScroll,
        child: AnimatedAmbientBackground(
          child: Stack(
            children: [
              if (_isMagnetMode && _magnetQuery.isNotEmpty)
                MagnetFilesView(key: ValueKey(_magnetQuery), magnet: _magnetQuery)
              else if (_isLoading && _results.isEmpty)
                Center(
                  child: CircularProgressIndicator(
                    color: AppThemeService.currentPalette.value.primaryColor,
                  ),
                )
              else if (!_isLoading && _lastQuery.isNotEmpty && _results.isEmpty)
                _buildSearchEmptyState(_outcome)
              else if (_results.isNotEmpty)
                Column(
                  children: [
                    if (_outcome == SearchOutcome.incomplete)
                      _buildFailureLedger(topPadding),
                    Expanded(
                      child: ListView.builder(
                        clipBehavior: Clip.none,
                        padding: EdgeInsets.only(
                          top: topPadding + kToolbarHeight + ZplaySpacing.s40,
                          bottom:
                              ZplaySpacing.s40 +
                              MediaQuery.paddingOf(context).bottom,
                        ),
                        physics: const BouncingScrollPhysics(),
                        itemCount: _results.length + (_isLoading ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index < _results.length) {
                            final sec = _results[index];
                            final slider = MovieSliderSection(
                              key: ValueKey(
                                '${sec.addonBaseUrl}_${sec.catalog.id}_${sec.subtitle}',
                              ),
                              section: sec,
                              // Only rails backed by a real addon catalog can expand.
                              // The titles rail is synthetic, and the CloudStream rails
                              // carry a cs_* id no addon serves, so See All would open a
                              // CatalogPage that fetches nothing.
                              showSeeAll:
                                  sec.catalog.id != _titleRailCatalogId &&
                                  !sec.catalog.id.startsWith('cs_'),
                            );

                            // The Cinemeta leg is pinned above the community legs, so
                            // it is tagged as the spine rather than left to look like
                            // one more addon's rail. `_performSearch` inserts it at
                            // index 0; this only names what the ordering already does.
                            final isSpine =
                                sec.addonBaseUrl.contains('cinemeta') ||
                                sec.subtitle.toLowerCase().contains('cinemeta');
                            if (!isSpine) return slider;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    ZplaySpacing.s16,
                                    0,
                                    ZplaySpacing.s16,
                                    ZplaySpacing.s4,
                                  ),
                                  child: _PinnedSpineTag(),
                                ),
                                slider,
                              ],
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: ZplaySpacing.s24,
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppThemeService
                                          .currentPalette
                                          .value
                                          .primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: ZplaySpacing.s8),
                                  Text(
                                    'Searching more sources...',
                                    style: ZplayType.bodySmall.toStyle(
                                      color: tokens.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                )
              else
                _buildDiscoveryEmptyState(topPadding),

              if (_isLoading && _results.isNotEmpty)
                Positioned(
                  top: topPadding + kToolbarHeight + ZplaySpacing.s8,
                  left: 0,
                  right: 0,
                  child: SizedBox(
                    height: 2,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppThemeService.currentPalette.value.primaryColor,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The finished-but-empty result area. A dead source and a real miss are
  /// different answers, so they get different screens: only the genuine miss
  /// may claim the title does not exist.
  Widget _buildSearchEmptyState(SearchOutcome outcome) {
    final tokens = context.tokens;

    switch (outcome) {
      case SearchOutcome.failed:
        final total = _ledger.searchedSourceCount;
        final errors = _ledger.sourceErrors;
        final failed = errors.length > total ? total : errors.length;
        return ErrorView(
          title: 'Search could not reach its sources',
          error:
              '$failed of $total sources did not respond'
              '${errors.isEmpty ? '' : ': ${errors.join(', ')}'}. '
              'A dead addon or an expired provider runtime is fixed in Addons.',
          onRetry: () => _performSearch(_lastQuery),
        );
      case SearchOutcome.noResults:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 64,
                color: tokens.textDisabled,
              ),
              const SizedBox(height: ZplaySpacing.s16),
              Text(
                'No results for "$_lastQuery"',
                style: ZplayType.subtitle.toStyle(color: tokens.textSecondary),
              ),
            ],
          ),
        );
      case SearchOutcome.complete:
      case SearchOutcome.incomplete:
        // Unreachable: both need at least one result, and this widget is only
        // reached when _results is empty.
        return const SizedBox.shrink();
    }
  }

  /// The Failure Ledger: names the sources that died while the rest of the
  /// search carried on.
  ///
  /// A partial list presented as a complete one is its own lie, so the failed
  /// legs are named above the results instead of the results being taken away.
  /// The names are real: `AddonManager.searchAll` reports the addon's own name,
  /// `CloudStreamManager.searchExtensions` the extension's, and the title leg
  /// reports itself, so this can say *which* provider is down rather than "some
  /// sources".
  ///
  /// Two things it deliberately does not claim. A status code: the services
  /// hand back the thrown error and the ledger keeps only the leg name, so
  /// printing a `504` would be inventing a number the app never saw. And a
  /// "N of M providers" count: `searchedSourceCount` counts legs (title lookup,
  /// addons, CloudStream) while `sourceErrors` counts the addons and extensions
  /// inside those legs, so subtracting one from the other would produce a
  /// number that is simply wrong - two dead addons would read as two dead legs.
  Widget _buildFailureLedger(double topPadding) {
    final tokens = context.tokens;
    final failed = _ledger.sourceErrors;

    return Padding(
      padding: EdgeInsets.only(
        top: topPadding + kToolbarHeight + ZplaySpacing.s8,
        left: ZplaySpacing.s16,
        right: ZplaySpacing.s16,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ZplaySpacing.s12,
          vertical: ZplaySpacing.s8,
        ),
        decoration: BoxDecoration(
          color: tokens.danger.withValues(alpha: 0.12),
          borderRadius: ZplayRadius.smAll,
          border: Border.all(color: tokens.danger.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: tokens.danger,
            ),
            const SizedBox(width: ZplaySpacing.s8),
            Expanded(
              child: Text(
                'Partial Source Failure: ${failed.join(", ")} '
                'did not respond. Other sources answered normally, so the '
                'results below are real but incomplete.',
                style: ZplayType.bodySmall.toStyle(color: tokens.danger),
              ),
            ),
            const SizedBox(width: ZplaySpacing.s12),
            FocusableCard(
              onTap: () => _performSearch(_lastQuery),
              builder: (context, state) => CardFocusRing(
                focused: state.focused,
                radius: ZplayRadius.xsAll,
                child: Container(
                  // A television has to be able to hit this with a D-pad, and
                  // the prototype's chip is 24 dp tall. The floor applies there
                  // only; on a pointer device the compact chip is the design.
                  constraints: BoxConstraints(
                    minHeight: DeviceProfile.isTelevision ? 48 : 0,
                    minWidth: 48,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZplaySpacing.s8,
                    vertical: ZplaySpacing.s4,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.danger.withValues(alpha: 0.2),
                    borderRadius: ZplayRadius.xsAll,
                  ),
                  child: Text(
                    'Retry',
                    style: ZplayType.caption.toStyle(color: tokens.textPrimary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveryEmptyState(double topPadding) {
    final tokens = context.tokens;

    return ListView(
      clipBehavior: Clip.none,
      padding: EdgeInsets.only(
        top: topPadding + kToolbarHeight + ZplaySpacing.s12,
        bottom: ZplaySpacing.s40 + MediaQuery.paddingOf(context).bottom,
      ),
      physics: const BouncingScrollPhysics(),
      children: [
        // Recent Searches
        if (_searchHistory.isNotEmpty) ...[
          const SizedBox(height: ZplaySpacing.s8),
          SectionHeader(
            title: 'Recent Searches',
            // The quiet page-level action the design contract asks for: a
            // ringed [FocusableCard], not a bare text button - it used to be a
            // focusable with no indicator at all, which a remote could reach
            // with nothing on screen saying where it was.
            trailing: FocusableCard(
              onTap: _clearSearchHistory,
              builder: (context, state) => CardFocusRing(
                focused: state.focused,
                radius: ZplayRadius.smAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZplaySpacing.s8,
                    vertical: ZplaySpacing.s8,
                  ),
                  child: Text(
                    'Clear All',
                    style: ZplayType.label.toStyle(
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: ZplaySpacing.s8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s16),
            child: Wrap(
              spacing: ZplaySpacing.s8,
              runSpacing: ZplaySpacing.s8,
              children: _searchHistory
                  .map((query) => _buildHistoryChip(query, tokens))
                  .toList(),
            ),
          ),
          const SizedBox(height: ZplaySpacing.s12),
        ],

        // Discover / Trending Content
        if (_suggestedSections.isNotEmpty) ...[
          const SizedBox(height: ZplaySpacing.s8),
          // One quiet section title rather than an eyebrow: the same
          // [SectionHeader] the rails under it use, so the group label and the
          // rail labels are one vocabulary instead of two.
          const SectionHeader(title: 'Trending & Suggested'),
          const SizedBox(height: ZplaySpacing.s8),
          ..._suggestedSections.map((sec) => MovieSliderSection(section: sec)),
        ] else if (_isLoadingSuggestions) ...[
          const SizedBox(height: ZplaySpacing.s32),
          Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppThemeService.currentPalette.value.primaryColor,
            ),
          ),
        ],

        // A void. With no search history and no suggestions, this rendered as a
        // black rectangle with nothing in it, which on a television reads as a
        // broken screen rather than an empty one - and there is no keyboard
        // there to make the cause obvious.
        if (_searchHistory.isEmpty &&
            _suggestedSections.isEmpty &&
            !_isLoadingSuggestions) ...[
          const SizedBox(height: ZplaySpacing.s48),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 44,
                  color: tokens.textDisabled,
                ),
                const SizedBox(height: ZplaySpacing.s16),
                Text(
                  'Nothing to suggest yet',
                  style: ZplayType.subtitle.toStyle(
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: ZplaySpacing.s8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    'Search for a title above, or connect an addon in Settings to have something to search.',
                    textAlign: TextAlign.center,
                    style: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// One recent search, as the app's quiet pill rather than a Material
  /// [InputChip].
  ///
  /// A chip is a control a remote has to be able to land on, so it is a
  /// [FocusableCard] wearing [CardFocusRing] like every other one, and it paints
  /// the Browse pill's resting rule - a borderless wash - so a row of them is
  /// not a row of boxes. `InputChip` also carried *two* actions on one focus
  /// node (run the query, delete the entry), which is why a remote could never
  /// delete a single entry: only the select action was reachable. The delete
  /// stays where it always effectively was - a pointer affordance beside the
  /// label - and `Clear All` above the row is the remote's way to empty it.
  Widget _buildHistoryChip(String query, ZplayTokens tokens) {
    return FocusableCard(
      onTap: () {
        _searchController.text = query;
        _performSearch(query);
      },
      builder: (context, state) => CardFocusRing(
        focused: state.focused,
        radius: ZplayRadius.fullAll,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            ZplaySpacing.s12,
            ZplaySpacing.s8,
            ZplaySpacing.s8,
            ZplaySpacing.s8,
          ),
          decoration: BoxDecoration(
            color: tokens.borderDefault,
            borderRadius: ZplayRadius.fullAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                query,
                style: ZplayType.label.toStyle(color: tokens.textEmphasis),
              ),
              const SizedBox(width: ZplaySpacing.s4),
              GestureDetector(
                onTap: () => _removeSearchHistory(query),
                child: Padding(
                  padding: const EdgeInsets.all(ZplaySpacing.s2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: tokens.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The `PINNED SPINE` tag above the canonical metadata rail.
///
/// Cinemeta is the one leg that answers for every install and the rail the
/// other legs are ranked against, so it is labelled rather than left looking
/// like one more addon's results. Not a control: nothing to focus, so it
/// carries no focus node.
///
/// One accent line of type, no fill and no box. It used to be a
/// `tokens.surfaceRaised` chip with a radius, which made the label read as a
/// button the remote could not reach - and the page's only other boxes were
/// the results, so the tag competed with them for attention it did not need.
class _PinnedSpineTag extends StatelessWidget {
  const _PinnedSpineTag();

  @override
  Widget build(BuildContext context) {
    return Text(
      'PINNED SPINE',
      style: ZplayType.overline.toStyle(color: context.tokens.accent),
    );
  }
}
