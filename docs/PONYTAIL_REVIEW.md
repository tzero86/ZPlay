# Ponytail review — over-engineering and deletable weight

Date: 2026-11-04 · Scope: `lib/` (428 files, 191k lines) · Version at review: 1.6.18+3055

Scope of this document: over-engineering and complexity only. Correctness bugs,
security holes and performance are out of scope here. Findings were produced by
four domain passes (player, IPTV, catalog/services, UI/shell) plus a repo-wide
dead-file and dependency scan, and each one was re-checked against source.
Three candidate findings were rejected on verification:

- `PlayerSettings.subPos` — **not** dead: set from `lib/widgets/player/player_sub_style_modal.dart:814`.
- `VideoEngine.setSubtitlesVisible` — driven by `test/services/player/exo_player_bridge_test.dart`.
- The space/K `Shortcuts` branch in `player_screen.dart` is *shadowed* by
  `handlePlayerRemoteKey`, not strictly unreachable — cutting it is still safe.

## Where it hurts, ranked

| # | Pain point | Evidence | Cost |
|---|---|---|---|
| 1 | Giant page classes: 7 pages over 2,800 lines, 40k lines in 13 files | `music_page` 5,631 · `player_screen` 5,577 · `watch_screen` 4,300 · `home_page` 4,185 | every change is a 5k-line read |
| 2 | Copy-paste within one file, not between files | 4 filter-menu triplets (~1,400 L) in `watch_screen`; 5 HUD state machines in `player_screen`; 4 duration formatters app-wide | features get fixed in 1 of N copies |
| 3 | Dead-but-compiled code | 5 orphan files (973 L), dead IPTV browser state (~400 L), `MediaKitEngine` unreachable (260 L), `anime_details_modal` prod-dead (959 L) | pure noise on every read |
| 4 | Provider/scraper boilerplate ×43–54 | 54 `addonName: 'ZPlayHTTP'` literals, 53 copies of one Chrome/131 UA, 46 identical `name` overrides | bloat from `sites/` |
| 5 | Duplicate widget implementations with divergent behaviour | 3 `_PosterFrame`s, 2 waveform seekbars (149/408 lines verbatim), 2 physics buttons (0.70 similar), 4 rail implementations, 18 settings scaffolds | drift: one copy gets the focus ring, the others don't |
| 6 | Two editors for the same settings | IPTV "Customize Portal/Browser" dialogs repeat `live_tv_settings_page`'s notifiers | two sources of truth |

## Batch 1 — zero-risk deletions (no behaviour change) — LANDED

Applied and verified on 2026-11-04: 10 files deleted, 45 paths touched,
+87 / −3,128 lines. `flutter analyze` clean, 1,362 tests pass (14 skipped),
`flutter build apk --debug` succeeds.

Deviations from the list below, recorded so nobody re-litigates them:

- Two extra findings that the cuts orphaned went with them:
  `TraktService.fetchNextEpisode`, `fetchEpisodePlaybackProgress`,
  `fetchEpisodePlaybackProgressOrNull` and `debugParseEpisodePlaybackProgress`
  (134 lines) — only ever added in 37e322a and never called.
- `PlayerSettings.fallbackToSoftware` had two live IPTV callers
  (`iptv_player_page.dart:188`, `:427`); both now call `applyNoVideoRecovery`
  with the same policy outcome.
- `MissingPoster`: the deleted local copy in `manga_card.dart` drew
  `broken_image_rounded` at 40 dp; the shared widget draws `movie_rounded` at
  46 dp, so manga cards now match Movie/Anime fallbacks. One visible change.
- `IptvDeadUrlStore.forget` and `IptvAliveStore.clear` were **not** deleted:
  tests call them even though production never does.

Everything below was verified to have zero production callers by grep.

### Orphan files

```
lib/widgets/anime/anime_hero_spotlight.dart        335 L  delete:
lib/services/simkl/simkl_menu_helpers.dart         321 L  delete:
lib/widgets/player/player_sub_style_bar.dart       165 L  delete:
lib/services/trakt/trakt_episode_model.dart        117 L  delete:
lib/services/anime/anime_stream_service.dart        35 L  delete:
```

### Unused dependencies

- `cupertino_icons` — 0 imports.
- `dart_mobi`, `fb2_parse` — 0 imports. `BookResult.isMobi`/`isFb2`
  (`lib/models/book/book_result.dart:90-91`) recognise the filetypes but no
  reader exists, so the UI advertises formats the app cannot open.
- `media_kit_libs_windows_video` is `^1.0.11` in `dependencies` *and*
  git-pinned in `dependency_overrides` — keep the override only.

### Player engine

```
engine/media_kit_engine.dart:1-260     delete: MediaKitEngine — built only by EngineSelector.create, which has zero callers (player_screen.dart:446 uses .choose()).
engine/engine_selector.dart:65-70      delete: create().
engine/video_engine.dart:58-84,215     delete: EngineCapabilities + capabilities getter — referenced only in a comment; drop the comment mention at player_screen.dart:2648.
video_engine.dart:15                   delete: doc bullet describing MediaKitEngine.
```

### IPTV controller dead state

