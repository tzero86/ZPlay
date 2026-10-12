# ZPlay — UX Findings

## Summary

This is a screen-by-screen usability review of ZPlay's real surfaces: Home, title Details,
the player chrome, Search, Discover, Catalog, My List, the whole Settings tree (root plus
appearance, player-studio and settings sub-pages), Anime (+ anime-arabic), Manga, Books,
Audiobooks, Music, IPTV, Downloads, Calendar and the two readers.

Method: static reading of `lib/` only. No builds, analyser, or test runs were performed
(the redesign is running in parallel on the same tree), so **nothing here was verified at
runtime**. Every finding cites the code that produces it. Where I reasoned from code to
user-visible consequence I say so; where a number is arithmetic on cited colour values it
is marked `[computed]`. Items I could not verify from source are marked `[INFERENCE]`.

32 findings: **4 Critical · 10 High · 11 Medium · 6 Low**, plus 10 positive observations
to protect. Findings are grouped by tier, not by screen; each one names the surface in its
heading so it can be routed to the right owner.

### The seven hypotheses from the brief — verified or refuted

| # | Hypothesis | Verdict |
|:-:|:--|:--|
| 1 | Hover/pressed/focus states missing or inconsistent | **Confirmed, worse than stated.** Hover is the *only* state that exists on most surfaces, and it is the state touch and TV cannot produce. Pressed exists on poster cards but not on the components that copy them. Focus exists almost nowhere and is never drawn as a ring. |
| 2 | Loading states are bare circular spinners | **Confirmed.** 46+ files use `CircularProgressIndicator`; only 3 skeleton implementations exist in the entire app, and only poster images get one. |
| 3 | Empty states are largely uncomposed | **Partially confirmed.** Three good ones exist (My List, Downloads, Books) and two excellent ones in the player; the *discovery* surfaces — Home filter, Catalog, Discover, Search — are bare one-liners with no action. The problem is inconsistency plus no shared component, not universal absence. |
| 4 | Error surfacing inconsistent: silent vs full-screen | **Confirmed, and it is four patterns, not two** — plus a fifth: row-level failures that disappear entirely and never tell the user anything. |
| 5 | Dead ends that force a re-search | **Sharpest instance confirmed** in the player's no-sources state for movies (the instruction points at a panel that is not rendered). Back-stack squashing via `pushReplacement` is a second, milder class. Notably, the worst historical dead end was already deliberately fixed (`_openSourcePicker`) — see Positives. |
| 6 | D-pad/TV focus traversal broken or absent | **Confirmed and total.** There is no TV detection, no focus traversal policy, no `Shortcuts`/`Actions` in `lib/pages`, and the primary content widget (`MovieCard`) is a `GestureDetector`, which Flutter does not focus. Several *navigational* controls are additionally hover-gated. On Android TV the app is usable only with a mouse. |
| 7 | Settings is one long scroll, no search, no grouping | **Confirmed with a correction.** The root is a 15-row category list, not a raw settings dump, and it has one `CATEGORIES` label — so it is *not* ungrouped by accident. The real defects are: no search, 15 rows on one scroll, two incompatible row behaviours interleaved (navigate vs toggle), and every sub-page overriding the user's palette with hardcoded chrome. |

### Recurring structural causes (fix these and most findings collapse)

1. **No shared presentational components.** `ErrorView` is the only shared state component, and its copy is hardcoded to “Could not load movies”. Empty, loading, back-button and section-header are re-implemented per screen.
2. **No interaction-state layer.** Hover, pressed and focus are re-derived per widget, so state coverage drifts (poster cards have all three; dock items, lists and rows have one; filter chips have none).
3. **No form-factor policy.** Layouts branch on `MediaQuery` width, but interaction branches on nothing. Hover-only affordances ship to touch and D-pad targets.

---

## Critical Issues

### Issue: Global search reports “no results” when every source has actually failed

**Current State**: `lib/pages/search/search_page.dart:269-334`. Both search legs swallow their
errors — addon search `.catchError` returns `[]` (269-272), CloudStream search `.catchError`
returns `{}` (328-331), and the surrounding `try` closes with `} catch (_) {}` (334). The body
then renders the loading spinner (495-498) and, because `_results` is empty, the empty state
`'No results for "$_lastQuery"'` (499-520).

**Problem**: A dead addon, an expired CloudStream runtime, or simply being offline produces
**exactly the same screen as a title that genuinely does not exist**. Search is the app's only
path to a specific title the user already has in mind, so the failure mode is not “something
went wrong” — it is “this app does not have The Bear”. The user then retries the same query,
edits it, or concludes their addons are useless. Zero diagnostics are surfaced, though
`lib/pages/search/search_page.dart` knows precisely which legs failed at the moment it
discards them.

**Recommendation**: Track failures instead of discarding them — increment a
`_failedSources` counter and collect `_sourceErrors` in both `catchError` handlers. Then split
the empty branch in three: (a) `_failedSources == 0` → today's empty state; (b)
`_results.isEmpty && _failedSources > 0` → error state reusing `ErrorView`
(`lib/widgets/common/error_view.dart`) with `onRetry: _performSearch` and copy naming the
count (“3 of 5 sources did not respond — check Addons or retry”); (c) partial results → render
what arrived, plus the existing “Searching more sources…” row turned into a warning line.
Also give `ErrorView` a `title` parameter so it stops saying “Could not load movies” on
non-catalog screens.

**Impact**: Converts the app's most trust-sensitive failure from “the content isn't here” into
“the source is down, retry or fix your addons” — the difference between a user uninstalling
and a user retrying.

**Implementation Notes**: `ErrorView` is already dependency-free and used by Home, Catalog and
Discover, so this is a copy change plus one counter, not new infrastructure.

### Issue: Continue Watching's play affordance is hover-only, so it is invisible on phones and TV

**Current State**: `lib/widgets/home/continue_watching_slider.dart:442-470` — the 44 px
circular Play button is wrapped in `AnimatedOpacity(opacity: _isHovered ? 1.0 : 0.0)` with
**no platform check**. Ten lines below, the Details/Remove buttons at 478-483 *are* gated
(`_isHovered || !(windows || macOS || linux)`), which proves the pattern was known and applied
only to the secondary controls.

**Problem**: Continue Watching is the app's most-used row — the fastest path back into
whatever you were watching. On a phone the tap target exists (372-395 is a `GestureDetector`
around the whole card) but **the affordance does not**: the user sees a progress bar and
nothing indicating the card resumes playback. On D-pad devices it is worse — there is no hover
and no focus, so the row cannot be activated at all. On desktop the button only appears if the
pointer happens to be over the card.

