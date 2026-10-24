# Security & Performance Audit: PlayTorrioZero (ZPlay)

**Date:** 2026-10-24
**Auditor:** OpenCode agent (DeepSeek V4.1 Flash), using the `audit-full` skill
**Mode:** Security + Performance + Dependencies
**Scope:** Entire repository at commit `a239d9e` (`v1.6.16+3053`), 2026-10-20
**Status:** Read-only review. No code was changed.

## Summary

| Metric | Value |
|--------|-------|
| Dart files | 421 |
| Dart lines | 172,626 |
| Direct dependencies | 62 declared, 140 hosted packages resolved |
| OSV advisories | 0 (Pub ecosystem, querybatch) |
| Security findings | 5 High, 6 Medium, 5 Low |
| Performance findings | 4 High, 5 Medium, 3 Low |

### Findings Overview

| Severity | Security | Performance |
|----------|----------|-------------|
| CRITICAL | 0 | 0 |
| HIGH | 5 | 4 |
| MEDIUM | 6 | 5 |
| LOW | 5 | 3 |
| **Total** | **16** | **12** |

**Overall Health Score: 5/10 (C)**  
Breakdown: security 5/10, performance 5/10, dependencies 9/10. Applying the `audit-full` severity formula literally gives 2.7/10 for security and 4.2/10 for performance; the scores above are adjusted for reachability, because the highest-impact issues sit in optional, user-installed subsystems rather than in a remotely reachable service.

**Bottom line:** the app's foundations are stronger than its integrations. Secret storage, backups, diagnostics, and dependency hygiene are good. The two dominant risks are trust boundaries: the CloudStream plugin/runtime pipeline executes unsigned third-party code, and the updater installs and runs downloads without verifying integrity. Performance is dominated by four screens (EPUB reader, music, Home, manga reader) doing per-event disk or network work that should be coalesced.

## What Is Solid

These were checked and should not be regressed:

- **Credentials at rest:** `SecureStore` uses the platform keystore with a migration path. No first-party upstream API keys are hardcoded; `legacy_upstream_credentials.dart` is deliberately blank. The one exception is a third-party Qobuz worker token (S-13).
- **Profile export:** AES-256-GCM with PBKDF2 and careful redaction of tokens before export.
- **Backups:** secret fields are redacted and the archive is encrypted, not just zipped.
- **Android OTA FileProvider:** scoped to the `ota_update/` subdirectory (`android/app/src/main/res/xml/filepaths.xml:3`).
- **Diagnostics:** secrets are scrubbed and the bundle is not uploaded automatically.
- **Trailer WebView:** local wrapper plus correct JS/HTML escaping of the video key; no JavaScript channels.
- **CI:** `flutter analyze`, format check, tests, and a Windows smoke build run in `.github/workflows/quality.yml`; tagged Android releases hard-fail without the release keystore.
- **Dependencies:** 140 hosted packages queried against OSV on 2026-10-24; zero known advisories.

## Security Findings

### HIGH

#### S-01: CloudStream executes unsigned third-party code with full app privileges
- **Category:** Security / supply chain
- **OWASP:** A08:2021 Software and Data Integrity Failures
- **Files:** `lib/services/cloudstream/marketplace/cloudstream_marketplace_service.dart:98-119`, `lib/services/cloudstream/cloudstream_manager.dart:620-695`, `lib/services/cloudstream/runtime/cloudstream_downloader.dart:22-47`, `android/app/src/main/kotlin/io/github/tzero86/zplay/CloudStreamNativeBridge.kt:87-170`, `lib/services/cloudstream/runtime/cloudstream_sidecar.dart:39-45`
- **Description:** The marketplace scrapes repositories from the unofficial `cloudstream-apk.com` site. Extensions are downloaded from arbitrary repo-supplied URLs and executed in-process: on Android via `DexClassLoader`, on desktop as JARs run by a JVM launched with `-noverify`. Runtime downloads (runtime host APK, bridge JAR, JRE, dex2jar) come from `releases/latest` URLs with no checksum or signature verification.
- **Impact:** A malicious repository, a compromised upstream release, or a MITM on a non-TLS repo yields arbitrary code execution with the app's permissions: stored tokens, debrid keys, files, network access, and session data. There is no sandbox, signature check, or explicit risk disclosure beyond the normal install confirmation.
- **Evidence:**
  ```dart
  // cloudstream_downloader.dart:23-27 - versionless "latest" downloads, no hash
  'https://github.com/.../releases/latest/download/anymex_runtime_host.apk';
  'https://github.com/.../releases/latest/download/anymex_desktop_runtime.jar';
  ```
  ```kotlin
  // CloudStreamNativeBridge.kt:127-130
  val loader = object : DexClassLoader(
      cacheApk.absolutePath,
      optimizedDir.absolutePath,
      libsDir.absolutePath,
      context.classLoader)
  ```
  ```dart
  // cloudstream_sidecar.dart:45
  '-noverify',
  ```
