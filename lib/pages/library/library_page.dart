import 'package:flutter/material.dart';

import '../../services/content/content_settings.dart';
import '../../services/download/download_service.dart';
import '../../services/layout/form_factor.dart';
import '../../services/my_list/my_list_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/common/segmented_tabs.dart';
import '../downloads/downloads_page.dart';
import '../my_list/my_list_page.dart';

/// The two Library tabs. Declaration order is the switcher order and the stack
/// index at once, so one list drives both.
enum LibraryTab {
  myList,
  downloads,
}

extension LibraryTabX on LibraryTab {
  String get label {
    switch (this) {
      case LibraryTab.myList:
        return 'My List';
      case LibraryTab.downloads:
        return 'Downloads';
    }
  }

  Widget get page {
    switch (this) {
      case LibraryTab.myList:
        return const MyListPage();
      case LibraryTab.downloads:
        return const DownloadsPage();
    }
  }
}

/// The switcher's options, carrying the live count each tab's body holds.
///
/// The prototype labels the two tabs with their totals (`My List (8)`,
/// `Downloads (4)`), and `SegmentedTabs` draws a count under the label rather
/// than beside it, so the label text the tests match stays exactly `My List`.
List<SegmentedTabOption<LibraryTab>> _libraryTabOptions() => [
  for (final tab in LibraryTab.values)
    SegmentedTabOption<LibraryTab>(
      value: tab,
      label: tab.label,
      count: switch (tab) {
        LibraryTab.myList => MyListService.visibleItems.length,
        LibraryTab.downloads => DownloadService.instance.tasksNotifier.value.length,
      },
    ),
];

/// Derived from the same source as [_libraryTabOptions], which is what keeps the
/// segment at index `n` and the stack child at index `n` the same tab.
final List<Widget> _tabs = [
  for (final tab in LibraryTab.values) tab.page,
];

/// Library: My List and Downloads under one switcher.
///
/// Both bodies are stacked rather than swapped, because each owns state that is
/// expensive or annoying to lose: My List holds a search query, a type filter
/// and a sort, Downloads holds in-flight transfer state and its own scroll
/// offset. An [IndexedStack] keeps the off-screen tab mounted, so coming back
/// returns to that state instead of a refetch from the top.
///
/// `SegmentedTabs` rather than a `TabStrip`: two labels fit one track on any
/// width, and the sliding indicator is the clearer read for a pair of peers.
///
/// No History tab, deliberately rather than by omission: watch history has no
/// single owner to read from. Anime Arabic keeps its own log in
/// `anime_arabic_service.dart`, Trakt and Simkl each keep their own
/// continue-watching lists, and `ContinueWatchingService` keeps resume sessions.
/// A tab would have to pick one source and hide the others, so it waits for a
/// service that unifies them.
///
/// The shell owns navigation, so this page contributes the switcher band and
/// nothing else; both tabs keep their own header and their own `Scaffold`.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  LibraryTab _tab = LibraryTab.myList;

  @override
  Widget build(BuildContext context) {
    // Ten-foot controls are sized like the shell rail's TV rows, so the switcher
    // and the rail read as one chrome; the pointer sizes match the rail's own
    // pointer rows.
    //
    // The rail's TV row is 48 dp (see `ShellRail._televisionRowHeight`). This
    // used to pass 64 dp, which the comment above already claimed was the rail's
    // size - so the switcher was a third taller than the rail it was supposed to
    // match, and nearly half again as tall as Home's filter pills. Three
    // top-level tabs at three different heights is what made My List look like a
    // different app from Browse.
    const double televisionTabHeight = ZplaySpacing.s48;
    final television =
        FormFactorService.of(context) == FormFactor.television;
    final double gutter = television ? ZplaySpacing.s32 : ZplaySpacing.s20;

    return FocusTraversalGroup(
      // Scopes D-pad order to this subtree, so the switcher is reached before
      // the visible tab instead of Flutter guessing one geometric order over the
      // switcher row and the content together.
      child: Column(
        // Stretch, not the default centre: the row's padding has to reach both
        // page edges so the switcher sits on the same gutter every other page
        // header uses; a centre aligned Column would size the row to the control
        // and float it.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // **No band.** The switcher used to sit on an opaque `tokens.bg` fill
          // with a `tokens.hairline` under it. That fill was the seam: the shell
          // nav bar blends over the page now, so a page that pins its own opaque
          // strip re-draws the boundary the bar just stopped drawing. The pills
          // are an overlay on the canvas - `SegmentedTabs` paints no fill of its
          // own - so all this row has to be is the padding that pays for the
          // chrome above it.
          //
          // The row is stretched to the page edges, but the control inside it is
          // not. `Align(alignment: Alignment.centerLeft)` hands the control a
          // *loose* constraint, which is what lets `SegmentedTabs` size its
          // track to its own labels - the same path the app bar's pills take.
          //
          // Without it the `Column`'s `CrossAxisAlignment.stretch` made the
          // constraints tight, and the rule in `SegmentedTabs` for a tight
          // parent is "divide whatever you are given". Two tabs across 896 dp
          // is a pair of 440 dp buttons on a television, which is why My List
          // looked like a different app from Browse: the band was right and the
          // thing inside it was enormous.
          Padding(
            // The chrome above this slot, out of the gutter rather than into
            // it: the shell's top bar on tablet, desktop and television - the
            // bar is painted over this page, so the page is charged its height
            // - and the status bar strip on a phone, where the bar is at the
            // foot. Browse's band pays the same inset the same way, which is
            // what keeps the two switchers on one line under one bar.
            padding: EdgeInsets.only(
              top:
                  (television ? ZplaySpacing.s12 : ZplaySpacing.s16) +
                  MediaQuery.paddingOf(context).top,
              left: gutter,
              right: gutter,
              bottom: ZplaySpacing.s12,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ListenableBuilder(
                // One subscription for both counts; the notifiers are static,
                // so the merge is built once instead of on every rebuild.
                listenable: Listenable.merge([
                  MyListService.items,
                  ContentSettings.adultEnabled,
                  DownloadService.instance.tasksNotifier,
                ]),
                builder: (context, _) => SegmentedTabs<LibraryTab>(
                  options: _libraryTabOptions(),
                  selected: _tab,
                  onSelected: (tab) => setState(() => _tab = tab),
                  semanticsLabel: 'Library section',
                  height: television ? televisionTabHeight : ZplaySpacing.s48,
                ),
              ),
            ),
          ),
          Expanded(
            // Clipped for the same reason as Browse's verticals: a tab is a whole
            // page whose scroll list may spill past its own viewport, and the
            // only thing between that spill and this row is a clip. The shell's
            // clip sits above the row and cannot cover it.
            child: ClipRect(
              // One slot gets exactly one inset consumer, the same rule Browse
              // states for its verticals: this row has already paid the chrome
              // above the slot - the shell's top bar, or the status bar strip on
              // a phone - so the tabs below must not pay it a second time. Both
              // of them read `paddingOf` in their own headers (My List's
              // `SafeArea`, Downloads' header), and clearing it here is what
              // starts each flush under the switcher instead of a chrome-height
              // lower.
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: IndexedStack(index: _tab.index, children: _tabs),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
