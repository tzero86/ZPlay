import 'dart:async';

import 'package:zplay/widgets/common/card_focus_expansion.dart';

/// Global test setup, picked up by `flutter test` for every file under test/.
///
/// The card pop waits for focus to rest ([CardFocusExpansion.dwell]) in the
/// app; the widget tests that pin the pop's geometry predate the dwell and
/// would otherwise end with a pending timer. A test of the dwell itself sets
/// it back explicitly.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  CardFocusExpansion.dwell = Duration.zero;
  await testMain();
}