```
iptv_controller.dart:72-122            delete: browsing/alive/EPG block (activePortal, activeSection, activeSeries, isLoading, categories, browserAllStreams, episodes, error, browserSelectedCategoryId, browserSearch, liveOnly, aliveStreamIds, isVerifyingAlive, alive*, _epgCache/epgFor/_hitEpgCache/epgForHit) — IptvPortalBrowserPage keeps its own copies.
iptv_controller.dart:1083-1195         delete: openSection, selectBrowserCategory, setBrowserSearch, _aliveSnapshotFresh, startAliveCheck, stopAliveCheck.
iptv_controller.dart:14-23,31,1196-1229 delete: IptvView, view, back() — navigation is Navigator; nothing reads view.
iptv_controller.dart:360-380,52-53     delete: runVerification(), manualVerified.
iptv_controller.dart:1231-1240,1265-1269 delete: getAllXtremeChannels/getAllM3uChannels — duplicates of the group getters.
iptv_controller.dart:687-689,765,860-1016 delete: _channelCancel plus its 10 guards; stopChannelSearch already bumps _channelScanToken.
```

### Continuity selection chain

```
lib/models/search/advanced_search_selection.dart:1-30   delete: only produced by the methods below; nothing reads the instance.
trakt_continue_watching_service.dart:98-152             delete: resolveSelection, selectionForItem.
simkl_continue_watching_service.dart:123-137            delete: selectionForItem.
```

### Anime details modal

```
lib/pages/anime/anime_details_modal.dart:22-959  delete: 959 lines; only test/widgets/anime_details_modal_test.dart instantiates it — every route pushes AnimeDetailsPage. Delete the test with it.
```

### Accessibility helpers

```
lib/utils/a11y.dart:21-28,38-88  delete: openDetailsHint, resumeLabel, announce, _hasBinding — only test/widgets/a11y_semantics_test.dart references them.
```

## Batch 1c — mechanical consolidation — LANDED

Applied 2026-11-04 on top of Batch 1: +246 / −522 lines. `flutter analyze` clean,
1,362 tests pass, APK builds. Verified by a throwaway widget test that the
appearance page's rows are now `FocusableCard`s (they were `InkWell`s, i.e.
unreachable from a remote).

```
player_settings.dart:1685-1895   shrink: 13 subtitle setters collapsed into one _persist<T>(notifier,key,raw,{write,coerce,player,notify}). Signatures, clamps and defaults unchanged.
player_settings.dart:1846-1862   shrink: 17 prefs.remove calls → loop over const List<String> _subtitleKeys.
widgets/player/player_speed_menu.dart:22-24,124-152  delete: SLEEP TIMER section and _selectedSleepMinutes — no timer was ever armed. Widget is now stateless. VISIBLE CHANGE.
pages/settings/settings_page.dart:1300  shrink: _SettingsNavRow moved to widgets/settings/settings_nav_row.dart as SettingsNavRow (public, focus ring intact).
pages/settings/settings_page.dart:766   shrink: _buildSection layout extracted to widgets/settings/settings_section.dart; l10n resolution and keys stay in the page.
pages/settings/appearance_settings_page.dart:305-407  delete: _buildGroup/_buildRow duplicates → SettingsSection + SettingsNavRow. BEHAVIOUR CHANGE (fix): these rows are focusable now, so a remote can enter Appearance settings.
utils/navigation/route_transitions.dart:8-24  delete: materialRoute (one call site) — inlined MaterialPageRoute. VISIBLE CHANGE: the multinutz portal-browser push uses the platform transition instead of the custom fade.
pages/player/watch_screen.dart:1595-1628,3254-3272  delete: _buildShimmerList/_buildShimmerCard/_buildEmptyState forwarders, inlined as const at their three call sites.
```

Rejected on verification: `exoPlayerAvailable`
(`player_screen.dart:5572`) is a deliberate seam for testing the platform
gating policy on a desktop host without a device — five cases in
`test/services/player/player_engine_wiring_test.dart` depend on it. It stays.

## Batch 2 — player stack (`net: -2,350` when the whole domain lands)

```
watch_screen.dart:1630-3252: shrink: four copy-pasted filter-menu triplets (dropdown/glass/sheet/row) for seeders, size, addon, audio. One _FilterMenu({label,icon,color,options,value,onChanged}) + one _showFilterMenu().
watch_screen.dart:600-690: shrink: three switch-over-string label getters. Const maps, 3 lines each.
watch_screen.dart:1595-1628,3254-3272: delete: _buildShimmerList/_buildShimmerCard/_buildEmptyState forwarding to one const widget each.
player_screen.dart:5050-5184: delete: _buildBrightnessHud is _buildVolumeHud with two values swapped. One _GaugeHud(icon,label,fraction,accent).
player_screen.dart:5428-5470: delete: _buildAspectHud is _buildAudioHud with a swapped icon. One _ToastHud(icon,text,accent).
player_screen.dart:730-886, 2929-3002, 3593-3601, 5355-5363: shrink: five HUDs each own bool+String+Timer+the same 1300ms cancel block. One _TransientHud({Duration life}).
player_screen.dart:3741-3782: delete: the space/K Shortcuts branch — handlePlayerRemoteKey (player_remote_keys.dart:100-102) answers both first. Keep escape + _PlayerDismissIntent.
player_screen.dart:4538-4730: shrink: four identical Positioned>KeyedSubtree>menu(onClose) popover wrappers. One _popover(Widget).
player_screen.dart:373,377: delete: autoResyncOnStall/hardwareAudioClock are ValueNotifiers hard-coded true (player_settings.dart:467-474) gating their own unconditional write.
player_screen.dart:5574-5577: yagni: exoPlayerAvailable exists only to be asserted in one test.
player_settings.dart:1689-1895: shrink: fifteen subtitle setters, same nine lines each. One _set(ValueNotifier,key,value).
player_settings.dart:1895-1911: shrink: eighteen prefs.remove calls. Loop over one key list.
player_settings.dart:1307-1334: delete: fallbackToSoftware re-implements applyNoVideoRecovery (1252-1296).
player_settings.dart:1680-1683: delete: applyToController, no-op stub, zero callers.
player_settings.dart:506-536: shrink: 31 lines of doc above 2 lines of code.
widgets/player/player_subtitle_menu.dart:387-824: shrink: compact and desktop layouts render the same Off/Embedded/language list twice. One _languageItem().
widgets/player/player_speed_menu.dart:22-24,124-152: delete: sleep-timer chips write _selectedSleepMinutes that nothing reads — no timer exists. Back to StatelessWidget.
widgets/player/player_glass.dart:30-95: yagni: 11 PlayerTheme members are bare forwards to AppThemeService.currentTokens; call sites already hold tokens.
widgets/player/player_seek_bar.dart:12-16 + player_transport.dart:18-22: yagni: position/buffered fields and positionListenable/bufferedListenable are two APIs for the same values; only the listenables are used.
widgets/player/player_aspect_menu.dart:60-125 + player_speed_menu.dart:44-112: shrink: identical header row and check-marked option row. _MenuHeader/_MenuOption in player_glass.dart.
widgets/player/player_top_bar.dart:184-270: shrink: Episodes and Sources badges are one 50-line block with a swapped icon/label. One _TopBarBadge.
player_seek_bar.dart:83-94: stdlib: 4th hand-rolled _formatDuration.
```

