import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';
import '../support/narrow_test_font.dart';
import '../support/real_font_environment.dart';

void main() {
  testWidgets('style locale and recognizer updates match fresh native shaping', (
    tester,
  ) async {
    final restore = enableRealFontLoading();
    addTearDown(restore);
    const family = 'TawLocaleFixture';
    await tester.runAsync(() async {
      await (FontLoader(
        family,
      )..addFont(Future.value(localeTestFont()))).load();
      await waitForFontRegistrationFrame();
    });
    final first = TapGestureRecognizer();
    final second = TapGestureRecognizer();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    TextSpan span(Locale locale, TapGestureRecognizer recognizer) => TextSpan(
      text: 'aaaa',
      locale: locale,
      recognizer: recognizer,
      style: TextStyle(fontSize: 10, fontFamily: family, locale: locale),
    );
    final english = span(const Locale('en'), first);
    final turkish = span(const Locale('tr'), second);
    RenderParagraph native(TextSpan source) => RenderParagraph(
      TextSpan(
        style: wrapStyle.copyWith(fontFamily: 'Ahem'),
        children: [source],
      ),
      textDirection: TextDirection.ltr,
    );
    final nativeEnglish = native(english);
    final nativeTurkish = native(turkish);
    addTearDown(nativeEnglish.dispose);
    addTearDown(nativeTurkish.dispose);
    const constraints = BoxConstraints.tightFor(width: 100);
    nativeEnglish.layout(constraints);
    nativeTurkish.layout(constraints);
    // The native shapers quantize advances differently. Verify the font's locl
    // feature changes geometry, then compare renderer geometry exactly below.
    expect(
      nativeTurkish.getMaxIntrinsicWidth(100),
      greaterThan(nativeEnglish.getMaxIntrinsicWidth(100)),
    );
    Widget host(TextSpan source) => wrapHost(
      TextAutoWrap.rich(
        source,
        softWrap: false,
        style: const TextStyle(fontFamily: 'Ahem'),
      ),
    );
    await tester.pumpWidget(host(english));
    final render = wrapRender(tester);
    expect(render.size, nativeEnglish.size);
    await tester.pumpWidget(host(turkish));
    expect(wrapRender(tester), same(render));
    expect(render.size, nativeTurkish.size);
    for (var offset = 0; offset <= 4; offset++) {
      final position = TextPosition(offset: offset);
      expect(
        render.getOffsetForCaret(position, Rect.zero),
        nativeTurkish.getOffsetForCaret(position, Rect.zero),
      );
    }
    expect(render.failures, isEmpty);
    expect(render.result!.reason, 'softWrapDisabled');
  });
}
