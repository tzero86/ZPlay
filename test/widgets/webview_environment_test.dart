/// Guards the one WebView2 environment.
///
/// WebView2 will not reconfigure its environment while a controller is alive:
/// `initializeEnvironment` fails with `environment_already_initialized`. The
/// trailer modal and the hover preview both need it, and either can be first -
/// the modal when a trailer is opened, the preview when a pointer rests on a
/// card - so configuring it from each of them was a race that failed the
/// second embed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/widgets/common/webview_environment.dart';

void main() {
  // The environment call needs a binding; a unit test has none until the
  // binding is initialised, and the failure it reports is the one this
  // class is built to swallow.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(WebviewEnvironment.resetForTesting);
  tearDown(WebviewEnvironment.resetForTesting);

  test('the autoplay switch is the one Chromium understands', () {
    expect(
      WebviewEnvironment.autoplayArgument,
      '--autoplay-policy=no-user-gesture-required',
    );
  });

  test('configuring twice does not throw', () async {
    // A machine with no WebView2 runtime cannot configure the environment at
    // all. The first call swallows that, and the second must not throw either
    // - the modal and the preview both call it, in whichever order they mount.
    await WebviewEnvironment.ensureAutoplayPolicy();
    await WebviewEnvironment.ensureAutoplayPolicy();
  });
}
