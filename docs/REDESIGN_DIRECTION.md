# ZPlay: UI and UX redesign direction

Review and design charter for the shell, navigation and identity rewrite. Companion to
`DESIGN_AUDIT.md` (what the tokens replaced) and `UX_FINDINGS.md` (screen-by-screen usability).
The interactive prototype for everything proposed here is `docs/redesign/preview.html`; open it
from the repository root so its relative font and icon paths resolve.

Measured against `main` as it stood when this review was written; phases 1 to 4 have landed since.
Every number in the review below is a `grep` or a `find` over `lib/`, reproducible with the commands
at the bottom.

## Status

Phases 1 to 4 of the plan below have landed. Phase 5 has not.

**Phase 4, the token migration, landed across `lib/`.** Every page and shared widget now reads
`context.tokens` and the `ZplaySpacing`, `ZplayRadius`, `ZplayType` and `ZplayOpacity` scales instead
of carrying its own literals: the shell slots (Home, Browse, Search, Library, Settings), the settings
family, the seven Browse verticals, the details screen, the media readers, the entity and modal
screens, and the shared poster cards, rails, skeletons and dialogs. The player and reader families are
on the same footing now rather than keeping a parallel vocabulary: `PlayerTheme` in
`lib/widgets/player/player_glass.dart` is a token-backed bridge that keeps its member names, so the
player widgets follow the active palette, and `ReaderTokens` is the same arrangement for the readers.
Because no screen carries a fixed near-black palette any more, a palette or accent change applies
everywhere instead of only to the shell, and the fork's competing greens, cyans and violets collapsed
onto the single accent plus the semantic status tokens; third-party service brands (Trakt, Simkl,
Discord) and the per-quality and HDR badges keep their identity colours. `flutter analyze` is clean,
so the 18 info-level issues recorded under Verification below are gone.

**Shipped**

| piece | file |
|:--|:--|
| The form-factor classifier, replacing the 11 ad-hoc breakpoints | `lib/services/layout/form_factor.dart` |
| The shell: five slots in an `IndexedStack`, adaptive rail, keyboard map, focus groups | `lib/shell/app_shell.dart` |
| The controller a slot page reaches the shell through | `lib/shell/app_shell_scope.dart` |
| The rail in all four placements | `lib/shell/shell_rail.dart` |
| The scrollable switcher control, for more options than fit | `lib/widgets/common/tab_strip.dart` |
| Browse, the seven verticals behind one switcher | `lib/pages/browse/browse_page.dart` |
| Library, My List and Downloads as two tabs | `lib/pages/library/library_page.dart` |
| The playback seam, and the bar that reads it | `lib/services/playback/now_playing_service.dart`, `lib/shell/now_playing_bar.dart` |
| The music adapter, so music survives leaving Music | `lib/services/playback/music_now_playing_bridge.dart` |
| The token layer as the single source for every screen and shared widget | `lib/services/theme/design_tokens.dart` |
| The player family's token bridge, keeping `PlayerTheme`'s member names | `lib/widgets/player/player_glass.dart` |

The dock is deleted: `app_liquid_dock.dart`, `liquid_dock.dart`, `dock_settings.dart`,
`appearance/dock_settings_page.dart` and `test/liquid_dock_test.dart` are gone, and `lib/` and
`test/` contain no reference to any of them. The nine pages that mounted one had it removed along
with the bottom padding that existed only to clear it.

**Found by running the built app rather than by reading it.** `DiscoverPage`, the Movies & TV
vertical, still rendered a back arrow in its toolbar whose only job was `Navigator.pop`. As a
vertical it is never pushed, so that arrow could only pop the shell. It is now gated on
`Navigator.of(context).canPop()`, which is the same treatment the other twelve back affordances in
slot pages got, and it is gated rather than deleted because the legacy search and genre route still
pushes this page with a query and that instance does need a back button. Nothing in the analyzer,
the test suite or any slice report caught it: the other five verticals were cleaned and this one was
missed because its back button lives in a scaffold the de-navigation slice never opened.

