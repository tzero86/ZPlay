import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdaterService {
  /// This fork's own release feed. Do NOT point this back at the upstream
  /// project: the updater downloads and installs whatever it finds here, so
  /// upstream assets would overwrite this build. Upstream changes are pulled
  /// in deliberately via git, never via the in-app updater.
  static const String githubRepo = 'tzero86/ZPlay';
  static const String githubApiUrl =
      'https://api.github.com/repos/$githubRepo/releases/latest';
  static const String _keyDismissedVersion = 'dismissed_update_version';

  static Future<void> dismissVersion(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDismissedVersion, version);
      debugPrint('[AppUpdaterService] Dismissed update version: $version');
    } catch (e) {
      debugPrint('[AppUpdaterService] Error dismissing update version: $e');
    }
  }

  static Future<bool> isVersionDismissed(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getString(_keyDismissedVersion);
      return dismissed == version;
    } catch (e) {
      return false;
    }
  }

  static Future<void> clearDismissedVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyDismissedVersion);
    } catch (_) {}
  }

  Future<UpdateInfo?> checkForUpdates({bool ignoreDismissed = false}) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse(githubApiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestVersion = (data['tag_name'] as String).replaceFirst(
          'v',
          '',
        );
        final releaseNotes =
            data['body'] as String? ?? 'No release notes available';
        final publishedAt = DateTime.parse(data['published_at']);

        if (_isNewerVersion(currentVersion, latestVersion)) {
          if (!ignoreDismissed && await isVersionDismissed(latestVersion)) {
            debugPrint('[AppUpdaterService] Update $latestVersion is newer but was dismissed by user.');
            return null;
          }

          final assets = data['assets'] as List;
          final downloadUrl = _findAssetForPlatform(assets);
          final expectedSha256 = downloadUrl == null
              ? null
              : await _fetchExpectedChecksum(assets, downloadUrl);

          return UpdateInfo(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            downloadUrl: downloadUrl ?? data['html_url'],
            releasePageUrl: data['html_url'] as String?,
            sha256: expectedSha256,
            releaseNotes: releaseNotes,
            publishedAt: publishedAt,
            isMacOS: kIsWeb ? false : Platform.isMacOS,
            isIOS: kIsWeb ? false : Platform.isIOS,
          );
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error checking for updates: $e');
      return null;
    }
  }

  /// Finds the release's checksum manifest. Releases published by the release
  /// workflow include `SHA256SUMS`; older releases do not.
  String? _findChecksumAsset(List assets) {
    for (final asset in assets) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (name == 'sha256sums' ||
          name == 'sha256sums.txt' ||
          name == 'checksums.txt') {
        return asset['browser_download_url'] as String?;
      }
    }
    return null;
  }

  Future<String?> _fetchExpectedChecksum(
    List assets,
    String downloadUrl,
  ) async {
    final checksumUrl = _findChecksumAsset(assets);
    final assetName = _assetNameFromUrl(downloadUrl);
    if (checksumUrl == null || assetName.isEmpty) return null;

    try {
      final response = await http.get(
        Uri.parse(checksumUrl),
        headers: const {'Accept': 'text/plain'},
      );
      if (response.statusCode != 200) {
        debugPrint(
          '[AppUpdaterService] Checksum manifest returned ${response.statusCode}',
        );
        return null;
      }
      return checksumForAsset(response.body, assetName);
    } catch (e) {
      debugPrint('[AppUpdaterService] Could not read checksum manifest: $e');
      return null;
    }
  }

  static String _assetNameFromUrl(String url) {
    final segments = Uri.tryParse(url)?.pathSegments;
    if (segments == null || segments.isEmpty) return '';
    return segments.last;
  }

  /// Parses one line of the `sha256sum` output format:
  /// `<64 hex chars>  <filename>` (or `*<filename>`).
  static String? checksumForAsset(String manifest, String assetName) {
    if (assetName.isEmpty) return null;
    final linePattern = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$');
    for (final line in const LineSplitter().convert(manifest)) {
      final match = linePattern.firstMatch(line.trim());
      if (match == null) continue;
      final name = match.group(2)!.split('/').last;
      if (name == assetName) {
        return match.group(1)!.toLowerCase();
      }
    }
    return null;
  }

  /// Detects the current CPU architecture and finds the matching release asset.
  String? _findAssetForPlatform(List assets) {
    if (kIsWeb) return null;

    Abi? abi;
    try {
      abi = Abi.current();
      debugPrint('Detected system ABI: $abi');
    } catch (e) {
      debugPrint('Error detecting ABI: $e');
    }

    if (Platform.isAndroid) {
      return _findAndroidAsset(assets, abi);
    } else if (Platform.isWindows) {
      return _findWindowsAsset(assets, abi);
    } else if (Platform.isLinux) {
      return _findLinuxAsset(assets, abi);
    } else if (Platform.isMacOS) {
      return _findMacOSAsset(assets, abi);
    }
    return null;
  }

  /// Android: match arm64-v8a, armeabi-v7a, x86_64, or fall back to universal
  String? _findAndroidAsset(List assets, Abi? abi) {
    final apks = assets
        .where((a) => (a['name'] as String).toLowerCase().endsWith('.apk'))
        .toList();

    if (apks.isEmpty) return null;

    // Determine architecture keywords to search for
    List<String> archKeywords = [];
    if (abi == Abi.androidArm64) {
      archKeywords = ['arm64-v8a', 'arm64_v8a', 'arm64', 'v8a', 'aarch64'];
    } else if (abi == Abi.androidArm) {
      archKeywords = ['armeabi-v7a', 'armeabi_v7a', 'armeabi', 'v7a', 'armv7', 'arm-v7a'];
    } else if (abi == Abi.androidX64) {
      archKeywords = ['x86_64', 'x86-64', 'x64'];
    } else if (abi == Abi.androidIA32) {
      archKeywords = ['x86', 'x86_32', 'ia32'];
    } else {
      // Default to arm64-v8a on modern Android if ABI couldn't be determined
      archKeywords = ['arm64-v8a', 'arm64', 'v8a'];
    }

    // 1. Try exact architecture match
    for (final keyword in archKeywords) {
      final match = apks
          .where((a) => (a['name'] as String).toLowerCase().contains(keyword))
          .firstOrNull;
      if (match != null) {
        debugPrint('Matched specific APK for $abi ($keyword): ${match['name']}');
        return match['browser_download_url'];
      }
    }

    // 2. Fall back to a "universal" APK if available
    final universal = apks
        .where((a) => (a['name'] as String).toLowerCase().contains('universal'))
        .firstOrNull;
    if (universal != null) {
      debugPrint('Falling back to universal APK: ${universal['name']}');
      return universal['browser_download_url'];
    }

    // 3. Fall back to standard release APK name
    final standardRelease = apks
        .where((a) => (a['name'] as String).toLowerCase().contains('release'))
        .firstOrNull;
    if (standardRelease != null) {
      debugPrint('Using standard release APK: ${standardRelease['name']}');
      return standardRelease['browser_download_url'];
    }

    // 4. Last resort: first available APK
    debugPrint('Using first available APK: ${apks.first['name']}');
    return apks.first['browser_download_url'];
  }

  /// Windows: match x64 or arm64 installer (.exe prioritized over .zip)
  String? _findWindowsAsset(List assets, Abi? abi) {
    final windowsAssets = assets.where((a) {
      final name = (a['name'] as String).toLowerCase();
      return (name.contains('windows') || name.contains('win') || name.contains('setup') || name.endsWith('.exe')) &&
          (name.endsWith('.exe') || name.endsWith('.msix') || name.endsWith('.zip'));
    }).toList();

    if (windowsAssets.isEmpty) return null;

    // 1. Look for installer .exe matching setup/installer
    final setupExe = windowsAssets
        .where((a) => (a['name'] as String).toLowerCase().endsWith('.exe') &&
            ((a['name'] as String).toLowerCase().contains('setup') || (a['name'] as String).toLowerCase().contains('install')))
        .firstOrNull;
    if (setupExe != null) {
      debugPrint('Selected Windows Setup installer: ${setupExe['name']}');
      return setupExe['browser_download_url'];
    }

    // 2. Look for any .exe
    final anyExe = windowsAssets
        .where((a) => (a['name'] as String).toLowerCase().endsWith('.exe'))
        .firstOrNull;
    if (anyExe != null) {
      debugPrint('Selected Windows exe: ${anyExe['name']}');
      return anyExe['browser_download_url'];
    }

    // 3. Match architecture in remaining assets (.zip/.msix)
    List<String> archKeywords;
    if (abi == Abi.windowsArm64) {
      archKeywords = ['arm64', 'aarch64'];
    } else {
      archKeywords = ['x64', 'x86_64', 'amd64', 'win64'];
    }

    for (final keyword in archKeywords) {
      final match = windowsAssets
          .where((a) => (a['name'] as String).toLowerCase().contains(keyword))
          .firstOrNull;
      if (match != null) return match['browser_download_url'];
    }

    return windowsAssets.first['browser_download_url'];
  }

  /// Linux: match x64 or arm64 AppImage/deb
  String? _findLinuxAsset(List assets, Abi? abi) {
    final linuxAssets = assets.where((a) {
      final name = (a['name'] as String).toLowerCase();
      return name.contains('linux') ||
          name.endsWith('.appimage') ||
          name.endsWith('.deb') ||
          name.endsWith('.tar.gz');
    }).toList();

    if (linuxAssets.isEmpty) return null;

    if (linuxAssets.length == 1) {
      return linuxAssets.first['browser_download_url'];
    }

    List<String> archKeywords;
    if (abi == Abi.linuxArm64) {
      archKeywords = ['arm64', 'aarch64'];
    } else {
      archKeywords = ['x86_64', 'x64', 'amd64'];
    }

    for (final keyword in archKeywords) {
      final match = linuxAssets
          .where((a) => (a['name'] as String).toLowerCase().contains(keyword))
          .firstOrNull;
      if (match != null) return match['browser_download_url'];
    }

    return linuxAssets.first['browser_download_url'];
  }

  /// macOS: match dmg or zip
  String? _findMacOSAsset(List assets, Abi? abi) {
    final macAssets = assets.where((a) {
      final name = (a['name'] as String).toLowerCase();
      return name.contains('mac') || name.contains('darwin') || name.endsWith('.dmg') || name.endsWith('.pkg');
    }).toList();

    if (macAssets.isNotEmpty) {
      return macAssets.first['browser_download_url'];
    }
    return null;
  }

  bool _isNewerVersion(String current, String latest) {
    // Strip any suffix like "-test" or "-beta" for comparison
    final currentClean = current.split('-').first;
    final latestClean = latest.split('-').first;

    final currentParts = currentClean
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final latestParts = latestClean
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();

    for (int i = 0; i < 3; i++) {
      final currentPart = i < currentParts.length ? currentParts[i] : 0;
      final latestPart = i < latestParts.length ? latestParts[i] : 0;

      if (latestPart > currentPart) return true;
      if (latestPart < currentPart) return false;
    }
    return false;
  }

  Future<void> openDownloadPage(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;

  /// SHA-256 of the selected download asset, published in the release's
  /// `SHA256SUMS`. Null when the release does not publish a checksum.
  final String? sha256;

  /// The GitHub release page, used when automatic installation is refused.
  final String? releasePageUrl;

  /// The release body exactly as published on GitHub: Markdown, and for older
  /// releases the licence block and GitHub's generated commit list as well.
  final String releaseNotes;

  final DateTime publishedAt;
  final bool isMacOS;
  final bool isIOS;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    this.sha256,
    this.releasePageUrl,
    required this.releaseNotes,
    required this.publishedAt,
    required this.isMacOS,
    this.isIOS = false,
  });

  /// Ends the changelog in a release body. `.github/workflows/build.yml` writes
  /// it as an HTML comment; only the inner text is matched so the comment syntax
  /// can change without the app losing its cut-off point.
  static const String _changelogEndMarker = 'zplay:changelog-end';

  /// Opens the licence block that build.yml appends below the changelog, and
  /// that release bodies published before the marker existed led with.
  static const String _forkTrailerMarker = 'is a modified fork of PlayTorrio V3';

  /// `**Full Changelog**: https://…` — the commit-diff line GitHub appends to
  /// generated notes, which is a link and not a changelog entry.
  static final RegExp _fullChangelogLine = RegExp(
    r'^\s*\**full changelog\**\s*:',
    caseSensitive: false,
  );

  static final RegExp _htmlComment = RegExp(r'<!--[\s\S]*?-->');
  static final RegExp _headingMarker = RegExp(r'^\s*#{1,6}\s+');
  static final RegExp _bulletMarker = RegExp(r'^(\s*)[-*]\s+');
  static final RegExp _boldAsterisk = RegExp(r'\*\*(.+?)\*\*');
  static final RegExp _boldUnderscore = RegExp(r'__(.+?)__');

  /// [releaseNotes] shaped for a plain `Text`: only the changelog section, with
  /// the Markdown a `Text` would print literally removed.
  String get releaseNotesForDisplay {
    final stripped = _stripMarkdown(_changelogSection(releaseNotes));
    // A body that was nothing but markers and licence text is still better shown
    // raw than as an empty box.
    return stripped.isEmpty ? releaseNotes.trim() : stripped;
  }

  /// Everything above the changelog end marker, or — for releases published
  /// before the marker existed — everything above the licence block, minus the
  /// generated commit list's trailing `Full Changelog` link.
  static String _changelogSection(String body) {
    final lines = body.replaceAll('\r\n', '\n').split('\n');

    final markerIndex = lines.indexWhere(
      (line) => line.contains(_changelogEndMarker),
    );
    if (markerIndex != -1) return lines.take(markerIndex).join('\n');

    final forkIndex = lines.indexWhere(
      (line) => line.contains(_forkTrailerMarker),
    );
    final section = forkIndex == -1 ? lines : lines.sublist(0, forkIndex);

    var end = section.length;
    while (end > 0) {
      final line = section[end - 1].trim();
      if (line.isEmpty || _fullChangelogLine.hasMatch(line)) {
        end--;
      } else {
        break;
      }
    }
    return section.take(end).join('\n');
  }

  /// Drops the Markdown a `Text` widget cannot interpret. Bullets become `•`
  /// so a list still reads as a list once the markers are gone.
  static String _stripMarkdown(String text) {
    final withoutComments = text.replaceAll(_htmlComment, '');
    final unmarked = withoutComments
        .split('\n')
        .map(
          (line) => line
              .replaceFirst(_headingMarker, '')
              .replaceFirstMapped(_bulletMarker, (match) => '${match[1]}• '),
        )
        .join('\n');

    return unmarked
        .replaceAllMapped(_boldAsterisk, (match) => match[1]!)
        .replaceAllMapped(_boldUnderscore, (match) => match[1]!)
        .replaceAll('`', '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