- **Remediation:** Pin runtime artifacts by version and SHA-256; verify before execution. Sign extension manifests and verify with an embedded public key. Add an explicit "this runs third-party code with full app access" consent screen. Long term, move plugin execution out-of-process behind a narrow IPC surface, and remove `-noverify`. If these are not feasible, stop auto-listing third-party repositories and remove the marketplace scraper.
- **Effort:** High

#### S-02: Zip-slip in runtime archive extraction (Dart and Kotlin)
- **Category:** Security / path traversal
- **OWASP:** A01:2021 Broken Access Control
- **Files:** `lib/services/cloudstream/runtime/cloudstream_downloader.dart:249-282`, `android/app/src/main/kotlin/io/github/tzero86/zplay/CloudStreamNativeBridge.kt:172-203`
- **Description:** Archive entry names are joined to a target directory without canonicalization. In Dart, JRE/dex2jar `.zip` and `.tar.gz` entries are extracted with `File(p.join(targetDir, filename))`. In Kotlin, APK entries under `lib/<abi>/` are written to `File(targetDir, libName)` and then marked executable. An entry named `../../payload` escapes the target directory.
- **Impact:** Arbitrary file write with app permissions; the Kotlin path additionally sets the executable bit, so a written `.so` can be loaded on the next runtime start. A malicious or compromised runtime archive turns into code execution.
- **Evidence:**
  ```dart
  // cloudstream_downloader.dart:257-262
  final filename = file.name;
  File(p.join(targetDir, filename))
    ..createSync(recursive: true)
    ..writeAsBytesSync(data);
  ```
  ```kotlin
  // CloudStreamNativeBridge.kt:192-203
  val libName = entry.name.substring(prefix.length)
  val outFile = File(targetDir, libName)
  ...
  outFile.setExecutable(true, false)
  ```
- **Remediation:** Resolve each entry against the canonical target root and reject anything that is not a strict child:
  ```dart
  final root = Directory(targetDir).absolute.path;
  final out = File(p.join(root, filename)).absolute.path;
  if (!p.isWithin(root, out)) throw StateError('archive entry escapes root');
  ```
  Apply the same check in Kotlin using `canonicalPath`, and never chmod extracted files executable unless the archive itself was verified.
- **Effort:** Low

#### S-03: TLS certificate validation disabled in five HTTP clients
- **Category:** Security / transport
- **OWASP:** A02:2021 Cryptographic Failures
- **Files:** `lib/services/books/book_download_service.dart:94`, `lib/services/music/music_download_service.dart:370,393`, `lib/services/subtitles/subtitlecat_service.dart:48`, `lib/services/subtitles/providers/subtitlecat_provider.dart:16`, `lib/services/anime/extractors/tryembed_extractor.dart:57`
- **Description:** Each client sets `badCertificateCallback = (cert, host, port) => true`, which accepts any certificate for any host. The book downloader is the most exposed: it applies this to `book.downloadUrl` and `book.link`, both supplied by remote metadata.
- **Impact:** A network attacker can impersonate the book API, music CDN, subtitle site, or extractor and substitute content or redirect downloads. For books, attacker-controlled bytes are written to disk and opened by a reader. This also makes the "HTTPS" protection on these paths cosmetic.
- **Evidence:**
  ```dart
  // book_download_service.dart:93-94
  final client = HttpClient();
  client.badCertificateCallback = (cert, host, port) => true;
  ```
- **Remediation:** Remove the callbacks. If a specific upstream has a broken chain, scope an exception to that exact host and pin its certificate/public key, never to all hosts. For extractors that only need HTML, use the normal `http` client.
- **Effort:** Low

#### S-04: Update installer has no integrity verification and auto-runs downloads
- **Category:** Security / supply chain
- **OWASP:** A08:2021 Software and Data Integrity Failures
- **Files:** `lib/services/updater/app_updater_service.dart:149-264`, `lib/widgets/updater/update_dialog.dart:379-433,493-631`
- **Description:** The updater selects a `browser_download_url` from the GitHub release API and installs it. Android calls `OtaUpdate().execute(...)` without a checksum, so the plugin's `CHECKSUM_ERROR` branch can never trigger. Windows downloads an `.exe` to the Downloads folder and immediately runs it with `Process.start(..., detached)`.
- **Impact:** A compromised GitHub account/release or a TLS interception yields code execution. Android's APK signature check is a partial mitigation (an APK signed with a different key will not install), but the app itself does not verify the signer, and Windows has no signature check at all.
- **Evidence:**
  ```dart
  // update_dialog.dart:387-392 - no checksum argument
  _otaSub = OtaUpdate()
      .execute(widget.updateInfo.downloadUrl,
          destinationFilename: 'ZPlay_${widget.updateInfo.latestVersion}.apk')
  ```
  ```dart
  // update_dialog.dart:624-630
  await Process.start(installer.path, const [],
      mode: ProcessStartMode.detached);
  await Future.delayed(const Duration(seconds: 2));
  exit(0);
  ```
- **Remediation:** Publish a `SHA256SUMS` asset with each release and verify the downloaded bytes before install. On Android, compare the APK signer certificate fingerprint with a pinned value. On Windows/macOS, code-sign the installer and verify the signature (or at minimum show the expected hash and require confirmation). Do not auto-run a freshly downloaded executable.
- **Effort:** Medium