**Chrome has to clip what it covers.** The shell puts chrome (the rail, the switcher band) above a
page's scroll view, so any page that scrolls with `clipBehavior: Clip.none` paints its content over
that chrome. The rule this work settled on is: **whatever stacks chrome above a page owns clipping
that page.** It is applied at three sites, `app_shell.dart:264` for the rail and the bottom bar,
`browse_page.dart:180` for the band above the seven verticals, and `library_page.dart:126` for the
band above its two tabs. That the first site alone was not enough is the part worth recording:
clipping at the shell only clips at the shell's top edge, which is *above* the band, so scrolled
anime content still covered all seven switcher chips. The defect was reproduced by scrolling the
Anime vertical, and the fix was re-checked the same way. The root cause is unchanged and still open:
about 21 files use `ListView(clipBehavior: Clip.none)` so a hidden slider arrow can sit outside the
viewport, which is a per-widget decision that predates the shell.

**The page header is opaque, not a 90-96% gradient.** `_GlassAppBar` in Home and `_AnimeGlassAppBar`
in Anime carried byte-identical `[0xF5080A0F, 0xE6080A0F]` gradients over a `white@0.06` hairline.
With bright artwork scrolling under them the bar read as a smear over the content. Neither bar has a
lens behind it (`PerformanceLiquidLens` wraps neither), and the gate that would supply one,
`GlassSettings.enabled`, defaults to `false`, so the smear was the default experience rather than a
misconfiguration. Both now use `context.tokens.bg` and `context.tokens.borderSubtle`: the hairline is
unchanged, the fill is opaque, and the fill is palette-derived. That last part fixes a second bug,
because `#080A0F` is only the ocean palette's `scaffoldBackgroundColor`, so the bar was ocean-black
under all eleven other palettes.

Two other translucent bars were deliberately left alone. Live TV's `_IptvGlassAppBar` fades to fully
transparent with no bottom border, which makes it a scrim over a hero rather than a bar, and making
it opaque would delete the fade's purpose. Music's `_MusicTopHeader` sits inside
`PerformanceLiquidLens`, so it does have a real glass path (`useImpellerBackdrop: true`) behind the
default-off gate, and opaque-ifying its fill would paint over the lens and leave the glass with
nothing to show. It still smears while glass is off, so closing that needs a decision about the
fallback decoration in `performance_liquid_lens.dart`, not a one-line fill change.

**Verification.** At the time of this review `flutter analyze` reported 18 issues, all `info` level
and all pre-existing in `lib/widgets/iptv/multinutz_channel_sheet.dart`, a file this work never
touched: zero errors and zero warnings. Phase 4 has since cleaned those up, so the command now reports
no issues at all. `flutter test` reports **257 passing, 8 failing**, against a pre-change baseline of
255 passing and the same 8 failing. The arithmetic closes: minus the six tests in the deleted
`test/liquid_dock_test.dart`, plus eight new boundary tests in `test/form_factor_test.dart`. The
eight failures are live-network scraper tests that were already failing before any of this, so no
test regressed.

The classifier is the one new piece with permanent tests, deliberately. It is a pure function over
two numbers, it is what every chrome decision reads, and its two easy-to-break facts are that the
bands are half open and that a television is decided by its input rather than its width. Everything
else in the shell was verified by running the built app instead.

`analysis_options.yaml` gained one exclude, `flutter/**`. The SDK is vendored at the repository root
as a gitlink, so `flutter analyze` from the root was walking into the SDK's own test fixtures and
reporting hundreds of errors that are not this project's Dart, which made the canonical command
useless as a signal. It now takes about six seconds and reports only this project.

**Not yet done, in the order I would take them**

1. **The now-playing bar cannot reach Music's expanded player.** Music's full player is a private
   flag, so the bridge ships a request counter (`MusicNowPlayingBridge.expandRequests`) that works
   only when Browse is already showing the Music vertical. Tapping the bar from another vertical
   switches to Browse and lands on whatever vertical was last shown. Closing it needs Browse to
   expose "select this vertical", which is a few lines in `browse_page.dart`.
2. **Audiobooks are only half wired.** Their playback lives in a private State, so the bar reflects
   them only while their player screen is open. The full extraction is a real refactor and changes
   when playback stops, so it wants its own pass.
3. **Phase 5, identity.** The palette presets still move the backgrounds rather than only the accent,
   there is still no light theme, the splash overlay still replays on every launch with no skip, the
   unused display serif still ships with no role, and Home still carries the duplicate Anime filter
   tab covered by the next item.