## Batch 2 wave 1 — shared widgets — LANDED

Applied 2026-11-04: +479 / −2,889 lines. `flutter analyze` clean, 1,362 tests
pass, APK builds, and the Windows app was launched and photographed to confirm
the Home hero, the shared meta line and the rail cards paint.

```
widgets/common/card_poster_frame.dart (new, 423 L)
  shrink: three private poster frames (movie 333 L, anime 155 L, manga 201 L) → one CardPosterFrame.
          Deltas the copies already had became parameters, not silent choices: accent-bloom alpha
          (0.35/0.28/0.30), highlight gradient (anime never drew one), raised-on-focus shadow
          (movie only), decode scale/clamp/height-ratio, alignment nudge, play affordance
          (disc vs chip — genuinely two shapes), badge gating.

widgets/common/hover_scroll_rail.dart (new, 318 L)
  shrink: four copies of the scroll machinery → one rail. edgeTolerance parameterises the
          0 vs 10 px can-scroll test; arrowStyle (pointer | focusable) keeps movie's focusable
          frosted arrow and the rails' hover-only arrow; movie's entrance stagger stays at its
          call site. movie_slider_section −150, anime_slider_section −100, continue_watching −52.

widgets/common/waveform_seekbar.dart (new, 861 L)
  shrink: MusicWaveformSeekbar + AudiobookWaveformSeekbar (443 + 436) → one widget with
          WaveformSeekbar.music/.audiobook named constructors so no call site changed meaning.
          Twenty-odd real differences (bar count, sample formula, gradients, thumb, readout,
          drag-start behaviour, focus/key-seek) are look-table entries, both values preserved.

widgets/common/interactive_physics_button.dart (new, 392 L)
  shrink: Music+AudiobookInteractivePhysicsButton (268 + 342) → one button resolving its effect
          through a passed enum. Audiobook's duplicate _isHovered/_isFocusedFromKey pair and its
          nested GestureDetector are gone; highlight now comes from CardInteraction, which fixes a
          real bug (mouse-exit used to clear the highlight while the remote was still on the card).

home_page.dart:3073-3205  delete: private _HeroMetaLine → common HeroMetaLine (terms + leadingRating
          already expressed it). String, order, genre cap and badge unchanged.
home_page.dart:3021-3067  delete: private _CarouselArrow → common SliderArrow, which gained
          frosted/size/iconSize so home keeps its 52/24 flat chrome and rails keep 48/20 frosted.
collections/collection_grid_page.dart:75-133  kept, with a comment recording why: SettingsAppBar has
          no subtitle slot and the header must live inside AnimatedAmbientBackground.
```

Wave 1 regression caught and fixed before landing: the movie card passed a
`Positioned.fill` wrapper into `CardPosterFrame.overlay`, which wrapped it again
— competing `ParentDataWidget`s, 78 failing tests. The frame owns the
`Positioned`; call sites pass bare widgets.

## Batch 2 wave 2 — rail + scaffold — LANDED

```
music_page.dart:1832-2003  shrink: _MusicHorizontalScrollSection (155 L stateful) → 59 L stateless over
          HoverScrollRail. Deltas accepted: scroll step 75%/450 ms → 80%/650 ms (the other three rails'
          constant), and the list is now Clip.none like the rest (a hovered card at a row end is no
          longer clipped). Music keeps edgeTolerance 5 and arrowInset 8, both explicit.
          The rail gained arrowInset for that — no dead parameters.
widgets/settings/settings_scaffold.dart (new, 100 L)
          shrink: the ambient → transparent Scaffold → SettingsAppBar → Center → ConstrainedBox(maxWidth)
          800 → body nesting, repeated in 19 sub-pages. maxWidth 820 passed explicitly by the two
          appearance pages; liquid glass passes `actions` (its Reset button, unchanged).
          Left raw, with the reason each differs: builtin_providers (ambient lives inside the body under
          extendBodyBehindAppBar), the two player-studio pages (hand-rolled two-line AppBar, 440 dp,
          editor body), and the Settings hub (sidebar theme, LayoutBuilder split).
```

Review note: this wave dedents bodies, so `git diff` shows ~2,800 changed lines for ~180
lines actually saved. Review it with `git diff -w`; there is no logic change in the moved lines.

## Measured result of everything above

