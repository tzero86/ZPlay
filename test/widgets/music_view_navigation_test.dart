/// Guards Music's five views against becoming unreachable again.
///
/// The page once dispatched on a private `String` with a comment listing five
/// tab values, but only two of them were ever written: the sidebar that set the
/// other three was removed when the shell replaced it, and the views it used to
/// select — Browse, Radio and Library — kept their builders and their service
/// wiring while losing their only way in. Roughly 1,900 lines of working
/// library, playlists and liked tracks, with no path to any of it.
///
/// A reachability test is the only thing that fails on that, because the code it
/// deleted was deletion, not a mistake a reader would spot.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/pages/music/music_page.dart';
import 'package:zplay/services/theme/app_theme_service.dart';
import 'package:zplay/widgets/common/tab_strip.dart';

Widget host() => MaterialApp(
      theme: AppThemeService.createThemeData(AppThemeService.palettes.first),
      home: const MusicPage(),
    );

/// The focus node of the pill labelled [label] inside the switcher.
///
/// Taken from the element rather than by tabbing, because the page is one long
/// traversal order: how many tabs it takes to reach the band depends on how
/// many cards the featured content fetched, so a tab count would be a test
/// that fails when the music service returns a different number of sections.
FocusNode pill(WidgetTester tester, String label) {
  final text = find.descendant(
    of: find.byType(TabStrip<MusicView>),
    matching: find.text(label),
  );
  FocusNode? node;
  tester.element(text).visitAncestorElements((element) {
    if (element.widget is Focus) {
      node = (element.widget as Focus).focusNode;
      return false;
    }
    return true;
  });
  expect(node, isNotNull, reason: 'the "$label" pill is not focusable');
  return node!;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // The heading each view is known by, keyed to the view it belongs to. Home
  // has no heading, so it is identified by the absence of every other one.
  const headings = <MusicView, String>{
    MusicView.search: 'All',
    MusicView.browse: 'Browse Moods & Genres',
    MusicView.radio: 'Radio Stations & Live Streams',
    MusicView.library: 'Your Library',
  };

  /// Whether [heading] is the one view on screen. Every other view is asserted
  /// to be gone, so a stale body left mounted behind the new one cannot pass.
  bool showing(String heading, MusicView except) {
    for (final entry in headings.entries) {
      if (entry.value == heading) continue;
      expect(
        find.text(entry.value),
        findsNothing,
        reason: '${entry.key.name} was still on screen behind $except',
      );
    }
    return find.text(heading, skipOffstage: false).evaluate().isNotEmpty;
  }

  testWidgets('the switcher offers all five views, Home selected', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.byType(TabStrip<MusicView>), findsOneWidget,
        reason: 'the views must be reached through the shared tab control');

    for (final view in MusicView.values) {
      expect(find.text(view.label), findsOneWidget,
          reason: '${view.name} has no way to be selected');
    }

    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text('Home')),
      matchesSemantics(
        label: 'Home',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
        textDirection: TextDirection.ltr,
      ),
    );
    handle.dispose();
  });

  testWidgets('every view is reachable from the switcher', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    for (final view in MusicView.values) {
      await tester.tap(find.text(view.label));
      await tester.pump();

      if (view == MusicView.home) {
        expect(showing('Browse Moods & Genres', view), isFalse);
        continue;
      }
      expect(showing(headings[view]!, view), isTrue,
          reason: '${view.name} is unreachable: its body never rendered');
    }
  });

  testWidgets('a search does not trap the page in the search view', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'lofi');
    await tester.pump(const Duration(milliseconds: 400));
    expect(showing(headings[MusicView.search]!, MusicView.search), isTrue);

    // The search field outranked the selection, so once anything had been
    // searched these two were unreachable for the rest of the session.
    for (final view in [MusicView.library, MusicView.browse]) {
      await tester.tap(find.text(view.label));
      await tester.pump();
      expect(showing(headings[view]!, view), isTrue,
          reason: '${view.name} was still overridden by the search field');
    }
  });

  testWidgets('a remote can reach the views the pointer can', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    pill(tester, MusicView.library.label).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(showing(headings[MusicView.library]!, MusicView.library), isTrue);

    // Traversal between the pills is what makes the band usable on a TV, and
    // the arrow key is the only thing that proves the control kept it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(showing(headings[MusicView.radio]!, MusicView.radio), isTrue);
  });
}