4. **Home still carries its `All / Movies / Series / Anime` filter.** The charter's phase 3 called for
   deleting the Anime tab because it duplicates the Anime vertical, and it was deliberately deferred:
   it is woven through about twenty sites in Home's content assembly, and it is a content change
   rather than a navigation one.
5. **Television chrome has not been seen on a real device.** It is driven by `navigationMode`, which
   no desktop build reports, so the ten-foot layout is covered by widget tests and by the prototype
   rather than by a screenshot.

## Design read

**Reading this as:** a daily-driver media client for phone, tablet, desktop and Android TV, where the
chrome should be calm and the artwork should be loud. Keeping the token layer and the shared
primitives that already work, replacing four competing navigation models with one adaptive shell.

| dial | value | why |
|:--|:--|:--|
| DESIGN_VARIANCE | **4** | Reordered from the baseline. This is a library people use every day, not a marketing page. The content supplies the visual interest; high-variance chrome is hostile when you are in it for hours. |
| MOTION_INTENSITY | **4** | The app ships a jank monitor and a perf HUD, and the player must not fight libmpv for frames. Fluid token-driven transitions only, and only where they communicate something. |
| VISUAL_DENSITY | **5** | Chrome calms down, content stays dense. Rails keep nine to twelve cards visible, server rows keep their codec and HDR badges, numbers stay tabular. |

### Scope honesty

The design-taste skill that prompted this review targets landing pages and portfolios, and puts
dense product UI and native mobile explicitly out of scope. So it is applied here where it applies
(one accent, one radius system, no em-dashes, no AI tells, real images, button and form contrast,
the eyebrow count rule) and the app screens are designed against the platform conventions Flutter
already provides: an adaptive shell, `FocusTraversalGroup`, honest hit targets. The one surface in
this repository that is genuinely in that skill's scope is `docs/index.html`, and it gets its own
pass in the last section.

---

## The review

### 1. Navigation is the structural problem, and the dock is a symptom

The user-facing complaint is that the dock appears on most pages but not all, and disappears on
Music and Audiobooks. The cause is deeper: **there is no app shell.**

`lib/main.dart` builds a plain `MaterialApp` with `home: const HomePage()` and no route table. Every
destination page owns its own `Scaffold` and stacks its own copy of the navigation on top:

| fact | value | evidence |
|:--|:--|:--|
| `AppLiquidDock(` mount sites | **8** (7 real destinations plus one live preview inside the dock settings page) | `home_page.dart:829`, `discover_page.dart:489`, `anime_page.dart:530`, `manga_page.dart:404`, `books_page.dart:322`, `iptv_page.dart:356`, `multinutz_page.dart:902`, `appearance/dock_settings_page.dart:192` |
| dock destinations defined | **13**, all enabled by default, only `home` and `settings` non-removable | `dock_settings.dart:4-95`, `:117-119` |
| navigation layer | exactly one file, and it holds transitions only. No routes, no shell | `lib/utils/navigation/route_transitions.dart` |
| adaptive navigation primitives | **zero** uses of `NavigationBar`, `NavigationRail` or `BottomNavigationBar` in the whole app | grep over `lib/`, no matches |
| `MaterialApp` routing | `home:` plus a global `navigatorKey` that only the update dialog reads | `main.dart:46`, `:199-215` |

A page can forget to render a dock. A page cannot forget to render a shell. That is the whole
argument, and it means the fix is not a better dock but moving navigation out of the pages.

There is a second, sharper consequence. `_navigateToPage` pushes only from Home and uses
`pushReplacement` everywhere else (`app_liquid_dock.dart:41-58`), so Home to Manga to Books leaves a
stack of two. Back skips a section, and every switch rebuilds the page, so scroll position, catalog
filters and search text are gone. The prior audit also recommended an `IndexedStack` shell
(`UX_FINDINGS.md:701-703`); this charter agrees and goes further, because mounting the existing
13-item dock on every surface would solve consistency by making the worst case universal.

### 2. Four navigation models, not one

| model | where | evidence |
|:--|:--|:--|
| the floating dock | 7 destinations | `app_liquid_dock.dart` |
| app-bar icons | Home only, duplicating Discover, Search and Settings | `home_page.dart:1090-1135` |
| Home filter tabs | All / Movies / Series / Anime, a second partial anime experience | `home_page.dart:879-905` |
| Music's private shell | a 240 px desktop sidebar, a 60 px mobile bottom nav, a floating player bar and two drawers | `music_page.dart:2088`, `:2785`, `:3548` |