`lib/` went from **191,336 lines / 428 files** to **187,773 lines / 423 files** — −3,563 lines,
−5 files (12 deleted, 7 shared widgets added). Reviewers should diff with `-w` from Batch 2
wave 2 onward. `flutter analyze` clean, 1,362 tests pass, APK and Windows builds succeed.

## Batch 3 — scraper sites (`net: −448`) — LANDED

Applied 2026-11-04: +185 / −633 across 50 site scrapers plus the model and base
class. `flutter analyze` clean, 1,366 tests pass, APK builds.

Three pieces were added once and adopted across the sites:

```
models/stream/stream_model.dart        add: StreamSource.zplayHttp({url, title, description, headers, name = 'ZPlayHTTP', behaviorHints, subtitles})
   Replaces the 8-line shape each site spelled out — the 'ZPlayHTTP' name and addon tag,
   notWebReady: false, and proxyHeaders.request mirroring headers. The mirroring was the
   rule nobody could see: a provider needing one extra header could add it to `headers`
   and forget the proxy map, and the fetcher reads the proxy map.

services/scraper/stream_scraper.dart   add: abstract class HttpScraper extends StreamScraper (name => 'ZPlayHTTP')
   Deleted 46 identical name overrides. providerId/providerName are unaffected: they key
   off runtimeType, which an intermediate base does not change (asserted in a new test).

services/scraper/stream_scraper.dart   add: const String kZplayUserAgent
   Replaced 43 hand-copied Chrome/131 strings. The four sites presenting other versions
   (114, 120, 124, 133) and one presenting a product token keep their own strings —
   those are site-specific, not drift.
```

Converted: 46 scrapers extend `HttpScraper`, 39 source constructions use
`zplayHttp`, 43 UA declarations point at the const. Left alone with reasons
recorded per file: `knaben`/`torrent_galaxy` (`'ZPlay'` label, torrent sources),
`a111477`/`vadapav` (hints come from the addon payload), and six sites whose
constructions carry no `behaviorHints` — the factory would have *added* hints
those sources never had.

New guard: `test/services/scraper/zplay_http_source_test.dart` pins the contract
the fetcher depends on — headers mirrored into `proxyHeaders.request`, no empty
proxy map, explicit name/hints winning, and converted scrapers still reporting
their original `providerId`.

## Batch 4 — service/catalog layer — LANDED

Applied 2026-11-09: measured `lib/` 187,325 → 187,024 (−301) plus four new shared
files. `flutter analyze` clean, 1,374 tests pass, APK and Windows builds succeed,
app launched and photographed.

```
utils/language_names.dart (new)                add: one ISO-639/name table + subtitleLanguageName()
   Replaced four private maps (117/70/65/92 lines) in the stremio, opensubtitles, wyzie and
   cloudstream providers, plus their four copies of the `<= 3 chars → uppercase` fallback.
   The union also names codes three providers used to leave raw, so labels change:
   OpenSubtitles and Wyzie 53 each (POB → Portuguese (BR), CZE → Czech …), CloudStream 28
   (Mac → Macedonian …), Stremio 3 (fil, ur, urd). One genuine conflict: `fil` was
   Tagalog in Stremio and Filipino in CloudStream; the reference reader's Filipino wins.
   The reader's tail is code-aware: an unknown 2–3 letter label still renders as XX.

services/tracker/tracker_auth.dart (new)       add: TrackerAuthorization, pruneTrackerAuthorizations,
   pollTrackerAuthorization, kMaxPendingTrackerAuthorizations
   Replaces the two device/PIN poll loops (trakt:451-514, simkl:322-373), the two
   {authorization, expiresAt} records, the two prune-and-cap-8 helpers, and simkl's three
   copies of the TTL + in-flight + generation cache (one _TtlCache there). Each service keeps
   its own request, its own 200-body parse and its own non-200 mapping — they genuinely differ
   (trakt maps 400/429, simkl reads pending from the body).

services/debrid/providers/debrid_provider.dart (new)  add: DebridKeyStorage mixin + DebridProvider
   Five providers were carrying byte-identical saveKey/hasKey pairs; the key trio is now the
   mixin, `debrid_service.dart`'s two 5-branch switches and the settings page's three if-chains
   are one Map<String, DebridProvider> lookup. Real-Debrid's getToken/saveToken/verifyToken
   rename to the Key names (two callers, both swept).

home_page_settings.dart:146-336   shrink: 19 setters + initialize → one table row per setting,
   one reader, one _set. Public setter signatures unchanged, same keys, same fallback values.
metadata_service.dart             shrink: search is fetchCatalog + extras (error policy is now a
   throwOnFailure parameter, because they genuinely differed); one _normalizeBase replaces four
   copies; one _getWithConfigFallback replaces six retry blocks (the review counted five).
addon_manager.dart:73-104         shrink: five activeXAddons getters → one _active(test).
stream_service.dart:233-286       shrink: CloudStream and ZPlayHTTP fan-out blocks → one _pump.
stream_scraper.dart:94-133        shrink: the custom filter starts from the same torrent-dropped list.
builtin_providers_settings_service.dart:147-155  shrink: getMeta is non-null; the `!` is gone.
```

### Two regressions this batch produced, and how they were caught

- `debrid_service.dart` ended one `}` short after the switch rewrite — `flutter analyze`
  found it (`Expected to find '}'`), and it was closed by hand.
