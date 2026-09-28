/// Guards the app's back policy: the remote's back key never leaves the app on
/// the first press, and only ever leaves it at Home.
///
/// The defect this pins was reported as "pressing back on pretty much any
/// screen makes it exit". `MaterialApp(home: AppShell())` makes the shell the
/// root route, a route with no `PopScope` reports [RoutePopDisposition.bubble]
/// from `willPop`, `Navigator.maybePop` therefore answers "not handled", and
/// `WidgetsBinding.handlePopRoute` finishes its walk with `SystemNavigator.pop`
/// - the launcher. Nothing about it depended on the slot, so every slot exited
/// and so did Home.
///
/// **The press is sent the way Android sends it.** Not by finding a widget and
/// calling a callback, and not by `WidgetsBinding.handlePopRoute()` (which is
/// `@protected`): the engine's own `popRoute` on `flutter/navigation`, decoded
/// by the binding, down through the observers to whichever route claims it.
/// That is the whole path under test, including the fallback that used to exit
/// the process.
///
/// **An exit is an outbound platform call and is read as one.**
/// `SystemNavigator.pop` is the only method on `SystemChannels.platform` this
/// test cares about, so the channel is mocked and its methods recorded: no
/// record means the framework never asked to leave. That is the only signal in
/// a widget test that distinguishes "handled" from "handled and left the app",
/// because `handlePopRoute` answers true for both.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/shell/app_shell.dart';
import 'package:zplay/shell/app_shell_scope.dart';
import 'package:zplay/shell/shell_back_guard.dart';

/// Sends one back press.
///
/// Nothing is returned: whether the press left the app is read from the
/// recorded platform traffic, because that is the only outward signal there is.
Future<void> _pressBack(WidgetTester tester) async {
  final ByteData message =
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute'));
  await tester.binding.defaultBinaryMessenger
      .handlePlatformMessage('flutter/navigation', message, (_) {});
  await tester.pump();
}

/// True when that press ended in `SystemNavigator.pop`.
///
/// Filtered, because `SystemChannels.platform` also carries
/// `SystemChrome` and clipboard traffic and a recorded call is not by itself an
/// exit.
bool _leftTheApp(List<MethodCall> calls) =>
    calls.any((call) => call.method == 'SystemNavigator.pop');

/// Pumps the real shell and lets its cold-start timers fire.
///
/// No `pumpAndSettle`: Home's ambient background animates continuously, so
/// settling is not a state it reaches. The 2 s pump is the splash timer
/// (`test/tv_chrome_density_test.dart` pumps it for the same reason), and it is
/// spent before any press, so it never consumes part of the exit window.
Future<void> _pumpShell(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await tester.pumpWidget(const MaterialApp(home: AppShell()));
  await tester.pump(const Duration(seconds: 2));
}

/// Records every platform method for the life of the test.
List<MethodCall> _recordPlatform(WidgetTester tester) {
  final calls = <MethodCall>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    calls.add(call);
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return calls;
}

AppShellController _shell(WidgetTester tester) =>
    tester.widget<AppShellScope>(find.byType(AppShellScope)).controller;