Anime is reachable from two of the four. Music is the clearest case: it needed its own navigation
precisely because it could not express "audio is playing" through the shared chrome.

### 3. The accessibility groundwork is done; the TV layer is not

This corrects a stale claim in `UX_FINDINGS.md`, which says the primary card is a `GestureDetector`
that Flutter cannot focus. That has since been fixed: `MovieCard`, `AnimeCard` and `MangaCard` all
return `FocusableCard`, which now has **126 uses across 57 files**, and `CardFocusRing` and
`CardInteraction` appear in 18.

What is still missing is everything that makes focus *usable*:

| fact | value | evidence |
|:--|:--|:--|
| TV or leanback detection | **none** in 336 files, though Android TV ships | grep `isTV` / `leanback`, no matches |
| `FocusTraversalGroup` | **none** | grep, no matches |
| `Shortcuts` / `Actions` | **none**, so there is no key map and no remote Back | grep, no matches |
| `FocusNode` | 13 files only | grep |

So focus order is Flutter's geometric guess, there is no consistent Back on entity screens, and the
app cannot even choose a 10-foot layout because it cannot tell it is on a TV.

### 4. Responsive behaviour is per-screen and has drifted

| fact | value |
|:--|:--|
| files branching on width or using `LayoutBuilder` | **58** (25 of them `LayoutBuilder`) |
| distinct breakpoint numbers | **11**: 600, 640, 700, 800, 900, 1024, 1100, 1200, and three more |
| `shortestSide` | never used |

There is no form-factor policy to extend, so each new screen invents one.

### 5. Foundations: one excellent token layer, then almost no adoption

`design_tokens.dart` is genuinely good work and the redesign should build on it, not replace it. At
the time of this review the migration had barely started, and the ad-hoc values had **grown** since
the audit, because new screens kept adding their own:

| measure | audit | now |
|:--|--:|--:|
| distinct hardcoded colours | 421 | **423** across 108 files, 1,836 literal occurrences |
| distinct `BorderRadius.circular(N)` values | 14 | **28** |
| distinct `fontSize:` values | 18 | **32** |
| files reading the token layer | n/a | **6** of 336 (`ZplayTokens` or `context.tokens`) |
| total references to the token scales | n/a | **54** |

Phase 4 has since closed both adoption rows: every page and shared widget reads `context.tokens` and
the scales beside it, which retires the private copies below (see Status).

Three screens kept private copies of the scales beside the real ones, and one of them hardcoded its
own background:

| file | private tokens |
|:--|:--|
| `pages/details/details_page.dart:22-41` | `_Space` plus `_Palette`, with literals `0xFF0B0D12` and `0xFF15171F` |
| `pages/anime/anime_details_page.dart:19-31` | `_Space` plus `_Palette` |
| `pages/anime_arabic/anime_arabic_details_page.dart:13-21` | `_Space` plus `_Palette` |

Two more foundation gaps, both cheap to close and both blocking later work:

* **`createThemeData` is thin.** It sets `scaffoldBackgroundColor`, `colorSchemeSeed`,
  `appBarTheme`, `cardTheme`, `pageTransitionsTheme` and the token extension
  (`app_theme_service.dart:171-201`). No `textTheme`, `inputDecorationTheme`, `dialogTheme`,
  `chipTheme`, `listTileTheme`, `dividerTheme`, `navigationBarTheme` or `snackBarTheme`, so every
  one of those is restyled by hand per screen. Filling them in is what turns the token layer into a
  design system.
* **No elevation scale.** The only shadow scale in the repository is inside
  `pages/books/widgets/reader_design_tokens.dart`, the token file the book reader grew for itself;
  `ReaderTokens` now bridges onto the contract layer rather than standing beside it, but the shadow
  scale is the missing piece for cards, sheets and menus.
* **No reduced-motion branch.** `ZplayMotion` documents the gap in its own comment, and exactly one
  surface implements it: `epub_reader_page.dart:262` and `widgets/focus_mode_view.dart:288` branch on
  `MediaQuery.disableAnimations`. The player chrome, the dock and the rails ignore the setting.

### 6. Identity: why the app still looks like the app it forked

This is the user's headline complaint, and it has one dominant cause.

