import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/layout/form_factor.dart';
import '../../services/theme/design_tokens.dart';
import '../../shell/app_shell_scope.dart';
import '../../widgets/common/tab_strip.dart';
import '../anime/anime_page.dart';
import '../audiobooks/audiobooks_page.dart';
import '../books/books_page.dart';
import '../collections/collections_page.dart';
import '../discover/discover_page.dart';
import '../iptv/iptv_page.dart';
import '../manga/manga_page.dart';
import '../music/music_page.dart';

/// The eight content verticals Browse switches between. Declaration order is
/// the switcher order and the stack index at once, so one list drives both.
enum BrowseVertical {
  moviesAndTv,
  collections,
  liveTv,
  anime,
  manga,
  books,
  audiobooks,
  music,
}

extension BrowseVerticalX on BrowseVertical {
  String get label {
    switch (this) {
      case BrowseVertical.moviesAndTv:
        return 'Movies & TV';
      case BrowseVertical.collections:
        return 'Collections';
      case BrowseVertical.liveTv:
        return 'Live TV';
      case BrowseVertical.anime:
        return 'Anime';
      case BrowseVertical.manga:
        return 'Manga';
      case BrowseVertical.books:
        return 'Books';
      case BrowseVertical.audiobooks:
        return 'Audiobooks';
      case BrowseVertical.music:
        return 'Music';
    }
  }

  IconData get icon {
    switch (this) {
      case BrowseVertical.moviesAndTv:
        return Icons.movie_rounded;
      case BrowseVertical.collections:
        return Icons.collections_rounded;
      case BrowseVertical.liveTv:
        return Icons.live_tv_rounded;
      case BrowseVertical.anime:
        return Icons.animation_rounded;
      case BrowseVertical.manga:
        return Icons.auto_stories_rounded;
      case BrowseVertical.books:
        return Icons.menu_book_rounded;
      case BrowseVertical.audiobooks:
        return Icons.headphones_rounded;
      case BrowseVertical.music:
        return Icons.music_note_rounded;
    }
  }

  /// Every vertical is a whole `Scaffold` with its own top bar, so Browse can
  /// stack it as-is and never rescale or re-head the page.
  Widget get page {
    switch (this) {
      case BrowseVertical.moviesAndTv:
        return const DiscoverPage();
      case BrowseVertical.collections:
        return const CollectionsPage();
      case BrowseVertical.liveTv:
        return const IptvPage();
      case BrowseVertical.anime:
        return const AnimePage();
      case BrowseVertical.manga:
        return const MangaPage();
      case BrowseVertical.books:
        return const BooksPage();
      case BrowseVertical.audiobooks:
        return const AudiobooksPage();
      case BrowseVertical.music:
        return const MusicPage();
    }
  }
}

/// Built once: the labels and icons are constants, and rebuilding them on every
/// switch would churn eight widgets for nothing.
final List<TabStripOption<BrowseVertical>> _options = [
  for (final vertical in BrowseVertical.values)
    TabStripOption<BrowseVertical>(
      value: vertical,
      label: vertical.label,
      icon: vertical.icon,
    ),
];

/// Derived from the same source as [_options], which is what keeps the pill at
/// index `n` and the stack child at index `n` the same vertical.
final List<Widget> _verticals = [
  for (final vertical in BrowseVertical.values) vertical.page,
];

/// Browse: one vertical switcher above the eight vertical pages.
///
/// The verticals are stacked rather than swapped because each of them owns
/// scroll controllers, catalog filters and load state; an [IndexedStack] keeps
/// the off-screen seven mounted, so switching away and back returns to the same
/// scroll offset and the same filtered catalog instead of a refetch from the
/// top. The shell owns navigation, so Browse adds only the switcher band and
/// nothing else.
class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  BrowseVertical _vertical = BrowseVertical.moviesAndTv;

  /// The shell's request channel for a specific vertical, or null outside a
  /// shell.
  ///
  /// The top bar's Live TV destination lands here rather than on a slot of its
  /// own, so the shell asks Browse to select a vertical and Browse is the one
  /// that changes. It is subscribed in [didChangeDependencies] and not read in
  /// [build], because the request can arrive while this page is mounted but
  /// hidden - the shell's `IndexedStack` keeps every slot alive - and a read at
  /// build time would only see the value once the page was already visible.
  ValueListenable<BrowseVertical>? _verticalRequest;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = AppShellScope.of(context)?.browseVertical;
    if (identical(next, _verticalRequest)) return;
    _verticalRequest?.removeListener(_onVerticalRequest);
    _verticalRequest = next;
    _verticalRequest?.addListener(_onVerticalRequest);
  }

  void _onVerticalRequest() {
    final requested = _verticalRequest?.value;
    if (!mounted || requested == null || requested == _vertical) return;
    setState(() => _vertical = requested);
  }

  @override
  void dispose() {
    _verticalRequest?.removeListener(_onVerticalRequest);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Ten-foot pills are sized like the shell rail's TV rows and the band grows
    // with them, per the prototype's TV variant; the pointer height matches the
    // rail's own pointer row so the two read as one chrome.
    final television =
        FormFactorService.of(context) == FormFactor.television;
    final double gutter = television ? ZplaySpacing.s32 : ZplaySpacing.s20;
    // The shell is inset-agnostic and wraps no slot in a `SafeArea`, so the band
    // owns the status bar strip for this slot and pays the inset itself instead
    // of taking it out of its gutter: `immersiveSticky` zeroes it on Android, but
    // on iOS the pills would otherwise sit under the status bar. The verticals
    // below are told it is already spent.
    final EdgeInsets inset = MediaQuery.paddingOf(context);

    return FocusTraversalGroup(
      // The group is what scopes D-pad order to this subtree, so the band is
      // reached before the visible vertical instead of Flutter guessing one
      // geometric order over the shell and the page together. Its default
      // policy is already reading order, which is the order wanted here.
      child: Column(
        // Stretch so the band and its hairline span the content width; a centre
        // aligned Column would size the band to the pills and float it.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.bg,
              border: Border(bottom: tokens.hairline),
            ),
            child: Padding(
              padding: EdgeInsets.only(
                top: (television ? ZplaySpacing.s20 : ZplaySpacing.s16) +
                    inset.top,
                left: gutter + inset.left,
                right: gutter + inset.right,
                bottom: television ? ZplaySpacing.s16 : ZplaySpacing.s12,
              ),
              child: TabStrip<BrowseVertical>(
                options: _options,
                selected: _vertical,
                onSelected: (vertical) => setState(() => _vertical = vertical),
                semanticsLabel: 'Browse verticals',
                height: television ? ZplaySpacing.s64 : ZplaySpacing.s48,
              ),
            ),
          ),
          Expanded(
            // Clipped, and this is the boundary the shell's own clip cannot
            // reach. Every vertical below is a whole page whose main scroll list
            // is a `ListView(clipBehavior: Clip.none)`, written to spill past its
            // viewport. Above the shell that spill is outside the window and
            // therefore invisible; inside one it lands on this band, and a
            // scrolled Anime page painted its hero straight over the pills. The
            // shell clips at the content column's top, which is above the band,
            // so the rule has to be restated here: whatever stacks chrome above a
            // page owns clipping that page.
            child: ClipRect(
              // One slot gets exactly one inset consumer: the band has already
              // covered the status bar strip, so the verticals below must not pay
              // the same inset again. They read `paddingOf` in their own floating
              // headers and app bars, so clearing the padding here starts each of
              // them flush under the band instead of a status bar lower.
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: IndexedStack(index: _vertical.index, children: _verticals),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