#### S-05: Remote extension name reaches filesystem paths and a shell
- **Category:** Security / path traversal, command injection surface
- **OWASP:** A01:2021 Broken Access Control, A03:2021 Injection
- **Files:** `lib/services/cloudstream/cloudstream_manager.dart:613-666,716-733,814-819`
- **Description:** `extName` is `source.internalName ?? source.name`, both supplied by repository metadata. It is interpolated into `temp_$extName`, `$extName.cs3`, and `$extName.jar` under the extensions directory, and the same names are used for deletion in `uninstallExtension`. The resulting paths also flow into `Process.run` with `runInShell: Platform.isWindows`.
- **Impact:** A malicious repo entry can write `.cs3`/`.jar` files outside the extensions directory, and can recursively delete arbitrary directories via the `temp_$extName` path. On Windows, shell metacharacters in the path may be interpreted by `cmd.exe`; even without that, the traversal is confirmed.
- **Evidence:**
  ```dart
  // cloudstream_manager.dart:613-616
  final extName = source.internalName ?? source.name;
  final tempDir = Directory(p.join(extDir.path, 'temp_$extName'));
  if (await tempDir.exists()) await tempDir.delete(recursive: true);
  ```
  ```dart
  // cloudstream_manager.dart:814-819
  final process = await Process.run(
    dex2jarPath, ['--force', dexPath, '-o', outJarPath],
    environment: env, runInShell: Platform.isWindows);
  ```
- **Remediation:** Sanitize `internalName`/`name` to `[A-Za-z0-9._-]`, reject empty names, `.`/`..`, and separators; use a random UUID for the temp directory; resolve the final path and assert it is inside `extDir`; use `runInShell: false` and pass arguments directly.
- **Effort:** Low

### MEDIUM

#### S-06: Book download path is built from remote `md5` without validation
- **Category:** Security / path traversal
- **Files:** `lib/services/books/book_download_service.dart:41-45,74`, `lib/models/book/book_result.dart:47`
- **Description:** `BookResult.md5` comes from remote JSON and is used directly in `p.join(dir.path, '$md5.$ext')`. The file type is stripped of dots, but `md5` is not validated. The same path is used for download, existence checks, and deletion.
- **Impact:** A malicious or compromised book API can cause writes and deletes outside the books directory, with the downloaded bytes appended by `.epub`/`.pdf`. Impact is limited to files with that suffix and requires a hostile metadata source, hence Medium.
- **Remediation:** Require `^[a-fA-F0-9]{32}$` for `md5` (or a URL-safe opaque id with a strict allowlist), then canonicalize and confirm the path stays under the books directory.
- **Effort:** Low

#### S-07: IPTV credentials are stored in plaintext, sent over cleartext, and logged
- **Category:** Security / credential handling
- **OWASP:** A02:2021 Cryptographic Failures, A09:2021 Security Logging Failures
- **Files:** `lib/services/iptv/iptv_storage.dart:44-52,329-347`, `lib/services/iptv/iptv_network.dart:16-40,93-94,120-122`, `lib/pages/player/player_screen.dart:1081-1086,1154`
- **Description:** Portal URL, username, and password are serialized as JSON into `SharedPreferences` under `pt_iptv_verified_portals`; password-derived pref keys are stored in clear (`'${p.url}|${p.username}|${p.password}'`). Xtream credentials are interpolated into query strings, and `http://` portals are accepted. Player startup logs the raw source URL and resolved debrid URL, both of which can contain credentials.
- **Impact:** Anyone with backup, root, ADB, or filesystem access can read the credentials. A network observer can capture them from an HTTP portal. Logcat/device logs may retain them indefinitely.
- **Remediation:** Move portal credentials to `SecureStore`; use a salted hash for pref keys, not the raw password; require HTTPS or warn explicitly; remove URL logging or redact userinfo/query/path segments.
- **Effort:** Medium

#### S-08: Provider secrets are compiled into shipped binaries
- **Category:** Security / secret management
- **OWASP:** A05:2021 Security Misconfiguration
- **Files:** `lib/services/config/env_service.dart:74-109`, `.github/workflows/build.yml:42-50,166-174,253-261,353-361,429-437,504-512`
- **Description:** CI writes `.env` from GitHub Secrets and passes `--dart-define-from-file=.env` to every release build. `EnvService` reads Trakt client ID/secret, Simkl client ID/secret, TMDb API key, and Discord app ID from compile-time defines. To the extent those fields are populated in CI, they are compiled into the shipped binary; AOT compilation does not hide these strings.
- **Impact:** Anyone who downloads the app can extract the values. A Trakt/Simkl client secret allows impersonating the application; TMDb/Discord keys allow quota abuse. Public client IDs are not secret, but client secrets are.
- **Remediation:** Treat installed-app client IDs as public and remove client secrets entirely (use PKCE/public clients). Move any privileged calls behind a small backend proxy. Rotate any secret that has shipped. Keep `.env` out of CI logs and artifacts.
- **Effort:** Medium

