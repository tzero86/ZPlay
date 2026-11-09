# Movy-style UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PlayTorrioZero's browsing UI read as a polished, Netflix-style dark app (movy.sx reference): full-bleed hero backdrops, precise poster tiles with metadata, ranked rows, and simple navigation, working on desktop, TV, mobile and web.

**Architecture:** This continues the redesign in `docs/REDESIGN_DIRECTION.md`. Phases 1-4 (shell, now-playing bar, Browse, token migration) have landed; this plan is its phase 5 (identity) plus the visual work the reference site implies. Changes are kept inside the existing token layer (`ZplaySpacing`, `ZplayRadius`, `ZplayType`, `context.tokens`) and the existing shell, so no screen gets a private palette. Home's hero and the shared poster widgets are the main surfaces.

**Tech Stack:** Flutter/Dart (Material 3, `ThemeExtension` tokens), existing `flutter_test` widget tests.

**Spec:** `docs/REDESIGN_DIRECTION.md` (Identity charter and Phase 5). The movy.sx reference was observed via its public page only; no CSS or pixel values were extracted, so exact visuals are chosen in Task 9 by side-by-side screenshot comparison.

## Global Constraints

- Backgrounds are palette-independent: `ZplaySurfaces.bg #0A0D12`, `surface #111621`, `raised #161C29`. Presets set the accent only.
- Radii come from `ZplayRadius` only: cards `md`/`cardAll` (14 per charter, or the existing content-tile `xs`/`sm` rule documented at `design_tokens.dart:121`; do not add new values), controls `sm`, pills `full`.
- No new hardcoded `0x` colours outside `design_tokens.dart`.
- The accent is a fill or indicator, never body text. It marks live/active/now only.
- Every motion honours the reduced-motion branch in `ZplayMotion`.
- `flutter analyze` must stay clean; `flutter test` must pass before each commit.

## Review Focus

- **Missing artwork:** a title with no backdrop or poster must show a token-coloured placeholder, not a broken image or empty hero. Expected: the hero falls back to a gradient on `ZplaySurfaces.surface`.
- **Long or non-Latin titles:** titles longer than the tile and Arabic/RTL titles (`lib/l10n` has `ar`) must truncate with ellipsis and not overflow. Expected: no `RenderFlex overflowed` in tests.
- **Focus visibility on TV/keyboard:** the new hover and tile styling must keep a visible focus ring. Expected: a focused tile shows `CardFocusRing` even with the new scrim.
- **Narrow phones (about 320 dp):** rails and hero buttons must fit without overflow. Expected: hero actions wrap or shrink; rail tiles remain tappable.
- **Reduced motion:** the fade-through and hero transitions must be instant when reduced motion is on. Expected: no animation controller runs.

---

### Task 1: Accent-only theming

**Files:**
- Modify: `lib/services/theme/app_theme_service.dart` (`AppThemePalette` at lines 27-57, `palettes` list from line 62)
- Test: `test/theme/palette_surfaces_test.dart` (create)

**Interfaces:**
- Consumes: `ZplaySurfaces` (existing).
- Produces: no new API. Presets carry `id`, `name`, `primaryColor`, `accentColor`, optional hover/pressed. Surfaces are read from `ZplaySurfaces` only.

- [ ] **Step 1: Write the failing test**

```dart
test('every palette uses the shared neutral surfaces', () {
  for (final p in AppThemeService.palettes) {
    expect(p.scaffoldBackgroundColor, ZplaySurfaces.bg);
    expect(p.cardBackgroundColor, ZplaySurfaces.surface);
    expect(p.appBarBackgroundColor, ZplaySurfaces.raised);
  }
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/theme/palette_surfaces_test.dart`
Expected: FAIL only if any preset still pins its own background. If it passes already, the getters are the cause of the drift noted in the charter, so confirm the presets have no background parameter and keep the test as a regression guard.

- [ ] **Step 3: Remove the per-preset background data**

Delete any remaining background literals from the preset list and make sure the three getters are the only source. Keep `id` values unchanged so stored choices still resolve.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/theme/palette_surfaces_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/theme/app_theme_service.dart test/theme/palette_surfaces_test.dart
git commit -m "refactor: keep theme presets accent-only"
```

---

### Task 2: Retire upstream motion and the replaying splash

**Files:**
- Modify: `lib/services/theme/route_transitions.dart` or `lib/shell/route_transitions.dart` (the 380 ms circular reveal, see `REDESIGN_DIRECTION.md` section 6; locate with `grep -rn "circular" lib`)
- Modify: `lib/pages/home/home_page.dart` (`_buildIntroOverlay`, line 1312; splash overlay at lines 819-875)
- Test: `test/shell/route_motion_test.dart` (create)

**Interfaces:**
- Consumes: `ZplayMotion` reduced-motion flag (existing).
- Produces: a `fadeThroughRoute<T>(WidgetBuilder)` helper used by pushed routes.

- [ ] **Step 1: Write the failing test**

Test that a pushed route uses a `FadeTransition` (not a clipper) and that with reduced motion the transition duration is `Duration.zero`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shell/route_motion_test.dart`
Expected: FAIL with the circular reveal widget found.

