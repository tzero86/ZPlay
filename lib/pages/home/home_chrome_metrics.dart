import 'package:flutter/widgets.dart';

import '../../services/home/home_page_settings.dart';
import '../../services/layout/form_factor.dart';
import '../../services/theme/design_tokens.dart';

/// The page's own control row, below `MediaQuery` top padding: Home's two
/// page-level actions with 4 dp of breathing room above and below them.
///
/// It is one row on every form factor and carries only what is the page's - the
/// AI quiz and the calendar. The brand and the destinations belong to the
/// shell's top bar, and the All/Movies/Series/Anime split belongs to Browse, so
/// the row carries no filter at all: Home is one feed. What is left is the two
/// actions, and they are what set the height.
const double televisionAppBarHeight = 36;

/// The pointer's version of the same row: 4 + 44 + 4.
///
/// The 44 is the touch minimum the two actions present, so the row is their
/// height plus its own breathing room - the actions do not set the chrome's
/// height by themselves.
const double pointerAppBarHeight = 52;

/// True only on a television. Read in one place so the height, the tab row and
/// the bar's own furniture cannot disagree about which layout they are in.
bool homeIsTelevision(BuildContext context) =>
    FormFactorService.of(context) == FormFactor.television;

/// Whether the page's own control row has anything in it.
///
/// The row holds exactly the two actions a user can switch off — the TV
/// airing calendar and the recommendation quiz — and nothing else.
///
/// That matters because the band above the hero is chrome *for* that row: it
/// is pinned to the row's height and painted with a tint. With both actions
/// off there is no row, so there must be no band either. Without this, Home
/// wore an empty bar across its top — the row's faint scrim at the top of the
/// page and the solid tint once scrolled, on a phone and a television alike.
/// A desktop escaped it only because a tab strip gave that row a child there,
/// which is why the bug looked phone-specific and was not.
///
/// Anything that ever joins that row has to be counted here too, or the
/// users with both actions off get the empty band back.
bool homeHasControlRow(BuildContext context) =>
    HomePageSettings.enableCalendar.value ||
    HomePageSettings.enableAiQuiz.value;

/// The page's own control row, below `MediaQuery` top padding — zero when the
/// row draws nothing, so everything derived from it (the scroll inset, the
/// hero's bleed, the skeleton's top slot, the hero-height arithmetic)
/// collapses together instead of each holding its own reservation. See
/// [homeHasControlRow].
double homeAppBarHeightFor(BuildContext context) => !homeHasControlRow(context)
    ? 0
    : (homeIsTelevision(context)
          ? televisionAppBarHeight
          : pointerAppBarHeight);

/// Everything the page draws above its first pixel of content: the band the
/// shell's nav bar occupies, the page's own control row, and the gap under it.
///
/// The shell's top bar is painted *over* this page rather than stacked above
/// it, so the page's box starts at the window's top edge and the bar is
/// charged here instead: `padding.top` is the bar's exact height wherever the
/// shell draws it, and zero on a phone, where the bar is at the foot and there
/// is no band to pay for. Nothing here is a second charge for the shell, and
/// the sum is what the page's own scroll inset reserves - which is also why
/// the hero's bleed reaches the window's top edge under the bar.
double homeTopInsetFor(BuildContext context) =>
    MediaQuery.paddingOf(context).top +
    homeAppBarHeightFor(context) +
    ZplaySpacing.s8;