- `home_page_settings`'s table crashed at `initialize()` for **every enum setting**:
  `_HomeSetting` was constructed through the raw type, so `firstWhere`'s `orElse` was
  typed `() => Object?` against a `List<SimilarSectionPosition>`. The analyzer and the
  1,366-test suite both passed; a throwaway runtime check of `initialize()` caught it.
  The reader no longer uses `firstWhere`, and the enum row now has a permanent test
  (`test/services/home/home_page_settings_table_test.dart`) including a stored name the
  enum no longer has.

Also fixed while verifying: `player_subtitle_menu`'s flag lookup used substring matching
(`contains('ar')`), which was harmless on raw codes but paints Bulgarian and Hungarian with
the Saudi flag now that labels are English names. It is a table lookup first, prefix match
for short codes only.

## Batch 4 findings, as reviewed (all landed above)

```
lib/services/subtitles/providers/{stremio,opensubtitles,wyzie} + cloudstream/stream/cloudstream_stream_provider.dart: shrink: four hand-copied ISO-639→English maps; 115 duplicated lines between cloudstream_stream_provider and stremio_subtitle_provider alone. One utils/language_names.dart.
scraper/sites/*.dart (54 sites): shrink: "name:'ZPlayHTTP', addonName:'ZPlayHTTP', behaviorHints:{notWebReady:false, proxyHeaders:...}" spelled out each time. StreamSource.zplayHttp({url,title,description,headers}).
scraper/sites/*.dart (46): yagni: identical "String get name => 'ZPlayHTTP'" override. HttpScraper base class.
scraper/sites/*.dart (53): shrink: identical Chrome/131 UA const. One kZplayUserAgent.
scraper/sites/tmdb_helper.dart:60-186: shrink: keyed and keyless calls are the same body twice. One _getJson(host,path,key?).
services/home/home_page_settings.dart:146-336: shrink: 19 setters of "value=; prefs.setX; notify". One map-driven generic set.
services/metadata/metadata_service.dart:222-297: shrink: search() is fetchCatalog() + mergedExtras['search']. ~45 lines.
metadata_service.dart:183,259,332,350,369: shrink: five copies of the /%7B retry. One _getWithConfigFallback.
metadata_service.dart:119-121,153-155,231-233,315-317: shrink: base-URL normalisation written four times.
trakt + simkl: shrink: device/PIN poll loops (trakt_service.dart:451-514, simkl_service.dart:322-373), {authorization,expiresAt} records, prune-by-expiry, TTL+in-flight+generation cache — all duplicated.
trakt_service.dart:131-145: shrink: _extractRatings is _extractListImdbIds keeping the rating.
services/debrid: shrink: two 5-branch provider switches (debrid_service.dart:84-98,117-176) + three in debrid_settings_page.dart:98-166 + five identical saveKey/hasKey pairs. One Map<String,DebridProvider> + a secretKey mixin.
services/addon/addon_manager.dart:73-104: shrink: five activeXAddons getters. One _active(test).
services/stream/stream_service.dart:233-286: shrink: CloudStream and ZPlayHTTP blocks verbatim. One _pump(Stream<StreamSource>).
scraper/stream_scraper.dart:94-133: shrink: the custom-mode branch rebuilds the default branch's torrent-drop before filtering again.
builtin_providers_settings_service.dart:147-155,186: shrink: getMeta returns nullable that orElse makes impossible, forcing getMeta(id)!.
```

## Batch 5 — IPTV stack — LANDED

Applied 2026-11-09: measured `lib/` 187,024 → 185,842 (**−1,182**). `flutter analyze`
clean, **1,383 tests pass**, APK and Windows builds succeed, app launched and painted.
IPTV area itself: +1,641 / −3,118.

```
models/iptv/iptv_models.dart      add: ChannelHit.toJson/fromJson; delete StoredHit and both hand-written mappers
   Key names are the persisted format (`pu uu pp pn sid sn si scid sce sk url`), kept
   byte-identical so an installed build's Boxing results still load and a downgrade can
   still read what this version writes. Pinned by test/services/iptv/channel_hit_persistence_test.dart.
models/iptv/iptv_models.dart      add: EpgEntry.progress
   Three surfaces computed the same clamped fraction — the browser page's rows, the guide
   band's bar and its "N mins elapsed (P% complete)" line.
iptv_storage.dart                 shrink: three identical string-set stores → StringSetStore(keyPrefix).
iptv_controller.dart              shrink: _saveChannelHits and its StoredHit builder gone; hits go through the store;
                                  hand-built `/live/…` URL → IptvClient.streamUrl (now percent-encodes credentials,
                                  which is what the other three hit producers already emitted).
iptv_network.dart                 shrink: five GET wrappers → _get(url,{headers,timeout,maxBytes}) + _text(); six IIFEs → _s();
                                  24-line expiry formatter → DateFormat('dd MMM yyyy','en_US'); 40×150ms polling lock →
                                  one memoised Future; Reddit Atom reader: four RegExps + hand-written entity decoder →
                                  XmlDocument.parse behind `IptvScraper.parseCatalogRss` (@visibleForTesting).
m3u_store.dart                    delete: M3uFetcher — RemoteM3uSource.fetchPlaylistText + M3uParser is that function.
iptv_portal_browser_page.dart     shrink: _LiveChannelListRow / _LiveChannelGridCard / _LiveChannelCompactListRow →
                                  one _LiveChannelRow(layout: detailed|grid|compact); four search TextFields → one;
                                  three ListView.builders → one; the VOD card pair → isSeries:.  3161 → 2998.
iptv_portals_modal.dart           delete: the "Customize Portals Modal" dialog (a second editor for notifiers
                                  live_tv_settings_page already owns) — the tune button now opens that page.
                                  shrink: icon trios → _cardIconButton; eleven styleFrom blocks → _toolbarButtonStyle.
multinutz_channel_sheet.dart      delete: the second portal manager (add manual, add M3U, edit, select-all,
                                  delete-all, source filters, favourites filter, generate) → one button into
                                  IptvPortalsModal(initialTab:). 1653 → 888.
iptv_page.dart                    shrink: _QuickChannelsSlider → HoverScrollRail (no fourth copy); _MultiStreamsAppBarButton
                                  → _GlassActionButton(label:); third QuickChannel→HardcodedChannel mapping →
                                  QuickChannel.toHardcoded() extension.
live_guide_band.dart              shrink: progress maths → EpgEntry.progress.
```

