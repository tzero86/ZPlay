# ZPlay — Feature Brief for UI/UX Prototype Design

**Purpose:** you are designing a prototype UI for ZPlay, a multiplatform media-streaming
app. Everything below was read from the shipped Flutter source, not from marketing copy.
Design against this feature set, not a generic streaming app.

**Deliverable:** prototype screens covering the surfaces marked ★ below, at **960×540 dp
(10-foot TV)** and **390×844 dp (phone)**. Show focus states — they are the whole point.

---

## 1. Non-negotiable constraints

| | |
|---|---|
| **Primary target** | Android TV. 960×540 logical dp at DPR 2 (physical 1920×1080). ~2 GB RAM, low-bit-depth panel. |
| **Also targets** | Android phone/tablet, Windows, macOS. |
| **Primary input** | D-pad remote. **Secondary:** mouse/pointer, touch, keyboard. |
| **Breakpoints** | <600 compact · ≥600 medium · ≥1024 expanded. Form factor is read from the platform's UI-mode, **not** from `MediaQuery`. |
| **Font** | Poppins (400/500/600/700 only — nothing else may be synthesised). |

### Why this matters more than anything else on the page

A tester put it plainly: **"Doesn't feel like this has been designed with TV remote
navigation in mind."** That is the single most important thing to fix.

Non-negotiable TV rules, each one a bug we shipped and fixed:

1. **Every actionable element must be D-pad reachable.** A `GestureDetector`/`InkWell`
   is invisible to a remote. Anything pointer-only is a shipped bug.
2. **One focus ring per element, and never a second edge.** The focus ring is a crisp
   2 dp accent border. Do not add a glow or shadow around it — a soft inner edge reads
   as a phantom second border.
3. **Selecting must never resize or shift the element.** An element that gains or loses
   a border, padding, or scale when selected makes its icon visibly jump. Reserve the
   space permanently.
4. **No element smaller than ~48 dp tall on TV.** The rail is 64 dp wide with 48 dp rows
   and 24 dp glyphs, matched against the reference app on the same panel.
5. **Text must not autofocus on TV.** A focused text field installs a directional action
   that traps arrow keys.
6. **Nothing interactive may be a 7 dp target.** We shipped carousel dots as focusable
   7 dp elements and they swallowed every arrow key aimed at real content.

### Density rules that exist because the canvas is small

At 960×540 dp a hero, a filter row, and a card row cannot all fit. The shipped rules:

- Hero on TV = **296 dp**. A filter row = **28–44 dp**. One rail = **~260 dp poster + 47 dp text**.
- Multi-row chrome collapses into **one** control row on TV (wordmark, page title and
  filter rows merge).
- Only one focal point per screen. Hero artwork and a full poster row at the same scale
  are two focal points and read as a mess.
- **A filter must never resize a card.** Give the content its natural size and let the
  page scroll instead.

---

## 2. Product shape

ZPlay is an **addon-driven** media app. The user imports Stremio-style addon manifests;
each supplies catalogs (browsable lists) and, separately, stream providers. The app also
reads metadata and recommendations from external services.

```
Addons (user-imported manifests)
  ├─ catalog resource  → browsable lists of titles
  └─ stream resource   → playable sources for a title

External services (credential-gated, each optional)
  Trakt · Simkl · TMDb · AniList · CloudStream extensions · Debrid · Discord RPC
```

**Design consequence:** every content surface is a list of *rails* or a *grid* fed by
whatever the user's addons provide. There is no fixed catalogue. Empty states, loading
states and partial-failure states are first-class, not edge cases.

---

## 3. Navigation model ★

A persistent shell with **5 destinations**, swapped not pushed. All five stay mounted in
an `IndexedStack`, so **each preserves its own scroll, filters and loaded pages.**

| Slot | Contents |
|---|---|
| **Home** | Personalised landing: hero + content rails. |
| **Browse** | 8 vertical switcher (below). |
| **Search** | Cross-source search. |
| **Library** | My List + Downloads. |
| **Settings** | 24 pages (below). |

**Persistent chrome**

- **Left rail** (medium/expanded/TV): 64 dp wide on TV, 88 dp on desktop, **48 dp rows,
  24 dp glyphs, icon-only, no text labels** anywhere. Order: Home · Browse · Search ·
  Library — then a hairline divider, then Fullscreen and Settings pinned to the foot.
  A 24 dp brand mark heads it on TV. **On phones the rail becomes a 64 dp bottom bar.**
