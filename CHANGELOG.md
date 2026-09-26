# Changelog

All notable changes to ZPlay will be documented in this file.

## [1.3.1] - 2026-09-26

- Debrid failures are now understood instead of printed. A refused torrent used to reach you as the provider's own output, `Exception: Real-Debrid rejected magnet (451): { "error": "infringing_file" }`, and one refusal could end the whole chain. Every failure is now sorted into what it actually means, and the player acts on the sort. A source that was refused, or that is not ready yet, moves on to the next ranked one immediately instead of waiting out the watchdog, so a dead entry no longer costs you nine seconds and the attempt behind it. A problem with your Debrid account stops instead, because every source fails the same way and walking the chain would only hide the one thing you can fix.
- A source Debrid turned down keeps its place in the list with a quiet marker on it instead of disappearing, and the automatic search stops spending attempts on it. A permanent refusal is remembered for good and a softer one for a fortnight, so the same dead link is not put back in front of you the next night.
- Sources you choose by hand now get the same handling as the ones the app picks. They are replaced by a ranked alternative when they fail, and the source search screen still appears only after the app has actually taken over a choice you made, never during the first attempt.
- Your Debrid key can now reach your Stremio addons. An addon URL may carry `{realdebrid}`, `{torbox}`, `{alldebrid}`, `{premiumize}`, `{debridlink}` or `{debrid}`, and the key you saved is substituted when the request is built, for the manifest, the catalog, the metadata, the streams and the subtitles alike. A placeholder naming a service you have not set up is left standing, so a misconfigured addon fails visibly instead of quietly asking the wrong service, and your key is never written into the saved addon, so rotating it keeps working without editing anything by hand.
- Addons gained a Debrid section with Connect and Disconnect, and a catalogue of Debrid addons to start from. Torrentio ships with it, one entry per service, each naming itself after the service you are connecting.
- Torrent sources now reach Debrid while the local P2P engine is switched off. Turning Debrid on used to switch the local engine's indexers off with it, so the magnets Debrid resolves in the cloud were discarded before anything asked for them, and the Debrid marker matched nothing on the built-in entries. A working Debrid service now brings its magnets with it whatever the local engine is set to. They are counted and marked as Debrid playable, and they stay listed when the local engine's own streams are off, so a verified account actually shows Debrid sources.
- The keys inherited from PlayTorrio are gone. They were never ZPlay's credentials to ship, so all six now ship empty, and the fallback that quietly borrowed the inherited TMDb key is gone with them. If you were relying on them, you will notice. Wyzie subtitles, both Audionest services, Paper2Audio, the Films365 downloader and the VidGod cache are each off until a key of your own is supplied, in Settings under Service API Keys, or injected at build time. Nothing is left half working, and the one place a key is not needed is unchanged: the six 1990s rails still show their built-in picks with no TMDb key at all, exactly as before.
- Search now says so when its sources fail. If nothing it asked came back, it reports `Search could not reach its sources`, tells you how many of how many sources did not answer, and offers a retry, instead of telling you the title does not exist. When only some sources answer, the results that did arrive are shown with a quiet count of what is missing, because a partly empty list is not the same thing as an empty one.
- A movie with no playable source no longer sends you back to episodes. A film has no episodes behind it, so the empty state now names only the exits that are actually on screen.
- The play button on Continue Watching is visible on touch devices without waiting for a hover that never comes. It was revealed on hover alone, which a touchscreen and a D-pad cannot do, so on those devices the tile showed no way to start the film.

### Windows: one-time profile migration

- The rebrand moved the folder your profile lives in, and it moved silently. Windows takes that path from the app's own name, so every install up to and including the rebrand wrote to `%APPDATA%\com.example\playtorrio` and every install after it writes to `%APPDATA%\tzero86\zplay`. A first launch after the rebrand therefore opened an empty app: no settings, no watchlist, no addons, no downloaded media index, no TorrServer database.
- 1.3.1 copies the old profile into the new location on first launch, before anything reads it, so an existing install comes up exactly as you left it.
- The old folder is left where it was. Nothing is moved and nothing is deleted, so the original is still there if anything about the new profile disappoints you.
- A destination that already exists is never overwritten, and a half-finished copy is never moved into place. If you have already run a build from after the rebrand and reconfigured it, that profile is yours, and a stale copy from the previous install will not be laid over it.
- A fresh install has no old profile to find and simply starts clean, and so does every platform other than Windows.