Guarded by two new tests, because both changes were in code no test touched:

- `test/services/iptv/channel_hit_persistence_test.dart` — the eleven persisted keys,
  round-trip, and tolerance of a hit written before `sk` existed.
- `test/services/iptv/reddit_rss_parse_test.dart` — the regex→XML swap: feed order,
  `t3_` ids and the empty id for everything else, single-pass entity decoding,
  HTML flattening, xhtml children, no title, and malformed feeds yielding no posts
  rather than throwing. The production test for this path is tagged `network`.

### Behaviour deltas accepted in this batch

- Playlist fetch: VLC UA → the browser UA `RemoteM3uSource` pins, 25 s → 15 s, body
  decoded as UTF-8 with `allowMalformed` (accented channel names survive a host with no
  charset). Same `FormatException` surface; nothing catches it by message.
- RSS on invalid XML that still contains `<entry>`: the regexes could salvage posts, the
  parser drops the page. Reddit's own feed is machine-generated and valid.
- Reddit content now resolves numeric character references the hand-written decoder did not
  (`&#8217;`), which is closer to the source text.
- Quick Channels rail: scroll step 0.75/500 ms → the shared 0.8/650 ms, arrows are
  `SliderArrow` at 10 dp, and they now also appear on web.
- The multinutz sheet's action bar is 12 dp taller (48 dp tap target, required by the grep
  that removed `shrinkWrap` from its single button).
- The modal's tune tooltip: "Customize Modal Style" → "Portal Display Settings" (it no
  longer opens a local editor).

## Batch 5 findings, as reviewed (all landed above)

```
iptv_controller.dart:726-745,1062-1082: shrink: hand-written StoredHit↔ChannelHit mappers. ChannelHit.toJson/fromJson.
iptv_controller.dart:1254: shrink: hand-built stream URL. IptvClient.streamUrl already owns that string.
iptv_portal_browser_page.dart:1999-2737: shrink: three near-identical live-channel rows, 738 lines. One _LiveChannelRow(layout:).
iptv_portal_browser_page.dart:149-330: yagni: 180-line "Customize Portal Browser" dialog editing notifiers live_tv_settings_page.dart already edits.
iptv_portal_browser_page.dart:848-905,1040-1100,1336-1385,1414-1462: shrink: four copies of one search TextField. One _searchField().
iptv_portal_browser_page.dart:1723-1820: shrink: three ListView.builders differing by itemExtent/padding/child.
iptv_portal_browser_page.dart:1878-1897: shrink: the if(series) pair building the same _VodSeriesCard twice.
iptv_portal_browser_page.dart:2085-2091: shrink: _nowAiringProgress re-derives what live_guide_band.dart:611 already computes. One EpgEntry.progress.
iptv_portals_modal.dart:206-337: yagni: "Customize Portals Modal" repeats portalCardStyle/showPortalExpiry/showPortalConnections from live_tv_settings_page.dart:543-660.
iptv_portals_modal.dart:1139-1190,1817-1868: shrink: copy/fav/delete IconButton trios written twice. One _cardIconButton().
iptv_portals_modal.dart:502-521,1488-1507,1533-1545: shrink: identical styleFrom blocks. One _toolbarButtonStyle(isMobile).
iptv_portals_modal.dart:1407-1468 ↔ multinutz_channel_sheet.dart:245-280: shrink: duplicated source chip.
iptv_page.dart:906-1114: shrink: _QuickChannelsSlider re-implements IptvSliderSection's rail.
iptv_page.dart:742-905: shrink: _MultiStreamsAppBarButton duplicates _GlassActionButton's focus stack.
iptv_page.dart:1049-1062: shrink: third copy of QuickChannel→HardcodedChannel mapping (also iptv_search_page.dart:84-92, multinutz_page.dart:521-530).
multinutz_channel_sheet.dart:44-116,245-280,291-1175: yagni: a second full portal manager (add/edit/select-all/favourites). IptvPortalsModal is that.
multinutz_channel_sheet.dart:749-794,962-1007: shrink: copy/favourite/delete IconButton trio twice in one file.
iptv_network.dart:18-40,657-659,1238-1252,1321-1355: shrink: five GET wrappers. One _get(url,{headers,timeout,maxBytes}).
iptv_network.dart:82-105: stdlib: 24-line expiry formatter with a hardcoded month array. intl is already a dep: DateFormat('dd MMM yyyy').
iptv_network.dart:855-874,1255-1262: native: RSS via four RegExps + hand-written entity decoder while xml:^6.5.0 is already used in services/audiobook/. XmlDocument.parse.
iptv_network.dart:639-651: shrink: 40×150ms polling loop as a lock. One memoized Future.
iptv_network.dart:154-190,213-218: shrink: six IIFEs re-deriving x?.toString() ?? ''. One _s(dynamic).
iptv_network.dart:873,893,897-903: delete: unused title/postIdx parameters of _processPostBody.
iptv_storage.dart:55-62,383-415: shrink: three identical string-set stores. One StringSetStore(keyPrefix).
iptv_storage.dart:72-73,140-148: delete: loadLiveOnly/saveLiveOnly — nothing writes the flag.
iptv_storage.dart:240-246,349-352: delete: IptvDeadUrlStore.forget, IptvChannelResultsStore.clear.
iptv_storage.dart:69-70,400-401: delete: two portalKey() copies of IptvPortal.key.
iptv_storage.dart:355-381: delete: StoredHit, an 11-field mirror of ChannelHit.
m3u_store.dart:47-75: delete: M3uFetcher — RemoteM3uSource.fetchPlaylistText (sources/m3u_remote_source.dart:129-145) is the same function.
models/iptv/m3u_models.dart:59-72: delete: M3uPlaylist.copyWith — zero call sites.
models/iptv/iptv_models.dart:77-90: delete: IptvStream.epgChannelId — parsed, never read.
live_guide_band.dart:454-471: shrink: third copy of now-airing percent math. stdlib: DateFormat.Hm().
widgets/iptv/iptv_slider_section.dart:134-139 + iptv_hero_carousel.dart:76-81: shrink: two desktop-platform tests identical to continueWatchingHasPointer().
iptv_search_page.dart:96-105: shrink: second grid-column breakpoint ladder, already at iptv_portal_browser_page.dart:1844-1856.
iptv_search_page.dart:143-190: shrink: fifth copy of the search-field InputDecoration.
```