- [ ] **Step 3: Replace the reveal with a fade-through, and show the splash once per install**

Store a `splash_shown` flag in preferences and skip the overlay when it is set. Add a tap-to-skip on the overlay.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shell/route_motion_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/shell lib/services/theme lib/pages/home/home_page.dart test/shell/route_motion_test.dart
git commit -m "feat: fade-through routes and one skippable intro"
```

---

### Task 3: Extract the hero out of Home

Home is 4036 lines. The hero must move before it can be restyled safely.

**Files:**
- Create: `lib/widgets/home/hero_banner.dart` (holds `_HeroCarousel`, `_HeroSlide`, `_HeroTitle`, `_HeroSynopsis`, `_HeroMaturityBadge`, `_HeroPressable`, `_HeroPressScale`, `_TrailerButton`, `_HeroLogoSlot`, moved and made public as `HeroBanner`, `HeroSlide`)
- Modify: `lib/pages/home/home_page.dart` (import the new file; delete moved classes)
- Test: existing `test/` home tests must pass unchanged.

**Interfaces:**
- Produces: `HeroBanner({required List<HeroItem> items, required ValueChanged<HeroItem> onPlay, required ValueChanged<HeroItem> onMoreInfo})`. `HeroItem` is whatever type `_HeroCarousel` already consumes; do not change it.

- [ ] **Step 1: Run the existing home tests to record the baseline**

Run: `flutter test test/pages/home` (or the closest existing home test; `grep -rln HomePage test`)
Expected: PASS. Record the count.

- [ ] **Step 2: Move the classes unchanged**

Cut the listed classes into the new file, make the two entry points public, and update imports. No behaviour or styling change in this task.

- [ ] **Step 3: Run tests to verify nothing changed**

Run: the same command as Step 1.
Expected: PASS with the same count.

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/home/hero_banner.dart lib/pages/home/home_page.dart
git commit -m "refactor: move home hero into its own widget file"
```

---

### Task 4: Full-bleed hero with metadata and scrim

**Files:**
- Modify: `lib/widgets/home/hero_banner.dart` (`HeroSlide` build; `_HeroTitle`, `_HeroSynopsis`)
- Use: `lib/widgets/common/hero_meta_line.dart` for the meta line
- Test: `test/widgets/home/hero_banner_test.dart` (create)

**Interfaces:**
- Consumes: `HeroBanner` from Task 3; `ZplayType`, `ZplaySpacing`, `context.tokens`.
- Produces: no new API.

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('hero shows rating, year and genres on one meta line', (t) async {
  await t.pumpWidget(wrap(HeroBanner(items: [sampleItem], onPlay: (_) {}, onMoreInfo: (_) {})));
  expect(find.text('8.0'), findsOneWidget);
  expect(find.text('2024'), findsOneWidget);
  expect(find.text('Action'), findsOneWidget);
});

testWidgets('hero with no backdrop shows a gradient, not an image', (t) async {
  await t.pumpWidget(wrap(HeroBanner(items: [itemWithoutBackdrop], onPlay: (_) {}, onMoreInfo: (_) {})));
  expect(find.byType(Image), findsNothing);
});
```

`wrap`, `sampleItem` and `itemWithoutBackdrop` are test helpers the implementer creates in the same file.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/home/hero_banner_test.dart`
Expected: FAIL on the meta line and the backdrop fallback.

- [ ] **Step 3: Implement**

- Backdrop fills the full width; a left-to-right scrim (`surface` at high alpha to transparent) and a bottom scrim (`bg`) keep text legible.
- Meta line: rating, year, type, genres, using `HeroMetaLine`.
- Actions: one filled Play button (accent fill) and one outlined More info (`ZplayRadius.sm`).
- Synopsis clamps to three lines.
- Backdrop-less items use a vertical gradient on `ZplaySurfaces.surface`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/home/hero_banner_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/home/hero_banner.dart test/widgets/home/hero_banner_test.dart
git commit -m "feat: full-bleed hero with meta line and scrim"
```

---

### Task 5: Poster tile with precise metadata

**Files:**
- Modify: `lib/widgets/movie/movie_card.dart` (text block below artwork; `MovieCardSizing` unchanged in shape)
- Modify: `lib/widgets/common/card_poster_frame.dart` (bottom scrim, "Recently added" badge placement)
- Test: `test/widgets/movie/movie_card_meta_test.dart` (create)

**Interfaces:**
- Consumes: existing `CardBadges` and `FocusableCard`.
- Produces: no new public API. Text block is: title (one line, ellipsis), second line `★ rating · year · Movie|Show`.

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('card shows title, rating · year · type', (t) async {
  await t.pumpWidget(wrap(MovieCard(movie: sampleMovie)));
  expect(find.text('The Odyssey'), findsOneWidget);
  expect(find.text('8.0 · 2024 · Movie'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/movie/movie_card_meta_test.dart`