## [1.3.0] - 2026-09-25

- Home and Browse gained curated collections: twelve verified franchise packs and six 1990s rails, browsable as a Collections vertical in Browse and as a Memory Lane zone at the end of Home.
- Every film in a pack was verified against Cinemeta before shipping, so each card resolves to the real title, year and poster, and tapping it opens the normal details screen.
- Packs render with no network request, because posters come from the same image CDN the rest of the library uses.
- Settings gained a TMDb API key field. The key is yours: it is stored only on this device, validated before it is saved, never logged, and no key ships with the app. With a key set, the six 1990s rails are replaced by lists ranked by real vote counts and refreshed at most once a day.
- Clearing the key restores the built-in picks, and a TMDb that cannot be reached never leaves a rail empty.
- The TMDb credential now has one source of truth. Precedence is the user's own key, then a build-time `TMDB_API_KEY`, then the inherited value as a last-resort fallback, so behaviour without a key is unchanged for the scraper lookups that already relied on it.
- TMDb attribution, their logo plus the required notice, appears in Credits as their terms require.
- Mouse wheel scrolling no longer changes the volume anywhere it is not the intended control. The player and the IPTV player now let a list under the pointer claim the scroll, so the subtitle panel, the episode list and the text sync view scroll without touching the volume.
- Search works on an install whose only catalog addon is Cinemeta. The dead Cinemeta search, which answered every query with the recency list, stays removed, but each search now also asks a keyless title source and shows the matches in a Titles rail, so `No results` appears only when there is genuinely nothing to show.
- Rails with no catalogue behind them no longer offer See All. On the titles rail and the CloudStream rails it opened a screen that could only come back empty.
- The scroll track on Home and the other long lists no longer reads as a volume slider. It fades in while you scroll or hover it and is hidden while the page is idle, and Home's private copy of the widget is gone.
- Fullscreen is no longer a one-way door. F11 toggles it from every screen, and the rail carries a fullscreen row above Settings, so exiting fullscreen no longer means navigating back to Home first.
- Resuming from the Continue Watching tile now plays instead of dropping you into the source chooser. Provider streams that refuse the seek at open no longer count as a fatal playback error: the player tells the engine the stream is seekable, and if a source still refuses, it plays from the beginning with a one line notice rather than failing.
- A resumed source that delivers nothing is now replaced by the next ranked candidate automatically, four attempts at most, before the chooser appears. The rescrape also waits past the scrapers' own deadline instead of cutting the candidate list short at five seconds, which used to throw away every provider that answered slowly.
- Switching source by hand during a resumed movie continues from where you were instead of restarting the film, the same way switching source during an episode already behaved.
- When a resume has to try more than one source, the search has its own screen instead of the player flickering between attempts: the title's logo art, `Testing other sources for you`, the source being tried with its attempt number, and a quiet `Choose a source myself` escape.
- A resumed title now carries its real metadata, so that screen has the title's logo to show and the rescrape behind it receives the title's genres instead of an empty list.
- Sources that look healthy but cannot play are no longer treated as good. The check behind the source search now follows an HLS stream from its playlist through to the first real media segment, so a playlist whose segments are dead, expired or refused is rejected instead of being counted as alive, and the automatic search spends its attempts on the sources that passed that test before it falls back to the rest.

## [1.2.1] - 2026-09-25

- Settings and Appearance are recomposed rather than restyled. Both were a flat stack of identical cards, which is what still read as the old app even after every colour moved onto the token layer.
- Rows now sit in labelled groups inside one grouped surface per section, separated by hairline dividers instead of each row carrying its own card, border, icon chip and badge.
- The badge became right-aligned value text, so a row reads as a setting with a current value instead of a marketing tile.
- The redundant intro card on Settings and the duplicated customization-scope tile list on Appearance are gone.
- Every callback, navigation target, dialog, switch binding and label is unchanged: this release moves no functionality.