## Batch 6 — player internals — LANDED

Applied 2026-11-09: measured `lib/` 185,842 → 184,673 (**−1,169**). `flutter analyze`
clean, **1,383 tests pass**, APK and Windows builds succeed, app launched and painted.

```
watch_screen.dart                shrink: four filter controls (chip + glass popover + bottom sheet + item row)
                                 → one _FilterMenu<T> with _buildFilterDropdown/_showFilterMenu/_showFilterSheet/
                                 _buildFilterOptionRow; the three label getters fold into the option's `short`.
                                 4,286 → 3,268 lines. Also: _buildSearchView's two identical grid delegates →
                                 one _musicGridDelegate in music_page (the last _MusicCardSizing user) — done
                                 in this batch, music_page 3172-line class deleted.
player_screen.dart               shrink: _buildVolumeHud/_buildBrightnessHud → _GaugeHud (chip steps, track
                                 gradient and glow alpha stay parameters, because they measured differently);
                                 _buildAudioHud/_buildAspectHud → _ToastHud; five bool/String/Timer triples →
                                 five _TransientHud instances with per-HUD lifetimes (1300/1300/1600/1600/6000 ms);
                                 four popover wrappers → _popover(); the dead space/K Shortcuts branch deleted.
player_seek_bar.dart + transport shrink: position/buffered and their listenable twins → listenables only.
widgets/player/player_menu_rows.dart (new)  add: PlayerMenuHeader/PlayerMenuOption shared by the aspect and
                                 speed menus.
player_subtitle_menu.dart        shrink: one entry list + one item builder, with the compact pill and the
                                 desktop row as its two decoration branches; 1,334 → 1,274 and each layout keeps
                                 its own chrome, labels ("All" vs "All Languages"), section markers and Off
                                 treatment.
player_top_bar.dart              shrink: Episodes/Sources badges → _TopBarBadge.
player_settings.dart             shrink: 31-line doc above playbackEngine → 13 lines, measured figures kept.
```

### Behavioural deltas accepted

- **space/K with a transport control focused** now activates that control instead of
  toggling play. With the page node focused — the state the player opens in — nothing
  changes, because `handlePlayerRemoteKey` answers first. This is the one place the dead
  `Shortcuts` branch was actually reachable, so deleting it is also the reason the
  behaviour moved.
- **Filter popover and sheet are now one look**: popover rows take the sheet's row style
  (12/16 padding, 20 px check, accent-pill selected row, light haptic), the audio popover
  takes the shared 230 px/250 ms chrome, the size sheet takes the popover's order and its
  `–` labels, and the audio sheet says `English / Orig`. The two surfaces had drifted; one
  of them had to move, and the popover was chosen because the sheet also had the addon
  filter in the same style.
- HUD slots now exist in the tree while hidden (empty, `IgnorePointer`, no paint, no
  hit-test) instead of being absent.

### Rejected on verification in this batch

- `PlayerTheme`'s token aliases (`player_glass.dart:30-95`): the review called them "bare
  forwards, every call site already holds tokens". There are ~230 call sites across the
  player widgets, several aliases are derived values rather than forwards
  (`accentSoft` = accent @0.20, `accentGlow` = @0.40), and many sites are in helper methods
  without a `tokens` local. Deleting the facade would be churn with no behavioural gain.
  It stays.

## Player findings, as reviewed (all landed above)