- **Now-playing bar**: persistent transport strip at the foot. Collapses to nothing when
  idle. 40 dp artwork (56 dp on TV), title + subtitle + tabular position/remaining, and
  prev / play-pause / next at 44 dp (56 dp TV). Disabled transport buttons are **not**
  focusable so D-pad never lands on them. Tapping the bar opens the full player.
  Bridges video, music and audiobook playback through one service.

**Back policy** — three-way, deliberately:

1. A pushed route (details, player, a vertical page) pops normally.
2. At a shell slot that is not Home → go Home.
3. At Home → **press again to exit**, with a visible "press back again" affordance.

**Keyboard (desktop only)**

`Ctrl/Cmd+K` search · `Ctrl/Cmd+,` settings · `F11` fullscreen · `Alt+1…5` slots ·
`?` shortcuts sheet.

---

## 4. Home ★

A single vertical scroll. Chrome is a `Positioned` overlay; the app bar's height is charged
as the scroll view's **top padding** so content can always scroll back above it.

**Hero carousel** — one slide at a time.

- **Backdrop artwork (16:9)** from TMDb — never a stretched poster. A poster is 2:3;
  stretching it crops the title out of the picture.
- **Clearlogo** overlaid when available, else the title text.
- **Directional scrim**: strong behind the text block on the left, clearing to nothing on
  the right so the artwork is what the eye lands on. The right ~18% is left clean.
- **Actions**: `Watch Now` (primary, autofocus on load) · `Details` · `Trailer`.
- **Trailer**: opens the in-app trailer modal — a medium 16:9 stage around the YouTube embed
  of the key TMDb returned, playing itself. There is still no stream-extraction in this
  codebase (`lib/widgets/common/trailer_modal.dart`); where no webview exists, the control
  hands the key to YouTube in the browser, as it always did.
- **Auto-rotate** on by default, 6 s; dots indicate position. **Dots are decoration on TV
  and are not focusable.** Users reach a slide by waiting, not by hunting a dot.
- **Hero styles** (a user setting): *Immersive Cinematic* · *Compact Spotlight* ·
  *Minimalist Header*.

**Filter pills** — `All · Movies · Series · Anime`, merged into the app-bar row on TV.

**Content rails** — horizontal scrollers, each with a header (title · count · subtitle)
and an optional **See All**. Kinds that can appear:

- Continue Watching (with resume progress)
- "Because you're watching…" recommendations (placement is a setting: top or bottom)
- Trakt: **Trending This Week** · **Popular Now** · **Coming Soon**
- Simkl recommendations
- Curated collections (Franchises / Memory Lane)
- Airing calendar
- Anime rows when the Anime tab is active
- Addon catalog rails

**Rail behaviours:** edge fades on the horizontal overflow · first six cards stagger in ·
desktop-only hover arrows.

---

## 5. Browse ★

A vertical switcher over 8 destinations, all kept mounted:

`Movies & TV · Collections · Live TV · Anime · Manga · Books · Audiobooks · Music`

### Movies & TV (Discover) ★

```
[ vertical pills: Movies & TV | Collections | Live TV | Anime | Manga | Books | Audiobooks | Music ]
[ Movie ▾ ]  [ Popular ]  [ New (genre) ]  [ Featured ]          ← catalog chips
[ genre: All ]                                                   ← required-filter chip
┌────────┬────────┬────────┬────────┐
│ card   │ card   │ card   │ card   │   ← grid, 4 columns on TV
└────────┴────────┴────────┴────────┘
```

- **Type selector** Movie / Series.
- **Catalog chips** switch the source list. The active one shows its name.
- **A required filter is named, not hidden** — a chip reading "New · genre" tells you the
  gate exists *before* you press it. An unnamed "Custom" chip hid the cost until selection.
- **In-catalog search field**, merged into the same control row on TV.
- **Infinite scroll** with a load-more spinner. Show loading / empty / error / no-results distinctly.

**Card anatomy ★** — the most-repeated element in the app:

```
┌──────────────┐   ← 2:3 poster, natural size, never squeezed
│  [SERIES]  ★8.4│   ← type badge (focused only) + rating badge (a setting)
│              │
└──────────────┘
Title                     ← 1 line, ellipsis
2024 · Movie              ← year · type
```