## [1.2.0] - 2026-09-25

- Every screen now draws its colours, radii, spacing, type and opacity from the contract token layer in `lib/services/theme/design_tokens.dart`.
- That covers the shell slots (Home, Browse, Search, Library, Settings), the settings family, the seven Browse verticals, the details screen, the media readers, the entity and modal screens, and the shared poster cards, rails, skeletons and dialogs.
- The player and reader chrome follows the same tokens: `PlayerTheme` and `ReaderTokens` are now bridges onto the token layer that keep their member names, so the player and reader widgets repaint with the active palette.
- A palette or accent change now applies everywhere. Screens no longer carry a fixed near-black palette, so the theme is no longer confined to the shell.
- The fork's competing greens, cyans and violets collapsed onto the single accent plus the semantic status colours. Third-party service brands (Trakt, Simkl, Discord) and the per-quality and HDR badges keep their identity colours.
- `flutter analyze` is clean. The project previously carried 18 info-level issues and now reports "No issues found!".
- The GitHub release body is composed from this changelog in CI, so the release description leads with what changed instead of the fork notice.
- The in-app update dialog shows only the changelog section, cut at the `<!-- zplay:changelog-end -->` marker.

### Android: one-time reinstall

- A release published before 1.1.9 was signed with a per-runner debug key that no longer exists, so Android refuses to install over the existing app with "App not installed as package conflicts with an existing package".
- An install made from such a release needs a one-time uninstall and reinstall.
- Before uninstalling, Settings, then Backup and Restore, exports settings, addons, IPTV portals and credentials as JSON, which can be imported afterwards.
- Downloaded media files are not part of the JSON export.
- 1.1.9 signs releases with a stored keystore instead of a per-runner debug key, so installs made from 1.1.9 or later update in place.

## [1.1.9] - 2026-09-24

- Android release builds are now signed with a fixed keystore stored as a repository secret, instead of a debug key regenerated on each CI runner.
- That per-runner key is what made sideloaded updates fail to install over an existing install.
- The signing key itself is unchanged from the one existing installs already trust, so updates now install in place.
- No app behaviour changed.

## [1.1.8] - 2026-09-24

- Replaced the per-page floating dock with one adaptive shell, mounted once at the app root, so every destination always has navigation.
- Added five destinations (Home, Browse, Search, Library, Settings), shown on a left rail on tablet, desktop and TV and on a bottom bar on phones.
- Moved the seven media verticals into a single switcher inside Browse, each keeping its own scroll position and filters.
- Grouped My List and Downloads as tabs of Library.
- Moved playback into the shell, through one now-playing bar that follows the user between destinations.
- Gated the back buttons on the framework's canPop rule, so a page only shows back when it can actually pop.
- Replaced the ad-hoc breakpoints with one form-factor classifier built on shortestSide and remote-input detection.
- Deleted the dock widget, its settings page and its tests.

## [1.1.7] - 2026-09-24

- Refreshed the README and redesigned the GitHub Pages presentation.

## [3.0.0-early] - 2026-08-11

### Added
- Stremio-compatible addon protocol with catalog browsing, search, and metadata enrichment
- 9 VOD stream scrapers (FlyStream, Videasy, VidSrc, MultiEmbed, VidCore, 4KHDHub, XDownloader, Knaben, TorrentGalaxy)
- Native libtorrent streaming engine with intelligent file selection and real-time stats
- 9-source audiobook aggregator with torrent and direct streaming support
- WeebCentral manga reader with horizontal/vertical modes, zoom, and progress tracking
- Octave music streaming with library management, playlists, and keyboard shortcuts
- Subdl subtitle download and extraction with multi-language support
- Glassmorphism UI system with GPU shader effects and performance fallback toggle
- Custom route transitions (LiquidRevealRoute, CinematicSlideRoute)
- Responsive card layout adapting to phone, tablet, and desktop widths
- macOS-style liquid dock navigation
- 5-platform support (iOS, macOS, Android, Linux, Windows)
- Audiobook sleep timer and variable playback speed
- "More Like This" recommendations via BestSimilar scraper
- Search relevance scoring with exact-match-first ranking
- Progressive content loading across all sections