Expected: FAIL, meta line not found.

- [ ] **Step 3: Implement**

Single meta line with `ZplayType` small caption and `context.tokens` secondary text colour. Bottom scrim on artwork so any overlay badge stays readable. The "Recently added" badge becomes a small pill (`ZplayRadius.full`) using the accent only when it is the live state.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/movie/movie_card_meta_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/movie/movie_card.dart lib/widgets/common/card_poster_frame.dart test/widgets/movie/movie_card_meta_test.dart
git commit -m "feat: poster tiles show rating, year and type"
```

---

### Task 6: Ranked row ("Top 10")

**Files:**
- Create: `lib/widgets/movie/ranked_poster_card.dart`
- Modify: `lib/widgets/movie/movie_slider_section.dart` (use ranked card when the section is ranked)
- Test: `test/widgets/movie/ranked_poster_card_test.dart` (create)

**Interfaces:**
- Produces: `RankedPosterCard({required int rank, required MovieCardSizing sizing, required Widget child})`. Renders the rank numeral behind the poster's left edge, using `ZplayType` display size and `tokens.textPrimary`.

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('ranked card shows its number', (t) async {
  await t.pumpWidget(wrap(RankedPosterCard(rank: 7, sizing: sizing, child: const SizedBox())));
  expect(find.text('7'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/movie/ranked_poster_card_test.dart`
Expected: FAIL, file not found.

- [ ] **Step 3: Implement** the widget, then have the section use it when given a `ranked: true` flag from the data source. Do not add the flag to any section that is not a Top list.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/movie/ranked_poster_card_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/movie/ranked_poster_card.dart lib/widgets/movie/movie_slider_section.dart test/widgets/movie/ranked_poster_card_test.dart
git commit -m "feat: ranked poster row for top lists"
```

---

### Task 7: Rails and section headers

**Files:**
- Modify: `lib/widgets/common/section_header.dart` (title, optional "See all" chevron, token spacing)
- Modify: `lib/widgets/common/horizontal_edge_fade.dart` (edge fade on the rail ends)
- Test: `test/widgets/common/section_header_test.dart` (create)

**Interfaces:**
- Consumes: `ZplaySpacing`, `ZplayType`.
- Produces: `SectionHeader({required String title, VoidCallback? onSeeAll})`. Existing callers keep their current parameters; add `onSeeAll` as optional.

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('header shows title and see-all when provided', (t) async {
  await t.pumpWidget(wrap(SectionHeader(title: 'Trending', onSeeAll: () {})));
  expect(find.text('Trending'), findsOneWidget);
  expect(find.byIcon(Icons.chevron_right), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/common/section_header_test.dart`
Expected: FAIL, no chevron.

- [ ] **Step 3: Implement** the optional chevron and token-based spacing. Keep the existing signature working.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/common/section_header_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/common/section_header.dart lib/widgets/common/horizontal_edge_fade.dart test/widgets/common/section_header_test.dart
git commit -m "feat: section headers with see-all and edge fade"
```

---

### Task 8: Navigation placement by form factor

The rail stays on TV and tablet. On desktop and web, a top bar with Home / Movies / Shows / Anime replaces it, matching movy.sx. This is a placement change inside the existing shell, not a new destination model, so the five-slot shell and its back behaviour stay as they are.

**Files:**
- Modify: `lib/shell/shell_rail.dart` (add a `top` placement using the existing `navigationMode` detection)
- Modify: `lib/shell/app_shell.dart` (choose placement from `lib/services/layout/form_factor.dart`)
- Test: `test/shell/shell_placement_test.dart` (create)

**Interfaces:**
- Consumes: `FormFactor` classification (existing).
- Produces: no new public API; a private `_placementFor(FormFactor)` in `app_shell.dart`.

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('desktop width uses the top bar; TV keeps the rail', (t) async {
  await t.binding.setSurfaceSize(const Size(1440, 900));
  await t.pumpWidget(wrap(AppShell()));
  expect(find.byKey(const Key('shell-top-bar')), findsOneWidget);
  await t.binding.setSurfaceSize(const Size(1920, 1080));
  // TV input is decided by navigationMode, not width (see REDESIGN_DIRECTION.md)
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shell/shell_placement_test.dart`
Expected: FAIL, no key found.