void main() {
  testWidgets('back from a non-home slot goes Home instead of leaving the app',
      (WidgetTester tester) async {
    final platform = _recordPlatform(tester);
    await _pumpShell(tester);

    final shell = _shell(tester);
    shell.go(ShellSlot.browse);
    await tester.pump();
    expect(shell.current.value, ShellSlot.browse);

    await _pressBack(tester);

    expect(shell.current.value, ShellSlot.home);
    expect(_leftTheApp(platform), isFalse,
        reason: 'the press was claimed by the shell, not passed to the platform');
    // Arming is Home-only: a press that navigated has nothing to confirm.
    expect(find.text('Press back again to exit'), findsNothing);
  });

  testWidgets('the first back at Home only arms the exit',
      (WidgetTester tester) async {
    final platform = _recordPlatform(tester);
    await _pumpShell(tester);
    expect(_shell(tester).current.value, ShellSlot.home);

    await _pressBack(tester);

    expect(_leftTheApp(platform), isFalse);
    expect(find.text('Press back again to exit'), findsOneWidget);
  });

  testWidgets('a second back inside the window exits',
      (WidgetTester tester) async {
    final platform = _recordPlatform(tester);
    await _pumpShell(tester);

    await _pressBack(tester);
    // Halfway through the window: strictly inside it, and not on the boundary
    // where a scheduler tick could decide the test.
    await tester.pump(shellExitWindow ~/ 2);
    await _pressBack(tester);

    expect(_leftTheApp(platform), isTrue);
    expect(find.text('Press back again to exit'), findsNothing,
        reason: 'the window closes with the press that used it');
  });

  testWidgets('a press after the window only arms again',
      (WidgetTester tester) async {
    final platform = _recordPlatform(tester);
    await _pumpShell(tester);

    await _pressBack(tester);
    await tester.pump(shellExitWindow + const Duration(milliseconds: 1));

    expect(find.text('Press back again to exit'), findsNothing,
        reason: 'the affordance is the window: it goes when the window does');

    await _pressBack(tester);

    expect(_leftTheApp(platform), isFalse);
    expect(find.text('Press back again to exit'), findsOneWidget);
  });

  testWidgets('leaving Home disarms the exit', (WidgetTester tester) async {
    final platform = _recordPlatform(tester);
    await _pumpShell(tester);

    await _pressBack(tester);
    expect(find.text('Press back again to exit'), findsOneWidget);

    final shell = _shell(tester);
    shell.go(ShellSlot.library);
    await tester.pump();

    expect(find.text('Press back again to exit'), findsNothing,
        reason: 'the pill must not ride into a slot where back navigates');

    await _pressBack(tester);
    expect(shell.current.value, ShellSlot.home);
    expect(_leftTheApp(platform), isFalse);
  });

  testWidgets('a route pushed above the shell is what back closes',
      (WidgetTester tester) async {
    final platform = _recordPlatform(tester);
    await _pumpShell(tester);

    final shell = _shell(tester);
    shell.go(ShellSlot.browse);
    await tester.pump();

    // Two pumps, like the SDK's own route tests: the push installs the route's
    // overlay entry on the frame after it is called, and the transition is
    // driven by the second.
    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('details')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('details'), findsOneWidget);

    await _pressBack(tester);
    // The pop is asserted from the navigator rather than from the text alone:
    // a popping route leaves the history at once but stays in the overlay for
    // the length of its exit transition, so `canPop` is the statement about
    // history and the text is the statement about the frame. The exit runs
    // longer than `transitionDuration` because the theme's builder animates
    // both routes for the whole of it.
    expect(navigator.canPop(), isFalse);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('details'), findsNothing);
    expect(_leftTheApp(platform), isFalse);
    // Popping a route is not a slot switch: the user is back on the screen they
    // came from, not sent Home.
    expect(shell.current.value, ShellSlot.browse);
  });

  testWidgets('a pushed route that refuses to pop keeps the press to itself',
      (WidgetTester tester) async {
    final platform = _recordPlatform(tester);
    await _pumpShell(tester);

    final refused = <bool>[];
    tester.state<NavigatorState>(find.byType(Navigator).first).push(
          MaterialPageRoute<void>(
            builder: (_) => PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) => refused.add(didPop),
              child: const Scaffold(body: Text('locked')),
            ),
          ),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await _pressBack(tester);

    expect(refused, <bool>[false],
        reason:
            'the pushed route owns the press, like the player does when locked');
    expect(find.text('locked'), findsOneWidget);
    expect(_leftTheApp(platform), isFalse);
  });

  testWidgets('a dialog above the shell is what back closes',
      (WidgetTester tester) async {
    final platform = _recordPlatform(tester);
    await _pumpShell(tester);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(showDialog<void>(
      context: tester.element(find.byType(ShellBackGuard)),
      builder: (_) => const AlertDialog(title: Text('update')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('update'), findsOneWidget);

    await _pressBack(tester);
    expect(navigator.canPop(), isFalse);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('update'), findsNothing);
    expect(_leftTheApp(platform), isFalse);
  });

  testWidgets('the pill fits a phone canvas', (WidgetTester tester) async {
    // The compact branch is the only place the pill's gutter is not a fixed
    // token: it has to clear the 64 dp bottom bar, and an overflow there is an
    // error no other test would raise, because every other test here runs at
    // the harness's 800x600.
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    _recordPlatform(tester);
    await _pumpShell(tester);
    // Home's hero row overflows this canvas before any pill exists
    // (`lib/pages/home/home_page.dart:1979`, a phone-width defect of the page,
    // not of the shell), so the baseline is cleared rather than asserted: what
    // this test owns is that the pill adds no second one.
    tester.takeException();

    await _pressBack(tester);

    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}