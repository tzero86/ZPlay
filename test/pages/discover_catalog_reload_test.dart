/// Browse showed "No catalogs available for \"movie\"" on a television that had
/// a working, enabled Cinemeta addon installed.
///
/// The cause is an init race, not a filter and not a network failure. The shell
/// keeps every slot mounted in one `IndexedStack`, so `DiscoverPage.initState`
/// runs exactly once - at startup - and never again. At that moment
/// `AddonManager.initialize()` is still hydrating the installed list from disk in
/// the background (`main.dart` starts it as deferred warm-up), so the synchronous
/// `getAvailableDiscoverCatalogs()` read returns an empty list. The page caches
/// that empty list for the rest of the process lifetime.
///
/// Home was never affected because it reloads when its slot is revisited. Browse
/// had no such cue, so its empty state was permanent until an app restart - and
/// restart did not help either, because the race can land either way.
///
/// These tests pin the rule that Browse re-reads its catalogs whenever it
/// becomes the visible slot, and not only when the widget is first built.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/pages/discover/discover_page.dart';
import 'package:zplay/services/addon/addon_manager.dart';
import 'package:zplay/services/layout/form_factor.dart';
import 'package:zplay/shell/app_shell_scope.dart';

/// A minimal installed-addon record whose manifest advertises catalogs, which is
/// all `getAvailableDiscoverCatalogs` needs to offer Browse something to show.
/// The catalog itself is never fetched - the test asserts on the catalog *list*,
/// which is built synchronously, so no network call has to succeed.
const String _cinemetaEntry = '''
[
  {
    "id": "com.cinemeta.stremio",
    "baseUrl": "https://v3-cinemeta.strem.io",
    "enabled": true,
    "enableCatalogs": true,
    "name": "Cinemeta",
    "manifest": {
      "id": "com.cinemeta.stremio",
      "name": "Cinemeta",
      "version": "v3.0.14",
      "description": "The official addon for movie and series catalogs",
      "catalogs": [
        {"type": "movie", "id": "top", "name": "Top"},
        {"type": "series", "id": "top", "name": "Top"}
      ]
    }
  }
]
''';

/// The empty state Browse shows when its catalog list came back empty.
final Finder _emptyState = find.textContaining('No catalogs available');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Replaces what the manager reads from storage and lets it settle. Each call
  /// is a completed read - never two in flight - so the tests never depend on
  /// which read wins a race.
  Future<void> hydrateWith(String? stored) async {
    AddonManager.readStoredForTesting = () async => stored;
    await AddonManager.instance.reload();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await hydrateWith(null);
  });

  tearDown(() => AddonManager.readStoredForTesting = null);

  /// A shell stand-in that behaves like the real one: one [ValueListenable] for
  /// the process lifetime, so a page mounted under it stays mounted across slot
  /// switches exactly as the `IndexedStack` keeps it.
  AppShellController newShell() {
    final slot = ValueNotifier(ShellSlot.browse);
    return AppShellController(
      current: slot,
      onSelect: (next) {
        slot.value = next;
        return true;
      },
      formFactor: () => FormFactor.compact,
    );
  }

  /// Mounts Browse the way the shell does: inside a real app surface, wrapped in
  /// the scope, with the controller already reporting Browse as the visible slot.
  /// The surface is the television's 960x540 dp, which is what the bug was
  /// reported on.
  Future<void> mountBrowse(WidgetTester tester, AppShellController shell) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AppShellScope(
          controller: shell,
          child: const Scaffold(body: DiscoverPage()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('picks up addons installed after the page was built', (
    tester,
  ) async {
    final shell = newShell();
    await mountBrowse(tester, shell);

    // Precondition: built before any addon was known, so it has nothing to show.
    expect(_emptyState, findsOneWidget);

    // The addon list is now populated - startup hydration finished, or the user
    // installed one in Settings. The page is still mounted, so nothing rebuilds
    // it on its own.
    await tester.runAsync(() => hydrateWith(_cinemetaEntry));
    await tester.pump();
    expect(
      _emptyState,
      findsOneWidget,
      reason: 'precondition: a mounted page does not rebuild by itself',
    );

    // Leaving Browse and coming back is the reload cue.
    shell.go(ShellSlot.home);
    await tester.pump();
    shell.go(ShellSlot.browse);
    await tester.pump();

    expect(
      _emptyState,
      findsNothing,
      reason: 'returning to Browse must refresh the catalog list',
    );
  });

  testWidgets('drops its slot listener when disposed', (tester) async {
    final shell = newShell();
    await mountBrowse(tester, shell);

    // Rebuild without the scope: the page disposes, and a listener left on a
    // long-lived shell controller would call into a dead State on the next
    // switch, which throws rather than failing quietly.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    shell.go(ShellSlot.home);
    await tester.pump();
    shell.go(ShellSlot.browse);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
