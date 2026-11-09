# TorrServer engine: where it comes from

The app streams torrents through TorrServer via the `torrserver_flutter` plugin.
That package's own repository was deleted while we depended on it, and every
desktop build path in 0.0.7 downloads its engine binary from that dead repo's
releases. A clean Windows or Linux build failed at the CMake install step with a
404; iOS and macOS failed at pod install the same way. Android only worked
because the pub package happened to commit four 64 MB binaries.

`pubspec.yaml` therefore overrides the dependency with our own fork:

```yaml
dependency_overrides:
  torrserver_flutter:
    git:
      url: https://github.com/tzero86/torrserver_flutter.git
      ref: v0.0.7
```

## The fork

`github.com/tzero86/torrserver_flutter` — plugin source unchanged from 0.0.7.
The only edits are the repo owner in five download URLs
(`windows/CMakeLists.txt`, `linux/CMakeLists.txt`, `android/build.gradle`,
`ios/torrserver_flutter.podspec`, `macos/torrserver_flutter.podspec`) and the two
`tool/` scripts. Both the app and the plugin are GPL-3.0, so this is a clean
arrangement.

Release `v0.0.7` on the fork carries the engine, built from upstream
[`YouROK/TorrServer`](https://github.com/YouROK/TorrServer) **MatriX.148** and
repacked to the filenames the build scripts fetch, with `checksums.txt`:

| Asset | Platform |
|---|---|
| `torrserver-windows-amd64.zip` | Windows x64 |
| `torrserver-linux-amd64.tar.gz` | Linux x64 |
| `torrserver-linux-arm64.tar.gz` | Linux arm64 |
| `torrserver-android-{arm64,arm7,amd64,386}.zip` | Android, four ABIs |
| `checksums.txt` | SHA-256 of every asset above |

Verified end to end on 2026-11-04: a Windows build with no environment variables
and no cached binary downloads the zip, the extracted `torrserver.exe` hashes
identically to the upstream release, and the running app starts the engine —
`GET 127.0.0.1:<port>/echo` answers `MatriX.148`. Android downloads and verifies
all four ABIs at build time, because the fork carries no committed binaries.

## Known gap: iOS and macOS

Their podspecs fetch `TorrServerKit.xcframework.zip`, an `xcframework` that has to
be built on a Mac with Xcode. It is not an upstream TorrServer artefact. Those
two targets still 404 until someone builds and uploads that framework to the
fork's release. Windows, Linux and Android are complete.

## Escape hatch, still supported

The plugin reads `TORRSERVER_FLUTTER_LOCAL_BINARIES` first: point it at a
directory holding `torrserver-windows-amd64.exe`, `torrserver-linux-amd64`, or
the Android zips and the build copies them instead of downloading. Useful for
offline or air-gapped builds; no longer needed for a normal build.

## Bumping the engine

1. Choose a TorrServer tag.
2. Download `TorrServer-windows-amd64.exe`, `-linux-amd64`, `-linux-arm64` and the
   four `TorrServer-android-*` assets.
3. Repack: zip for Windows and Android, `tar.gz` for Linux. The Windows archive's
   single entry must be named `torrserver-windows-amd64.exe`; the Linux tarball's
   `torrserver-linux-<arch>`.
4. Regenerate `checksums.txt` as `<sha256>  <filename>`.
5. Tag `vX.Y.Z` with those assets, then update `TORRSERVER_VERSION` in the two
   CMake lists, `android/build.gradle` and the two podspecs, and bump the fork's
   `pubspec.yaml` version to match — the download URL is built from that constant,
   not from the pubspec. Update `ref:` here afterwards.

## What this replaces

`docs/PONYTAIL_REVIEW.md` records the original finding: `flutter build windows`
failed with `MSB3073` from `INSTALL.vcxproj` because
`github.com/ayman708-UX/torrserver_flutter/releases/download/v0.0.7/…` returns
404, and the repository itself is gone. That is now fixed; the plugin override
is the fix.