#### S-09: Cleartext traffic is allowed globally on Android, iOS, and macOS
- **Category:** Security / transport policy
- **OWASP:** A02:2021 Cryptographic Failures
- **Files:** `android/app/src/main/AndroidManifest.xml:59`, `ios/Runner/Info.plist:7-10`, `macos/Runner/Info.plist:7-10`
- **Description:** Android sets `android:usesCleartextTraffic="true"`; both Apple targets set `NSAllowsArbitraryLoads` plus `NSAllowsLocalNetworking`. The comments in the manifest indicate this is intentional for IPTV and arbitrary stream sources.
- **Impact:** Every HTTP URL accepted by addons, IPTV portals, or extractors is permitted, including credential-bearing requests. It removes the platform's defense-in-depth and makes downgrade attacks invisible.
- **Remediation:** Use an Android `network_security_config.xml` that permits cleartext only for explicitly user-added local/IPTV hosts (or only in debug), and per-domain ATS exceptions rather than a global `NSAllowsArbitraryLoads`. Enforce HTTPS for first-party APIs.
- **Effort:** Medium

#### S-10: Remote response bodies are unbounded
- **Category:** Security / denial of service
- **OWASP:** A04:2021 Insecure Design
- **Files:** `lib/services/iptv/iptv_network.dart:16-33,1105-1109`, `lib/services/subtitles/subtitle_extractor.dart:70-72,110-118`, `lib/services/stream/stream_service.dart:528-538`, `lib/services/books/book_download_service.dart:96-136`
- **Description:** Several clients read an entire response into memory (`bytesToString()`, `response.body`, `jsonDecode`) with only timeouts, no size cap. Zip/gzip subtitle archives are decoded with no decompressed-size limit. The ~50 scraper site clients follow the same pattern.
- **Impact:** A hostile or compromised portal, addon, subtitle provider, or scraper target can return a multi-gigabyte body or a compression bomb, causing memory exhaustion, ANR, or a crash. On mobile this is an easy remote DoS.
- **Remediation:** Cap `Content-Length` and streamed bytes (for example 2-10 MB for JSON/HTML, 50 MB for books/subtitles), enforce decompressed-size limits before decoding, and fail closed. Add per-host concurrency limits for scraper fan-out.
- **Effort:** Medium

#### S-11: Remote playlists, addons, and APIs control request targets and receive credentials
- **Category:** Security / SSRF, credential exposure
- **OWASP:** A10:2021 Server-Side Request Forgery, A01:2021 Broken Access Control
- **Files:** `lib/services/download/hls_download_engine.dart:228,261-269,287`, `lib/services/music/convertytmp3_client.dart:26-47,56-60`, `lib/services/addon/addon_url_resolver.dart:32-46`, `lib/services/stream/stream_service.dart:524-526`, `lib/models/stream/stream_model.dart:90-101`, `lib/pages/player/watch_screen.dart:314-338,1292-1294`
- **Description:** HLS segment/key/init URIs are resolved with `baseUri.resolve(...)` and fetched, so a playlist can target loopback/LAN addresses. The music conversion API returns `convertURL`/`redirectURL`/`progressURL`/`downloadURL`, and the app follows them while attaching `Authorization: Bearer <key>`. Addon base URLs get `{realdebrid}`/`{torbox}` placeholders replaced with the user's saved key, and addon-supplied `headers`/`proxyHeaders.request` are applied verbatim, including `Host`, `Cookie`, and `Authorization`. `externalUrl` is passed to the OS with no scheme allowlist.
- **Impact:** A malicious addon, playlist, or conversion response can make the app fetch internal services (SSRF), exfiltrate a debrid bearer token, override request headers, or invoke arbitrary OS URL schemes. These require a user-installed addon or a hostile stream source, hence Medium.
- **Remediation:** For HLS, allow only `http`/`https` and reject private, loopback, and link-local addresses unless the original source was local. Do not substitute secrets into addon-supplied URLs; proxy debrid requests through a first-party endpoint or require the user to configure the full URL. Allowlist headers (`User-Agent`, `Referer`, `Origin`, `Range`, `Accept`) and strip `Host`/`Cookie`/`Authorization`. Allow only `https`/`http`/`stremio` schemes for external opens.
- **Effort:** Medium

### LOW

#### S-12: MegaProxy token is predictable and CORS is wildcard
- **Files:** `lib/services/anime_arabic/mega_proxy.dart:34-87,131-140`
- **Description:** The loopback server issues tokens as `microsecondsSinceEpoch_seq` and serves `/v/<token>.mp4` with `Access-Control-Allow-Origin: *`. The `_files` map has no eviction.
- **Impact:** A local process, or a web page that guesses the port/token, can fetch proxied streams while the proxy is alive. Content is transient and not highly sensitive, so Low.
- **Remediation:** Use `Random.secure()` for 128-bit tokens, check the `Origin` header, restrict CORS to the app's own origin (or omit it for native clients), and evict entries after playback ends.
- **Effort:** Low

