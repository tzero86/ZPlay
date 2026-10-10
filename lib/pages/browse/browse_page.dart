import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/content/content_settings.dart';
import '../../services/layout/form_factor.dart';
import '../../services/theme/design_tokens.dart';
import '../../shell/app_shell_scope.dart';
import '../../widgets/common/tab_strip.dart';
import '../adult/adult_page.dart';
import '../anime/anime_page.dart';
import '../audiobooks/audiobooks_page.dart';
import '../books/books_page.dart';
import '../collections/collections_page.dart';
import '../discover/discover_page.dart';
import '../iptv/iptv_page.dart';
import '../manga/manga_page.dart';
import '../music/music_page.dart';

/// The content verticals Browse switches between. Declaration order is
/// the switcher order and the stack index at once, so one list drives both.
///
/// [adult] is declared last and is offered only while the global Adult Content
/// switch is on. Appending it is what keeps every value above it at the index
/// it already has: inserting it anywhere else renumbers the verticals that
/// follow and points the switcher at the wrong page.
enum BrowseVertical {
  moviesAndTv,
  collections,
  liveTv,
  anime,
  manga,
  books,
  audiobooks,
  music,
  adult,
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
      case BrowseVertical.adult:
        return '18+';
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
      case BrowseVertical.adult:
        return Icons.eighteen_up_rating_rounded;
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
      case BrowseVertical.adult:
        return const AdultPage();
    }
  }
}

/// The switcher's pills, the stack's children, and the verticals behind them,
/// derived together from one list.
///
/// They come from one call rather than three top-level lists because the stack
/// selects by index: lists built from the enum independently can disagree about
/// which vertical a child belongs to, and a one-entry difference in length is
/// enough for the stack to show a page the selected pill does not name. One
/// function, one source, all three outputs.
///
/// The stack's index is looked up in the returned verticals rather than read
/// off the enum. An enum index is wrong twice over once a vertical is gated:
/// it addresses a child that is not in the list at all.
({List<BrowseVertical> verticals, List<TabStripOption<BrowseVertical>> options, List<Widget> pages})
    _buildVerticals({required bool adultEnabled}) {
  // `BrowseVertical.values` minus the verticals the current settings do not
  // offer. Only [BrowseVertical.adult] is conditional today; the filter is
  // written as a per-vertical rule so adding another gated vertical does not
  // mean re-deriving which list is authoritative.
  final visible = <BrowseVertical>[
    for (final vertical in BrowseVertical.values)
      if (vertical != BrowseVertical.adult || adultEnabled) vertical,
  ];

  return (
    verticals: visible,
    // Built per call rather than cached in a top-level final, because the list
    // is no longer constant: the labels and icons still are, and the strip is
    // rebuilt only when the visible set actually changes.
    options: [
      for (final vertical in visible)
        TabStripOption<BrowseVertical>(
          value: vertical,
          label: vertical.label,
          icon: vertical.icon,
        ),
    ],
    // `vertical.page` returns a `const` widget, so the canonical instance is
    // reused on every rebuild: an adult toggle re-lists these children without
    // remounting the verticals that were already stacked, and the off-screen
    // pages keep their scroll offsets.
    pages: [for (final vertical in visible) vertical.page],
  );
}

