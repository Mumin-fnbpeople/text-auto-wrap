import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';
import '../support/narrow_test_font.dart';
import '../support/real_font_environment.dart';

void main() {
  testWidgets(
    'late font loading refreshes measurement and source dry geometry',
    (tester) async {
      final restore = enableRealFontLoading();
      addTearDown(restore);
      const family = 'TawLateFontFixture';
      const source = TextSpan(
        text: 'abcdef',
        style: TextStyle(
          fontSize: 10,
          fontFamily: family,
          fontFamilyFallback: ['FlutterTest', 'Ahem'],
        ),
      );
      final controller = TextAutoWrapController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap.rich(
            source,
            style: const TextStyle(fontFamily: 'Ahem'),
            controller: controller,
            model: offsetModel([3]),
            strategy: offsetStrategy([3]),
          ),
        ),
      );
      final render = wrapRender(tester);
      expect(render.result!.applied, isTrue);
      expect(render.result!.widths, [30, 30]);
      const query = BoxConstraints(maxWidth: 100);
      expect(render.getDryLayout(query), const Size(60, 10));
      final before = render.result!.diagnostics!.cache;
      final changed = Completer<void>();
      void onFontChange() {
        if (!changed.isCompleted) changed.complete();
      }

      PaintingBinding.instance.systemFonts.addListener(onFontChange);
      addTearDown(
        () => PaintingBinding.instance.systemFonts.removeListener(onFontChange),
      );
      await tester.runAsync(() async {
        await (FontLoader(
          family,
        )..addFont(Future.value(narrowTestFont()))).load();
        // Web batches the real platform notification into requestAnimationFrame.
        // The VM test messenger delivers it on the following pump instead.
        await waitForFontRegistrationFrame();
      });
      await tester.pumpAndSettle();
      expect(changed.isCompleted, isTrue);
      final native = RenderParagraph(
        const TextSpan(
          style: TextStyle(fontSize: 10, fontFamily: 'Ahem'),
          children: [source],
        ),
        textDirection: TextDirection.ltr,
      );
      addTearDown(native.dispose);
      native.layout(query);
      expect(native.size.width, 30);
      expect(render.result!.applied, isTrue);
      expect(render.result!.widths, [15, 15]);
      expect(render.getDryLayout(query), native.getDryLayout(query));
      expect(
        render.getMaxIntrinsicWidth(100),
        native.getMaxIntrinsicWidth(100),
      );
      expect(
        render.result!.diagnostics!.cache.planMisses,
        greaterThan(before.planMisses),
      );
      expect(controller.failures, isEmpty);
    },
  );
}
