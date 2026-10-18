import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as web;

void Function() enableRealFontLoading() {
  final previous = web.TestEnvironment.instance;
  // The web tester normally replaces custom font families with FlutterTest
  // and ignores the engine's fontsChange platform message. Exercise both real
  // paths while retaining the other test environment settings.
  web.TestEnvironment.setUp(
    web.TestEnvironment(
      forceTestFonts: false,
      ignorePlatformMessages: false,
      disableFontFallbacks: previous.disableFontFallbacks,
      keepSemanticsDisabledOnUpdate: previous.keepSemanticsDisabledOnUpdate,
      defaultToTestUrlStrategy: previous.defaultToTestUrlStrategy,
    ),
  );
  return () => web.TestEnvironment.setUp(previous);
}

@JS('requestAnimationFrame')
external void _requestAnimationFrame(JSFunction callback);

Future<void> waitForFontRegistrationFrame() {
  final completed = Completer<void>();
  _requestAnimationFrame(((JSNumber timestamp) => completed.complete()).toJS);
  return completed.future;
}
