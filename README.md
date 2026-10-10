<p align="center">
  <img src="assets/branding/zplay/lockup.svg" alt="ZPlay" width="360" />
</p>

<p align="center">
  <strong>Your media, on your device.</strong><br />
  Screen, page, sound, and live television in one local-first player, with no account required.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-F04E3C?style=flat" alt="GPL-3.0 license" /></a>
  <img src="https://img.shields.io/badge/telemetry-none-F04E3C?style=flat" alt="No telemetry" />
  <img src="https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Android%20%7C%20iOS-F04E3C?style=flat" alt="Windows, macOS, Linux, Android, and iOS" />
</p>

<p align="center">
  <a href="https://tzero86.github.io/ZPlay/"><strong>Project site</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/tzero86/ZPlay/releases"><strong>Download a release</strong></a>
  &nbsp;·&nbsp;
  <a href="#build-from-source">Build from source</a>
</p>

---

## One library. Four ways to play.

ZPlay keeps your progress, preferences, and library on your device. There are no required accounts, analytics SDKs, crash reporters, subscriptions, or paywalls. Optional services such as Trakt, Simkl, and debrid providers remain yours to connect.

| Mode | What it is for | What sets it apart |
|:--|:--|:--|
| **Screen** | Movies, television, anime, and live TV | Built-in HTTP and torrent providers, Stremio-compatible addons, optional Real-Debrid / TorBox, IPTV portals, curated film collections, and a dual-engine player: Android's ExoPlayer/Media3 on a SurfaceView for mainstream video — the only path that decodes 4K on a low-RAM television without copying every frame — and `media_kit` / libmpv for torrents, live streams, HDR handling, Anime4K upscaling and full subtitle styling. |
| **Page** | Manga | Horizontal or vertical reading, pinch zoom, and exact chapter-and-page resume. |
| **Sound** | Audiobooks and music | Multi-source audiobook playback with speed, sleep timer, chapters, and saved position; music search, artists, playlists, likes, quality switching, and a persistent mini-player. |
| **Live** | Television you bring with you | Xtream-style IPTV portals, channel search, favourites, and viewing history. |

### Curated collections

Browse carries a Collections vertical, and Home keeps a Memory Lane zone, both built from hand-picked packs whose every IMDb id was verified against Cinemeta before shipping: twelve franchise packs (The Godfather, Rocky and Creed, Back to the Future, Alien, Die Hard, Lethal Weapon, The Terminator, Predator, Jurassic Park, Rambo, Indiana Jones, and The Marx Brothers) plus six 1990s rails covering Action, Comedy, Horror, Sci-Fi, Animation, and Thriller. Tapping a pack opens a grid; tapping a film opens the normal details screen. Because posters come from the same image CDN the rest of the library uses, the packs paint instantly and need no catalog lookup.

Add a free TMDb API key in Settings, stored only on your device, and those 1990s rails are replaced by lists ranked by real vote counts, refreshed at most once a day. No key ships with the app, and your key is never sent anywhere except TMDb.

### A player that respects your place

Watch progress, reading position, and listening position are saved locally. Catalogs can render from cache while they refresh, and source results arrive as providers respond rather than waiting for the slowest one. Addons and scrapers are isolated so one unavailable source does not stop the rest.

---

## Get ZPlay