Hover/focus lifts the card slightly and brightens the poster. The type badge appears only
while focused — the resting card carries poster, title and year only.

### Collections

Curated franchises and eras, shown as **3-poster mosaics**, grouped. Each opens a grid page
with its own header and subtitle.

### Live TV

IPTV/M3U subscription. Channel list + EPG guide; playback goes through its own player.

### Anime / Manga / Books / Audiobooks / Music

Each is a bespoke surface, not a template:

- **Anime** — AniList-backed. Rails: Trending, Popular This Season, Top Rated, Upcoming,
  by genre. Hero carousel + grids + a modal details/episode sheet.
- **Manga** — reader with page modes, per-title atmosphere settings.
- **Books** — reader with typography/zoom/customisation controls.
- **Audiobooks** — library, chapter navigation, sleep timer, speed.
- **Music** — library, artists, albums, playlists; persistent mini-player.

---

## 6. Search ★

Rails, not a grid. Three legs run in parallel and **fail independently**:

1. **Addons** — every enabled catalog with a search capability.
2. **CloudStream extensions** — streaming providers.
3. **IMDb suggestions** (via the metadata service).

- Debounced field; detects magnet links and direct URLs and routes them to playback.
- **Cinemeta results are pinned to the top** as the metadata spine.
- A **failure ledger**: if one source is dead the others still render, and the dead source
  is named. A source error must never present as "no results".
- Empty state offers discovery rails rather than a blank page.

---

## 7. Details ★

```
┌────────────────────────────────────────┐
│  full-bleed backdrop + 3 gradient scrims │
│                                        │
│  [clearlogo or title, max 380×130]     │
│  2024 · 2h 16m · ★7.8 · Drama, Action  │
│  Synopsis, 3 lines … [Read more]       │
│  [ Play ]  [ Library ]                  │
│  Cast ●●●●●●                            │
│  Season selector ──●───                │
│  Episodes ▭ ▭ ▭ ▭ ▭ ▭                   │
│  Related ▭ ▭ ▭    Similar ▭ ▭ ▭         │
└────────────────────────────────────────┘
```

- **Play** adapts to the title: *Play Movie* / *Play Episodes* / *Play First Movie*.
- **Library** is a toggle; its label reflects state.
- Cast avatars navigate to a search for that person.
- On TV the hero art is bounded so **Play never falls below the fold**.

---

## 8. Playback ★

Flow: **Details → Watch (source selection) → Player.**

**Watch screen** — pick a source; filter by seeder, size, addon, audio.

**Player**

- **Dual engine**: mpv default, Media3 (ExoPlayer) for mainstream HTTP/HLS/DASH and 4K.
  Mainstream adaptive video and 4K go to Media3; torrents, live and Anime4K go to mpv.
- **Top bar**: back, title + quality pill, episode label, and labelled badges for
  Episodes / Sources, plus copy-URL, download, and lock (mobile).
- **Transport**: play-pause, −10 s, +10 s, volume/mute, prev/next episode, and
  Episodes · Aspect · Speed · Audio · Subtitles · Sub-sync · Fullscreen.
- **Seek bar** is its own focus target; left/right steps ±10 s. Shows buffered position and
  **intro/credit skip segments** highlighted.
- **Remote keys on TV**: arrows are *never* volume or seek — they are left to focus
  traversal. Centre raises the HUD. `M` mute · `Space/K` play-pause · `F` fullscreen ·
  `C` cycle fit · `Esc` exit fullscreen. Hardware volume rockers always work.
- Fullscreen, aspect-ratio cycling, playback speed, audio track and subtitle track.

---

## 9. Library ★

Two tabs, both state-preserving:

- **My List** — saved titles. Grid with a full-bleed poster card and overlaid title.
- **Downloads** — what can be downloaded, its states, and management.

---

## 10. Calendar

"Airing today/this week" rail from addon metadata. Toggleable; appears as a rail header action.

---

## 11. Settings ★ (24 pages)

**Root**

| Section | Rows |
|---|---|
| Playback | Video & Upscaling · Built-in P2P Torrent Source |
| Content | Addons · Built-in Providers · Debrid & Cloud Streaming |
| Services | Trakt.tv Sync · Simkl Sync · TMDb API Key · Service API Keys · Discord Rich Presence |
| Interface | Appearance & Interface · TV Airing Calendar · AI Recommendation Quiz · Adult Content |
| System | Backup & Restore · App Updates · About |