#### S-13: Hardcoded Qobuz session token in source
- **Files:** `lib/services/music/qobuz_music_service.dart:53-57`
- **Description:** A worker endpoint URL contains a literal session token in its path (`/u/4opn…`). The full value is in the source at the line above.
- **Impact:** The token is public in the repository and in shipped binaries. Impact depends on what the worker authorizes; at minimum it is an uncontrolled shared credential.
- **Remediation:** Remove the literal, rotate it, and obtain a per-install token from the service. If the endpoint is intentionally public, document that and drop the token-shaped path.
- **Effort:** Low

#### S-14: Debug logging leaks cookies and stream URLs
- **Files:** `lib/services/scraper/sites/hindmoviez.dart:681,694`, `lib/services/scraper/sites/fourkhdhub.dart:92,142,174,221,228,236`, `lib/services/subtitles/subtitle_extractor.dart:31-40`
- **Description:** `print`/`debugPrint` statements emit `set-cookie` headers, session cookies, search URLs, redirect URLs, and stream URLs. `print` is not stripped in release builds.
- **Impact:** Cookies and signed URLs persist in logcat/console logs, where other apps or support tooling can read them. Low because it needs log access.
- **Remediation:** Remove the cookie/URL prints or route them through a redacting logger gated on `kDebugMode`. Never log `Set-Cookie` or query strings that contain tokens.
- **Effort:** Low

#### S-15: Persisted download task paths are trusted on reload
- **Files:** `lib/services/download/download_service.dart:58-95,376,592-610`
- **Description:** `zplay_download_tasks.json` stores `targetFilePath`; the service writes, renames, copies, and deletes that path without re-validating it is under the downloads directory.
- **Impact:** A local attacker who can edit app storage can turn a queued task into an arbitrary write/delete. Low because it requires local access.
- **Remediation:** Validate persisted paths against the downloads root on load, and regenerate them from task id/name rather than trusting the stored absolute path.
- **Effort:** Low

#### S-16: TorrServer is started without an explicit bind address or auth
- **Files:** `lib/services/stream/torrent_stream_service.dart:184-198`; package args at `torrserver_flutter-0.0.7/lib/src/torrserver_controller_subprocess.dart:70-76`
- **Description:** The app calls `_controller.start()` with no `--ip` or `--httpauth`. The client connects to `127.0.0.1`, but the server's bind address is determined by the upstream binary's default. The package passes only `-p <port> -d <dir>`.
- **Impact:** If TorrServer defaults to `0.0.0.0`, any LAN peer can reach its unauthenticated API and add torrents or read cached pieces. This is conditional on the upstream default, so Low/informational until verified.
- **Remediation:** Pass `--ip 127.0.0.1` (and `--httpauth` if the version supports it) via `extraArgs`, then verify with `netstat`/`ss` on each platform.
- **Effort:** Low

### Notes / Accepted Risks

- `android/app/src/main/res/xml/filepaths.xml:3` exposes only `ota_update/` through the FileProvider. Scoped correctly; keep it that way.
- The trailer WebView uses `JavaScriptMode.unrestricted`, but it loads a local wrapper, has no JavaScript channel, and escapes the video key (`trailer_modal.dart:272-285`). Current risk is low; adding a `NavigationDelegate` that blocks non-local navigations would harden it.
- `http://` addon URLs are accepted (`addon_manager.dart:336-386`). This is user-initiated, but it should warn or require confirmation.

## Performance Findings

The prior audit's already-fixed items were re-checked and are not repeated here. Notably, startup services were split after `runApp` (`lib/main.dart:107-115`), the home carousel and audiobook timers are cancelled in `dispose`, and `memCacheWidth` is now used at 60 sites. The remaining hot spots are per-event work, not missing micro-optimizations.

### HIGH

#### P-01: EPUB reader persists progress on every scroll event
- **Files:** `lib/pages/books/epub_reader_page.dart:56,70-72,171-194`, `lib/services/books/continue_reading_service.dart:52-69`, `lib/services/storage/json_document_store.dart:123-137,209-219`
- **Description:** `_scrollController.addListener(_onScrollChanged)` calls `_saveProgress()` for every scroll notification. Each save copies the reading list, notifies Home via `activeItems.value`, then enqueues a store write that parses the existing document, computes a SHA-256 checksum, and performs two `SharedPreferences` writes (backup + primary).
- **Impact:** At 60 scroll events/s this is ~60 JSON decode/encode + SHA-256 + 2 platform-channel writes per second, serialized into an ever-growing `_writeChains` queue. It causes reader stutter, battery drain, and I/O churn, and it wakes Home on every tick.
- **Evidence:**
  ```dart
  // epub_reader_page.dart:70-72
  void _onScrollChanged() {
    _saveProgress();
  }
  ```
- **Remediation:** Save on `dispose`, chapter change, and a 2-second debounce/`ScrollEndNotification` instead of every scroll tick. In `JsonDocumentStore`, coalesce writes with a dirty flag and flush every 5-10 seconds.
- **Effort:** Low

