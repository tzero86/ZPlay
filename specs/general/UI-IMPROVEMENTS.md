# UI/UX Improvements

## Summary

Review of the shell, home rails and content cards after the 1.6.x navigation
work. The navigation model is sound: one `FocusableCard` per destination, one
autofocus owner per bar, explicit focus rings, and a dedicated regression suite.
The remaining problems are visual and informational rather than structural:
pointer users get anonymous thumbnails, tiles are softer than their artwork, and
the menu says the same thing twice.

This pass changes only the shape and content of existing controls. It does not
add, remove or reorder focus nodes, change autofocus, or introduce a second
interaction model.

## High Priority

### Pointer rails carry no title

**Current state.** Home passes `CardArtwork.landscape` to every
`MovieSliderSection` (`lib/pages/home/home_page.dart:1076`). Landscape cards are
artwork only (`CardArtwork.showsTextBlock == false`), so a desktop or phone rail
is a row of pictures with a section heading and no way to tell one title from
another without moving focus or opening it.

**Problem.** The landscape choice exists for a 540 dp television, where a seven
wide row of 2:3 posters would be unreadable and too tall. Applying it to a
pointer device removes the caption for no benefit; the window is tall enough for
posters.

**Recommendation.** Keep landscape on `FormFactor.television` and use posters
everywhere else. Posters already carry the title, year, type and now rating.

**Impact.** A desktop user can identify a title before interacting with it.

### Tile metadata stops at year and type

**Current state.** The caption row under a poster prints the year and the type.
The rating is only in the expanded panel, which requires focus or a click.

**Problem.** A tile with `2024 · Movie` says very little; the rating is already in
the catalog response (`Movie.imdbRating`), so it costs nothing to show.

**Recommendation.** Append `★ 8.1` to the caption row, with the same separator
used between year and type. Keep the value tabular so it does not jitter.

**Impact.** Rating, year and type are scannable without opening anything.

### Tiles are too rounded for their size

**Current state.** Cards use `ZplayRadius.mdAll` (14 dp) on a 190–205 dp poster.
The focus ring, expanded panel and overlay copy repeat it.

**Problem.** At card scale a 14 dp corner reads as a soft pill; dozens of them
in a rail soften the whole page, and the artwork's own rectangle is the strongest
shape on screen.

**Recommendation.** Add a dedicated `ZplayRadius.card` (10 dp) for content tiles
and their expanded panel. Leave sheets, dialogs, controls and pills on the
existing scale.

**Impact.** Crisper tiles without a global radius change that would disturb
unrelated surfaces.

### The top menu says every destination twice

**Current state.** Every labelled top-bar row draws an icon and its name
(`_RailRow`, `lib/shell/shell_rail.dart`). Selection is already an accent
underline, and the focus ring is a pill.

**Problem.** At the bar's height the glyph is small and decorative, while the
name is the actual target. Icon plus label plus underline is three marks for one
destination, and the pill ring adds a fourth rounded shape.

**Recommendation.** Draw the name only in the top bar, keep the glyph only in the
compact bottom bar, and use a crisp `ZplayRadius.xs` focus ring. The underline
remains the selected mark; tooltips and semantics keep the name available to
pointer and screen-reader users.

**Impact.** A quieter bar with the same hit targets, order and focus behavior.

### Artwork arrives at whatever size the upstream addon chose

**Current state.** `ArtQuality` rewrote metahub `small`/`medium` stills to
`large`, but a TMDb `w500` poster stayed `w500`. Card decodes were fixed at 3x
logical width, which is generous at DPR 2 and soft at DPR 3–4.

**Problem.** A poster drawn at 410 physical pixels from a 500 px source, then
grown 1.35x on focus, is visibly soft; the focused copy is the one a viewer
studies.

**Recommendation.** Upgrade TMDb posters to `w780` and backdrops to `w1280`
(`original` stays), and decode at `DPR × 1.5` floored at the old 3x, capped at
2048 px. Foreign hosts stay untouched.

**Impact.** The same artwork is sharp at 1x, 2x and 3x without downloading a 4K
still for a 200 dp tile.

## Medium Priority

### Hover reveals nothing

**Current state.** `CardFocusExpansion` is driven by focus, not hover. On a
pointer device, moving the mouse over a card does not reveal the panel.

**Problem.** Hover is the pointer equivalent of "tell me about this"; requiring a
click adds a step for every title.

**Resolution.** The poster caption now carries the useful catalog data, and a
deliberate 1.1 s dwell starts a muted, chrome-free trailer in the artwork
rectangle on platforms with a WebView. `TrailerPreviewGate` cancels on the first
frame the pointer leaves, never mounts on a television or touch surface, and is
wrapped in `IgnorePointer` so the card's click still opens the title. The pop
panel stays focus-driven, so hover cannot paint app chrome over the page.

### Caption at large text scales

**Current state.** The caption row uses a `LayoutBuilder` so the type text is
flexible only when the card has bounded width; a 200% scale test covers it.

**Problem.** Adding the rating increases the fixed-width part of the row. The
type remains the flexible part, so the rating stays legible while the type
ellipsises; verify this on a 220 dp card at 200%.

**Recommendation.** Keep the existing bounded/unbounded split and extend the
text-scale test to assert the rating is present and no overflow is reported.

## Positive Observations

- One focus model: every card is a `FocusableCard` with an explicit focus ring;
  the shell owns a single autofocus row.
- The underline is anchored to the name's own box, so it cannot resize the row
  or move focus.
- Reduced motion collapses the underline's duration rather than removing state.
- Cards carry one semantics node with a title and an "Open details" hint.
- The television still gets the landscape shape, which is the right call for ten
  feet and is now documented as such.

## Navigation Guardrails

- Do not wrap `FocusableCard` in another focusable widget; the card's own
  `FocusableActionDetector` is the single node.
- Keep `ShellSlot.values` order and the Live TV insertion after Browse.
- Keep `autofocus` on exactly one marked row.
- Run `test/shell_rail_tv_test.dart`, `test/tv_dpad_focus_regression_test.dart`,
  `test/tv_shell_focus_test.dart`, `test/widgets/movie_card_focus_expansion_test.dart`
  and `test/l10n/localization_test.dart` after any card or bar change.