/// Browse: one vertical switcher above the vertical pages.
///
/// The verticals are stacked rather than swapped because each of them owns
/// scroll controllers, catalog filters and load state; an [IndexedStack] keeps
/// the off-screen ones mounted, so switching away and back returns to the same
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
  void initState() {
    super.initState();
    ContentSettings.adultEnabled.addListener(_onAdultContentChanged);
  }

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

  /// The 18+ vertical stops being offered the moment the global Adult Content
  /// switch goes off, so a selection that names it has to fall back - or the
  /// strip would show no pill selected and the stack no child to show.
  void _onAdultContentChanged() {
    if (!mounted) return;
    if (!ContentSettings.adultEnabled.value &&
        _vertical == BrowseVertical.adult) {
      setState(() => _vertical = BrowseVertical.moviesAndTv);
    }
  }

  /// The visible verticals are settings, not a constant, so the whole layout
  /// is rebuilt from the switch's live value.
  ///
  /// Read through a [ValueListenableBuilder] rather than at build time: the
  /// shell keeps every slot mounted, so Browse can sit hidden while the switch
  /// is flipped in Settings, and a value read during build would be read again
  /// on the next unrelated rebuild - with no rebuild coming until the user
  /// returns, the 18+ pill would still be there.
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ContentSettings.adultEnabled,
      builder: (context, adultEnabled, _) =>
          _buildLayout(adultEnabled: adultEnabled),
    );
  }

  Widget _buildLayout({required bool adultEnabled}) {
    // One derivation, one lookup, two consumers: the strip's `selected` and
    // the stack's `index` read the same element of the same list, so they
    // cannot name different verticals even while the visible set is changing
    // underneath them.
  final verticals = _buildVerticals(adultEnabled: adultEnabled);
  // `_onAdultContentChanged` moves the selection off a vertical that has just
  // stopped being offered, so the lookup succeeds. The clamp is the index
  // guard for [IndexedStack], which throws on an out-of-range index, and it
  // lands on `moviesAndTv` - the first visible vertical, and the default
  // selection, for the same reason it is the default.
  final selectedIndex = verticals.verticals
      .indexOf(_vertical)
      .clamp(0, verticals.pages.length - 1);
  final selected = verticals.verticals[selectedIndex];
    // Ten-foot pills are sized like the shell rail's TV rows and the band grows
    // with them, per the prototype's TV variant; the pointer height matches the
    // rail's own pointer row so the two read as one chrome.
    final television =
        FormFactorService.of(context) == FormFactor.television;
    final double gutter = television ? ZplaySpacing.s32 : ZplaySpacing.s20;
    // The band pays for the chrome above this slot out of its own gutter rather
    // than into it: `paddingOf(context).top` is the shell's top bar on tablet,
    // desktop and television - the bar is painted over this page, so the page is
    // charged its height - and the status bar strip on a phone, where the bar is
    // at the foot. Adding rather than subtracting is what keeps the pills clear
    // of either. The verticals below are told it is already spent.
    final EdgeInsets inset = MediaQuery.paddingOf(context);

    // No `FocusTraversalGroup` around this column. The group would install a
    // scope boundary between the switcher band and the shell's top bar, and a
    // boundary is what stops a remote crossing between chrome and page: the
    // shell removed its own groups for exactly this reason (`AppShell._layout`),
    // because traversal running off a scope edge hits `stop` and never leaves.
    // Without it the shell stays one focus tree, so D-pad UP runs from the
    // vertical's content through these pills to the shared menu by geometry
    // alone, and DOWN runs back the same way.
    return Column(
      // Stretch so the row's padding reaches both content edges and the strip
      // is laid out against the page's full width; a centre aligned Column would
      // size the row to the pills and float it.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // **No band.** The strip used to sit on an opaque `tokens.bg` fill with
        // a `tokens.hairline` under it, and that fill was the seam: the shell's
        // nav bar now blends into whatever the page paints under it
        // (`AppShell._nav`), so a page that pins its own opaque strip above its
        // content re-creates the "different app" boundary in the one place the
        // nav bar just stopped drawing one. The pills are an overlay on the
        // canvas - `TabStrip` paints no fill and no edge of its own, so all this
        // row has to be is the padding that pays for the chrome above it.
        //
        // Nothing scrolls *under* this row: the verticals live in the `Expanded`
        // below it and are clipped there, so there is no legibility case that
        // would justify the scroll-driven tint Home's glass bar uses.
        Padding(
          padding: EdgeInsets.only(
            top: (television ? ZplaySpacing.s20 : ZplaySpacing.s16) +
                inset.top,
            left: gutter + inset.left,
            right: gutter + inset.right,
            bottom: television ? ZplaySpacing.s16 : ZplaySpacing.s12,
          ),
          child: TabStrip<BrowseVertical>(
            options: verticals.options,
            selected: selected,
            onSelected: (vertical) =>
                setState(() => _vertical = vertical),
            semanticsLabel: 'Browse verticals',
            height: television ? ZplaySpacing.s64 : ZplaySpacing.s48,
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
            // covered the chrome above this slot - the shell's top bar, or the
            // status bar strip on a phone - so the verticals below must not pay
            // the same inset again. They read `paddingOf` in their own floating
            // headers and app bars, so clearing the padding here starts each of
            // them flush under the band instead of one chrome-height lower.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: IndexedStack(
                index: selectedIndex,
                children: verticals.pages,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
