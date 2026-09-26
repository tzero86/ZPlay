/// One-shot migration of the Windows application-support profile left behind by
/// the rebrand.
///
/// **Why this exists.** `windows/runner/Runner.rc` is not cosmetic: the Windows
/// `path_provider` / `shared_preferences` plugins derive the app-support root
/// from its VERSIONINFO fields, as
/// `%APPDATA%\<CompanyName>\<ProductName>` (see the plugin's own
/// `_getApplicationSpecificSubdirectory`, which drops the company component
/// when the field is empty and falls back to the executable name when the
/// product name is empty). Those fields read `com.example` / `playtorrio` for
/// every install up to and including the rebrand commit `57b590d`
/// (`git show 57b590d~1:windows/runner/Runner.rc`), which changed them to
/// `tzero86` / `zplay`. That silently relocated every user's profile, so the
/// first launch after the rebrand saw an empty directory: no settings, no
/// watchlist, no addons, no TorrServer database. `docs/RENAME_PRODUCT_PLAN.md`
/// (§6, phase P5) scheduled this copy step; it was never implemented.
///
/// **Why it refuses to overwrite.** The destination is skipped whenever it
/// already exists. A user who has already run the new build and reconfigured
/// it has real work in that directory, and clobbering it with a stale copy from
/// the previous install would destroy it — the failure this whole file exists
/// to prevent, just pointed the other way.
///
/// The source is never deleted or moved: it stays in place as a fallback, so
/// the migration is reversible by removing the destination.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// What a (legacy, destination) pair calls for.
enum WindowsStateMigrationAction {
  /// The legacy profile exists and holds something, and the new location is
  /// free. This is the only action that writes anything.
  copy,

  /// The new profile directory already exists: the user owns it, so the
  /// migration stays out of it. Also returned when it is created by a previous
  /// successful run, which is what makes the whole thing one-shot.
  skipDestinationExists,

  /// Nothing at the legacy path — a fresh install, or a user who already moved
  /// their own data across.
  noLegacyProfile,

  /// The legacy directory exists but is empty, so copying it would only
  /// manufacture an empty destination that then blocks every later attempt.
  emptyLegacyProfile,

  /// The migration does not apply here: not Windows, or no resolvable
  /// `%APPDATA%` to derive a profile root from.
  notApplicable,
}

/// Suffix of the staging directory used while copying, as a sibling of the
/// destination.
const String _stagingSuffix = '.migrating';

/// Candidate legacy profile roots, most specific first, relative to
/// `%APPDATA%`.
///
/// `com.example/playtorrio` is the identity every pre-rebrand install wrote
/// to. The bare entries cover the fallback layouts `path_provider_windows`
/// produces when a VERSIONINFO field is missing: without a company name the
/// root is the product name alone, without a product name it is the executable
/// name. Probing a candidate list rather than one hardcoded path is the
/// established convention on this side of the codebase — see the renderer
/// preference lookup in `windows/runner/main.cpp:35-38`, which probes the same
/// two-way layout split.
const List<List<String>> _legacyProfileCandidates = <List<String>>[
  <String>['com.example', 'playtorrio'],
  <String>['playtorrio'],
  <String>['zplay'],
];

/// Destination identity. Pinned here rather than read from `path_provider`
/// because this runs before any plugin call: it must mirror `Runner.rc`'s
/// `CompanyName` / `ProductName` exactly, so changing the rebrand identity
/// means changing this line too.
const List<String> _destinationProfileSegments = <String>['tzero86', 'zplay'];

/// Decides what should happen to a profile pair, touching the filesystem only
/// to stat it. Kept free of the platform guard, `%APPDATA%` resolution and
/// copying so the rule can be exercised directly by a unit test on any host.
WindowsStateMigrationAction planWindowsStateMigration({
  required String legacyPath,
  required String destinationPath,
}) {
  // Checked before anything else: if the destination is there we must not
  // touch it, whatever the legacy directory contains.
  if (Directory(destinationPath).existsSync()) {
    return WindowsStateMigrationAction.skipDestinationExists;
  }
  final legacy = Directory(legacyPath);
  if (!legacy.existsSync()) {
    return WindowsStateMigrationAction.noLegacyProfile;
  }
  if (legacy.listSync().isEmpty) {
    return WindowsStateMigrationAction.emptyLegacyProfile;
  }
  return WindowsStateMigrationAction.copy;
}