**The theme picker moves the backgrounds.** `AppThemePalette` carries
`scaffoldBackgroundColor`, `cardBackgroundColor` and `appBarBackgroundColor` per preset, and there
are 9 presets. Preset two is upstream's Amethyst Violet on upstream's near-blacks
(`app_theme_service.dart:54-62`), so choosing it makes ZPlay look like PlayTorrio by design. A brand
whose surfaces are user-swappable back to the ancestor's palette is not a brand.

Secondary causes, in order of how much they cost:

| cause | evidence |
|:--|:--|
| Upstream's signature motion is still the app's signature motion | a 380 ms circular liquid reveal on every push (`route_transitions.dart:31-81`) and a pointer-driven jelly magnification on the dock (`liquid_dock.dart:196-258`) |
| A splash overlay replays on every launch, with no skip | `home_page.dart:819-875` |
| Accent-era leftovers | resolved by phase 4: the fork's extra greens, cyans and violets collapsed onto the single accent and the semantic status tokens, which is what the token layer's own comment asks for (`design_tokens.dart:349-352`) |
| A decorative italic serif ships and is never used | `PlayfairDisplay-SemiBoldItalic.ttf` is declared in `pubspec.yaml` and referenced **nowhere** in `lib/` |
| There is no light theme at all | `createThemeData` hardcodes `Brightness.dark` (`app_theme_service.dart:177-201`); no file mentions `Brightness.light` or `ThemeMode.light`, and `segmented_tabs.dart:32-40` documents that the control assumes a dark surface |

---

## The design

### Destination model: three tiers, one owner each

Thirteen peers is the root cause. Content types are not peers of Settings, and they keep growing. The
model below gives every existing destination exactly one entry point and never deletes a feature.

**Tier 1, shell slots.** Persistent, at most five.

| slot | contents |
|:--|:--|
| Home | the landing surface: continue watching, recommendations, rails |
| Browse | every content vertical, behind the switcher below |
| Library | My List, Downloads and History as three tabs of one surface |
| Settings | unchanged in scope, recomposed in layout |
| Search | a slot on phone and TV only; a pinned top-bar field on tablet and desktop |

**Tier 2, the vertical switcher**, inside Browse: Movies & TV, Live TV, Anime, Manga, Books,
Audiobooks, Music. Seven destinations become one `SegmentedTabs` control, a primitive that already
exists, already carries 44 px targets, a focus ring and semantics, and already has 36 call sites.

**Tier 3, entity routes**: Details, the player, the readers, the stream sheet, the portal browser.
These are a level *below* the shell, which is the correct answer to "Details has no dock". They get
their own back, and they push rather than replace.

Where each of the 13 dock items goes:

| today | after |
|:--|:--|
| Home, Settings | slots 1 and 4, unchanged |
| Search | slot 5 on phone and TV, top-bar field plus a shortcut elsewhere |
| Discover | Browse, the catalog feed for the selected vertical |
| Anime, Manga, Books, Audiobooks, Music, Live TV | Browse verticals |
| My List, Downloads | Library tabs 1 and 2 |
| Addons | Settings, where it already lives |
| Catalog, Calendar, MultiNutz, anime-arabic, the quiz | folded into Browse or Home as views, nothing deleted |

That resolves the duplicate entry points the prior audit flagged: Home loses its Anime tab (its All
tab already appends anime rows at `home_page.dart:662`), Search and Settings leave the app bar once
the shell owns them, and Music's sidebar is deleted.

### The shell

One widget, above every destination, owning:

* the slot index and the rail placement for the current form factor
* an `IndexedStack` over the slots, so section state survives a switch. This is the fix for the
  `pushReplacement` history squash and for lost scroll and filter state, and it is what makes Back
  the same gesture everywhere.
* the now-playing bar
* the form-factor value that pages read instead of branching on width themselves

A per-slot `Navigator` is the alternative to a single `IndexedStack` and is worth the extra
complexity only if a slot needs its own deep stack. Start with `IndexedStack`.

### The now-playing bar is the real fix for Music and Audiobooks

Music ships four private mini-player presets (`music_page.dart:3584-3669`) and Audiobooks ships its
own transport, which is exactly why neither can host the dock: they already occupy the bottom of the
screen. Move playback to one shell-owned bar.

* Audio gets full transport: artwork, title and artist, previous and play and next, a 2 px accent
  progress line, and tap-to-expand into the full player.