**Recommendation**: Make the play badge state-independent — always visible on touch form
factors, hover-revealed only where a mouse exists: `final hasPointer = (windows || macOS ||
linux);` then `opacity: (!hasPointer || _isHovered) ? 1.0 : 0.35` so desktop still gets the
reveal but never a fully hidden primary action. Add `Semantics(button: true, label: 'Resume
<name>')` at the same time (see Medium #M9 for the wider semantics gap).

**Impact**: Restores the primary action of the most-used row on the two form factors that
cannot hover; the row currently reads as a passive progress bar on phones.

### Issue: Android TV (D-pad) has no focus traversal, and the entire catalogue is unreachable with a remote

**Current State**:
- No TV/form-factor detection exists anywhere: grepping `lib/` for `isTV`, `androidtv`,
  `television`, `leanback`, `dpad` returns only IPTV *copy* text
  (`lib/pages/settings/appearance/live_tv_settings_page.dart:1032`) and an unrelated channel
  keyword list — no detection code.
- No focus traversal anywhere in `lib/pages`: no `FocusTraversalGroup`,
  `FocusTraversalOrder`, `Shortcuts`, `Actions`, or `FocusableActionDetector`.
- The primary content widget is not focusable: `MovieCard` is
  `MouseRegion > GestureDetector` (`lib/widgets/movie/movie_card.dart:96-101`), and
  `GestureDetector` is not a focusable node in Flutter. Same shape in
  `lib/widgets/anime/anime_card.dart:25-27`, `lib/widgets/manga/manga_card.dart:87-89`,
  `lib/widgets/iptv/iptv_channel_card.dart:26-28`, and the Continue Watching card
  (`lib/widgets/home/continue_watching_slider.dart:372-395`).
- Row navigation is hover-gated: the cast / seasons / episodes / related / similar arrows in
  `lib/pages/details/details_page.dart:1792-1800` are driven by the hover booleans
  `_isHoveringCast`…`_isHoveringSimilar` (call sites at 1208, 1282, 1375, 1515, 1749), and the
  hero carousel arrows by `_isHovering` (`lib/pages/home/home_page.dart:1406`).
- In the player, every arrow key is consumed before focus can move:
  `lib/pages/player/player_screen.dart:1826-1848` maps Up/Down to volume and Left/Right to
  seek, so a remote can never reach the on-screen Episodes/Sources buttons.

**Problem**: Android TV is a declared target (per the project brief), and on it the app cannot
be operated: you cannot focus a poster, cannot scroll a row that has no arrows, cannot open the
HUD of the player. The only reachable controls are the filter tabs (`InkWell`, focusable) and
the app-bar `IconButton`s. A TV user's first impression is an app that simply does not respond
to the remote.

**Recommendation**: Introduce one form-factor layer and use it everywhere:
1. Detect TV once (Android + no touchscreen, or `MediaQuery.navigationMode ==
   NavigationMode.directional`) and publish it as e.g. `FormFactor.isTv`.
2. Restructure dock/app-bar order to be the D-pad entry point: `TraversalEdgeBehavior.
   closedLoop` plus `FocusTraversalGroup`s per row/dock so Down from the dock lands on the
   first row rather than fighting the `Stack` order.
3. Replace `GestureDetector` with `InkWell` (or wrap in `FocusableActionDetector`) on
   `MovieCard`/`AnimeCard`/`MangaCard`/`IptvChannelCard`/Continue-Watching card — a single
   widget change that makes all rows focusable and gives an activation Enter/Select for free.
4. Draw focus: add a 2 px accent outline on `_hovered || _focused` in the card frame
   (`lib/widgets/movie/movie_card.dart:240-262` already branches on `hovered`).
5. In the player, only consume Left/Right when controls are hidden; when the HUD is up, route
   the D-pad to the transport/Episodes/Sources controls, and map Select to show/hide the HUD.
   `lib/pages/player/player_screen.dart:1873-1883` already tracks HUD visibility for the cursor,
   so it is the natural gate.
6. Un-gate the arrows in rule 3 of this list from hover: show them when `hasPointer` is false,
   and always when a row is focused.

**Impact**: Only change in this document that makes the Android TV build operable at all.

**Implementation Notes**: Steps 1, 3 and 4 are the highest ratio of benefit to risk; they do not
require restructuring any layout and cannot regress the touch/mouse experience. `InkWell`
already provides focus highlight, hover and splash from the theme, which also removes some of
the bespoke hover code.

### Issue: Player's “no streams” state tells movie viewers to go back to an Episodes panel that is not rendered

**Current State**: `lib/widgets/player/player_sources_panel.dart:471-485`. The heading is
conditional (`showBackToEpisodes ? 'No streams found for this episode' : 'No streams found for
this title'`) but the guidance underneath is **not**: “Try going back to episodes and choosing
another episode or provider.” The back-to-episodes button the sentence refers to is also
conditionally hidden for movies (`lib/widgets/player/player_sources_panel.dart:311-318`, driven
by `showBackToEpisodes: widget.detail?.videos.isNotEmpty == true` set at
`lib/pages/player/player_screen.dart:2575`).

**Problem**: This is a textbook dead end. A user watching a *movie* whose source died opens
Sources, reads an instruction to go somewhere that does not exist, finds no such button in the
drawer, and has no stated next step beyond the generic “Rescrape Sources” button (which will
usually return the same dead provider). The only remaining escape is to back out of the player
entirely and re-enter via Details — i.e. re-find the title, the exact loop the brief asks about.

**Recommendation**: Branch the body copy on the same flag the heading already uses:
- series: “Go back to Episodes and pick another episode, or Rescrape for a different provider.”
- movie: “Rescrape for another provider, or use Go back → Sources on the title page to pick a
  different addon.”
Additionally, for movies only, render a secondary action that closes the drawer and opens the
full `WatchScreen` source picker (the navigation already exists as `_openSourcePicker`,
`lib/pages/player/player_screen.dart:700-726`), giving the user a real escape instead of prose.

**Impact**: Turns a confusing instruction into an actionable exit; removes the last known
“re-find the title” loop in the player.

---

## High Priority Improvements

### Issue: The accent colour is hardcoded per screen — the two most-visited screens ignore the user's theme

**Current State**:
- `lib/pages/details/details_page.dart:28-34` defines its own palette with
  `static const accent = Color(0xFFE50914)` — Netflix red, a `const`, not the theme. It drives
  the loading spinner (461), the play button gradient and glow (977-979), poster glow (739),
  episode numbers (1925), the similarity badge (1653) and the play spinner (604-607).
- The player chrome is *also* fixed: `PlayerTheme.accent = Color(0xFF7C5CFF)`
  (`lib/widgets/player/player_glass.dart:19`) and `_C.accent = Color(0xFF7C5CFF)`
  (`lib/pages/player/watch_screen.dart:37`).
- My List mixes both: delete is red (`lib/pages/my_list/my_list_page.dart:114`, `748`) while
  its empty state is purple (`lib/pages/my_list/my_list_page.dart:487-493`).
- By contrast the anime pages do it correctly — `lib/pages/anime/anime_details_page.dart:27-33`
  and `lib/pages/anime_arabic/anime_arabic_details_page.dart:18-23` read
  `AppThemeService.currentPalette.value.primaryColor` as getters.

**Problem**: The Settings › Appearance screen offers eight palettes and a live preview, but a
user who picks *Emerald Aurora* gets a green Home page and a red Play button on the very next
screen they open. Every personalised surface flips back to purple inside the player and red
inside title details. Personalisation that visibly reverses itself reads as a bug, and it
undermines the redesign's whole token-layer premise (the accent is supposed to be a parameter
sourced from `AppThemePalette.primaryColor`).

**Recommendation**: Convert the fixed palettes to getters over the live theme, exactly as the
anime pages already do:
```dart
// details_page.dart
static Color get accent => AppThemeService.currentPalette.value.primaryColor;
static Color get accentDim => AppThemeService.currentPalette.value.primaryColor.withValues(alpha: 0.7);
```
Do the same for `PlayerTheme.accent` / `_C.accent`, and replace the red delete affordances in
My List with a semantic `danger` token (which is legitimately theme-independent). Then remove
the gradient endpoints derived from the old constants (`_Palette.accentDim`,
`lib/pages/details/details_page.dart:33`) so no stale red survives a palette switch.

**Impact**: Makes the user's palette choice truthful everywhere, including the two screens
where they press Play — and unblocks the token-layer work, since two of the largest surfaces
stop being theming exceptions.

**Implementation Notes**: Constraint-safe: no new accent is introduced, and the eight preset
names/ids are untouched. `accentDim` must remain a getter too or it will pin the old colour.

### Issue: The hero carousel is mouse-only — 7 px dot targets and arrows that need a hover

**Current State**: `lib/pages/home/home_page.dart:1373-1400` — each indicator dot is a bare
`GestureDetector` wrapping an `AnimatedContainer` of `width: active ? 22 : 7, height: 7` with
no padding, no `Semantics`, no focus node. The prev/next arrows only mount when
`_isHovering && screenWidth > 600` (1406-1420) and the arrow itself is a 38×38
`GestureDetector` (`lib/pages/home/home_page.dart:2228-2230`).