- [ ] **Step 3: Implement** the `top` placement reusing the same destination list, and keep the rail for TV and tablet.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shell/shell_placement_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/shell test/shell/shell_placement_test.dart
git commit -m "feat: top navigation bar on desktop and web"
```

---

### Task 9: Responsive check and visual comparison

**Files:**
- Create: `test/widgets/responsive_home_test.dart`
- Create: `docs/shots/movy-style/` (screenshots, not committed unless the user asks)

- [ ] **Step 1: Write the test** that pumps Home at 320x640, 768x1024, 1440x900 and 1920x1080 and expects no exceptions (`tester.takeException()` is null).

- [ ] **Step 2: Run it**

Run: `flutter test test/widgets/responsive_home_test.dart`
Expected: PASS. Any `overflowed` error is a bug to fix in the widget that caused it, not in the test.

- [ ] **Step 3: Visual check**

Run the desktop app (`flutter run -d linux`) and capture Home at the widths above. Compare against movy.sx side by side: hero scrim contrast, tile corner radius, meta-line spacing, rail rhythm. Record the differences in the commit message of the final tweak.

- [ ] **Step 4: Commit**

```bash
git add test/widgets/responsive_home_test.dart
git commit -m "test: home renders without overflow across form factors"
```

---

## Out of scope

- Footer, legal links and version line from movy.sx (not part of an app shell).
- A light theme (charter lists it as possible later; this plan does not add it).
- Changing the content model or the Home Anime filter tab (charter phase 3 item, tracked separately).
- Re-creating movy.sx's exact colours or fonts. The reference is used for layout and feel only.

## Verification limits

- `flutter` is not on `PATH` in this environment and the vendored `flutter/` directory contains only `dart` and `cache`. Each task's test command needs a working Flutter SDK. If none is available, the implementer must say so and verify by reading the code, and the visual check in Task 9 must be done by the user.

## Execution notes (2026-11-09, `tzero86/UIRedesign`)

Implemented against `main` at `5907834` in the `PlayTorrioZero/UIRedesign` worktree. A full Flutter 3.47.4 SDK was found at `<main clone>/flutter/` (not on `PATH`), so every task was verified with `flutter analyze` and `flutter test` after all; the verification-limits note above is obsolete.

Final state: `flutter analyze` clean; full `flutter test` **1388 passed, 14 skipped, 0 failed**.

| task | outcome |
|:--|:--|
| 1 | `app_theme_service.dart` was already accent-only. Added the regression test (`test/theme/palette_surfaces_test.dart`); production code unchanged. |
| 2 | Both halves landed. `LiquidRevealRoute` became a fade-through and was then renamed `FadeThroughRoute` with `tapPosition` removed (18 call sites). The splash moved from a process `static` to `home_intro_seen` in `SharedPreferences`, is written when shown, and a tap or the `Skip intro` semantics action dismisses it. |
| 3 | Hero family extracted to `lib/widgets/home/hero_banner.dart` (`HeroBanner`, `HeroSlide`, `HeroArtwork` public; private state stays private). Page-chrome helpers moved to `lib/pages/home/home_chrome_metrics.dart` to avoid a page/widget import cycle. `home_page.dart` 4185 → 1692 lines. |
| 4 | The full-bleed backdrop, scrims, actions, badge and title slot already existed, so only the metadata line changed: the private `_HeroMetaLine` was deleted in favour of the shared `HeroMetaLine` (three-genre cap now at the call site). The plan's three-line synopsis and gradient fallback were **not** adopted: the committed design uses two lines and a poster-last fallback, and `hero_never_blank_test.dart` pins the latter. |
| 5 | Poster caption is now one `Text`: `8.0 · 2024 · Movie`. `card_poster_frame.dart` does not exist on this branch and was not created; `_PosterFrame` already paints the bottom vignette, so no scrim was added. `_formatRating` was corrected to keep a supplied decimal (`8.0` stayed `8` before). |
| 6 | **Not implemented.** `MovieSection` and `AddonCatalog` carry no rank or "Top list" signal; wiring `ranked: true` anywhere would invent a data source. The widget was not added with no truthful caller. |
| 7 | **Already satisfied** by committed code: `SectionHeader` renders See All as a focusable control with a chevron and its own test; `HorizontalEdgeFade` is used across detail/search rails. No change. |
| 8 | **Already satisfied, premise stale.** `ShellRail` uses the bottom bar for `compact` and the top bar for every other form factor; the plan's "rail stays on TV and tablet" contradicts the shipped chrome and its tests. No change. |
| 9 | Responsive test added (`test/widgets/responsive_home_test.dart`) for 320×640, 768×1024, 1440×900 and 1920×1080: no exceptions and no overflow on any. The side-by-side visual comparison against movy.sx still needs a display (`flutter run -d linux`) and is left to the user. |

Commits: `74b4fcd`, `cbc98e8`, `8778144`, `f545f73`, `964f63a` (plan document itself: `b47d837`).