/// Copies [legacyPath] to [destinationPath] if [planWindowsStateMigration]
/// says so. Never throws and never deletes: a failed run leaves the legacy
/// profile exactly as it was.
Future<WindowsStateMigrationAction> migrateWindowsProfile({
  required String legacyPath,
  required String destinationPath,
}) async {
  final action = planWindowsStateMigration(
    legacyPath: legacyPath,
    destinationPath: destinationPath,
  );
  if (action != WindowsStateMigrationAction.copy) return action;

  // Copy into a staging sibling and rename it into place. Writing straight
  // into the destination would leave a half-copied profile behind if the
  // process died mid-copy, and since the destination then exists, this
  // migration would skip it forever — the user would be left with a partial
  // profile and no way to retry. rename() is atomic within a volume, and a
  // sibling path is always the same volume.
  final stagingPath = '$destinationPath$_stagingSuffix';
  final staging = Directory(stagingPath);
  if (staging.existsSync()) {
    // A killed run leaves its staging directory behind. The name is reserved
    // by this file, so reclaiming it is safe and is what makes the migration
    // recoverable rather than permanently blocked.
    debugPrint('[WindowsMigration] reclaiming leftover $stagingPath');
    staging.deleteSync(recursive: true);
  }

  try {
    final legacy = Directory(legacyPath);
    final counts = await _copyTree(legacy, stagingPath);
    staging.renameSync(destinationPath);
    debugPrint(
      '[WindowsMigration] $legacyPath -> $destinationPath '
      '(${counts.files} files, ${counts.directories} directories, '
      '${counts.skippedLinks} links skipped); legacy profile left in place',
    );
  } catch (e) {
    // Only ever removes the directory this run created — the destination is
    // still untouched, so the next launch retries from a clean slate.
    if (staging.existsSync()) {
      try {
        staging.deleteSync(recursive: true);
      } catch (_) {
        // Nothing useful to do: the copy already failed and the next run
        // reclaims the same path anyway.
      }
    }
    debugPrint('[WindowsMigration] migration from $legacyPath failed: $e');
  }
  return action;
}

/// Resolves the real profile root and runs the migration once. Call it from
/// the Dart bootstrap before anything reads a plugin-owned path; it is
/// deliberately synchronous work behind an awaited call, because the first
/// `path_provider` / `shared_preferences` read creates the destination and
/// would then make the copy unreachable.
Future<WindowsStateMigrationAction> migrateLegacyWindowsState() async {
  if (!Platform.isWindows) return WindowsStateMigrationAction.notApplicable;

  // `%APPDATA%` is already the Roaming known folder, so this matches
  // `windows/runner/main.cpp`, which builds the same paths from the same
  // environment variable.
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.isEmpty) {
    debugPrint('[WindowsMigration] %APPDATA% is not set; nothing to migrate');
    return WindowsStateMigrationAction.notApplicable;
  }

  final destinationPath = p.joinAll(<String>[appData, ..._destinationProfileSegments]);
  // The overwhelmingly common case after the first successful migration is
  // "already done", so this single stat short-circuits before any candidate
  // is stat'ed.
  if (Directory(destinationPath).existsSync()) {
    return WindowsStateMigrationAction.skipDestinationExists;
  }

  for (final segments in _legacyProfileCandidates) {
    final legacyPath = p.joinAll(<String>[appData, ...segments]);
    if (!Directory(legacyPath).existsSync()) continue;
    return migrateWindowsProfile(
      legacyPath: legacyPath,
      destinationPath: destinationPath,
    );
  }

  debugPrint('[WindowsMigration] no legacy profile under $appData');
  return WindowsStateMigrationAction.noLegacyProfile;
}

Future<({int files, int directories, int skippedLinks})> _copyTree(
  Directory source,
  String targetPath,
) async {
  final target = Directory(targetPath);
  await target.create(recursive: true);

  var files = 0;
  var directories = 0;
  var skippedLinks = 0;
  // followLinks: false so a link is copied as nothing rather than silently
  // expanded — a cycle in a profile directory would otherwise recurse until
  // the disk filled up.
  await for (final entity in source.list(followLinks: false)) {
    final childPath = p.join(targetPath, p.basename(entity.path));
    if (entity is Directory) {
      directories++;
      final counts = await _copyTree(entity, childPath);
      files += counts.files;
      directories += counts.directories;
      skippedLinks += counts.skippedLinks;
    } else if (entity is File) {
      await entity.copy(childPath);
      files++;
    } else {
      skippedLinks++;
    }
  }
  return (files: files, directories: directories, skippedLinks: skippedLinks);
}
