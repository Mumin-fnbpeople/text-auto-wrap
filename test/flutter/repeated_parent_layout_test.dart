import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  testWidgets('height-only parent passes reuse the verified paragraph', (
    tester,
  ) async {
    final builds = <int>[0];
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap.rich(
          TextSpan(
            children: [
              _CountingSpan(builds),
              const TextSpan(text: 'def'),
            ],
          ),
          model: offsetModel([3]),
          strategy: offsetStrategy([3]),
        ),
      ),
    );
    final render = wrapRender(tester);
    expect(render.result!.applied, isTrue);
    final built = builds.single;
    final effective = render.effectiveText;
    // Equal-height list rows lay out each child at its natural height, then
    // raise the minimum height without changing its available text width.
    for (final height in [30.0, 40.0, 50.0]) {
      render.layout(
        BoxConstraints(minWidth: 100, maxWidth: 100, minHeight: height),
      );
      expect(render.size, Size(100, height));
      expect(render.result!.widths, [30, 30]);
      expect(render.effectiveText, same(effective));
      expect(render.failures, isEmpty);
    }
    expect(
      builds.single,
      built,
      reason: 'height-only passes must not reshape a verified paragraph',
    );
  });

  testWidgets('explicitly dirtied opaque spans are verified again', (
    tester,
  ) async {
    final size = ValueNotifier<double>(10);
    addTearDown(size.dispose);
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap.rich(
          TextSpan(
            children: [
              _MutableSpan(size),
              const TextSpan(text: 'def'),
            ],
          ),
          model: offsetModel([3]),
          strategy: offsetStrategy([3]),
        ),
      ),
    );
    final render = wrapRender(tester);
    expect(render.result!.widths, [30, 30]);
    expect(
      render.getOffsetForCaret(const TextPosition(offset: 3), Rect.zero).dx,
      30,
    );
    size.value = 20;
    render.markNeedsLayout();
    await tester.pump();
    expect(render.result!.widths, [60, 30]);
    expect(
      render.getOffsetForCaret(const TextPosition(offset: 3), Rect.zero).dx,
      60,
    );
    expect(render.failures, isEmpty);
  });

  testWidgets(
    'native opaque spans refresh speculative sizes before and after layout',
    (tester) async {
      final size = ValueNotifier<double>(10);
      addTearDown(size.dispose);
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap.rich(
            _MutableSpan(size),
            model: offsetModel([]),
            strategy: offsetStrategy([]),
          ),
        ),
      );
      final render = wrapRender(tester);
      expect(render.result!.applied, isFalse);
      const query = BoxConstraints(maxWidth: 100);
      expect(render.computeDryLayout(query), const Size(30, 10));
      expect(render.computeMinIntrinsicWidth(100), 30);
      size.value = 20;
      render.markNeedsLayout();
      final effective = render.effectiveText;
      for (var pass = 0; pass < 2; pass++) {
        expect(render.computeDryLayout(query), const Size(60, 20));
        expect(render.computeMinIntrinsicWidth(100), 60);
        expect(render.computeMaxIntrinsicWidth(100), 60);
        expect(render.computeMinIntrinsicHeight(100), 20);
        expect(render.computeMaxIntrinsicHeight(100), 20);
        expect(render.effectiveText, same(effective));
        await tester.pump();
      }
      expect(
        render.getOffsetForCaret(const TextPosition(offset: 3), Rect.zero).dx,
        60,
      );
      expect(render.failures, isEmpty);
    },
  );
}

class _CountingSpan extends TextSpan {
  _CountingSpan(this.builds) : super(text: 'abc', style: wrapStyle);
  final List<int> builds;

  @override
  void build(
    ui.ParagraphBuilder builder, {
    TextScaler textScaler = TextScaler.noScaling,
    List<PlaceholderDimensions>? dimensions,
  }) {
    builds[0]++;
    super.build(builder, textScaler: textScaler, dimensions: dimensions);
  }
}

class _MutableSpan extends TextSpan {
  const _MutableSpan(this.size) : super(text: 'abc', style: wrapStyle);
  final ValueNotifier<double> size;

  @override
  void build(
    ui.ParagraphBuilder builder, {
    TextScaler textScaler = TextScaler.noScaling,
    List<PlaceholderDimensions>? dimensions,
  }) {
    builder.pushStyle(ui.TextStyle(fontSize: size.value));
    builder.addText('abc');
    builder.pop();
  }
}