#### P-02: Music page rebuilds its entire tree on every player position tick
- **Files:** `lib/pages/music/music_page.dart:135,163-165,765`, `lib/services/music/music_player_controller.dart:212-216`
- **Description:** The controller calls `notifyListeners()` from `player.stream.position.listen`. `MusicPage` responds with an unconditional `setState(() {})`, rebuilding the ~5,000-line page, its tabs, home view, and expanded player. Only the seek bar and lyrics need position updates.
- **Impact:** Sub-second full-page builds and layout passes, even when the music tab is hidden in the shell's `IndexedStack`. This is the main reason the music tab is the heaviest screen.
- **Remediation:** Expose position as a separate `ValueNotifier<Duration>` and wrap only the seek bar/lyrics in `ValueListenableBuilder`. Throttle position notifications to 4-10 Hz.
- **Effort:** Medium

#### P-03: Music page nests shrink-wrapped scrollables inside its page `ListView`
- **Files:** `lib/pages/music/music_page.dart:645,1166,1223,1256,1307,1375,1647,1719,3508`
- **Description:** Multiple `ListView`/`GridView` use `shrinkWrap: true` with `NeverScrollableScrollPhysics` inside the page scroller. `shrinkWrap` forces every child to be built and laid out on each parent build.
- **Impact:** Combined with P-02, the full music catalog is rebuilt and laid out many times per second. It also defeats lazy list building.
- **Remediation:** Convert the page to a `CustomScrollView` with slivers, or give the inner grids bounded heights and keep them lazy. Avoid `shrinkWrap` for lists with more than a screen of content.
- **Effort:** Medium

#### P-04: Hidden Home page rebuilds and makes four network calls while the user is elsewhere
- **Files:** `lib/pages/home/home_page.dart:473-476,646-657,787-816`, `lib/shell/app_shell.dart:636`
- **Description:** Home listens to `MyListService.items` and `ContinueWatchingService.activeItems` for its entire lifetime. Every progress tick fires a post-frame `setState`, and an 800 ms debounce then calls `_refreshSimilarSections()`, which fans out four `forceRefresh` requests (list, continue-watching, Trakt, Simkl). The shell keeps Home mounted in an `IndexedStack`.
- **Impact:** Reading a book or watching a video triggers continuous background rebuilds and recurring network traffic, competing with playback and wasting battery/data.
- **Remediation:** Gate the expensive listener path and the four-request refresh on the active shell slot (`_shellController?.current.value == ShellSlot.home`), and mark the page dirty instead of rebuilding it while hidden. The existing `_onSlotChanged` handler (`home_page.dart:516-521`) already runs on return to Home, so flush the dirty state there. Cache the four sections between visits.
- **Effort:** Low

### MEDIUM

#### P-05: Five-second progress timers rewrite the same JSON document
- **Files:** `lib/pages/player/player_screen.dart:1324-1325`, `lib/pages/audiobooks/audiobook_player_screen.dart:99-101`, `lib/services/books/continue_reading_service.dart:52-69`
- **Description:** Both players save progress every 5 seconds, landing in the same parse + checksum + two-write path as P-01 and notifying Home.
- **Impact:** 12 writes/minute per active player, each with a SHA-256 and two platform-channel writes. It is unnecessary because a crash loses at most a few seconds of playback.
- **Remediation:** Save every 30 seconds, on pause, on seek, and on dispose. Let the store coalesce writes.
- **Effort:** Low

#### P-06: Manga reader precaches an entire chapter and saves on a fixed 900 px pitch
- **Files:** `lib/pages/manga/manga_reader_page.dart:172-192,228-239`
- **Description:** On chapter open, the reader queues `precacheImage` for every page thumbnail in the chapter (40-100 images) in one synchronous loop, plus ±2 full-width pages. In webtoon mode it estimates the current page as `offset / 900` and saves progress whenever that estimate changes.
- **Impact:** Visible freeze and memory spike on chapter open from decoding the whole chapter at once. The fixed pitch does not match variable image heights, so the page indicator is often wrong and progress saves fire repeatedly during continuous scroll.
- **Remediation:** Precache a window of ~8 pages around the current page, not the whole chapter. Derive page extents from image aspect ratios (or use `ScrollablePositionedList`), and debounce the progress save.
- **Effort:** Medium

#### P-07: Synchronous filesystem stats inside list item builders
- **Files:** `lib/pages/audiobooks/audiobooks_page.dart:1193,1302`, `lib/pages/audiobooks/generate_audiobook_screen.dart:1027,1260`, `lib/pages/music/music_page.dart:5022`, `lib/pages/downloads/downloads_page.dart:60`
- **Description:** Item widgets call `File(path).existsSync()` during build to decide whether to show a local cover.
- **Impact:** One blocking `stat` per row per rebuild. On a scrolled grid this can be dozens to hundreds of syscalls per frame on Android/Windows.
- **Remediation:** Resolve existing cover paths once when the list/jobs load into a `Set<String>`, pass the result into the item widgets, and refresh on file-system events or after downloads complete.
- **Effort:** Low

#### P-08: Two independent update checks race at startup
- **Files:** `lib/main.dart:195-201`, `lib/pages/home/home_page.dart:488-491,578-606`
- **Description:** `ZPlayApp` schedules `_checkForUpdates()` 1.5 s after the first frame; Home's `_runStartupDialogs()` also calls `_checkAutoUpdate()`. Each has its own static guard, so they are not mutually exclusive.
- **Impact:** Two release-manifest requests in the first two seconds and two dialog code paths that can race, producing duplicate prompts.
- **Remediation:** Make the app root the single owner of update checks; remove the Home path. Keep one "already checked this session" guard.
- **Effort:** Low