**Appearance & Interface** → Custom Background & Wallpaper · Liquid Glass Setup · Home Page
UI & Themes · Live TV & Sports UI · Manga UI & Reader Atmosphere · Audiobook UI & Player
Studio · Music UI & Player Studio.

**Home Page UI & Themes** — the Home controls a designer most needs to see:

- **Hero style** — Immersive Cinematic / Compact Spotlight / Minimalist Header
- **Hero auto-rotate** + interval
- **Card density** — Compact (dense) / Standard / Cinematic (large posters)
- **Show rating badges**
- **Ambient glow**
- **Recommendation placement** — top of page or bottom
- Per-section toggles: Spotlight, Similar, Watching-Similar, Trakt recommendations,
  Simkl recommendations, Calendar, AI Quiz
- **Theme palette** — 11 presets

---

## 12. Design system as it stands

- **Spacing** 4 pt scale: 2 · 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 · 64
- **Radii** 6 · 10 · 14 · 20 · 28 · full
- **Palettes** — 11 presets. The default is **Ember Crimson** (warm red, chroma ~0.86),
  chosen over the previous teal because it reads as film rather than as software:
  `Signal Teal` · `Amethyst Violet` · `Cyberpunk Neon` · `Emerald Aurora` ·
  `Sunset Crimson` · `Midnight Sapphire` · `Golden Amber` · `Vampire Red` ·
  `Pink Barbie` · **`Ember Crimson`** (default) · **`Studio Bone`** (chroma 0.15, for cheap
  low-bit-depth panels).
- **Contrast is enforced**: every preset's button label must clear **WCAG AA 4.5:1 against
  all three of its own states** (base, hover, pressed). One existing preset fails at
  3.79:1 — flagged, not shipped as default.
- **Type**: Poppins, four weights. Title / subtitle / body / caption ramp.
- **Surfaces** come from a single palette-independent ramp; a palette changes accent only.

---

## 13. What testers have said about the current design ★

Real feedback, so the prototype answers it rather than repeating it:

1. **"Doesn't feel like this has been designed with TV remote navigation in mind."**
   → The dominant issue. Design the focus model first, then lay out around it.
2. **Focus is erratic; the highlight gets lost.** → One focusable node covering the whole
   page silently swallowed every arrow key. *Never let a full-screen container be focusable.*
3. **"Why is Rocky in the new hot stuff?"** → A "newest" catalog that actually means
   *newly added to the catalogue*. **Label rails by what they truly contain.**
4. **Couldn't find the latest/newest.** → Surface recency explicitly and early.
5. **"Do it like Netflix — the carousel shows the latest, and they can even be trailers."**
6. **Disliked the colour palette.** → Resolved with Ember Crimson.
7. **Liked the breadth of content.** → Variety is a strength; keep all 8 verticals.

---

## 14. Known inconsistencies to resolve in the prototype

- Two focus-target conventions existed side by side (`Image`-based mark vs drawn mark).
  One focus ring per element, everywhere.
- Three different chrome heights across Home / Discover / Search for the same job.
- A carousel arrow pair exists but prev/next-episode in the player transport is dormant.
- Player has a screenshot icon that is never wired to an action.
- Home's rail budget and the hero band were historically computed from different
  assumptions; one number now owns each.

---

## 15. Prototype checklist

Cover at minimum, each at **TV 960×540** and **phone 390×844**, with focus states drawn:

- [ ] Shell: rail + now-playing bar, both idle and active
- [ ] Home: hero (backdrop, logo, scrim, three actions, trailer badge), filter pills,
      ≥3 rails, and its loading / empty / error states
- [ ] Browse: vertical switcher, catalog chips, genre chip, card grid, load-more
- [ ] Card: resting, hovered, focused, selected
- [ ] Search: results, and a **partial-failure** state naming a dead source
- [ ] Details: full page with episode list
- [ ] Watch (source picker) → Player with HUD raised
- [ ] Library: My List + Downloads
- [ ] One non-video vertical in depth (Anime, Manga, Books, Audiobooks or Music)
- [ ] Settings root + Home Page UI & Themes
- [ ] A **focus-path walkthrough**: from cold start, show exactly where focus lands and
      where each arrow key takes it on every screen above

**The walkthrough is the deliverable that matters most.** A prototype that looks right
but navigates wrong has not solved the problem.