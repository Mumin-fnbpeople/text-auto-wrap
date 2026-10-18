import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  testWidgets(
    'semantic breaks do not change the source maximum intrinsic width',
    (tester) async {
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap(
            'abcdef',
            model: offsetModel([3]),
            strategy: offsetStrategy([3]),
          ),
        ),
      );
      final render = wrapRender(tester);
      expect(render.result!.applied, isTrue);
      expect(render.effectiveText.toPlainText(), 'abc\ndef');
      expect(render.getMaxIntrinsicWidth(double.infinity), 60);
      expect(render.getMinIntrinsicWidth(double.infinity), 60);
    },
  );

  testWidgets('an unrelated parent layout does not shrink IntrinsicWidth', (
    tester,
  ) async {
    final revision = ValueNotifier<int>(0);
    addTearDown(revision.dispose);
    final child = TextAutoWrap(
      'abcdef',
      model: offsetModel([3]),
      strategy: offsetStrategy([3]),
    );
    await tester.pumpWidget(
      wrapHost(
        ValueListenableBuilder<int>(
          valueListenable: revision,
          child: child,
          builder: (_, value, child) => Padding(
            padding: EdgeInsets.only(top: value.toDouble()),
            child: Align(
              alignment: Alignment.topLeft,
              child: IntrinsicWidth(child: child),
            ),
          ),
        ),
      ),
    );
    final render = wrapRender(tester);
    expect(render.result!.applied, isTrue);
    expect(render.size.width, 60);
    revision.value++;
    await tester.pump();
    expect(wrapRender(tester), same(render));
    expect(render.size.width, 60);
    expect(render.result!.applied, isTrue);
  });

  testWidgets('source intrinsic width measures repeated widget occurrences', (
    tester,
  ) async {
    const widget = WidgetSpan(child: SizedBox(width: 12, height: 8));
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap.rich(
          const TextSpan(
            text: 'ab',
            children: [
              widget,
              TextSpan(text: 'cd'),
              widget,
              TextSpan(text: 'ef'),
            ],
          ),
          model: offsetModel([3, 6]),
          strategy: offsetStrategy([3, 6]),
        ),
      ),
    );
    final render = wrapRender(tester);
    expect(render.result!.applied, isTrue);
    expect(render.getMaxIntrinsicWidth(double.infinity), 84);
    expect(render.result!.widths, [32, 32, 20]);
    expect(render.effectiveText.toPlainText(), 'ab\uFFFC\ncd\uFFFC\nef');
  });
}
