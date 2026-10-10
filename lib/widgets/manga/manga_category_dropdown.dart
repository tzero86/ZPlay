import 'package:flutter/material.dart';
import '../../services/theme/design_tokens.dart';
import '../common/focusable_card.dart';
import '../common/pill_button.dart';
import '../common/section_header.dart';

class MangaCategoryDropdown extends StatefulWidget {
  final String selectedGenre;
  final List<String> genres;
  final ValueChanged<String> onGenreSelected;

  const MangaCategoryDropdown({
    super.key,
    required this.selectedGenre,
    required this.genres,
    required this.onGenreSelected,
  });

  @override
  State<MangaCategoryDropdown> createState() => _MangaCategoryDropdownState();
}

class _MangaCategoryDropdownState extends State<MangaCategoryDropdown>
    with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  late AnimationController _animController;
  late Animation<double> _expandAnim;
  late Animation<double> _fadeAnim;

  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _expandAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
  }

  @override
  void dispose() {
    _hideDropdown(instant: true);
    _animController.dispose();
    super.dispose();
  }

  void _toggleDropdown() {
    if (_isOpen) {
      _hideDropdown();
    } else {
      _showDropdown();
    }
  }

  void _showDropdown() {
    if (_isOpen) return;

    final overlay = Overlay.of(context, rootOverlay: true);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final buttonOffset = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.sizeOf(context);

    setState(() => _isOpen = true);

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        return _DropdownOverlayContent(
          layerLink: _layerLink,
          buttonSize: size,
          buttonOffset: buttonOffset,
          screenSize: screenSize,
          genres: widget.genres,
          selectedGenre: widget.selectedGenre,
          anim: _expandAnim,
          fadeAnim: _fadeAnim,
          onClose: _hideDropdown,
          onSelect: (genre) {
            _hideDropdown();
            widget.onGenreSelected(genre);
          },
        );
      },
    );

    overlay.insert(_overlayEntry!);
    _animController.forward();
  }

  void _hideDropdown({bool instant = false}) {
    if (!_isOpen && _overlayEntry == null) return;

    if (instant) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      if (mounted) setState(() => _isOpen = false);
      return;
    }

    _animController.reverse().then((_) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      if (mounted) {
        setState(() => _isOpen = false);
      }
    });
  }

  IconData _getGenreIcon(String genre) {
    switch (genre.toLowerCase()) {
      case 'all':
        return Icons.auto_stories_rounded;
      case 'action':
        return Icons.flash_on_rounded;
      case 'adventure':
        return Icons.explore_rounded;
      case 'comedy':
        return Icons.sentiment_very_satisfied_rounded;
      case 'drama':
        return Icons.theater_comedy_rounded;
      case 'ecchi':
        return Icons.favorite_border_rounded;
      case 'fantasy':
        return Icons.auto_fix_high_rounded;
      case 'harem':
        return Icons.groups_rounded;
      case 'historical':
        return Icons.account_balance_rounded;
      case 'horror':
        return Icons.nights_stay_rounded;
      case 'isekai':
        return Icons.cyclone_rounded;
      case 'martial arts':
        return Icons.sports_martial_arts_rounded;
      case 'mature':
        return Icons.explicit_rounded;
      case 'mystery':
        return Icons.search_rounded;
      case 'psychological':
        return Icons.psychology_rounded;
      case 'romance':
        return Icons.favorite_rounded;
      case 'school life':
        return Icons.school_rounded;
      case 'sci-fi':
        return Icons.rocket_launch_rounded;
      case 'seinen':
        return Icons.person_rounded;
      case 'shounen':
        return Icons.local_fire_department_rounded;
      case 'slice of life':
        return Icons.coffee_rounded;
      case 'sports':
        return Icons.sports_baseball_rounded;
      case 'supernatural':
        return Icons.bolt_rounded;
      case 'tragedy':
        return Icons.heart_broken_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isSelectedGenre = widget.selectedGenre != 'All';
    final genreIcon = _getGenreIcon(widget.selectedGenre);

    return CompositedTransformTarget(
      link: _layerLink,
      child: FocusableCard(
        onTap: _toggleDropdown,
        builder: (context, state) {
          return CardFocusRing(
            // The chip had no ring at all: a remote could land on it and the
            // only thing that moved was a hover wash, which a D-pad never fires.
            focused: state.focused,
            radius: ZplayRadius.mdAll,
            child: AnimatedContainer(
              duration: ZplayMotion.base,
              curve: ZplayMotion.standard,
              padding: const EdgeInsets.symmetric(
                horizontal: ZplaySpacing.s12,
                vertical: ZplaySpacing.s8,
              ),
              decoration: BoxDecoration(
                // The fill says selection, nothing else. It was an 0.85
                // near-black chip behind a 1-1.5 dp accent border with an
                // accent bloom under it - the bordered box this page's language
                // exists to remove.
                color: isSelectedGenre || _isOpen
                    ? tokens.accentSubtle
                    : (state.highlighted
                        ? tokens.borderStrong
                        : tokens.borderDefault),
                borderRadius: ZplayRadius.mdAll,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Category glyph badge. A swatch's fill is its own content,
                  // so this container stays; the colours under it do not.
                  Container(
                    padding: const EdgeInsets.all(ZplaySpacing.s4),
                    decoration: BoxDecoration(
                      color: isSelectedGenre
                          ? tokens.accentSubtle
                          : tokens.borderSubtle,
                      borderRadius: ZplayRadius.smAll,
                    ),
                    child: Icon(
                      genreIcon,
                      size: 15,
                      color: isSelectedGenre
                          ? tokens.accent
                          : tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(width: ZplaySpacing.s8),

                  // Selected Category Text. Accent is the state signal for the
                  // genre that is on; the rest is weight and brightness.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      widget.selectedGenre,
                      overflow: TextOverflow.ellipsis,
                      style: (isSelectedGenre
                              ? ZplayType.label.copyWith(
                                  weight: FontWeight.w700,
                                )
                              : ZplayType.label)
                          .toStyle(
                        color: isSelectedGenre
                            ? tokens.accent
                            : (state.highlighted
                                ? tokens.textPrimary
                                : tokens.textEmphasis),
                      ),
                    ),
                  ),
                  const SizedBox(width: ZplaySpacing.s4),

                  // Animated Rotating Chevron
                  AnimatedRotation(
                    turns: _isOpen ? 0.5 : 0.0,
                    duration: ZplayMotion.base,
                    curve: ZplayMotion.standard,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 19,
                      color: _isOpen || isSelectedGenre
                          ? tokens.accent
                          : tokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DropdownOverlayContent extends StatefulWidget {
  final LayerLink layerLink;
  final Size buttonSize;
  final Offset buttonOffset;
  final Size screenSize;
  final List<String> genres;
  final String selectedGenre;
  final Animation<double> anim;
  final Animation<double> fadeAnim;
  final VoidCallback onClose;
  final ValueChanged<String> onSelect;

  const _DropdownOverlayContent({
    required this.layerLink,
    required this.buttonSize,
    required this.buttonOffset,
    required this.screenSize,
    required this.genres,
    required this.selectedGenre,
    required this.anim,
    required this.fadeAnim,
    required this.onClose,
    required this.onSelect,
  });

  @override
  State<_DropdownOverlayContent> createState() => _DropdownOverlayContentState();
}

class _DropdownOverlayContentState extends State<_DropdownOverlayContent> {
  final TextEditingController _filterController = TextEditingController();
  String _filterQuery = '';

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  IconData _getGenreIcon(String genre) {
    switch (genre.toLowerCase()) {
      case 'all':
        return Icons.auto_stories_rounded;
      case 'action':
        return Icons.flash_on_rounded;
      case 'adventure':
        return Icons.explore_rounded;
      case 'comedy':
        return Icons.sentiment_very_satisfied_rounded;
      case 'drama':
        return Icons.theater_comedy_rounded;
      case 'ecchi':
        return Icons.favorite_border_rounded;
      case 'fantasy':
        return Icons.auto_fix_high_rounded;
      case 'harem':
        return Icons.groups_rounded;
      case 'historical':
        return Icons.account_balance_rounded;
      case 'horror':
        return Icons.nights_stay_rounded;
      case 'isekai':
        return Icons.cyclone_rounded;
      case 'martial arts':
        return Icons.sports_martial_arts_rounded;
      case 'mature':
        return Icons.explicit_rounded;
      case 'mystery':
        return Icons.search_rounded;
      case 'psychological':
        return Icons.psychology_rounded;
      case 'romance':
        return Icons.favorite_rounded;
      case 'school life':
        return Icons.school_rounded;
      case 'sci-fi':
        return Icons.rocket_launch_rounded;
      case 'seinen':
        return Icons.person_rounded;
      case 'shounen':
        return Icons.local_fire_department_rounded;
      case 'slice of life':
        return Icons.coffee_rounded;
      case 'sports':
        return Icons.sports_baseball_rounded;
      case 'supernatural':
        return Icons.bolt_rounded;
      case 'tragedy':
        return Icons.heart_broken_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isMobile = widget.screenSize.width < 500;

    // Calculate dropdown dimensions
    final menuWidth = isMobile
        ? (widget.screenSize.width - 32).clamp(280.0, 360.0)
        : 380.0;
    const menuMaxHeight = 440.0;

    // Determine horizontal alignment relative to button
    final bool alignRight = (widget.buttonOffset.dx + menuWidth) > widget.screenSize.width - 16;
    final double leftOffset = alignRight
        ? -(menuWidth - widget.buttonSize.width)
        : 0.0;

    // Filtered genre list
    final filteredGenres = widget.genres.where((g) {
      if (_filterQuery.isEmpty) return true;
      return g.toLowerCase().contains(_filterQuery.toLowerCase());
    }).toList();

    return Stack(
      children: [
        // Full screen invisible barrier to dismiss dropdown on tap.
        //
        // Deliberately NOT a FocusableCard: it is a modal scrim, and making it a
        // focus stop adds an invisible screen-sized target to traversal. The
        // remote's dismiss path is the trigger button above (itself a
        // FocusableCard) which toggles this closed — the same reasoning that
        // left the player's three panel scrims as plain detectors.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            child: const SizedBox.expand(),
          ),
        ),

        // Animated Dropdown Menu
        Positioned(
          child: CompositedTransformFollower(
            link: widget.layerLink,
            showWhenUnlinked: false,
            offset: Offset(leftOffset, widget.buttonSize.height + 8),
            child: FadeTransition(
              opacity: widget.fadeAnim,
              child: ScaleTransition(
                scale: widget.anim,
                alignment: alignRight ? Alignment.topRight : Alignment.topLeft,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: menuWidth,
                    constraints: const BoxConstraints(maxHeight: menuMaxHeight),
                    // A popover is a surface, so it keeps a container - but the
                    // fill is its own separation. What went: the two-stop
                    // near-black gradient, the 1.5 dp accent border, the accent
                    // bloom under it and the 24-sigma full-panel
                    // `BackdropFilter` this design language warns about. What
                    // is left is one neutral drop, which is the only thing a
                    // menu needs to sit above the page.
                    decoration: BoxDecoration(
                      color: tokens.surfaceOverlay,
                      borderRadius: ZplayRadius.lgAll,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Header / Filter Search ──
                        //
                        // One heading primitive for the title and the count. It
                        // replaces a sparkle glyph, an 0.9-white w800 title and a
                        // filled "N Tags" pill; the primitive draws the count
                        // itself, muted and tabular, because a count is not a
                        // state for the accent to mark.
                        SectionHeader(
                          title: 'Manga Categories',
                          count: widget.genres.length,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            ZplaySpacing.s16,
                            ZplaySpacing.s4,
                            ZplaySpacing.s16,
                            ZplaySpacing.s12,
                          ),
                          // A filter input is a form field, so it keeps a fill
                          // and its hairline. What went was a white 0.06 wash
                          // inside a white 0.08 border - a box drawn around a
                          // box, neither of which said "type here".
                          child: Container(
                            height: 38,
                            decoration: BoxDecoration(
                              color: tokens.surface,
                              borderRadius: ZplayRadius.smAll,
                              border: Border.fromBorderSide(tokens.hairline),
                            ),
                            child: TextField(
                              controller: _filterController,
                              onChanged: (val) => setState(() => _filterQuery = val),
                              style: ZplayType.label.toStyle(color: tokens.textPrimary),
                              decoration: InputDecoration(
                                hintText: 'Filter categories...',
                                hintStyle: ZplayType.bodySmall.toStyle(
                                  color: tokens.textMuted,
                                ),
                                prefixIcon: Icon(
                                  Icons.search_rounded,
                                  size: 18,
                                  color: tokens.textSecondary,
                                ),
                                // The clear action was a bare `IconButton`, so a
                                // remote could not reach it and its splash was a
                                // second indicator. The card is the one way this
                                // app makes something reachable, and the ring is
                                // its only marker.
                                suffixIcon: _filterQuery.isNotEmpty
                                    ? FocusableCard(
                                        onTap: () {
                                          _filterController.clear();
                                          setState(() => _filterQuery = '');
                                        },
                                        builder: (_, state) => CardFocusRing(
                                          focused: state.focused,
                                          radius: ZplayRadius.xsAll,
                                          child: SizedBox(
                                            width: 34,
                                            height: 34,
                                            child: Icon(
                                              Icons.close_rounded,
                                              size: 16,
                                              color: state.highlighted
                                                  ? tokens.textPrimary
                                                  : tokens.textMuted,
                                            ),
                                          ),
                                        ),
                                      )
                                    : null,
                                suffixIconConstraints: const BoxConstraints(
                                  minWidth: 34,
                                  minHeight: 34,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: ZplaySpacing.s12,
                                  vertical: ZplaySpacing.s8,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // ── Categories List / Grid ──
                        Flexible(
                          child: filteredGenres.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(ZplaySpacing.s24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.search_off_rounded,
                                        size: 32,
                                        color: tokens.textDisabled,
                                      ),
                                      const SizedBox(height: ZplaySpacing.s8),
                                      Text(
                                        'No matching categories',
                                        style: ZplayType.bodySmall.toStyle(
                                          color: tokens.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : RawScrollbar(
                                  thumbColor: tokens.accent.withValues(alpha: 0.35),
                                  radius: const Radius.circular(ZplayRadius.sm),
                                  thickness: 4,
                                  padding: const EdgeInsets.only(right: ZplaySpacing.s4),
                                  child: GridView.builder(
                                    padding: const EdgeInsets.all(ZplaySpacing.s12),
                                    shrinkWrap: true,
                                    physics: const BouncingScrollPhysics(),
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: ZplaySpacing.s8,
                                      crossAxisSpacing: ZplaySpacing.s8,
                                      mainAxisExtent: 44,
                                    ),
                                    itemCount: filteredGenres.length,
                                    itemBuilder: (context, index) {
                                      final genre = filteredGenres[index];
                                      final isSelected = genre == widget.selectedGenre;
                                      final icon = _getGenreIcon(genre);

                                      return _CategoryItemTile(
                                        genre: genre,
                                        icon: icon,
                                        isSelected: isSelected,
                                        onTap: () => widget.onSelect(genre),
                                      );
                                    },
                                  ),
                                ),
                        ),

                        // ── Footer / Reset to All ──
                        //
                        // Secondary, not primary: clearing the filter is a way
                        // out of the current selection, not this page's main
                        // action. It was an `InkWell` over its own filled and
                        // accent-bordered box, and the divider above it is gone
                        // - the gap and the pill's own scrim draw the seam.
                        if (widget.selectedGenre != 'All')
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              ZplaySpacing.s12,
                              ZplaySpacing.s4,
                              ZplaySpacing.s12,
                              ZplaySpacing.s12,
                            ),
                            child: PillButton(
                              label: 'Reset to All Categories',
                              variant: PillVariant.secondary,
                              icon: Icons.refresh_rounded,
                              expand: true,
                              onPressed: () => widget.onSelect('All'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryItemTile extends StatelessWidget {
  final String genre;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryItemTile({
    required this.genre,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  /// The tile's own radius, also handed to the ring so it hugs the fill.
  static const BorderRadius _radius = ZplayRadius.smAll;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return FocusableCard(
      onTap: onTap,
      builder: (context, state) {
        return CardFocusRing(
          // The tile had a 1.4 dp accent border and an accent glow of its own
          // but no ring, so a remote landing on it moved nothing.
          focused: state.focused,
          radius: _radius,
          // Every state here is paint-only: the fill and the glyph colour
          // change, nothing else does, so neither hover nor selection can move
          // the tile in the 2-column grid.
          child: AnimatedContainer(
            duration: ZplayMotion.fast,
            curve: ZplayMotion.standard,
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s12,
              vertical: ZplaySpacing.s8,
            ),
            decoration: BoxDecoration(
              // Selected is the accent's own surface blend; unselected is no
              // fill at all, with the hover wash carrying the pointer case. The
              // 6 dp accent dot that used to glow beside the label is gone with
              // the border and the shadow: the fill and the accent glyph are
              // what say selected, and a glow was the third thing saying it.
              color: isSelected
                  ? tokens.accentSubtle
                  : (state.highlighted
                      ? tokens.textPrimary.withValues(
                          alpha: ZplayOpacity.overlayHover,
                        )
                      : Colors.transparent),
              borderRadius: _radius,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: isSelected ? tokens.accent : tokens.textPrimary,
                ),
                const SizedBox(width: ZplaySpacing.s8),
                Expanded(
                  child: Text(
                    genre,
                    overflow: TextOverflow.ellipsis,
                    // One weight in every state: the descriptor is the fill and
                    // the accent, and a focus move should not restyle the label.
                    style: ZplayType.label.toStyle(
                      color: isSelected ? tokens.accent : tokens.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