**Problem**: The featured banner is the app's primary merchandising surface. On a phone or
tablet the only way to reach slide 2 is a swipe (legitimate) or hitting a 7×7 px dot
(effectively impossible — Material's minimum target is 44×44, this is 4 % of that area). On TV
nothing works: the arrows are hover-gated *and* the `PageView` is not focusable. There is also
no auto-advance pause indicator, so the user cannot tell whether the carousel will move under
their finger.

**Recommendation**: Keep the visual dots, wrap each in a 44×48 transparent hit area
(`SizedBox(width: 44, height: 48, child: Center(child: dot))`) with
`Semantics(button: true, selected: active, label: 'Slide ${i + 1} of $total')`; render the
arrows when `screenWidth > 600 && (!hasPointer || _isHovering)`; and make the `PageView`
focusable with `Actions` mapping Left/Right so D-pad users can advance it.

**Impact**: Makes the hero operable by touch and remote, and stops accidental mis-taps on a
33×7 px target.

### Issue: Home filter tabs are a ~32 px hit target with a focus state you cannot see

**Current State**: `lib/pages/home/home_page.dart:935-945`. The `InkWell` uses
`padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4)` around 13 px text, then a 3 px gap
and a 2 px underline — roughly 32 px tall. Focus is only a fill:
`focusColor: Colors.white.withValues(alpha: 0.10)` (939). There is no outline, no scale, no
border change.

**Problem**: Two accessibility failures in one control. (a) The target is ~27 % under the 44 px
minimum, and these tabs sit in the densest part of the Home screen, so mis-taps are likely —
and on a phone they are the only way to filter content. (b) A 10 % white wash is not a visible
focus indicator; combined with the fact that these are among the few focusable elements on Home
(see Critical #3), a keyboard/remote user gets almost no positional feedback.

**Recommendation**: Raise the vertical padding to 12 (→ 48 px tall) and add a real focus ring:
animate a `Border.all(color: accent, width: 2)` on `_focused || _hovered`
(`InkWell` exposes `onFocusChange`), or wrap in `FocusableActionDetector` and use the same
outline treatment the poster cards will adopt. Keep `hoverColor`/`focusColor` as a secondary
wash only.

**Impact**: Filtering becomes reliable by touch and legible by keyboard/remote — the filter tabs
are the app's model for a *good* focusable control (`Semantics(button: true, selected: …)` at
929-932), so they should be the reference implementation rather than the exception.

### Issue: The Music hub fails silently to a blank screen

**Current State**: `lib/pages/music/music_page.dart:151-154` — the load `catch` does
`setState(() => _isLoading = false);` and nothing else. There is no `_error` field on the page.
`_buildTabContent` (996-1000) then falls through to the Home tab, whose body renders only the
sections that are non-empty (`if (_heroTrack != null)`, `if (_trendingArtists.isNotEmpty)`, …, at
1029-1064). With no data, that is an almost-blank scrollable with a pull-to-refresh and no
explanation.

**Problem**: The user gets an empty Music screen and no way to tell whether they have no music,
whether the service is down, or whether the app is broken. Unlike every other hub — Books shows
a composed error with Retry (`lib/pages/books/books_page.dart:218-236`), Anime shows an
icon + message + Retry (`lib/pages/anime/anime_page.dart:302-336`), Home shows `ErrorView`
(`lib/pages/home/home_page.dart:686-687`) — Music says nothing. There is no in-page retry,
volunteering only the hidden pull-to-refresh gesture.

**Recommendation**: Add `String? _error;` set in the catch, and render
`ErrorView(error: _error, onRetry: _loadMusicData)` at the top of `_buildTabContent` when
`_error != null && _heroTrack == null`. Long-term this belongs in the shared state component
(High #H7).

**Impact**: Removes a blank-screen failure from a top-level destination and gives Music the same
recovery affordance as every other hub.

### Issue: Settings is 15 flat rows with no search, mixing two incompatible row behaviours

**Current State**: `lib/pages/settings/settings_page.dart:415-820` — one `ListView` under a
single `'CATEGORIES'` label (486-495) containing 15 rows: Appearance (500-522), Video (523-560),
Debrid (562-579), Addons (581-593), Built-in Providers (595-625), then *inline toggles* — P2P
(613-650), TV Calendar (652-681), AI Quiz (683-712), Adult (714-745), Discord (746-779) — then
Trakt (781-796), Simkl (798-813), Backup (815-830), Updates (832-846), About (848-858). Toggles
are `_SettingsSwitchTile` (952+), navigation rows are `_SettingsCategoryTile` (824+); both are
private to this file.

**Problem**: A user looking for “turn off the AI quiz” has to scan a 15-row scroll with no
search, and — worse — has to work out from visual cues which rows *do* something in place and
which *go* somewhere. The two tile types differ only by a trailing switch vs a chevron, and the
toggles are interleaved between navigation rows, so the list has no predictive structure. There
is also no way to reach a specific setting from anywhere else in the app (no deep link, no
command palette), even though every sub-page is already a standalone route.

**Recommendation**:
1. Group the list into labelled sections using the header style the sub-pages already use
   (e.g. `SETTINGS › Settings` pattern in `lib/pages/settings/appearance/home_ui_settings_page.dart:44-215`):
   *Playback* (Video, Player studios), *Content & Sources* (Addons, Built-in Providers, Debrid,
   P2P), *Discovery & UI* (Appearance, Calendar, AI Quiz, Dock), *Accounts & Sync* (Trakt, Simkl),
   *System* (Backup, Updates, About, Adult, Discord).
2. Separate toggles from navigations — either give each section a “toggles” block at its end, or
   move them into a dedicated *Quick Settings* section at the top (they are the five most-flipped
   settings in the app, so top placement is a real win).
3. Add a filter field over title + subtitle, reusing the proven pattern at
   `lib/pages/settings/builtin_providers_settings_page.dart:475-500` (search box, clear button,
   empty state at 149-159). Names are short and stable, so a plain `contains` match is enough.

**Impact**: Cuts “where is that setting” time from a full scroll to a keyword, and makes the two
row behaviours predictable. Grouping needs no new widget — only headers between existing tiles.

### Issue: Every Settings sub-page overrides the user's palette with its own hardcoded chrome

**Current State**: 11 sub-pages each declare their own scaffold/AppBar colours:
`about_settings_page.dart:11-14`, `addons_settings_page.dart:647-650`,
`appearance_settings_page.dart:33-36`, `builtin_providers_settings_page.dart:39-42`,
`debrid_settings_page.dart:253-256`, `simkl_settings_page.dart:135-138`,
`trakt_settings_page.dart:136-139`, `appearance/dock_settings_page.dart:16-19`,
`appearance/liquid_glass_settings_page.dart:17-20`, `appearance/manga_settings_page.dart:20-23`,
`appearance/music_settings_page.dart:24-27`, `appearance/home_ui_settings_page.dart:25-28` — all
`backgroundColor: const Color(0xFF080A0F)` + `AppBar(backgroundColor: const Color(0xFF0D1017))`.
The root page does the same (`settings_page.dart:399-402`).

**Problem**: The Settings root shows the user's palette in its badges and header gradient, then
every tap leads to a page that ignores it. A user who picks *Sunset Crimson* sees the tint on the
Settings list and pure navy on the next screen — the same self-reversing personalisation problem
as High #H1, reproduced across an entire subtree. It is also the reason the settings tree will
need touching twice during the token migration.

**Recommendation**: Extract the shared settings scaffold that all 12 pages already duplicate
(nav bar with back button + title, ambient background, `ConstrainedBox(maxWidth: 800)`, standard
padding) into one widget that reads
`AppThemeService.currentPalette.value.{scaffoldBackgroundColor, appBarBackgroundColor}`, and
have every sub-page use it. This is the single highest-leverage deletion in the settings tree:
it removes ~12 copies of the same 25 lines and the palette override at once.

**Impact**: Theme choice becomes consistent from the Settings root all the way down, and future
settings pages inherit correct chrome for free.

### Issue: Empty states are either fully composed or a single sentence — with no shared component

**Current State**: Two families.
*Composed* (icon + headline + body, sometimes an action): My List
(`lib/pages/my_list/my_list_page.dart:481-520`, with a contextual Reset Filters button),
Downloads (`lib/pages/downloads/downloads_page.dart:220-240`), Books
(`lib/pages/books/books_page.dart:239-260`), player sources
(`lib/widgets/player/player_sources_panel.dart:462-500`), EPUB reader
(`lib/pages/books/epub_reader_page.dart:726-760`).
*Bare one-liners*: Home filtered-empty — `'No titles match this filter.'` / `'No anime available
right now.'`, text only (`lib/pages/home/home_page.dart:649-659`); Catalog —
`'No items found'` (`lib/pages/catalog/catalog_page.dart:237-242`); Discover —
`'No results found for "…"'` (`lib/pages/discover/discover_page.dart:1215-1218`); Search —
`'No results for "…"'` (`lib/pages/search/search_page.dart:499-520`); Music — icon + title only
(`lib/pages/music/music_page.dart:1109-1130`).

**Problem**: The bare states give the user a fact and no next step. Home's is the worst:
“No titles match this filter.” appears with **no way to clear the filter**, even though Home is
currently hiding content the user could otherwise see — the filter tabs are in the app bar on
wide screens (`lib/pages/home/home_page.dart:576-577`) and inline above the hero on narrow ones,
so the remedy is on screen but never named. Discover and Catalog repeat the same pattern for
searches.

**Recommendation**: Add one shared `EmptyState({icon, title, body, action})` beside `ErrorView`
in `lib/widgets/common/`, then:
- Home: `action: TextButton('Show all titles', () => _setFilter(_HomeFilter.all))`.
- Catalog / Discover / Search: `action: TextButton('Clear search', () => _clearSearch())`.
- Music: add the missing body line + a “Browse genres” action.
The already-composed examples need no change — they become the reference for the shared widget's
default styling.

**Impact**: Every zero-result screen ends with an action instead of a dead end; one widget
replaces five ad-hoc implementations.

### Issue: List loading is a bare centred spinner on every list screen; skeletons exist but only for posters

**Current State**: 46+ files use `CircularProgressIndicator`; the recurring pattern is
`Center(child: CircularProgressIndicator(color: …))` with no layout underneath:
Home (`lib/pages/home/home_page.dart:683-685`), Catalog (first load and pagination —
`lib/pages/catalog/catalog_page.dart:229-231`, `263-265`), Discover (527-529, 591-593),
Search (`lib/pages/search/search_page.dart:495-498`), Anime (`lib/pages/anime/anime_page.dart:299-301`),
Books (`lib/pages/books/books_page.dart:214-216`), Music (`lib/pages/music/music_page.dart:998-1000`),
Audiobooks (`lib/pages/audiobooks/audiobooks_page.dart:635-637`), Details
(`lib/pages/details/details_page.dart:460-461`), Calendar
(`lib/pages/calendar/tv_calendar_page.dart:700-702`), IPTV portal browser
(`lib/pages/iptv/iptv_portal_browser_page.dart:1142-1143`, `2511-2512`).
Only three skeleton implementations exist in the whole app:
`lib/widgets/common/poster_skeleton.dart` (used by `MovieCard` only, at
`lib/widgets/movie/movie_card.dart:288`), `lib/pages/player/watch_screen.dart:3347-3365`
(`_ShimmerCard`, for source rows), and `lib/pages/books/epub_reader_page.dart:643`
(`_buildSkeletonLoading`, for books).

**Problem**: A centred spinner carries zero information about what is coming, so the page
*reflows violently* on arrival — on Home, a spinner becomes hero + 6 rows; on Catalog the grid
jumps from one dot to 20 posters. This is felt most on the cold-start path (Home), where the
user's first impression is a spinner on black, and on paginated scrolling in Catalog/Discover,
where the spinner appears mid-grid with no reserved space. The app already knows the shape it is
about to draw (`MovieCardSizing`, `lib/widgets/movie/movie_card.dart:23-76`), so the placeholder
can be layout-exact.

**Recommendation**: Build `PosterRowSkeleton` / `PosterGridSkeleton` on the existing
`PosterSkeleton` (which already explains in its own comment why a `FadeTransition` is the cheap
option, `lib/widgets/common/poster_skeleton.dart:40-42`), sized from `MovieCardSizing.fromWidth`
so the placeholder is pixel-identical to the loaded card. Adopt in this order of value: Home
(replaces the whole-screen spinner with hero + 3 rows), Catalog, Discover, Search, My List,
Music. Reserve space for the pagination spinner inside the grid via the existing
`itemCount: _items.length + (_hasMore ? 1 : 0)` slot.

**Impact**: Cold start stops flashing empty, and infinite scroll stops jumping. Reuses an
existing, already-tuned animation.

### Issue: The dock is 13 icon-only destinations whose labels exist only in a tooltip, and whose signature interaction requires a mouse

**Current State**: `lib/services/theme/dock_settings.dart:5-95` defines 13 entries — Home,
Discover, Manga, Books, Audiobooks, Music, Anime, Live TV, Addons, Downloads, My List, Settings,
Search. `lib/widgets/common/liquid_dock.dart:274-283` renders each item as a `Tooltip` wrapping
an `Icon` and **nothing else** — no visible label. The hover magnification (the app's signature
interaction, `GlassSettings.hoverProximity`/`hoverScale`) is computed from `_mouseX` in
`lib/widgets/common/liquid_dock.dart:196-215` and gated in `236-258`, i.e. driven purely by
pointer position; on mobile it is additionally size-capped (42 px base) and pairs of icons are
visually near-identical by choice of glyph: Manga `auto_stories` vs Books `menu_book`, Anime
`animation` vs Live TV `live_tv`.

**Problem**: On a phone the user faces up to 13 unlabelled 42 px glyphs in a scrolling glass bar,
with no magnification feedback (no pointer) and no labels (tooltips need a long-press, which
nobody discovers for navigation). Distinguishing Manga from Books is a guess the first several
times. On TV, none of it is focusable at all, so the entire primary navigation is dead (see
Critical #3). The dock also grows: because every item is user-toggleable on by default
(`dock_settings.dart:117-119`), the shipped default is the worst case.

**Recommendation**:
1. Show text labels under the icons for the enabled set on non-pointer form factors (a
   `Column(icon, Text(label, 10px))` inside the existing item box) — the dock already scrolls, so
   the extra width is affordable.
2. Ship a default set of ~5 enabled destinations (Home, Discover, My List, Downloads, Settings)
   and let the rest be opt-in, matching the “Settings › Appearance › Dock items” screen the
   toggle UI already provides (`lib/pages/settings/appearance/dock_settings_page.dart:140-192`).
3. Drive magnification from focus as well as hover (feed `FocusNode.hasFocus` into the same
   `proximity` computation at `lib/widgets/common/liquid_dock.dart:196-215`) so the signature
   effect also rewards remote navigation.
4. Add `Semantics(label: item.label, button: true, selected: current)`, since the Tooltip is not
   reliably announced as a button role.

**Impact**: Navigation becomes self-describing on touch and remote, and the default install stops
presenting 13 cryptic glyphs as the way around the app.

### Issue: The dock disappears on half the app's top-level surfaces

**Current State**: `AppLiquidDock` is mounted on exactly 7 pages — Home
(`lib/pages/home/home_page.dart:778`), Discover (`lib/pages/discover/discover_page.dart:487`),
Anime (`lib/pages/anime/anime_page.dart:529`), Manga (`lib/pages/manga/manga_page.dart:416`),
Books (`lib/pages/books/books_page.dart:321`), Live TV (`lib/pages/iptv/iptv_page.dart:355`) and
MultiNutz (`lib/pages/multinutz/multinutz_page.dart:901`, with `currentDestination: null`).
It is absent from Search, My List, Downloads, Music, Audiobooks, Settings, Catalog, Details,
Calendar and every reader and player — even though My List, Downloads, Music and Audiobooks are
listed as first-class destinations in the very same enum.

**Problem**: Navigation is available on some top-level screens and not others, with no rule the
user can infer. From My List the only way to another section is Back to Home (two taps plus a
lost position); from Downloads likewise. From the anime-arabic catalogue and the catalogue grid
pages there is no way to switch sections at all. Music ships its own private sidebar instead
(`lib/pages/music/music_page.dart:2147-2151`), so the app has three navigation models: dock,
app-bar shortcuts, and Music's sidebar.

**Recommendation**: Treat the dock as a *section* chrome element and mount it on every
first-class destination (Search, My List, Downloads, Music, Audiobooks, Settings, Catalog,
Calendar); the entity screens (Details, player, readers) keep their own back button. Two
implementation notes: `AppLiquidDock` currently takes `onSettingsTap`/`onSearchTap` overrides
that only some callers pass, so the defaults need to work for all callers; and Music's sidebar
should be removed in favour of the shared dock once it is present everywhere, otherwise the two
will keep diverging.

**Impact**: Removes the “how do I get out of this section” question from four destinations and
collapses three navigation models into one.

---

## Medium Priority Enhancements

### Issue: No keyboard or remote “Back” on entity screens

**Current State**: The Home page handles only `F`/`F11`/`Escape`-from-fullscreen
(`lib/pages/home/home_page.dart:721-732`) and the player handles its own keys (1826-1861).
`DetailsPage` has **no** keyboard handling at all — the only back affordance is the floating
button at `lib/pages/details/details_page.dart:621-638`. Readers do it properly: EPUB handles
Left/Right/PageUp/PageDown/Escape/F/T (`lib/pages/books/epub_reader_page.dart:231-258`), PDF
handles arrows/Escape/F (`lib/pages/books/pdf_reader_page.dart:96-120`), the manga reader maps
arrows/space/Escape (`lib/pages/manga/manga_reader_page.dart:306-340`).

**Problem**: A desktop user must mouse to a floating circular button to leave a title page; a TV
user cannot leave it at all. Escape — the near-universal “go back” on desktop and the remote's
Back key — does nothing on Details, Discover, Catalog, anime details or either stream sheet.
Consistency matters more than the individual screens here: keyboard support exists, it just
stops at the boundary of the readers.

**Recommendation**: Handle Back once, at the app root, with a `Shortcuts`/`Actions` pair mapping
`Escape`, `Backspace`, `BrowserBack` and `GoBack` (the Android TV remote key) to
`Navigator.maybePop`, letting inner pages opt out while a dialog or text field has focus (the
player already demonstrates the “don't intercept while an `EditableText` has focus” guard at
`lib/pages/player/player_screen.dart:1817-1822` — reuse it).

**Impact**: Esc/Back works everywhere it should; entity screens become escapable on TV.

### Issue: “Similar” navigation squashes the back stack

**Current State**: `lib/pages/details/details_page.dart:431-435` (`_openSimilarItem`) and
`1470-1474` (episode/related picks) use `Navigator.pushReplacement` to the new `DetailsPage`.

**Problem**: The user opens Title A from Search, taps a similar title B, and the back gesture
takes them to Search — not back to A where they were reading. A is destroyed even though “back”
conventionally means “the previous screen”. The same applies when hopping between episodes.

**Recommendation**: Use `Navigator.push` for user-initiated title hops so Back walks the history
the user actually built, and cap the depth (e.g. collapse A when B is opened *from* A twice) if
runaway stacks are the concern. If `pushReplacement` is retained for a deliberate reason, the
new page should at least offer an explicit “Back to <previous title>” affordance so the loss is
visible rather than silent.

**Impact**: Back means what users expect on the app's most-traversed browsing loop.

### Issue: Failures are surfaced four different ways — and row-level failures not at all

**Current State**:
1. Full-screen `ErrorView` with retry: Home (`home_page.dart:686-687`), Catalog
   (`catalog_page.dart:232-236`), Discover legacy (`discover_page.dart:1211-1212`).
2. Inline red text with no retry: IPTV portal browser (`iptv_portal_browser_page.dart:1145`,
   `2514`).
3. Transient SnackBar: player subtitle failures (`player_screen.dart:998-1002`, `1128-1135`),
   addon install (`addons_settings_page.dart:89-95`), audiobook generation
   (`generate_audiobook_screen.dart:184-186`).
4. **Nothing at all** — row/section failures that a user never learns about: Home anime rows
   (`home_page.dart:223-227`, `debugPrint` then clear the flag), Details “Similar Content”
   (`details_page.dart:417-420`), Music load (`music_page.dart:151-154`).

**Problem**: The same class of failure produces a full-screen takeover in one place, an
unstyled red sentence in another, a toast in a third, and silence in the fourth — so users cannot
form an expectation of “what happens when something breaks”. Case 4 is the damaging one: on
Home, a failed anime row simply never appears, so an empty Anime tab looks like “no anime
exists” rather than “the fetch failed”, which is the same false-negative that makes Critical #1
expensive.

**Recommendation**: Adopt one rule and apply it mechanically: **page-level load** → `ErrorView`
with `onRetry`; **row/section-level load** → an inline placeholder row occupying the real row's
height with “Couldn't load this row · Retry” (this also removes the layout jump from a row that
silently vanishes); **user action** (install, copy, sync) → SnackBar; **player action** → HUD, not
SnackBar (Medium #M5). Then port the four currently-silent sites onto rule 2 first — they are
the only ones where the user has no information at all.

**Impact**: Consistent, learnable failure behaviour; three currently invisible failures become
visible and retryable.

### Issue: Player notices are shown as Material SnackBars over the video

**Current State**: `lib/pages/player/player_screen.dart:959-1002`, `1128-1135`, `1799-1803`,
`2077-2082` (and `lib/pages/player/watch_screen.dart:3267-3289`) all use
`ScaffoldMessenger.showSnackBar` with default M3 placement/styling, including during playback,
e.g. “Download started in background…” and “Screen is locked…”.

**Problem**: Two problems. (a) The player hides its chrome deliberately (`_showControls = false`,
`lib/pages/player/player_screen.dart:901`) so the user gets an unstyled Material bar where the
app's own glass HUD language would be expected; it visually belongs to a different app. (b) With
`ScaffoldMessenger` the bar is inserted at the bottom of the Scaffold over the video surface,
competing with the transport controls and (in fullscreen) appearing in a region the user just
dismissed. SnackBars also stack and replace each other, so rapid subtitle switching
(959/988/1029) queues up four bars in a row.

**Recommendation**: Route player messages through the HUD/toast treatment that already exists
in the player widget set (`PlayerGlassCard`, `lib/widgets/player/player_glass.dart:57`, and the
`_fallbackNoticeText` pattern at `player_screen.dart:99-104`), positioned above the transport
bar. Keep `ScaffoldMessenger` for pre-playback surface screens only.

**Impact**: Player feedback stops looking like a different application and stops covering the
controls.

### Issue: Continue Watching thumbnails have no loading placeholder

**Current State**: `lib/widgets/home/continue_watching_slider.dart:413-421` — `CachedNetworkImage`
is given `fit`, `cacheManager`, `memCacheWidth` and `errorWidget`, but **no `placeholder:`**. The
container behind it is a flat `Color(0xFF1E212E)` (line ~403). Compare `MovieCard`, which passes
`placeholder: (context, url) => const PosterSkeleton()` (`lib/widgets/movie/movie_card.dart:288`).

**Problem**: On a cold Home load the Continue Watching row renders as a strip of flat grey
rectangles while its neighbours (in the rows below) shimmer — an inconsistent, unfinished-looking
first screen, made worse because Continue Watching sits *above* the first content row.

**Recommendation**: `placeholder: (context, url) => const PosterSkeleton(),` — one line,
identical to the card.

**Impact**: Removes the most visible loading inconsistency on the launch screen for one line of
code.

### Issue: Several controls are well below the 44 px minimum touch target

**Current State**:
- My List sync refresh: `IconButton(constraints: BoxConstraints(), padding: EdgeInsets.zero)`
  with a 14 px icon — roughly a 14–20 px target (`lib/pages/my_list/my_list_page.dart:323-331`).
- Hero carousel dots: 7×7 (inactive) to 22×7 (active) (`lib/pages/home/home_page.dart:1381-1400`).
- Genre / filter chips: `EdgeInsets.symmetric(horizontal: 16, vertical: 6)` around 13 px text
  ≈ 28 px tall (`lib/pages/catalog/catalog_page.dart:561-585`; the same shape recurs in
  Discover's extras and `lib/pages/my_list/my_list_page.dart:424-470`).
- Row scroll arrows: 32 px interactive area in Catalog (`lib/pages/catalog/catalog_page.dart:524-545`)
  and 38 px on Home (`lib/pages/home/home_page.dart:2228-2230`).
- Player HUD icon buttons: 36 px (`lib/widgets/player/player_sources_panel.dart:306-318`).

**Problem**: These are the controls users hit repeatedly, and several sit in dense, adjacent
layouts (dots, chips, arrows) where a near-miss selects the wrong thing — a mis-tapped genre chip
reloads the catalogue grid, a mis-tapped dot advances the hero. Touch accuracy targets exist for
a reason and none of these meet them.

**Recommendation**: Apply a minimum-target rule mechanically rather than per widget — either wrap
in `SizedBox(width: 44, height: 44, child: Center(child: …))` for small visual glyphs (dots,
arrows, the refresh icon) or raise vertical padding (chips: `vertical: 6` → `12`). For
`IconButton`, prefer removing the `BoxConstraints()` override and letting the Material default
48 px stand; the visual size stays governed by the icon.

**Impact**: Fewer wrong-taps on the densest screens; brings the interactive layer in line with
platform guidelines on touch devices.

### Issue: Secondary text sits below WCAG AA contrast on dark surfaces

**Current State**: The design audit recorded five alphas used as “secondary text” (0.35, 0.4,
0.45, 0.5, 0.8). Two concrete cases of the low end used for real, normal-size text:
- poster card metadata, 13 px at `Colors.white.withOpacity(0.42)` on a `Color(0xFF171A23)`
  surface (`lib/widgets/movie/movie_card.dart:204`, `lib/widgets/movie/movie_card.dart:169`) —
  `[computed]` ≈ **4.0:1**, below the 4.5:1 AA threshold for normal text;
- the Settings section label, 12 px at `withValues(alpha: 0.35)` on `Color(0xFF0D1017)`
  (`lib/pages/settings/settings_page.dart:486-495`) — `[computed]` ≈ **3.2:1**.
  (For reference, the same card's 13 px year at alpha 0.52 computes to ≈5.5:1 and passes.)

**Problem**: The “type” line under every poster — the thing that tells a user this is a Series
rather than a Movie — is the least legible text on the screen. On a phone in daylight or a TV
viewed from a sofa, the metadata that drives the user's choice is the hardest text to read. Since
these alphas were chosen per widget, the problem is scattered rather than systemic, which is why
it needs a token rather than a fix-up.

**Recommendation**: Introduce a semantic `textSecondary` (and `textTertiary` for genuinely
decorative items) with a floor of ~0.65 white on the app's surfaces `[computed: ≈7:1]`, and
migrate the “secondary text” usages to it; keep the 0.05–0.12 range for borders/dividers only.
Note the two cited cases are the minimum to fix — the token migration should sweep all 0.3–0.45
text usages, not just these.

**Impact**: Makes title metadata readable in daylight/at distance, which is exactly the context
this app is used in.

**Implementation Notes**: Contrast values above are arithmetic from the cited colour constants,
not runtime measurements.

### Issue: Poster cards carry no semantic label, so screen readers announce fragments

**Current State**: `Semantics` appears twice in all of `lib/pages` — the Home filter tabs
(`lib/pages/home/home_page.dart:895-896`, `929-932`) and one reader button
(`lib/pages/books/widgets/focus_mode_view.dart:452-455`). `MovieCard`
(`lib/widgets/movie/movie_card.dart:96-200`) exposes only its raw child text nodes (name, year,
type) with no combined label, no `button: true`, no `image: true` for the poster.

**Problem**: A screen-reader user swiping through a Home row hears a sequence of unconnected
fragments (“Dune”, “2021”, “Movie”) with no indication that they are one tap target, what the
rating is, or that activating it opens details. The filter tabs demonstrate the correct treatment
in the same codebase, so this is inconsistency rather than unawareness.

**Recommendation**: Wrap the card in
`Semantics(button: true, label: '<name>, <year>, <type>, <rating>')` (keeping the child text for
visuals, using `excludeSemantics` on the inner texts so they are not read twice). Do the same for
`AnimeCard`, `MangaCard`, `IptvChannelCard` and the Continue Watching card.

**Impact**: The app's primary content becomes navigable and intelligible with a screen reader —
currently it is effectively unusable.

### Issue: Dock navigation flattens history and destroys section state

**Current State**: `lib/widgets/common/app_liquid_dock.dart:41-58` — `_navigateToPage` uses
`Navigator.push` only when `currentDestination == DockItemKey.home`, and
`Navigator.pushReplacement` otherwise. So Home → Manga → Books leaves a stack of `[Home, Books]`,
and Back from Books lands on Home.

**Problem**: Two consequences. (a) Back behaviour is unpredictable: the same Back gesture returns
to the previous app section when you came from Home, but skips a section when you came from
anywhere else — the user cannot build a mental model. (b) Section state is destroyed on every
switch: scroll position, catalogue filters, Discover's selected catalog and search text, Manga's
reading history scroll — all rebuilt from scratch, so hopping to check something and coming back
loses the user's place. Real tab bars preserve this; a `pushReplacement` chain does not.

**Recommendation**: Keep section pages alive rather than replacing them — an `IndexedStack` (or
per-section `Navigator`s inside a `StatefulWidget` shell) keyed by `DockItemKey`, with the dock
switching the visible index. That also fixes the “dock absent on half the surfaces” problem
(High #H10) structurally: if there is one shell, every destination gets the dock by construction.

**Impact**: Predictable Back, preserved browsing context, and one navigation implementation
instead of seven.

### Issue: Duplicate entry points to the same destinations across Home, the app bar and the dock

**Current State**: Anime is simultaneously a Home filter tab
(`lib/pages/home/home_page.dart:879-905` — `All / Movies / Series / Anime`) and a dock
destination (`lib/services/theme/dock_settings.dart:44-48`). Search and Settings appear both in
the floating app bar (`lib/pages/home/home_page.dart:1106-1135`) and in the dock
(`dock_settings.dart:44-95`). Discover appears as both an app-bar icon
(`home_page.dart:1090-1101`) and a dock item.

**Problem**: Three separate mechanisms offer the same destinations with different labels and
placement, so the app never teaches the user where things live. The Home “Anime” tab is the worst
case: it renders a partially different content model (AnimeSliderSection rows fetched from
AniList, `home_page.dart:611-620`) under the same top bar as the dedicated Anime page, so users
see two similar-but-not-identical anime experiences and have no way to know which is canonical.

**Recommendation**: Pick one owner per destination: remove the Anime tab from Home (its All tab
already appends anime rows, `home_page.dart:662`) and let the dock/Anime section own it; drop
Search and Settings from the app bar once the dock is universal (High #H10). Where two entry
points must remain (e.g. Search from the app bar for muscle memory), make them the same
component with the same icon and label so they at least read as one thing.

**Impact**: A learnable information architecture; removes a confusing near-duplicate anime
experience.

---

## Low Priority Suggestions

### Issue: Deprecated `withOpacity` and current `withValues` are mixed within the same widget

**Current State**: `lib/widgets/movie/movie_card.dart` uses `withOpacity` at 184, 195, 204, 248,
254 and 299-322 while the rest of the file (and most of the app) uses `withValues`. Same pattern
in `lib/pages/details/details_page.dart:633-635` (three `withOpacity` calls) versus the encoded
`withValues(alpha: 20 / 100)` two hundred lines earlier at 415-425.

**Problem**: Purely visual parity today, so no user-visible defect — but it doubles the work of
the opacity-scale cleanup the design audit calls for (Finding 3), and it makes greps for
“remaining ad-hoc alphas” unreliable during the migration.

**Recommendation**: Migrate `withOpacity` → `withValues(alpha: …)` while touching each file for
other reasons; do not schedule a dedicated sweep.

**Impact**: None directly; keeps the token migration from needing a second pass.

### Issue: Back affordances differ in glyph, container and placement on every screen

**Current State**: `arrow_back_ios_rounded`
(`lib/pages/search/search_page.dart:387-391`, `lib/pages/my_list/my_list_page.dart:250-256`),
`arrow_back_ios_new_rounded` (`lib/pages/details/details_page.dart:629-637`,
`lib/pages/books/books_page.dart:336`), `arrow_back_rounded`
(`lib/pages/manga/manga_page.dart:694`, `lib/pages/music/music_page.dart:2105`),
`chevron_left_rounded` (`lib/pages/iptv/iptv_page.dart:891`,
`lib/pages/player/watch_screen.dart:2783`). Containers vary too: bare `IconButton`, a tinted
`IconButton.styleFrom(backgroundColor: white @ 0.06)` (My List), a `ClipOval` + `BackdropFilter`
floating pill over the artwork (Details), and a 44 px frosted circle (player,
`lib/widgets/player/player_top_bar.dart:60-68`).

**Problem**: The single most-used control in the app has four glyphs and four visual treatments,
so it moves around and changes shape between screens — a small but constant friction on every
navigation, and it makes the interface feel assembled rather than designed.

**Recommendation**: One `ZPlayBackButton` (glyph + size + container), used by every non-tab
screen, with the two legitimate variants being “in a nav bar” and “floating over media”.

**Impact**: The app stops feeling like it was built screen-by-screen; navigation gains muscle
memory.

### Issue: The intro splash plays on every launch with no skip and no caching awareness

**Current State**: `lib/pages/home/home_page.dart:819-875` (`_buildIntroOverlay`) renders a
full-screen `Container(color: Color(0xFF080A0F))` with logo, “ZPlay”, “Your Cinema Universe” and
an 800 ms `AnimatedOpacity` over the loading content, driven by `_showIntro`. It is never
dismissible and its duration is fixed regardless of how fast data arrives.

**Problem**: A returning user who relaunches the app, or switches back to a warm process, sees
branded splash before content every time — and because the fade is a fixed 800 ms, the splash can
outlive the load and become the slowest part of startup. It also blocks the first interaction
(`IgnorePointer(ignoring: !_showIntro)` at 830).

**Recommendation**: Show the intro only on first launch per install (a `SharedPreferences` flag,
matching the pattern the app already uses for `app_theme_id` and dock items), or cap it at the
shorter of “800 ms” and “data ready”, and let a tap dismiss it immediately.

**Impact**: Faster perceived startup for returning users; no functional loss, since the splash
carries no information.

### Issue: Music uses a private toast mechanism while the rest of the app uses SnackBars

**Current State**: `lib/pages/music/music_page.dart:107-113` implements `_showToast` with a
`Timer` and a `_toastMessage` field, used for player actions and playlist feedback (240, 244,
247, 403-405, 515-518, 1030). Other music actions — download queueing — use
`ScaffoldMessenger.showSnackBar` instead (`music_page.dart:3497-3501`, `4443-4447`).

**Problem**: Two feedback channels for the same class of message inside one screen. The custom
toast is arguably better (it survives the mini-player layout, which the SnackBar may not), which
makes the split harder to justify rather than easier: users get feedback at a different location
depending on which button they pressed.

**Recommendation**: Standardise on the custom toast for Music (it is the form-factor-correct
choice) and re-route the two SnackBar sites through it — or, if the token/component work produces
a shared toast, adopt that in both places.

**Impact**: Consistent feedback placement within the app's most interaction-dense screen.

### Issue: “Cloud Synced” is a permanent badge with no timestamp and no failure state

**Current State**: `lib/pages/my_list/my_list_page.dart:288-330` renders a pill that shows
“Syncing…” or “Cloud Synced” based solely on `MyListService.isSyncing`, always in the same accent
treatment, with a 14 px refresh button. A failed sync has no representation here.

**Problem**: “Cloud Synced” is asserted unconditionally — even before a sync has ever run, and
even after one has failed. Users relying on cross-device watchlists (the reason the pill exists)
get a reassurance they cannot trust, and no way to see when the last successful sync happened.

**Recommendation**: Track a last-synced timestamp and a last-error, and show three states:
“Synced 2 min ago”, “Syncing…”, “Sync failed · Retry” (the retry already exists). Failures should
also be visible on the icon rather than requiring the user to notice that a timestamp never
advanced.

**Impact**: Makes a trust signal trustworthy, at the cost of one stored timestamp.

### Issue: Half-pixel type sizes are still in active use

**Current State**: `fontSize: 9.5` (`lib/pages/anime/anime_details_page.dart:1358`),
`fontSize: 12.5` (`lib/pages/settings/settings_page.dart:698-700`,
`lib/widgets/player/player_top_bar.dart:135`), `fontSize: 13.5`
(`lib/pages/settings/addons_settings_page.dart:132`, `400`), among the 18 sizes the design audit
recorded between 9 and 22.

**Problem**: A half point is invisible at these sizes on a 1× display and indistinguishable from
its integer neighbour on high-DPI, so these values encode only which screen they were written on.
As the type scale lands, they will be the entries nobody can map to a token.

**Recommendation**: Fold each half-pixel size into the nearest scale step during the token
migration; verify visually (they are all metadata/chip text) rather than preserving the value.

**Impact**: Removes the last residue of per-widget type decisions; no visible change expected.

---

## Positive Observations

These are working well and should be preserved through the redesign — several are the reference
implementations the fixes above should copy.

1. **The player's stalled-stream state is a model dead-end-avoider.** When a stream stops
   responding, `_openSourcePicker` (`lib/pages/player/player_screen.dart:700-726`) opens the
   in-player sources panel with an explanatory banner instead of ejecting the user, and its
   doc comment states the exact failure it prevents: the user being “told to pick another source
   with no way to do so” while the Continue Watching tile re-resumes a dead source. The stalled
   overlay then offers **both** “Choose another source” and “Go back”
   (`lib/pages/player/player_screen.dart:1999-2013`). This is the standard the rest of the app
   should meet.
2. **The sources drawer has real failure states.** An error banner with icon and message
   (`lib/widgets/player/player_sources_panel.dart:271-300`), a composed empty state with a
   “Rescrape Sources” action (`462-500`), plus an incremental-loading row for additional sources
   (`_buildSourcesList`, 520-540). Provider name, season/episode chip and episode title are all
   present in the header (`318-395`), so the user always knows what they are picking a source
   *for*.
3. **The sources drawer and the episodes panel are genuinely good information architecture.**
   Seasons are tabbed, the current episode auto-scrolls into view on open
   (`lib/widgets/player/player_episodes_panel.dart:60-66`), and the panel is reachable from the
   player without losing playback.
4. **Continue Watching exposes its destructive and secondary actions on touch.**
   `lib/widgets/home/continue_watching_slider.dart:478-483` deliberately makes Details/Remove
   always visible on non-desktop platforms — the correct instinct, which just needs to be applied
   to the play button as well (Critical #C2).
5. **Keyboard support, where it exists, is thoughtful.** Music has a full shortcut set
   (space/K, J/L seek, M mute, Q queue, F expand, `/` shortcuts overlay, Escape unwind —
   `lib/pages/music/music_page.dart:231-267`) plus a discoverable shortcuts modal
   (`919-924`); both readers handle Escape/arrows/F and document focus mode
   (`lib/pages/books/epub_reader_page.dart:231-258`,
   `lib/pages/manga/manga_reader_page.dart:306-340`); the player's key map covers volume, seek,
   mute, play/pause, fullscreen and video-fit (`lib/pages/player/player_screen.dart:1826-1861`).
   The pattern is right — it just needs to be visible from more screens.
6. **Search has a real zero-state.** Recent searches with a clear action plus a discovery feed
   (`lib/pages/search/search_page.dart:588-600`) mean an empty query is an opportunity rather
   than a blank screen; the paste-from-clipboard and magnet-link paths (`436-472`) make it
   genuinely useful for the addon ecosystem.
7. **Poster loading is already solved once, properly.** `PosterSkeleton`
   (`lib/widgets/common/poster_skeleton.dart`) is a `FadeTransition`-driven shimmer with a
   comment explaining why that is the cheap choice, and it is wired into `MovieCard` at
   `lib/widgets/movie/movie_card.dart:288` with an accompanying `MissingPoster` fallback
   (`poster_skeleton.dart:47-63`). The building blocks for High #H8 exist.
8. **Page-level errors carry a retry everywhere they are handled.** `ErrorView`
   (`lib/widgets/common/error_view.dart`) is composable and already used by Home, Catalog and
   Discover; Books (`lib/pages/books/books_page.dart:218-236`) and Anime
   (`lib/pages/anime/anime_page.dart:302-336`) hand-roll equivalents in the same spirit. The
   problem is coverage and copy, not the concept.
9. **Settings persists meaningful state into its labels.** The category tiles show the live
   current value — palette name plus “Glass ON”, the active Anime4K preset, connected/offline for
   Trakt and Simkl, version for Updates (`lib/pages/settings/settings_page.dart:500-560`,
   `670-860`). A user can confirm most settings without opening the sub-page, which is exactly
   the right instinct for a long list.
10. **Watch progress and resume are handled seriously.** Playback progress is saved on a timer
    and on exit, with final Trakt/Simkl scrobbles on pop
    (`lib/pages/player/player_screen.dart:1535-1568`), resume position is threaded through
    `initialPosition` (`player_screen.dart:61-72`), and Continue Watching persists per-episode
    progress (`lib/widgets/home/continue_watching_slider.dart:368-370`, `600-606`). This is the
    plumbing the Critical/High fixes should build on rather than replace.

---

## Appendix — Verification notes and findings count

**Counts by tier**: Critical 4 · High 10 · Medium 11 · Low 6 · **Total 31**, plus 10 positive
observations.

**How each finding was established**

| Tier | Finding | Evidence type |
|:--|:--|:--|
| Critical | Search false “no results” | Read: `search_page.dart:269-334`, `495-520` |
| Critical | Hover-only play affordance | Read: `continue_watching_slider.dart:442-483` |
| Critical | No D-pad/focus traversal | Grep (no TV detection, no `Shortcuts`/`FocusTraversal*` in `lib/pages`) + Read of card widgets and player key handling |
| Critical | Movie “back to episodes” dead end | Read: `player_sources_panel.dart:311-318`, `471-485` + `player_screen.dart:2575` |
| High | Accent hardcoded per screen | Grep `0xFFE50914` / `PlayerTheme.accent` + Read of `_Palette` definitions |
| High | Hero carousel mouse-only | Read: `home_page.dart:1373-1420`, `2228-2230` |
| High | Filter tab target/focus | Read: `home_page.dart:929-960` |
| High | Music silent blank | Read: `music_page.dart:151-154`, `996-1064` |
| High | Settings flat list | Read: `settings_page.dart:415-820` + grep (no search field) |
| High | Settings chrome hardcoded | Grep of `Scaffold`/`AppBar` colours across `lib/pages/settings` |
| High | Empty-state inconsistency | Grep `EmptyState`/`No results`/`No items` + Read of each site |
| High | Spinner-only loading | Grep `CircularProgressIndicator` (46+ files) vs grep `Skeleton`/`Shimmer` (3 implementations) |
| High | Dock labels/hover | Read: `liquid_dock.dart:196-215`, `236-283` + `dock_settings.dart` |
| High | Dock absent on half the surfaces | Grep `AppLiquidDock(` → 7 pages |
| Medium | No keyboard Back on entity screens | Grep `LogicalKeyboardKey` across `lib/pages` + Read of Details |
| Medium | pushReplacement back-stack squash | Grep `pushReplacement` + Read of call sites |
| Medium | Four error patterns + silent failures | Grep `SnackBar`/`catch` + Read of each site |
| Medium | SnackBars over video | Grep `ScaffoldMessenger` in player files |
| Medium | Missing image placeholder | Read: `continue_watching_slider.dart:403-421` vs `movie_card.dart:288` |
| Medium | Sub-44 px touch targets | Read of each cited widget's padding/constraints |
| Medium | Contrast below AA | `[computed]` from cited colour constants (arithmetic, not measured) |
| Medium | Missing semantics on cards | Grep `Semantics(` across `lib` → 2 sites in `lib/pages` |
| Medium | Dock flattens history | Read: `app_liquid_dock.dart:41-58` |
| Medium | Duplicate entry points | Read: `home_page.dart:879-905`, `1090-1135` + `dock_settings.dart` |
| Low | withOpacity/withValues mix | Grep both APIs per file |
| Low | Back-button drift | Grep `arrow_back`/`chevron_left` across `lib/pages` |
| Low | Intro splash | Read: `home_page.dart:819-875` |
| Low | Music toast vs SnackBar | Read: `music_page.dart:107-113`, `3497-3501` |
| Low | Cloud Synced badge | Read: `my_list_page.dart:288-330` |
| Low | Half-pixel type | Grep `fontSize: 9.5|12.5|13.5` |

**Declared inferences**: no finding in this document depends on runtime behaviour I did not read.
Two places where I reasoned from code to consequence rather than observing it are marked inline:
(a) “the Tooltip label is not reliably announced as a button” (High #H9) is Flutter behaviour
inference; (b) the emphasis on screen-reader impact (Medium #M9) assumes a screen-reader user,
which is standard guidance rather than a measured session. All contrast values are arithmetic on
cited constants and are labelled `[computed]`. No builds, analysers or tests were run, per the
assignment's constraints, so no finding here is a runtime-verified failure.

**Not covered / out of scope**: the AI quiz surface (`lib/pages/ai/wewatch_quiz_page.dart`),
MultiNutz, the TV calendar beyond its loading spinner, the music/audiobook “studio” editors
beyond their chrome and section headers, and the anime-arabic detail page beyond confirming it
themes correctly. `lib/pages/settings/updates_settings_page.dart` was not opened.

---

## Television focus pass — 2026-10-12 (open findings)

A remote-only pass over the whole television UI on build 1.6.2 (Google TV emulator, 1920×1080 @ 320
dpi = 960×540 dp) with the real profile imported — Real-Debrid plus eleven addons — so streams
actually play. Everything below is device-observed; the frames are in `build/emu_shots/v3_*`
(gitignored, so regenerate if absent). **Six findings are open.**

| Severity | Finding | Evidence | Suspected cause |
| --- | --- | --- | --- |
| High | After a source filter is applied the Watch Sources page holds no focus and Up/Down do nothing — Back is the only way out | `v3_193_filtered.png`, `v3_197_applied.png`, `v3_202..v3_205` (four byte-identical frames) | the panel's list is rebuilt under the remote and nothing claims focus afterwards |
| Medium | A second focus ring stays lit on Home's Continue Watching card indefinitely — through scrolls, a detail page and a full player round trip — so two rings are lit at once and the true one is hidden | `v3_58_up_a.png` (bbox (32,784)-(591,1079), 280×148 dp), `v3_73`, `v3_80`, `v3_140` | `[inference]` a stuck `state.focused` in that card's `FocusableActionDetector`/`CardFocusRing` |
| Medium | The source-type filter chips (All / Debrid / Torrents / Direct) take focus with no ember ring — Material's own highlight only | `chips_cmp.png`, `v3_188_r.png`, `v3_189_r2.png` | no `CardFocusRing` in `_buildTypeChip` in `lib/pages/player/watch_screen.dart` |
| Medium-Low | The player top bar's `Sources` pill takes focus and paints its ring, and OK opens nothing | `v3_131_sources_focus.png`, `v3_132_panel.png` | the action needs `_sourcesTarget != null` while the panel needs `_sourcesEpisode != null` |
| Low | A seek step on the focused seek bar hides the whole HUD within 0.25 s and it stays hidden | `v3_113_seekbar2.png`, `v3_114_seek_fast.png`, `v3_115_seek_after3s.png` | the HUD had survived eleven transport presses just before, so it is not the auto-hide timer |
| Low | Up out of the transport is not deterministic — from −10 it reached the top bar in one run and the seek bar in another | `v3_100_probe.png`, `v3_111_seekbar.png` | see the traversal-hysteresis note in `lib/shell/app_shell.dart` |

Also observed, not yet triaged: re-entering the same Continue Watching card restarted near 1:17
after the first entry was at 33:07 (`v3_84_details2.png` vs `v3_85_transport.png`) — an inference,
not a measurement; and the imported profile ships both Home top-row glyphs **disabled**, which is
why the calendar hand-over cannot be reached on a fresh import until they are enabled
(`v3_40_appearance_page.png`).

**Confirmed good on the same pass**, for the record: all eleven transport stops paint exactly one
3 dp ember ring on the focused control's own edge, with real playback over Real-Debrid (position
33:07 → 36:10, video-area pixels changing between frames); a title page opens with the ring on its
primary action; the Live TV hero band holds the channel's dimmed wordmark while the nav marks Live
TV; and the Home calendar's arrival is reversible in both directions.

**Rig note.** The television emulator is built with `--dart-define=ZPLAY_FORM_FACTOR=tv` — every
Android TV image declares a touchscreen, so production detection reads one as a phone — and with
`--dart-define=ZPLAY_AUTO_IMPORT=true`, which imports `zplay_profile.json` from the app's own
external files directory at startup. That file sits at
`/storage/emulated/0/Android/data/io.github.tzero86.zplay/files/zplay_profile.json` on both
emulators (a copy also sits in `/sdcard/Download/`), and it is what makes real sources available.