Every tagged release is built by CI for five platforms. Download the files you need from [GitHub Releases](https://github.com/tzero86/ZPlay/releases).

| Platform | Release artifacts |
|:--|:--|
| **Windows** | `ZPlay-Windows-Setup.exe` installer · `ZPlay-Windows-x64-Portable.zip` |
| **Android** | `app-arm64-v8a-release.apk` · `app-armeabi-v7a-release.apk` · Android TV support |
| **Linux** | `ZPlay-Linux-x86_64.AppImage` · `ZPlay-Linux-x86_64.tar.gz` |
| **macOS** | Apple Silicon and Intel `.dmg` / `.zip` builds |
| **iOS** | `ZPlay-iOS.ipa` (unsigned; sideloading required) |

For release notes and downloads, visit **[github.com/tzero86/ZPlay/releases](https://github.com/tzero86/ZPlay/releases)**. The public project site is **[tzero86.github.io/ZPlay](https://tzero86.github.io/ZPlay/)**.

---

## Build from source

Requires Flutter 3.x (Dart 3.11+).

```bash
git clone https://github.com/tzero86/ZPlay.git
cd ZPlay
flutter pub get
flutter run -d windows      # or macos / linux
```

Release builds:

```bash
flutter build windows --release
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
```

---

## Addons, sources, and architecture

ZPlay combines Stremio-compatible addons (Cinemeta is installed by default) with built-in scrapers. Open a title and enabled providers are queried concurrently; streams appear as each provider responds. The provider list can be reordered, and individual providers can be enabled or disabled.

Scrapers are isolated plugins. To add one, extend `StreamScraper`, implement `scrape()`, then register it in `stream_service.dart`; the manager supplies concurrency, timeouts, deduplication, and error isolation.

```dart
class MyNewScraper extends StreamScraper {
  @override
  String get name => 'ZPlayHTTP';

  @override
  Future<List<StreamSource>> scrape({
    required String type,
    required String title,
    required int? year,
    required int? season,
    required int? episode,
    required String? imdbId,
  }) async {
    // Your source lookup.
  }
}
```

### Technical stack

- **Flutter / Dart** for one codebase across five platforms
- **ExoPlayer / Media3** on Android, rendering into a SurfaceView, for mainstream video. This is what makes 4K work on small Android TVs: the bundled libmpv only ships `mediacodec-copy` hardware decoding, so every 4K frame was copied out of the decoder into system memory and composited into a Flutter texture, measuring 1,389–1,917 ms of latency and about 1.5 dropped frames a second on a 2 GB Chromecast with Google TV. Media3 renders the decoder output straight to the display: 904 ms and zero dropped frames on the same device and the same file.
- **media_kit / libmpv** for torrents, live streams, HLS/DASH fallbacks, Anime4K GLSL upscaling, and the full subtitle styling surface
- **TorrServer** (`libtorrent`) as the embedded torrent engine
- **Stremio addon protocol** for catalogs, search, and metadata
- **SharedPreferences** for local watchlists, positions, and settings
- **Liquid Glass** GPU shader UI via `liquid_glass_easy`, with a low-end-device setting

<details>
<summary><strong>Project layout</strong></summary>

```text
lib/
├── main.dart                     # entry point
├── models/                       # data classes
├── services/
│   ├── addon/                    # Stremio addon manager
│   ├── metadata/                 # metadata and recommendations
│   ├── stream/                   # stream aggregation, health checks, torrent engine
│   ├── scraper/                  # scraper base class, manager, providers
│   ├── anime/                    # anime services and extractors
│   ├── subtitles/                # subtitle services and providers
│   ├── manga/                    # reader sources and progress tracking
│   ├── audiobook/                # aggregation and progress service
│   ├── music/                    # music client, library, and player controller
│   ├── continue_watching/        # resume and source matching
│   └── diagnostics/              # local breadcrumbs and performance monitor
├── pages/                        # screens
├── widgets/                      # reusable components
└── utils/                        # parsing, scoring, and transitions
```

</details>

---

## Technical notes

ZPlay uses stale-while-refresh catalog loading, bounded image decoding, and a shared disk/memory cache. Release builds use a pruned asset bundle; Android release APKs are minified and resource-shrunk. On Windows, Skia is the default renderer and can be changed in the app.

Crash breadcrumbs are written locally in release builds; the performance HUD is debug-only. Neither is a telemetry service.

---

## Legal

ZPlay is a media player and aggregator. It hosts no content and stores none. Content is fetched from third-party sources only at your request. You are responsible for ensuring that you have the right to access anything you stream in your jurisdiction.

## License and attribution

ZPlay is licensed under the [GNU General Public License v3.0](LICENSE).

ZPlay is a modified version of **[PlayTorrio V3](https://github.com/ayman708-UX/PlayTorrioV3)**, © 2026 Ayman ([@ayman708-UX](https://github.com/ayman708-UX)), and is distributed under the same license. The original project and its full corresponding source remain available at [github.com/ayman708-UX/PlayTorrioV3](https://github.com/ayman708-UX/PlayTorrioV3).

Poppins and Playfair Display are bundled under the SIL Open Font License 1.1.

Film metadata and images can be sourced from [The Movie Database (TMDb)](https://www.themoviedb.org). This product uses the TMDB API but is not endorsed or certified by TMDB.

<p align="center">
  Maintained by <a href="https://github.com/tzero86">tzero86</a>
</p>