```
pages/music/music_page.dart:3568-4276: shrink: four detail modals repeat one scrim>lens>720x640 sheet chrome plus art+title+tracks. One _MusicDetailSheet.
music_page.dart:1832-2003: shrink: third rail implementation (scroll controller, edge detect, hover arrows).
music_page.dart:5182-5250: shrink: fifth copy of the glass-sheet chrome.
music_page.dart:3267-3280: yagni: _MusicCardSizing is a 4-branch table used once.
widgets/music/music_waveform_seekbar.dart:28-443 + widgets/audiobook/audiobook_waveform_seekbar.dart:30-436: shrink: one widget twice — 149 of 408 non-blank lines identical after name-token normalization. One WaveformSeekbar<T> in widgets/common.
widgets/{music,audiobook}/*_interactive_physics_button.dart: shrink: 0.70 structural similarity, same tilt math and ripple controller. One InteractivePhysicsButton(effect:).
anime_card.dart:146-300 + manga_card.dart:190-390 + movie_card.dart:540-872: shrink: three _PosterFrame implementations (shadow stack, accent bloom, memCache clamp, vignette, play disc). One CardPosterFrame(posterUrl, aspectRatio, badges, onPlay).
manga_card.dart:393-410: delete: local MissingPoster duplicates widgets/common/poster_skeleton.dart:49.
anime_slider_section.dart:30-140 + continue_watching_slider.dart:150-230 + music rail: shrink: 4 copies of the same hover-arrow rail. One HoverScrollRail.
settings sub-pages (18 files with maxWidth:800 + AnimatedAmbientBackground + SettingsAppBar): shrink: one SettingsScaffold(title:, children:). ~-200.
appearance_settings_page.dart:334-407,305-330: delete: _buildRow/_buildGroup duplicate settings_page.dart's _SettingsNavRow/_buildSection — and the copy has no focus ring, so those rows are pointer-only on TV.
appearance/music_settings_page.dart:88-166: shrink: _buildThemesGrid rebuilds PalettePicker with a different column rule.
appearance/{manga,audiobook,home_ui}_settings_page.dart: delete: one-line _buildThemesGrid() => const PalettePicker() wrappers.
home_page.dart:3073-3205: delete: _HeroMetaLine duplicates widgets/common/hero_meta_line.dart.
home_page.dart:3021-3067: delete: _CarouselArrow is a second arrow beside widgets/common/slider_arrow.dart.
widgets/common/slider_arrow.dart:19-33: shrink: StatefulWidget with SingleTickerProviderStateMixin but no AnimationController, plus hand-rolled hover/press where FocusableCard+CardFocusRing exist.
collection_grid_page.dart:75-133: shrink: hand-rolled app bar that settings_app_bar.dart already is.
utils/navigation/route_transitions.dart:8-24: yagni: materialRoute has one call site. Inline MaterialPageRoute.
widgets/common/card_focus_expansion.dart:110,159-160: yagni: scale parameter with no caller passing it.
library_page.dart:104,169: delete: television ? s48 : s48.
```

## The review, closed

Started: 428 files / 191,336 lines. Now: 427 files / 184,673 lines — **−6,663 lines
(−3.5%)**, with 12 shared pieces replacing ~40 copies. Every batch verified the same way:
`flutter analyze` clean, the full suite green (1,366 → 1,383 tests, +17 guards),
`flutter build apk --debug`, `flutter build windows --debug`, app launched and photographed.

Batches: 1 (orphans/dead code), 1c (player settings + settings rows), 2 waves 1–2 (poster
frame, rail, seekbar, physics button, scaffold, hero line), 3 (scraper sites), 4 (catalog
services), 5 (IPTV), 6 (player internals).

### Left on the table, with reasons

- **`music_page`'s four detail modals** (~700 L, `:3568-4276`): one scrim>lens>sheet chrome
  with art+title+tracks repeated four times. Not done — it is the last big one and it is a
  pure layout merge, best done with a visual pass per modal.
- **`collection_grid_page`'s `_Header`**: verified non-equivalent to `SettingsAppBar`
  (no subtitle slot, must live inside the ambient background, different chevron). Left,
  documented at the site.
- **`player_glass` aliases**: rejected above.
- **`widgets/common/slider_arrow.dart` frosted branch is pointer-only** (`GestureDetector`),
  so the rail arrows are not D-pad reachable. That is a UX decision, not over-engineering:
  the cards themselves are the focus targets.

## Judged, do not cut

- `lib/services/iptv/hardcoded_channels.dart` (1,873 const entries) — read by the
  Live rails, search, and every scan's admission rule. `const` costs no parse; an
  asset would add a decoder, a remote list would add a failure mode to the one
  thing that must work offline.
- `lib/services/iptv/m3u_parser.dart` — quoted-comma handling is real work; no
  package covers it.
- `services/iptv/pastesh_decryptor.dart` — proper pointycastle use.
- `TrailerHost` (test seam) and `VideoEngine` (two real implementations).

## Observations outside this review's scope

- `flutter/` at the repo root is a 1.8 GB Flutter SDK checkout. Gitignored and
  untracked, so it is local environment, not repository weight — worth knowing
  when the tree is measured.
- Cross-file clone detector (14-line windows) found 2,086 duplicated lines,
  concentrated in the four subtitle/stream providers and the two anime details
  pages.
- `docs/UX_FINDINGS.md` (1,038 lines) and the audit/redesign docs predate
  `FocusableCard`; several TV findings there are already fixed and should not be
  rescheduled as work.
- **Windows, Linux, iOS and macOS builds could not fetch the TorrServer engine**:
  `torrserver_flutter 0.0.7` downloads it from a repository that was deleted.
  Resolved by publishing a fork under our org — see `docs/TORRSERVER.md`. The
  plugin is now pinned in `dependency_overrides` to
  `tzero86/torrserver_flutter` `v0.0.7`, whose release carries YouROK/TorrServer
  MatriX.148 binaries with checksums. Verified: clean Windows build with no
  environment variables, real engine booting (`/echo` → `MatriX.148`), Android
  fetching and verifying all four ABIs. iOS/macOS still need a Mac-built
  `TorrServerKit.xcframework`.

`net: -~9,900 lines possible` at review time (≈5% of `lib/`), plus 8 files and 3
dependencies gone. All six batches have landed: measured outcome is 191,336 → 184,673 lines
(−6,663) and 428 → 427 files of `lib/`.