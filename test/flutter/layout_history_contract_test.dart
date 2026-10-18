import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  testWidgets(
    'dry and intrinsic height queries ignore previous inserted breaks',
    (tester) async {
      final model = offsetModel([3]);
      final strategy = offsetStrategy([3]);
      final fresh = RenderParagraph(
        const TextSpan(text: 'abcdef', style: wrapStyle),
        textDirection: TextDirection.ltr,
      );
      addTearDown(fresh.dispose);
      const query = BoxConstraints(maxWidth: 100);
      final expectedSize = fresh.getDryLayout(query);
      expect(expectedSize, const Size(60, 10));
      final expectedMin = fresh.getMinIntrinsicHeight(100);
      final expectedMax = fresh.getMaxIntrinsicHeight(100);
      expect(expectedMin, 10);
      expect(expectedMax, 10);
      await tester.pumpWidget(
        wrapHost(TextAutoWrap('abcdef', model: model, strategy: strategy)),
      );
      final render = wrapRender(tester);
      expect(
        render.result!.applied,
        isTrue,
        reason:
            "${render.result!.reason}: ${render.failures.map((f) => f.error)}",
      );
      expect(render.effectiveText.toPlainText(), 'abc\ndef');
      expect(render.getDryLayout(query), expectedSize);
      expect(render.getMinIntrinsicHeight(100), expectedMin);
      expect(render.getMaxIntrinsicHeight(100), expectedMax);
      expect(render.effectiveText.toPlainText(), 'abc\ndef');
      expect(
        render.result!.applied,
        isTrue,
        reason:
            "${render.result!.reason}: ${render.failures.map((f) => f.error)}",
      );
    },
  );
  testWidgets('dry baseline uses source spans after an inserted break', (
    tester,
  ) async {
    const source = TextSpan(
      text: 'abc',
      style: wrapStyle,
      children: [TextSpan(text: 'def', style: TextStyle(fontSize: 30))],
    );
    final model = offsetModel([3]);
    final strategy = offsetStrategy([3]);
    final fresh = RenderParagraph(source, textDirection: TextDirection.ltr);
    addTearDown(fresh.dispose);
    const query = BoxConstraints(maxWidth: 200);
    final expected = fresh.getDryBaseline(query, TextBaseline.alphabetic);
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap.rich(source, model: model, strategy: strategy),
        width: 200,
      ),
    );
    final render = wrapRender(tester);
    expect(
      render.result!.applied,
      isTrue,
      reason:
          "${render.result!.reason}: ${render.failures.map((f) => f.error)}",
    );
    expect(render.getDryBaseline(query, TextBaseline.alphabetic), expected);
    expect(
      render.result!.applied,
      isTrue,
      reason:
          "${render.result!.reason}: ${render.failures.map((f) => f.error)}",
    );
  });

  testWidgets('an unrelated parent layout does not grow IntrinsicHeight', (
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
              child: IntrinsicHeight(child: child),
            ),
          ),
        ),
      ),
    );
    final render = wrapRender(tester);
    expect(render.result!.applied, isTrue);
    expect(render.size.height, 10);
    for (var index = 0; index < 3; index++) {
      revision.value++;
      await tester.pump();
      expect(wrapRender(tester), same(render));
      expect(render.size.height, 10);
      expect(render.result!.applied, isTrue);
    }
  });

  for (final overflow in TextOverflow.values) {
    testWidgets('rich dry measurements preserve native $overflow constraints', (
      tester,
    ) async {
      const placeholder = WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Baseline(
          baseline: 9,
          baselineType: TextBaseline.alphabetic,
          child: SizedBox(
            width: 12,
            height: 14,
            child: Text('x', style: wrapStyle),
          ),
        ),
      );
      const source = TextSpan(
        text: 'ab',
        style: wrapStyle,
        children: [
          placeholder,
          TextSpan(text: 'cd'),
          placeholder,
          TextSpan(text: 'ef'),
        ],
      );
      await tester.pumpWidget(
        wrapHost(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextAutoWrap.rich(
                source,
                model: offsetModel([3, 6]),
                strategy: offsetStrategy([3, 6]),
                overflow: overflow,
                maxLines: 4,
                textScaler: const TextScaler.linear(1.2),
              ),
              RichText(
                text: source,
                overflow: overflow,
                maxLines: 4,
                textScaler: const TextScaler.linear(1.2),
              ),
            ],
          ),
        ),
      );
      final render = wrapRender(tester);
      final native = tester.allRenderObjects
          .whereType<RenderParagraph>()
          .where(
            (paragraph) => paragraph.text.toPlainText() == source.toPlainText(),
          )
          .single;
      expect(
        render.result!.applied,
        isTrue,
        reason:
            "${render.result!.reason}: ${render.failures.map((f) => f.error)}",
      );
      final effective = render.effectiveText;
      final actualSize = render.size;
      final actualBaseline = render.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      for (final width in [100.0, 45.0, 20.0, 100.0]) {
        final query = BoxConstraints(maxWidth: width);
        expect(render.getDryLayout(query), native.getDryLayout(query));
        expect(
          render.getMinIntrinsicHeight(width),
          native.getMinIntrinsicHeight(width),
        );
        expect(
          render.getMaxIntrinsicHeight(width),
          native.getMaxIntrinsicHeight(width),
        );
        expect(
          render.getDryBaseline(query, TextBaseline.alphabetic),
          native.getDryBaseline(query, TextBaseline.alphabetic),
        );
      }
      expect(render.effectiveText, same(effective));
      expect(render.size, actualSize);
      expect(
        render.computeDistanceToActualBaseline(TextBaseline.alphabetic),
        actualBaseline,
      );
      expect(
        render.result!.applied,
        isTrue,
        reason:
            "${render.result!.reason}: ${render.failures.map((f) => f.error)}",
      );
      // Parent queries may run after properties change but before performLayout.
      // The old committed breaks must not survive into those source estimates.
      render.maxLines = 1;
      native.maxLines = 1;
      const narrow = BoxConstraints(maxWidth: 20);
      expect(render.getDryLayout(narrow), native.getDryLayout(narrow));
      expect(
        render.getMaxIntrinsicHeight(20),
        native.getMaxIntrinsicHeight(20),
      );
      expect(
        render.getDryBaseline(narrow, TextBaseline.alphabetic),
        native.getDryBaseline(narrow, TextBaseline.alphabetic),
      );
      render.softWrap = false;
      native.softWrap = false;
      expect(render.getDryLayout(narrow), native.getDryLayout(narrow));
      expect(
        render.getMinIntrinsicHeight(20),
        native.getMinIntrinsicHeight(20),
      );
      expect(
        render.getDryBaseline(narrow, TextBaseline.alphabetic),
        native.getDryBaseline(narrow, TextBaseline.alphabetic),
      );
      expect(render.effectiveText, same(effective));
    });
  }
}
