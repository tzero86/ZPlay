import 'package:flutter/material.dart';

import '../../services/layout/form_factor.dart';
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

/// Built once: the labels are constants, and rebuilding them on every switch
/// would churn the control for nothing.
final List<SegmentedTabOption<LibraryTab>> _options = [
  for (final tab in LibraryTab.values)
    SegmentedTabOption<LibraryTab>(value: tab, label: tab.label),
];

/// Derived from the same source as [_options], which is what keeps the segment
/// at index `n` and the stack child at index `n` the same tab.
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
    final tokens = context.tokens;
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
      // band and the content together.
      child: Column(
        // Stretch, not the default centre: a band that shrank to the control's
        // own width would let the hairline and the bg stop short of the page
        // edges, which reads as a floating control rather than a band. The
        // control itself still sizes to its labels inside the gutter.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.bg,
              border: Border(bottom: tokens.hairline),
            ),
            child: Padding(
              padding: EdgeInsets.only(
                top: television ? ZplaySpacing.s12 : ZplaySpacing.s16,
                left: gutter,
                right: gutter,
                bottom: television ? ZplaySpacing.s12 : ZplaySpacing.s12,
              ),
              child: SegmentedTabs<LibraryTab>(
                options: _options,
                selected: _tab,
                onSelected: (tab) => setState(() => _tab = tab),
                semanticsLabel: 'Library section',
                height: television ? televisionTabHeight : ZplaySpacing.s48,
              ),
            ),
          ),
          Expanded(
            // Clipped for the same reason as Browse's verticals: a tab is a whole
            // page whose scroll list may spill past its own viewport, and the
            // only thing between that spill and this band is a clip. The shell's
            // clip sits above the band and cannot cover it.
            child: ClipRect(
              child: IndexedStack(index: _tab.index, children: _tabs),
            ),
          ),
        ],
      ),
    );
  }
}