#### P-09: IPTV portal search rebuilds the full browser on every keystroke
- **Files:** `lib/pages/iptv/iptv_portal_browser_page.dart:932,1124`
- **Description:** `onChanged: (v) => setState(() => _searchQuery = v)` has no debounce. Each keystroke rebuilds both panes and re-runs channel/category projections over portals that routinely carry thousands of streams.
- **Impact:** Typing in search becomes janky on TV/low-end hardware.
- **Remediation:** Debounce 150-250 ms and filter into a cached list; keep the text field's immediate value local to the field.
- **Effort:** Low

### LOW

#### P-10: Player settings extraction blocks the first frame on first launch
- **Files:** `lib/main.dart:90-92`, `lib/services/player/player_settings.dart:619-691,694-819`
- **Description:** `PlayerSettings.initialize()` is awaited before `runApp`; it extracts the libass font and 11 shader files (9 Anime4K + 2 FSR) to disk on first run (subsequent runs only stat them).
- **Impact:** First-launch startup does ~12 asset loads and writes before any UI appears. Small but avoidable.
- **Remediation:** Defer extraction to after `runApp` (idle callback or first player open); the paths are only needed for playback/subtitles.
- **Effort:** Low

#### P-11: Expanded music player decodes a full-resolution cover under a 50-sigma blur
- **Files:** `lib/pages/music/music_page.dart:4193-4202`
- **Description:** A `CachedNetworkImage` with no `memCacheWidth` is placed under `BackdropFilter(ImageFilter.blur(sigmaX: 50, sigmaY: 50))` and 0.85 opacity.
- **Impact:** A 1400×1400 cover is fully decoded and mipmapped for a backdrop that is visually indistinguishable from a 256 px version, then blurred each frame the modal is open.
- **Remediation:** Set `memCacheWidth: 256` (and `memCacheHeight: 256`) on the backdrop image.
- **Effort:** Low

#### P-12: Unhandled Trakt future, uncached `Image.network`, and no video repaint boundary
- **Files:** `lib/pages/home/home_page.dart:907-911`, `lib/widgets/player/player_loading_overlay.dart:145-149,178-183`, `lib/pages/player/player_screen.dart:3866-3884,3993,4023`
- **Description:** `unawaited(traktPublic.then(...))` has no `catchError`, so a failure becomes an unhandled async error and the loaded flag is never set. The loading overlay uses `Image.network` (memory cache only), so posters re-download across runs. `mk.Video` has no `RepaintBoundary`; on the mpv path it is a `Texture` with its own layer, so the win is mainly on the Media3/platform-view branch.
- **Impact:** Debug noise/retry loops and repeated poster downloads are the concrete costs; the missing boundary is minor on the mpv path and matters more for platform-view composition. Each is small on its own.
- **Remediation:** Add `catchError` and set the loaded flag in `finally`; use `CachedNetworkImage` for posters; wrap the video surface (or at least the overlay) in a `RepaintBoundary`.
- **Effort:** Low

## Architecture & Trust Boundaries

```
UI pages / widgets
  │
  ├── SecureStore (keystore)        ← tokens, debrid keys (good)
  ├── SharedPreferences / files     ← IPTV creds, reading progress (plaintext)
  │
  ├── AddonManager ──► addon baseUrl ──► {debrid} key substitution
  │                      └── headers / externalUrl passed through
  ├── IptvClient ─────► portal (http/https) + credentials in query string
  ├── BookDownloadService ──► remote metadata (md5) + TLS verification OFF
  ├── CloudStreamManager ──► repo metadata ──► .cs3 ──► DEX/JVM in-process
  │      └── runtime downloads (no hash) ──► zip/tar extraction (zip-slip)
  ├── HlsDownloadEngine ──► playlist-controlled URIs (SSRF surface)
  ├── Music conversion API ──► server-controlled URLs + Bearer key
  ├── AppUpdaterService ──► GitHub release ──► auto-run .exe / install APK
  └── Loopback services ──► MegaProxy (CORS *), TorrServer (bind TBD)
```

The first-party core (UI, settings, storage, backup) is reasonably layered. Risk concentrates where remote metadata crosses into filesystem paths, process execution, or credential-bearing requests. The two boundaries that deserve design-level work are the CloudStream runtime and the updater.

## Dependency Summary

OSV `querybatch` against the Pub ecosystem was run for 140 hosted packages resolved in `pubspec.lock` on 2026-10-24. **No advisories were returned.**