* Video gets a resume entry, so leaving the player is not a dead end.
* One component, in every chrome: above the bottom bar on phone, at the foot of the content column
  elsewhere.

This is the element that makes the app feel seamless rather than stitched, because playback state
stops belonging to a page.

### Form-factor matrix

One classifier decides once, at the shell. No page branches on width again.

| form factor | classified by | chrome | slots | targets | input |
|:--|:--|:--|:--|:--|:--|
| Phone | `shortestSide < 600` | bottom bar, content scrolls under a translucent top bar | 5, Search included | 44 px, 48 for the primary action | touch; no hover-only affordance ships |
| Tablet | `600` to `1024` | left rail, 88 px, icon over label | 4 plus a top-bar field | 48 px | touch and keyboard, both orientations |
| Desktop | `>= 1024` on Windows, macOS, Linux | left rail, 88 px, window-managed minimum width | 4 plus a top-bar field and Ctrl or Cmd K | 44 px, hover and pressed on everything | full keyboard: search, back, transport, rail traversal |
| Android TV | a **new** detector | expanded left rail, 236 px, always labelled | 5, Search is a rail row | 56 to 64 px | `FocusTraversalGroup`, one accent focus ring, hierarchy-aware Back |
| Any, reduced motion | `MediaQuery.disableAnimations` | unchanged layout | unchanged | unchanged | every duration collapses to zero, every curve is kept, loops stop |

Two rules that fall out of the matrix and should be enforced in review:

1. **One search affordance per form factor.** A nav row on phone and TV, a field on tablet and
   desktop. Never two on the same screen.
2. **The wordmark needs 236 px of rail.** At 88 px the mark alone carries the brand.

### Identity charter

| decision | why |
|:--|:--|
| **The picker moves only the accent** | Keep the presets if the freedom is wanted, but have every one of them feed `ZplayTokens` surfaces from a single neutral ramp. Then no preset can make the app look like its ancestor, and the structure is recognisably ZPlay in all of them. |
| **One accent, six jobs** | The accent means one thing everywhere: this is live, active or now. The current nav slot, the focus ring, playback progress, a live channel, the selected segment. Nothing else gets it, so the colour teaches the app. Which colour that is comes from the preset — the default is `ember` (Ember Crimson) — but the rule is about what the accent *means*, and it holds for every preset. |
| **The accent is never body text** | It is a fill and an indicator. That is also what lets one accent work on both a dark and a light ramp, since `onAccent` is already chosen by measured contrast (`design_tokens.dart:_onAccentFor`). |
| **Retire upstream's theatre** | The circular liquid reveal, the pointer jelly and the replaying splash are exactly the moves that make the two apps feel identical. Replace with a fade-through and one skippable cold-start brand moment. |
| **Light mode becomes possible** | Every colour is already semantic, so the ramp is the only missing piece. Snap the three private `_Space` and `_Palette` copies to the real scales first, then invert. |
| **One radius rule** | Cards 14, controls and inputs 10, pills fully round, sheets 20 on the top corners only. 28 ad-hoc radii collapse to one documented rule. |
| **Delete the dead** | Drop the unused display serif, or give it exactly one role. A decorative italic serif beside a geometric sans is also the specific mixed-family move the taste rules ban. |

---

## Frontend pass on the landing page

`docs/index.html` is the repository's actual frontend surface, and it is otherwise in good shape:
headings, hierarchy, the token-matched palette and honest measured numbers are all fine. Five
specific findings, all mechanical:

| finding | measured | rule it breaks |
|:--|:--|:--|
| Em-dashes everywhere | **9**, plus a second one in `<title>` | Zero is the rule. Hyphens, full stops or a colon all work. |
| An eyebrow above *every* section | **5 eyebrows for 5 sections**, allowed is 2 | Max one per three sections. Drop three of the five. |
| A decorative dot on every card heading | **23** occurrences of `class="dot"` | No decorative status dots. The dots carry no state on this page. There is also a **second accent**: `--green:#10B981` beside `--accent:#2FD0C0`. (Those names and values are the audited revision's; the stylesheet has since been re-tokenised and both are gone.) |
| Six radii, three of them off the app's own scale | 12, 16, 26, 6, 999, 50% | The stylesheet's own comment claims it matches the token layer. The app's scale is 6, 10, 14, 20, 28, 999. |
| Five images, and none of them the product | 4 shields.io badges and the app icon | A media app's landing page with no screenshot of the media app. Generate or shoot three or four real surfaces: a browse grid, the player with the sources panel, a reader, and now-playing. |

Not applied, because both the dot and eyebrow changes are design decisions on a live public page and
the screenshot work needs real assets. Say the word and they are a single small commit.

---

## Order of work

Each phase ships on its own and is visible on its own. The enabling work comes first because every
later phase gets cheaper as a result.

### Phase 1, shell skeleton

* the form-factor classifier, the TV detector, and the reduced-motion branch `ZplayMotion` is missing
* the shell widget: rail, content, now-playing, slots kept alive in an `IndexedStack`
* route entity screens above the shell, leaving every current page untouched inside it

**Acceptance:** switch slots four times and return. Scroll position, filters and search text are all
still there, and Back is the same gesture from every slot.

### Phase 2, the now-playing bar

* one shell-owned transport reading the existing music and audiobook services
* delete Music's four mini-player presets and its sidebar, delete the Audiobooks transport
* video gets a resume entry

**Acceptance:** start audio in Music, navigate to Settings, and the transport is still there and
still playing.

### Phase 3, Browse and the vertical switcher

* seven verticals behind one `SegmentedTabs`
* delete Home's Anime tab and its second, partial anime content model
* fold Catalog, Calendar, MultiNutz and anime-arabic in as views of a vertical

**Acceptance:** every one of the 13 old destinations is reachable in two actions or fewer from the
shell, and exactly once.

### Phase 4, token migration on the surfaces the shell just created

* delete the three private `_Space` and `_Palette` copies and the 1,836 literals, Details first, then
  Settings, then the verticals
* fill in the missing Material sub-themes so components inherit instead of being restyled per screen
* add the elevation scale, and extract the shared empty, loading, error and section-header
  components out of the 86 `CircularProgressIndicator` call sites

**Acceptance:** changing the accent repaints the whole app correctly. Zero literal hex colours
outside provider brand marks.

### Phase 5, identity

* accent-only theming, and a real light ramp
* retire the liquid reveal, the splash replay and the jelly-only magnification
* drop the unused display serif, or give it one role

**Acceptance:** no preset makes the app look like its upstream, and light mode passes the same
contrast checks as dark.

---

## The one decision this does not make for you

Whether **Library is a single slot with three tabs**, or **My List and Downloads stay two separate
slots**. Both are defensible, the rest of the plan is unaffected, and the prototype is built for the
single-slot version. Everything else in this document follows from the evidence rather than from
preference.

---

## Reproduce

```bash
# readings taken when this review was written, before phases 1 to 4 landed; Status records what shipped since
cd lib

# scale of the app
find . -name '*.dart' | wc -l
find . -name '*.dart' -exec cat {} + | wc -l

# colour and scale drift
grep -rhoE '0x[0-9A-Fa-f]{8}' --include=*.dart . | sort -u | wc -l      # 423
grep -rhoE '0x[0-9A-Fa-f]{8}' --include=*.dart . | wc -l               # 1836
grep -rhoE 'BorderRadius\.circular\([0-9.]+\)' --include=*.dart . \
  | grep -oE '[0-9.]+' | sort -u | wc -l                               # 28
grep -rhoE 'fontSize: [0-9.]+' --include=*.dart . \
  | grep -oE '[0-9.]+' | sort -u | wc -l                               # 32

# token adoption
grep -rlE 'ZplayTokens|context\.tokens' --include=*.dart . | wc -l     # 6 before phase 4
grep -rhoE 'ZplaySpacing|ZplayRadius|ZplayType|ZplayMotion|ZplayOpacity' \
  --include=*.dart . | wc -l                                           # 54 before phase 4

# the missing navigation and TV layers
grep -rc 'NavigationBar\|NavigationRail' --include=*.dart .            # no matches
grep -rn 'FocusTraversalGroup\|Shortcuts(' --include=*.dart .          # no matches
grep -rn 'isTV\|leanback' --include=*.dart .                           # no matches

# the dock
grep -rn 'AppLiquidDock(' --include=*.dart pages widgets | wc -l       # 8

# reduced motion, the whole app
grep -rn 'disableAnimations' --include=*.dart .                        # 2 files, both the EPUB reader
```
