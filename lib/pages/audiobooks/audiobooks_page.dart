import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/audiobook/audiobook_model.dart';
import '../../services/layout/form_factor.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../services/audiobook/audiobook_progress_service.dart';
import '../../services/audiobook/audiobook_scraper_service.dart';
import '../../services/audiobook/audiobook_settings.dart';
import '../../services/audiobook/paper2audio_service.dart';
import '../../services/audiobook/custom_audiobook_service.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/hero_meta_line.dart';
import '../../widgets/common/pill_button.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/common/segmented_tabs.dart';
import '../../widgets/common/slider_arrow.dart';
import '../../widgets/common/tab_strip.dart';
import '../../widgets/player/player_glass.dart';
import '../settings/appearance/audiobook_settings_page.dart';
import 'audiobook_detail_page.dart';
import 'audiobook_player_screen.dart';
import 'audiobook_route_transitions.dart';
import 'generate_audiobook_screen.dart';
import '../../services/storage/app_image_cache.dart';

class AudiobooksPage extends StatefulWidget {
  const AudiobooksPage({super.key});

  @override
  State<AudiobooksPage> createState() => _AudiobooksPageState();
}

class _AudiobooksPageState extends State<AudiobooksPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _continueScrollController = ScrollController();

  bool _isSearching = false;
  List<Audiobook> _searchResults = [];
  List<AudiobookProgress> _continueListeningList = [];
  String? _errorMessage;
  int _searchSequence = 0;
  String _selectedCategory = 'All';

  /// The Continue Listening rail's own hover and scroll-edge state. `right`
  /// starts true, because a rail that has just been mounted at offset 0 always
  /// has somewhere to go and the arrows would otherwise stay hidden until the
  /// first scroll event arrived.
  bool _isHoveringContinueRail = false;
  bool _canScrollContinueLeft = false;
  bool _canScrollContinueRight = true;

  final List<String> _categories = [
    'All',
    'Fantasy',
    'Sci-Fi',
    'Mystery',
    'Thriller',
    'Non-Fiction',
    'Self-Help',
    'Horror',
    'Romance',
    'Adventure',
    'Classics',
  ];

  @override
  void initState() {
    super.initState();
    AudiobookSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onSettingsChanged);
    Paper2AudioService.instance.jobs.addListener(_onSettingsChanged);
    CustomAudiobookService.instance.audiobooks.addListener(_onSettingsChanged);

    Paper2AudioService.instance.getJobs();
    CustomAudiobookService.instance.ensureLoaded();

    _continueScrollController.addListener(_updateContinueScrollArrows);
    _loadContinueListening();
    _performSearch('Harry Potter');
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    AudiobookSettings.changeNotifier.removeListener(_onSettingsChanged);
    AppThemeService.currentPalette.removeListener(_onSettingsChanged);
    Paper2AudioService.instance.jobs.removeListener(_onSettingsChanged);
    CustomAudiobookService.instance.audiobooks.removeListener(_onSettingsChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _continueScrollController.removeListener(_updateContinueScrollArrows);
    _continueScrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadContinueListening() async {
    final list = await AudiobookProgressService.instance.getAllProgress();
    if (!mounted) return;
    setState(() {
      _continueListeningList = list;
    });
    // The rail's length changed, so its right-hand arrow has to be re-asked
    // whether there is still anything to its right - and it can only be asked
    // once the new list has laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateContinueScrollArrows();
    });
  }

  /// Whether a rail's hover arrows would be useful at all.
  ///
  /// The same predicate every other rail in the app writes for itself
  /// (`MovieSliderSection`, `IptvSliderSection`, `ContinueWatchingSlider`): the
  /// arrows are a pointer affordance revealed by hover, and no touch or D-pad
  /// platform can raise a hover, so there they are simply not drawn.
  bool _hasPointer() {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// Keeps the two hover arrows honest about which way the rail can still move.
  void _updateContinueScrollArrows() {
    if (!_continueScrollController.hasClients) return;
    final canLeft = _continueScrollController.position.pixels > 10;
    final canRight = _continueScrollController.position.pixels <
        _continueScrollController.position.maxScrollExtent - 10;
    if (canLeft == _canScrollContinueLeft &&
        canRight == _canScrollContinueRight) {
      return;
    }
    setState(() {
      _canScrollContinueLeft = canLeft;
      _canScrollContinueRight = canRight;
    });
  }

  /// One viewport-fraction glide, rather than the fixed 280 dp step this rail
  /// used to take: a card is 285 dp wide, so a fixed step moved it by less than
  /// one card and the rail felt stuck.
  void _scrollContinue(double direction) {
    if (!_continueScrollController.hasClients) return;
    final viewport = _continueScrollController.position.viewportDimension;
    final target =
        (_continueScrollController.position.pixels + viewport * 0.8 * direction)
            .clamp(0.0, _continueScrollController.position.maxScrollExtent);
    _continueScrollController.animateTo(
      target,
      duration: ZplayMotion.slow,
      curve: ZplayMotion.standard,
    );
  }

  Timer? _searchDebounce;

  void _onSearchChanged(String query) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted && query.trim().isNotEmpty) {
        _performSearch(query);
      }
    });
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _searchDebounce?.cancel();

    final currentSequence = ++_searchSequence;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final results = await AudiobookScraperService.instance.search(trimmed);
      if (mounted && currentSequence == _searchSequence) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted && currentSequence == _searchSequence) {
        setState(() {
          _isSearching = false;
          _errorMessage = 'Failed to fetch audiobooks: $e';
        });
      }
    }
  }

  void _selectCategory(String cat) {
    setState(() => _selectedCategory = cat);
    if (cat == 'All') {
      _performSearch('Harry Potter');
    } else {
      _searchController.text = cat;
      _performSearch(cat);
    }
  }

  void _showAudiobookCustomizer(BuildContext context) {
    final tokens = context.tokens;

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: tokens.surfaceOverlay,
          shape: const RoundedRectangleBorder(
            borderRadius: ZplayRadius.lgAll,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune_rounded, color: tokens.accent, size: 20),
                      const SizedBox(width: ZplaySpacing.s12),
                      Text(
                        'Customize Audiobook Section',
                        style: ZplayType.title.toStyle(color: tokens.textPrimary),
                      ),
                      const Spacer(),
                      FocusableInkWell(
                        onTap: () => Navigator.pop(ctx),
                        borderRadius: ZplayRadius.fullAll,
                        hoverColor: tokens.textPrimary.withValues(
                          alpha: ZplayOpacity.borderDefault,
                        ),
                        child: SizedBox(
                          width: ZplaySpacing.s48,
                          height: ZplaySpacing.s48,
                          child: Icon(
                            Icons.close_rounded,
                            color: tokens.textSecondary,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // No dividers: a 1 px line between two groups is the border
                  // this design does not draw, and the gap carries the same
                  // grouping on its own.
                  const SizedBox(height: ZplaySpacing.s20),

                  Text(
                    'Poster Card Density',
                    style: ZplayType.label
                        .copyWith(weight: FontWeight.w700)
                        .toStyle(color: tokens.textPrimary),
                  ),
                  const SizedBox(height: ZplaySpacing.s8),
                  ValueListenableBuilder<AudiobookCardDensity>(
                    valueListenable: AudiobookSettings.cardDensity,
                    builder: (context, density, _) {
                      return SegmentedTabs<AudiobookCardDensity>(
                        semanticsLabel: 'Audiobook poster card density',
                        selected: density,
                        onSelected: AudiobookSettings.setCardDensity,
                        options: [
                          for (final option in AudiobookCardDensity.values)
                            SegmentedTabOption(
                              value: option,
                              label: option.label,
                            ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 14),

                  ValueListenableBuilder<bool>(
                    valueListenable: AudiobookSettings.enableSpotlight,
                    builder: (context, enabled, _) {
                      return SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Featured Hero Spotlight Carousel',
                          style: ZplayType.label.toStyle(color: tokens.textPrimary),
                        ),
                        value: enabled,
                        activeColor: tokens.accent,
                        onChanged: (val) => AudiobookSettings.setEnableSpotlight(val),
                      );
                    },
                  ),

                  ValueListenableBuilder<bool>(
                    valueListenable: AudiobookSettings.enableAmbientLights,
                    builder: (context, enabled, _) {
                      return SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Moving Ambient Background Glow',
                          style: ZplayType.label.toStyle(color: tokens.textPrimary),
                        ),
                        value: enabled,
                        activeColor: tokens.accent,
                        onChanged: (val) => AudiobookSettings.setEnableAmbientLights(val),
                      );
                    },
                  ),

                  ValueListenableBuilder<bool>(
                    valueListenable: AudiobookSettings.showContinueListening,
                    builder: (context, show, _) {
                      return SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Show "Continue Listening" Carousel',
                          style: ZplayType.label.toStyle(color: tokens.textPrimary),
                        ),
                        value: show,
                        activeColor: tokens.accent,
                        onChanged: (val) => AudiobookSettings.setShowContinueListening(val),
                      );
                    },
                  ),

                  const SizedBox(height: ZplaySpacing.s20),

                  // The shared pill, expanded: it is the dialog's only way out
                  // to another surface, and its column is sized by it.
                  PillButton(
                    variant: PillVariant.secondary,
                    label: 'Open Player Studio & Themes',
                    icon: Icons.palette_rounded,
                    expand: true,
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AudiobookSettingsPage()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screenW = MediaQuery.sizeOf(context).width;
    final isMobile = screenW < 600;
    final television = FormFactorService.of(context) == FormFactor.television;
    final tokens = context.tokens;
    final ambientEnabled = AudiobookSettings.enableAmbientLights.value;
    final showSpotlight = AudiobookSettings.enableSpotlight.value;
    final showContinue = AudiobookSettings.showContinueListening.value;
    final showCategoryPills = AudiobookSettings.showCategoryPills.value;
    final cardDensity = AudiobookSettings.cardDensity.value;

    final spotlightBook = _searchResults.isNotEmpty ? _searchResults.first : null;

    // What the studio banner shows: the audiobook with saved progress is the one
    // "now playing", so it outranks the featured spotlight. Either can be
    // absent, and when both are, the band is simply not drawn.
    final resumeEntry = showContinue && _continueListeningList.isNotEmpty
        ? _continueListeningList.first
        : null;
    final bannerBook =
        resumeEntry?.audiobook ?? (showSpotlight ? spotlightBook : null);

    return Scaffold(
      backgroundColor: tokens.bg,
      body: Stack(
        children: [
          // ── Ambient Background Glows ──
          if (ambientEnabled)
            const Positioned.fill(child: AnimatedAmbientBackground())
          else
            Positioned.fill(
              child: Container(color: tokens.bg),
            ),

          // ── Main Content Scroll ──
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Top Header Bar. In flow and below the inset the shell charges
              // this page, so the strip above it is canvas and nothing else: no
              // band, no fill, no hairline. The destination is already named by
              // the shell's top bar and the Browse band, so what is left is one
              // accent glyph, the page's own name, and the two actions as bare
              // glyphs - the gradient badge and the two blurred pills that used
              // to open this row were three boxes whose fills were not their
              // content.
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? ZplaySpacing.s16 : ZplaySpacing.s24,
                    topInset + ZplaySpacing.s12,
                    isMobile ? ZplaySpacing.s8 : ZplaySpacing.s16,
                    ZplaySpacing.s8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.headphones_rounded,
                        color: tokens.accent,
                        size: 22,
                        // Over the ambient canvas and, once the page scrolls,
                        // over whatever artwork is under the shared nav. The
                        // glyph shadow is what keeps it legible with no tint
                        // behind it, and it is the same one Home's chrome uses.
                        shadows: const [_glyphShadow],
                      ),
                      const SizedBox(width: ZplaySpacing.s12),

                      // Title
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Audiobook Hub',
                              style: ZplayType.titleLarge.toStyle(color: tokens.textPrimary),
                            ),
                            Text(
                              'Explore, stream & listen to thousands of stories',
                              style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // AI Generator & Studio
                      _ChromeActionButton(
                        icon: Icons.auto_awesome_rounded,
                        tooltip: 'Audiobook Generator & Studio',
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const GenerateAudiobookScreen()),
                          );
                          _loadContinueListening();
                        },
                      ),

                      // Quick Customize
                      _ChromeActionButton(
                        icon: Icons.tune_rounded,
                        tooltip: 'Audiobook Customizer',
                        onTap: () => _showAudiobookCustomizer(context),
                      ),
                    ],
                  ),
                ),
              ),

              // Search Bar. A form field is the one container this design keeps,
              // because its fill *is* what it is. It lost the 12 dp backdrop
              // blur - there is nothing behind it to refract on a flat canvas -
              // and the hairline that changed colour with the query: the text in
              // the field is already the state, and a resting outline is the
              // edge the shared selector next to it no longer draws either.
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? ZplaySpacing.s16 : ZplaySpacing.s24,
                    vertical: ZplaySpacing.s4,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      // Opaque, not a 75% wash behind a blur: the field floats
                      // over the shelf, so a translucent fill only let artwork
                      // smear through the text it is supposed to frame.
                      color: tokens.surface,
                      borderRadius: ZplayRadius.mdAll,
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: ZplayType.body.toStyle(color: tokens.textPrimary),
                      textInputAction: TextInputAction.search,
                      onChanged: _onSearchChanged,
                      onSubmitted: _performSearch,
                      decoration: InputDecoration(
                        hintText: 'Search audiobooks by title, author, or genre...',
                        hintStyle: ZplayType.body.toStyle(color: tokens.textMuted),
                        prefixIcon: Icon(Icons.search_rounded, color: tokens.accent),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? FocusableInkWell(
                                onTap: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                borderRadius: ZplayRadius.fullAll,
                                hoverColor: tokens.textPrimary.withValues(
                                  alpha: ZplayOpacity.borderDefault,
                                ),
                                child: SizedBox(
                                  width: ZplaySpacing.s48,
                                  height: ZplaySpacing.s48,
                                  child: Icon(
                                    Icons.clear_rounded,
                                    color: tokens.textSecondary,
                                    size: 18,
                                  ),
                                ),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s20,
                          vertical: ZplaySpacing.s12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Genre / Category Filter. The shared [TabStrip], not a hand-rolled
              // chip row: a strip of labels is an overlay on the page, so a pill
              // at rest is nothing but its label, the selected one carries the
              // short accent bar under it, and [CardFocusRing] is the only edge
              // one ever draws. The bespoke chip painted its own 2 dp border,
              // which was a second focus mark beside the ring and put a box on
              // every genre.
              if (showCategoryPills)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: ZplaySpacing.s8,
                      bottom: ZplaySpacing.s4,
                    ),
                    child: TabStrip<String>(
                      options: [
                        for (final category in _categories)
                          TabStripOption<String>(
                            value: category,
                            label: category,
                          ),
                      ],
                      selected: _selectedCategory,
                      onSelected: _selectCategory,
                      semanticsLabel: 'Audiobook genres',
                      height: television ? ZplaySpacing.s64 : ZplaySpacing.s48,
                    ),
                  ),
                ),

              // Player studio banner. The resume hero takes precedence: an
              // audiobook with saved progress is the one "now playing", and the
              // prototype's banner is exactly that surface. With nothing in
              // progress it falls back to the featured spotlight, so the band is
              // never empty and never doubled.
              if (!_isSearching && bannerBook != null)
                SliverToBoxAdapter(
                  child: _buildStudioBanner(
                    resume: resumeEntry,
                    book: bannerBook,
                    isMobile: isMobile,
                  ),
                ),

              // Continue Listening Section (If available)
              if (showContinue && _continueListeningList.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildContinueListeningSection(),
                ),

              // Generated & Personal Audiobooks Studio Shelf
              if (!_isSearching)
                SliverToBoxAdapter(
                  child: _buildGeneratedAndUploadedSection(),
                ),

              // Discovery Header. The count is the shared header's muted tabular
              // number rather than a second accent badge: accent is the signal
              // for what you are on, and a result count is a caption.
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: ZplaySpacing.s16),
                  child: SectionHeader(
                    title: _searchController.text.isNotEmpty
                        ? 'Search Results'
                        : 'Featured Audiobooks',
                    count: _searchResults.length,
                  ),
                ),
              ),

              // Search Status / Loading / Grid
              if (_isSearching)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: tokens.accent),
                        const SizedBox(height: ZplaySpacing.s16),
                        Text(
                          'Scraping high-quality audiobook sources...',
                          style: ZplayType.body.toStyle(color: tokens.textEmphasis),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  // The shared failure view: it names what failed and offers the
                  // retry the bare red sentence never did.
                  child: ErrorView(
                    title: 'Could not load audiobooks',
                    error: _errorMessage,
                    onRetry: () => _performSearch(_searchController.text),
                  ),
                )
              else if (_searchResults.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No audiobooks found. Try another search query.',
                      style: ZplayType.subtitle.toStyle(color: tokens.textSecondary),
                    ),
                  ),
                )
              else
                SliverPadding(
                  // The shared header above sits at `s16`, so the grid does too
                  // and the first poster lines up with its heading.
                  padding: EdgeInsets.fromLTRB(
                    ZplaySpacing.s16,
                    ZplaySpacing.s8,
                    ZplaySpacing.s16,
                    ZplaySpacing.s32 + bottomInset,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: (isMobile ? 150 : 180) * cardDensity.scale,
                      childAspectRatio: 0.60,
                      crossAxisSpacing: isMobile ? 12 : 16,
                      mainAxisSpacing: isMobile ? 12 : 16,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final book = _searchResults[index];
                        final heroTag = 'audiobook-cover-$index-${book.uuid.isNotEmpty ? book.uuid : book.title}';
                        return _AudiobookCard(
                          key: ValueKey('book-$index-${book.uuid}'),
                          book: book,
                          heroTag: heroTag,
                          onReturn: _loadContinueListening,
                        );
                      },
                      childCount: _searchResults.length,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Player Studio Banner ──
  //
  // The prototype's `.audiobook-hero-banner`: the cover at 88 dp, the resume or
  // spotlight copy beside it, and one row of controls.
  //
  // Every figure is read from a real service. The progress bar and the time-left
  // caption come from [AudiobookProgressService] through the resume entry, the
  // chapter line from that entry's own chapter list, and Resume re-enters
  // [AudiobookPlayerScreen] at the stored chapter and position.
  //
  // The prototype also draws a `Speed: 1.25×` chip and a `Sleep Timer: 30m`
  // chip. Neither has a backing field - playback rate is per-session state
  // inside the player screen (`_playbackSpeed`, never persisted) and the app has
  // no sleep timer at all - so they are deliberately absent rather than faked.
  Widget _buildStudioBanner({
    required AudiobookProgress? resume,
    required Audiobook book,
    required bool isMobile,
  }) {
    final tokens = context.tokens;

    // A saved entry whose chapter list came back empty cannot be resumed into
    // the player, so it falls back to the detail route with everything else.
    final resumable = resume != null && resume.chapters.isNotEmpty ? resume : null;
    final subject = resumable?.audiobook ?? book;
    final heroTag = resumable != null
        ? 'studio-banner-${resumable.key}'
        : 'spotlight-hero-${subject.uuid.isNotEmpty ? subject.uuid : subject.title}';
    final coverUrl = subject.coverImage.trim();

    final position = Duration(milliseconds: resumable?.positionMs ?? 0);
    final duration = Duration(milliseconds: resumable?.durationMs ?? 0);
    final remaining = duration - position;
    final percent = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final author = (subject.author ?? '').trim();

    // What there is to say about this audiobook, in the order the reference
    // reads it: who made it, then how far in you are.
    //
    // Terms the service does not carry are absent rather than guessed.
    // `Audiobook` has no genre, no year and no duration of its own, so a
    // spotlight entry prints the author - or the source when there is no author
    // - and stops. The time left is deliberately not repeated here: the
    // progress row below already carries it, and one fact in two places on one
    // banner is the second register the shared meta line exists to remove.
    final metaTerms = <String>[
      if (author.isNotEmpty) author,
      if (resumable != null)
        'Chapter ${resumable.chapterIndex + 1} of ${resumable.chapters.length}',
      if (resumable == null && author.isEmpty) subject.source.toUpperCase(),
    ];

    return Container(
      // One gutter with the header and the grid, and no hairline: the fill and
      // the cover's own artwork carry this panel, and a 1 px edge across a
      // banner whose content is a photograph is the border this design keeps
      // only where a fill *is* the content.
      margin: const EdgeInsets.symmetric(
        horizontal: ZplaySpacing.s16,
        vertical: ZplaySpacing.s12,
      ),
      padding: const EdgeInsets.all(ZplaySpacing.s16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.smAll,
      ),
      child: Row(
        children: [
          // Cover
          SizedBox(
            width: 88,
            height: 88,
            child: Hero(
              tag: heroTag,
              child: ClipRRect(
                borderRadius: ZplayRadius.smAll,
                child: coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        cacheManager: AppImageCache.manager,
                        httpHeaders: const {
                          'User-Agent':
                              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                        },
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: tokens.surfaceRaised),
                        errorWidget: (_, __, ___) => Container(
                          color: tokens.surfaceRaised,
                          child: Icon(Icons.headphones_rounded, color: tokens.textMuted),
                        ))
                    : Container(
                        color: tokens.surfaceRaised,
                        child: Icon(Icons.headphones_rounded, color: tokens.textMuted),
                      ),
              ),
            ),
          ),
          const SizedBox(width: ZplaySpacing.s20),

          // Metadata & controls
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  resumable != null ? 'NOW PLAYING AUDIOBOOK' : 'SPOTLIGHT FEATURED',
                  style: ZplayType.overline.toStyle(color: tokens.accent),
                ),
                const SizedBox(height: ZplaySpacing.s4),
                Text(
                  subject.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ZplayType.title
                      .copyWith(size: isMobile ? 16 : 18)
                      .toStyle(color: tokens.textPrimary),
                ),
                // One metadata line: the author and, when this is a resume, the
                // chapter the reader stopped in. This was a string joined here by
                // hand; the shared line is the same facts in the same order, and
                // the "drop an absent term, ellipsis the rest" rule is now one
                // implementation rather than one per banner.
                //
                // No fetch and no invented terms. `Audiobook` carries no genre,
                // no year and no duration, and the time left is already on the
                // progress row below, so a spotlight entry prints the author -
                // or the source when there is no author - and stops.
                if (metaTerms.isNotEmpty) ...[
                  const SizedBox(height: ZplaySpacing.s4),
                  HeroMetaLine(terms: metaTerms),
                ],
                if (resumable != null && duration.inMilliseconds > 0) ...[
                  const SizedBox(height: ZplaySpacing.s12),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: ZplayRadius.fullAll,
                          child: LinearProgressIndicator(
                            value: percent,
                            minHeight: ZplaySpacing.s4,
                            backgroundColor: tokens.borderStrong,
                            valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
                          ),
                        ),
                      ),
                      const SizedBox(width: ZplaySpacing.s12),
                      Text(
                        '${_formatRemaining(remaining)} left',
                        style: ZplayType.caption
                            .copyWith(weight: FontWeight.w600)
                            .toStyle(color: tokens.textSecondary),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: ZplaySpacing.s12),
                // The shared pill, so this banner's call to action is the same
                // shape as Home's hero and the music billboard's. It replaced a
                // 36 dp `ElevatedButton` that hand-rolled its own ten-foot
                // height; the pill states the 48-on-a-television rule once for
                // the whole app instead of each banner deciding for itself.
                //
                // The time left stays in the label rather than moving to the
                // line above: it counts down while the banner is on screen, and
                // a term that changes under the title reads as a glitch.
                Builder(
                  builder: (context) => PillButton(
                    label: resumable != null
                        ? 'Resume (${_formatRemaining(remaining)} left)'
                        : 'Listen Now',
                    icon: Icons.play_arrow_rounded,
                    onPressed: () async {
                      if (resumable != null) {
                        await Navigator.push(
                          context,
                          AudiobookPageRoute(
                            page: AudiobookPlayerScreen(
                              audiobook: subject,
                              chapters: resumable.chapters,
                              initialChapterIndex: resumable.chapterIndex,
                              initialPosition: position,
                            ),
                          ),
                        );
                      } else {
                        await Navigator.push(
                          context,
                          AudiobookPageRoute(
                            page: AudiobookDetailPage(
                              audiobook: subject,
                              heroTag: heroTag,
                            ),
                          ),
                        );
                      }
                      _loadContinueListening();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `14:32:10` above an hour, `32:10` below it.
  static String _formatRemaining(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  // ── Continue Listening Carousel ──
  Widget _buildContinueListeningSection() {
    final isDesktop = _hasPointer();

    return Padding(
      // A section header carries its own `s16` gutter, so only the vertical
      // rhythm is spent here and the rail's own padding lines the first card up
      // with the heading above it.
      padding: const EdgeInsets.only(bottom: ZplaySpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One heading type for the whole app, and the count as the shared
          // header's muted tabular number. The accent glyph that used to lead
          // this row was a second mark for a title that already names itself.
          SectionHeader(
            title: 'Continue Listening',
            count: _continueListeningList.length,
          ),
          const SizedBox(height: ZplaySpacing.s8),
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveringContinueRail = true),
            onExit: (_) => setState(() => _isHoveringContinueRail = false),
            child: SizedBox(
              height: 110,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ListView.builder(
                    controller: _continueScrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZplaySpacing.s16,
                    ),
                    itemCount: _continueListeningList.length,
                    itemBuilder: (context, index) {
                      final item = _continueListeningList[index];
                      return _ContinueListeningCard(
                        progress: item,
                        onDelete: () async {
                          await AudiobookProgressService.instance
                              .removeProgress(item.key);
                          _loadContinueListening();
                        },
                        onTap: () async {
                          await Navigator.push(
                            context,
                            AudiobookPageRoute(
                              page: AudiobookPlayerScreen(
                                audiobook: item.audiobook,
                                chapters: item.chapters,
                                initialChapterIndex: item.chapterIndex,
                                initialPosition:
                                    Duration(milliseconds: item.positionMs),
                              ),
                            ),
                          );
                          _loadContinueListening();
                        },
                      );
                    },
                  ),

                  // The same floating arrows every other rail in the app uses:
                  // revealed by hovering the row, and only on a platform that
                  // can hover at all. The two round buttons these replaced sat
                  // in the heading on every form factor - a second way to scroll
                  // a rail that no other rail offers, focusable on a television
                  // where a remote already moves the row by moving focus
                  // through it, and drawn as a fill change where this design
                  // gives a control one ring.
                  if (isDesktop)
                    AnimatedPositioned(
                      duration: ZplayMotion.base,
                      curve: ZplayMotion.standard,
                      left: _canScrollContinueLeft && _isHoveringContinueRail
                          ? ZplaySpacing.s8
                          : -60,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: SliderArrow(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onTap: () => _scrollContinue(-1),
                        ),
                      ),
                    ),
                  if (isDesktop)
                    AnimatedPositioned(
                      duration: ZplayMotion.base,
                      curve: ZplayMotion.standard,
                      right: _canScrollContinueRight && _isHoveringContinueRail
                          ? ZplaySpacing.s8
                          : -60,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: SliderArrow(
                          icon: Icons.arrow_forward_ios_rounded,
                          onTap: () => _scrollContinue(1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Generated & Uploaded Audiobooks Shelf ──
  Widget _buildGeneratedAndUploadedSection() {
    final tokens = context.tokens;

    final jobs = Paper2AudioService.instance.jobs.value;
    final uploaded = CustomAudiobookService.instance.audiobooks.value;
    final hasItems = jobs.isNotEmpty || uploaded.isNotEmpty;

    if (!hasItems) {
      // Quiet studio banner. It lost the accent gradient box and its 0.25 accent
      // edge - an inner surface whose fill was not its content, on a page that
      // already spends the accent once - and it is no longer one bare `InkWell`
      // around the whole row, which was a pointer-only `GestureDetector` with no
      // `Focus` node anywhere in it. One action, one ring: the shared pill.
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          ZplaySpacing.s16,
          ZplaySpacing.s8,
          ZplaySpacing.s16,
          ZplaySpacing.s16,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: ZplaySpacing.s20,
            vertical: ZplaySpacing.s16,
          ),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: ZplayRadius.mdAll,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tokens.accentSubtle,
                  borderRadius: ZplayRadius.smAll,
                ),
                child: Icon(Icons.auto_stories_rounded, color: tokens.accent, size: 20),
              ),
              const SizedBox(width: ZplaySpacing.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Audiobook Studio & EPUB Generator',
                      style: ZplayType.label
                          .copyWith(weight: FontWeight.w700)
                          .toStyle(color: tokens.textPrimary),
                    ),
                    Text(
                      'Generate audiobooks from EPUBs or import your own MP3/M4B audiobooks.',
                      style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ZplaySpacing.s16),
              PillButton(
                label: 'Open Studio',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const GenerateAudiobookScreen()),
                  );
                  _loadContinueListening();
                },
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(
        top: ZplaySpacing.s8,
        bottom: ZplaySpacing.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'My Generated & Uploaded Audiobooks',
            count: jobs.length + uploaded.length,
            // The shared header's trailing slot rather than a `TextButton.icon`
            // beside it: one row height, one heading type, and a control that is
            // a `Focus` node with the app's single ring.
            trailing: FocusableInkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GenerateAudiobookScreen()),
                );
                _loadContinueListening();
              },
              borderRadius: ZplayRadius.smAll,
              hoverColor: tokens.textPrimary.withValues(
                alpha: ZplayOpacity.borderDefault,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune_rounded, size: 18, color: tokens.textSecondary),
                      const SizedBox(width: ZplaySpacing.s4),
                      Text(
                        'Studio',
                        style: ZplayType.label.toStyle(color: tokens.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: ZplaySpacing.s8),
          SizedBox(
            height: 120,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s16),
              children: [
                // Render Generated Jobs
                ...jobs.map((job) {
                  final cleanTitle = job.fileName.replaceAll(RegExp(r'\.epub$', caseSensitive: false), '');
                  final isDone = job.isDone;
                  final isFailed = job.isFailed;

                  return Container(
                    width: 270,
                    margin: const EdgeInsets.only(right: ZplaySpacing.s12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      // Fill and a black drop, no hairline: this is the shelf
                      // card convention the rest of the app uses, where a 1 px
                      // outline was a second edge on every tile in the row.
                      color: tokens.surface.withValues(alpha: 0.85),
                      borderRadius: ZplayRadius.mdAll,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.30),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 100,
                          decoration: BoxDecoration(
                            color: tokens.borderDefault,
                            borderRadius: ZplayRadius.smAll,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: job.coverPath != null && File(job.coverPath!).existsSync()
                              ? Image.file(File(job.coverPath!), fit: BoxFit.cover)
                              : Icon(
                                  Icons.headphones_rounded,
                                  color: tokens.textDisabled,
                                  size: 24,
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                cleanTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ZplayType.label
                                    .copyWith(weight: FontWeight.w700)
                                    .toStyle(color: tokens.textPrimary),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                isDone ? 'Voice: ${job.voiceId}' : (isFailed ? 'Failed' : 'Generating ${(job.progress * 100).round()}%'),
                                style: ZplayType.caption
                                    .copyWith(weight: FontWeight.w600)
                                    .toStyle(
                                      color: isDone
                                          ? tokens.success
                                          : (isFailed ? tokens.danger : tokens.warning),
                                    ),
                              ),
                              const SizedBox(height: ZplaySpacing.s8),
                              if (isDone)
                                // The shared pill, so this tile's only action is
                                // the same control as the banner's. A 44 dp pill
                                // fits the 100 dp column the cover leaves.
                                PillButton(
                                  label: 'Play',
                                  icon: Icons.play_arrow_rounded,
                                  onPressed: () {
                                    final streamOrLocalPath = job.localAudioPath ?? job.downloadUrl!;
                                    final book = Audiobook(
                                      uuid: 'p2a_${job.runId}',
                                      audioBookId: 'p2a_${job.runId}',
                                      dynamicSlugId: job.runId,
                                      title: cleanTitle,
                                      author: 'AI Generated',
                                      coverImage: job.coverPath ?? '',
                                      source: 'Paper2Audio AI',
                                      pageUrl: streamOrLocalPath,
                                    );
                                    Navigator.push(
                                      context,
                                      AudiobookPageRoute(
                                        page: AudiobookPlayerScreen(
                                          audiobook: book,
                                          chapters: [AudiobookChapter(title: cleanTitle, url: streamOrLocalPath)],
                                        ),
                                      ),
                                    );
                                  },
                                )
                              else if (!isFailed)
                                ClipRRect(
                                  borderRadius: ZplayRadius.xsAll,
                                  child: LinearProgressIndicator(
                                    value: job.progress > 0 ? job.progress : null,
                                    backgroundColor: tokens.borderDefault,
                                    color: tokens.accent,
                                    minHeight: 4,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                // Render Uploaded Audiobooks
                ...uploaded.map((b) {
                  return Container(
                    width: 270,
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tokens.surface.withValues(alpha: 0.85),
                      borderRadius: ZplayRadius.mdAll,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.30),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 100,
                          decoration: BoxDecoration(
                            color: tokens.borderDefault,
                            borderRadius: ZplayRadius.smAll,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: b.coverPath != null && File(b.coverPath!).existsSync()
                              ? Image.file(File(b.coverPath!), fit: BoxFit.cover)
                              : Icon(
                                  Icons.library_music_rounded,
                                  color: tokens.textDisabled,
                                  size: 24,
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                b.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ZplayType.label
                                    .copyWith(weight: FontWeight.w700)
                                    .toStyle(color: tokens.textPrimary),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${b.author} • Local',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                              ),
                              const SizedBox(height: ZplaySpacing.s8),
                              PillButton(
                                label: 'Play',
                                icon: Icons.play_arrow_rounded,
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    AudiobookPageRoute(
                                      page: AudiobookPlayerScreen(
                                        audiobook: b.toAudiobookModel(),
                                        chapters: b.toChapters(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueListeningCard extends StatelessWidget {
  final AudiobookProgress progress;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ContinueListeningCard({
    required this.progress,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final television = FormFactorService.of(context) == FormFactor.television;
    final item = progress;
    final book = item.audiobook;
    final hasCover = book.coverImage.isNotEmpty;
    final heroTag = 'continue-cover-${book.uuid.isNotEmpty ? book.uuid : book.title}';

    final percent = item.durationMs > 0
        ? (item.positionMs / item.durationMs).clamp(0.0, 1.0)
        : 0.0;

    final currentChapterTitle = item.chapters.isNotEmpty && item.chapterIndex < item.chapters.length
        ? item.chapters[item.chapterIndex].title
        : 'Chapter ${item.chapterIndex + 1}';

    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FocusableCard(
            onTap: onTap,
            builder: (context, state) {
              // Pointer-only, like every other card in the app: focus draws the
              // ring and leaves the tile where it is.
              final scale = state.pressed ? 0.96 : (state.hovered ? 1.03 : 1.0);

              return AnimatedScale(
                scale: scale,
                duration: ZplayMotion.fast,
                curve: ZplayMotion.standard,
                child: AnimatedContainer(
                  duration: ZplayMotion.fast,
                  curve: ZplayMotion.standard,
                  width: 285,
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: ZplayRadius.mdAll,
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: CardFocusRing(
                    focused: state.focused,
                    radius: ZplayRadius.mdAll,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          // Book Cover Art
                          SizedBox(
                            width: 60,
                            height: 90,
                            child: Hero(
                              tag: heroTag,
                              child: ClipRRect(
                                borderRadius: ZplayRadius.smAll,
                                child: hasCover
                                    ? CachedNetworkImage(
                                        imageUrl: book.coverImage,
                                        cacheManager: AppImageCache.manager,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => Container(color: tokens.surface),
                                        errorWidget: (_, __, ___) => Container(
                                          color: tokens.surface,
                                          child: Icon(
                                            Icons.headphones_rounded,
                                            color: tokens.textMuted,
                                          ),
                                        ))
                                    : Container(
                                        color: tokens.surface,
                                        child: Icon(
                                          Icons.headphones_rounded,
                                          color: tokens.textMuted,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Info & Progress
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  book.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ZplayType.label
                                      .copyWith(weight: FontWeight.w700)
                                      .toStyle(color: tokens.textPrimary),
                                ),
                                const SizedBox(height: ZplaySpacing.s4),
                                Text(
                                  currentChapterTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                                ),
                                const SizedBox(height: ZplaySpacing.s8),
                                // Progress bar
                                ClipRRect(
                                  borderRadius: ZplayRadius.xsAll,
                                  child: LinearProgressIndicator(
                                    value: percent,
                                    minHeight: ZplaySpacing.s4,
                                    backgroundColor: tokens.borderDefault,
                                    valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
                                  ),
                                ),
                                const SizedBox(height: ZplaySpacing.s4),
                                Text(
                                  '${(percent * 100).toInt()}% completed',
                                  style: ZplayType.caption
                                      .copyWith(weight: FontWeight.w600)
                                      .toStyle(color: tokens.accent),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),

                          // Play Button Icon
                          Container(
                            padding: const EdgeInsets.all(ZplaySpacing.s8),
                            decoration: BoxDecoration(
                              color: state.highlighted
                                  ? tokens.accent
                                  : tokens.accentSubtle,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: state.highlighted ? tokens.onAccent : tokens.accent,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // X Delete Button
          Positioned(
            top: -ZplaySpacing.s8,
            right: -ZplaySpacing.s8,
            // 48 dp on a television; the glyph and its ring stay small.
            child: SizedBox(
              width: television ? ZplaySpacing.s48 : ZplaySpacing.s32,
              height: television ? ZplaySpacing.s48 : ZplaySpacing.s32,
              child: FocusableCard(
                onTap: onDelete,
                builder: (context, state) {
                  return Center(
                    child: CardFocusRing(
                      focused: state.focused,
                      radius: ZplayRadius.fullAll,
                      child: Container(
                        padding: const EdgeInsets.all(ZplaySpacing.s4),
                        decoration: BoxDecoration(
                          color: state.highlighted ? tokens.danger : tokens.surfaceOverlay,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          color: tokens.textPrimary,
                          size: 14,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Home's glyph shadow, reused: what keeps a chrome glyph legible over bright
/// artwork at offset 0, where there is no tint behind it. One constant rather
/// than one per call site, so the chrome's glyphs carry the same weight.
const Shadow _glyphShadow = Shadow(
  color: Color(0x99000000),
  blurRadius: 6,
  offset: Offset(0, 1),
);

/// A page-level action in the header row: a bare glyph on the canvas, the app's
/// single focus ring, and nothing else.
///
/// The two actions this replaced were `IconButton`s inside `ClipRRect` +
/// `BackdropFilter` boxes painted with an accent gradient and a 1 px accent
/// edge: the only filled pills in a row that carries no other, and a blur with
/// nothing behind it to refract on a flat canvas. The glyph takes the shadow
/// instead, so it reads at offset 0 over the ambient canvas and over whatever is
/// under the shared nav once the page has scrolled.
class _ChromeActionButton extends StatelessWidget {
  const _ChromeActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // 48 dp on a television, 44 on a pointer: the ten-foot rule the rest of the
    // chrome states, and the same target the `IconButton` it replaced used.
    final size = FormFactorService.of(context) == FormFactor.television
        ? ZplaySpacing.s48
        : 44.0;

    return Tooltip(
      message: tooltip,
      child: FocusableInkWell(
        onTap: onTap,
        borderRadius: ZplayRadius.fullAll,
        hoverColor: tokens.textPrimary.withValues(
          alpha: ZplayOpacity.borderDefault,
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: tokens.textEmphasis,
            size: 22,
            shadows: const [_glyphShadow],
          ),
        ),
      ),
    );
  }
}

class _AudiobookCard extends StatelessWidget {
  final Audiobook book;
  final String heroTag;
  final VoidCallback? onReturn;

  const _AudiobookCard({
    super.key,
    required this.book,
    required this.heroTag,
    this.onReturn,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasCover = book.coverImage.isNotEmpty;
    final cardHoverGlow = AudiobookSettings.cardHoverGlow.value;

    return FocusableCard(
      onTap: () async {
        await Navigator.push(
          context,
          AudiobookPageRoute(
            page: AudiobookDetailPage(
              audiobook: book,
              heroTag: heroTag,
            ),
          ),
        );
        onReturn?.call();
      },
      builder: (context, state) {
        // Lift and zoom answer the pointer, not focus: a D-pad press must not
        // nudge the card the user is aiming at, and the ring is the only mark a
        // focused card carries. This is `MovieCard`'s own rule, stated there for
        // the same reason the 3 dp ring exists.
        final scale = state.pressed ? 0.95 : (state.hovered ? 1.04 : 1.0);
        final author = (book.author ?? '').trim();

        return AnimatedScale(
          scale: scale,
          duration: ZplayMotion.base,
          curve: ZplayMotion.standard,
          child: AnimatedContainer(
            duration: ZplayMotion.base,
            curve: ZplayMotion.standard,
            child: CardFocusRing(
              focused: state.focused,
              radius: ZplayRadius.mdAll,
              child: Container(
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: ZplayRadius.mdAll,
                  boxShadow: [
                    BoxShadow(
                      // Hover may glow, and only while the user keeps
                      // `cardHoverGlow` on. Focus draws the ring and nothing
                      // else - no second edge, no glow, no depth change.
                      color: state.hovered && cardHoverGlow
                          ? tokens.accent.withValues(alpha: 0.35)
                          : Colors.black.withValues(alpha: 0.4),
                      blurRadius: state.hovered ? 16 : 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  // `stretch` for the same reason as the shelf cards: the ring's
                  // stack loosens the constraints, and the card must stay the
                  // size of the grid cell rather than of its widest child.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Cover Image with Hero Transition
                    Expanded(
                      child: Hero(
                        tag: heroTag,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(ZplayRadius.md),
                          ),
                          child: hasCover
                              ? CachedNetworkImage(
                                  imageUrl: book.coverImage,
                                  cacheManager: AppImageCache.manager,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(color: tokens.surface),
                                  errorWidget: (_, __, ___) => Container(
                                    color: tokens.surface,
                                    child: Icon(
                                      Icons.headphones_rounded,
                                      size: 40,
                                      color: tokens.textMuted,
                                    ),
                                  ))
                              : Container(
                                  color: tokens.surface,
                                  child: Center(
                                    child: Icon(
                                      Icons.headphones_rounded,
                                      size: 40,
                                      color: tokens.textMuted,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    // Information
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: ZplayType.label
                                .copyWith(weight: FontWeight.w700)
                                .toStyle(color: tokens.textPrimary),
                          ),
                          // Narrator is not a field the scrapers fill, so the
                          // subtitle carries the author when there is one and the
                          // source otherwise.
                          const SizedBox(height: ZplaySpacing.s2),
                          Text(
                            author.isNotEmpty ? author : book.source,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ZplayType.caption.toStyle(color: tokens.textSecondary),
                          ),
                          const SizedBox(height: ZplaySpacing.s4),
                          Builder(
                            builder: (context) {
                              final isTorrent = book.source.toLowerCase().contains('audiobookbay');
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: ZplaySpacing.s4,
                                  vertical: ZplaySpacing.s2,
                                ),
                                decoration: BoxDecoration(
                                  // No resting border: the fill carries the
                                  // warning and the badge is a label, not a
                                  // control.
                                  color: isTorrent
                                      ? tokens.warning.withValues(alpha: 0.25)
                                      : tokens.accent.withValues(alpha: 0.2),
                                  borderRadius: ZplayRadius.xsAll,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isTorrent) ...[
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        color: tokens.warning,
                                        size: 10,
                                      ),
                                      const SizedBox(width: 3),
                                    ],
                                    Flexible(
                                      child: Text(
                                        isTorrent ? 'AUDIOBOOKBAY' : book.source.toUpperCase(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: ZplayType.overline
                                            .copyWith(size: 9)
                                            .toStyle(
                                              color: isTorrent ? tokens.warning : tokens.accent,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