| Package | Resolved | Notes |
|---------|----------|-------|
| `archive` | 4.2.0 | Used for runtime/subtitle archives; extraction needs containment (S-02). |
| `http` | 1.6.0 | Clean. |
| `webview_flutter` | 4.14.1 | Trailer modal only; no JS channels. |
| `media_kit` / `media_kit_video` | 1.1.11 (git pin `11d02cb`) | Pinned fork; reproducible, but fork maintenance is a supply-chain consideration. |
| `pdfrx` | 2.6.1 | Clean. |
| `ota_update` | 7.1.0 | Checksum support exists but is not used (S-04). |
| `flutter_secure_storage` | 10.3.4 | Keystore-backed; good. |
| `torrserver_flutter` | 0.0.7 | Pre-1.0 engine wrapper; verify bind/auth defaults (S-16). |
| `pointycastle` | 3.9.1 | Profile encryption; clean. |
| `cached_network_image` | 3.4.1 | 92 uses, 60 with `memCacheWidth`. |

License compliance was not scanned; that is a separate pass. No unused-dependency analysis was performed beyond the resolution check. The `media_kit` modules are git-pinned rather than hosted, so they are not covered by the Pub advisory feed; the pinned commit was not reviewed beyond its integration points.

## Recommendations

### Immediate (this sprint)

1. Add SHA-256 verification for updater downloads and CloudStream runtime artifacts; pin versions instead of `releases/latest`. On Windows, verify a code signature before running an installer (S-01, S-04).
2. Fix zip-slip in both extractors with canonical-path containment (S-02).
3. Sanitize `internalName`/`name` and book `md5`, use UUID temp directories, and remove `runInShell` (S-05, S-06).
4. Delete the five `badCertificateCallback` overrides and scope any unavoidable exception to one host (S-03).
5. Redact URL logging and move IPTV credentials to `SecureStore` (S-07, S-14).
6. Throttle EPUB progress saves, scope the music position listener, and gate Home refresh to the active tab (P-01, P-02, P-04).

### Short-term (this quarter)

1. Replace global cleartext/ATS bypasses with per-domain network security configuration (S-09).
2. Harden the addon boundary: strip secret-bearing headers, stop substituting debrid keys into addon URLs, allowlist external schemes (S-11).
3. Add response-size and decompression limits to IPTV, scrapers, subtitles, and stream fetching (S-10).
4. Remove provider client secrets from the binary; use PKCE/public clients or a backend proxy (S-08).
5. Coalesce progress writes in `JsonDocumentStore`; bound manga precache; cache `existsSync` results; debounce IPTV search; make the updater single-owner (P-05 through P-09).
6. Replace the MegaProxy token with `Random.secure()` and restrict CORS (S-12).

### Long-term (backlog)

1. Move CloudStream plugin execution out-of-process behind a narrow, permissioned IPC surface; sign extensions and publish a clear risk disclosure. If that is not viable, reconsider shipping the marketplace at all (S-01).
2. Code-sign and notarize Windows/macOS builds; verify signatures in the updater (S-04).
3. Add a performance regression budget for the four hot screens (frame time, writes/minute, network calls while idle).
4. Add a CI security gate: `flutter analyze`, OSV scan, secret scan, and a check that `badCertificateCallback`/`usesCleartextTraffic` do not reappear.

## Appendix

### Methodology

- Read-only static review of 421 Dart files (172,626 lines) plus Android Kotlin, manifests, plists, and CI workflows at commit `a239d9e`.
- The codebase exceeds the skill's single-context budget, so a map-reduce-style review was used instead of one 1M-token load: repository reconnaissance, secret/credential review, CloudStream/updater/IPTV/addon/backup deep reads, and two parallel inventories (security sinks, performance hot spots), followed by source-level verification of every reported finding.
- Cross-checked every reported finding against the source before inclusion. One performance claim (off-screen ambient animation) was rejected because `TickerMode` already pauses inactive shell slots (`lib/shell/app_shell.dart:525-526`).
- Dependency check: OSV `querybatch` for 140 hosted Pub packages.
- Prior audit claims were re-tested; fixed items were excluded from the findings.

### Limitations

- No dynamic testing, fuzzing, or penetration test was performed.
- No device profiling; performance findings are based on code paths and call frequency, not measured frame times.
- Platform plugin internals (notably `torrserver_flutter` and the CloudStream runtime host) were only reviewed at the integration boundary.
- Some findings depend on runtime configuration or upstream defaults (S-16, the impact of S-01's marketplace).
- License compliance and unused-dependency analysis were out of scope.

### Key Files Reviewed

`lib/main.dart`, `lib/shell/app_shell.dart`, `lib/pages/home/home_page.dart`, `lib/pages/music/music_page.dart`, `lib/pages/books/epub_reader_page.dart`, `lib/pages/manga/manga_reader_page.dart`, `lib/pages/player/player_screen.dart`, `lib/services/cloudstream/**`, `lib/services/books/**`, `lib/services/iptv/**`, `lib/services/addon/**`, `lib/services/stream/**`, `lib/services/download/**`, `lib/services/updater/**`, `lib/services/config/env_service.dart`, `lib/services/storage/json_document_store.dart`, `android/app/src/main/kotlin/io/github/tzero86/zplay/CloudStreamNativeBridge.kt`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`, `macos/Runner/Info.plist`, `.github/workflows/build.yml`, `.github/workflows/quality.yml`, `pubspec.yaml`, `pubspec.lock`.
