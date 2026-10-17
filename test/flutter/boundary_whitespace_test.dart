import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  for (final fixture in [
    (text: '프랜차이즈를 프랜차이즈답게', width: 144.0),
    (text: 'Making franchises truly franchises', width: 192.0),
    (text: 'Making franchises truly franchises', width: 288.0),
  ]) {
    testWidgets('bundled model applies whitespace breaks at ${fixture.width}', (
      tester,
    ) async {
      final controller = TextAutoWrapController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap(
            fixture.text,
            style: const TextStyle(fontSize: 12),
            controller: controller,
          ),
          width: fixture.width,
        ),
      );
      final result = controller.result!;
      expect(result.reason, 'calculatedSelected');
      expect(result.source, TextWrapSelectionSource.calculated);
      expect(result.applied, isTrue);
      _expectPainted(tester, result, fixture.text);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final rich in [false, true]) {
    for (final text in [
      'aa  bb',
      'aa\tbb',
      'aa  bb\ncc  dd',
      'aa  bb\r\ncc  dd',
      'aa  bb\u2028cc  dd',
      'aa  bb\u2029cc  dd',
      '  aa  bb  ',
    ]) {
      testWidgets('preserves boundary whitespace rich=$rich text=$text', (
        tester,
      ) async {
        // Select the ends of interior whitespace runs, independently of the
        // renderer, to exercise preservation even when native fits one line.
        final offsets = RegExp(
          r'(?<=\S)[ \t]+(?=\S)',
        ).allMatches(text).map((match) => match.end).toList();
        final controller = TextAutoWrapController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          wrapHost(
            rich
                ? TextAutoWrap.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: text.substring(0, 3)),
                        TextSpan(text: text.substring(3)),
                      ],
                    ),
                    model: offsetModel(offsets),
                    strategy: offsetStrategy(offsets),
                    controller: controller,
                  )
                : TextAutoWrap(
                    text,
                    model: offsetModel(offsets),
                    strategy: offsetStrategy(offsets),
                    controller: controller,
                  ),
            width: 200,
          ),
        );
        final result = controller.result!;
        expect(result.reason, 'calculatedSelected');
        expect(result.applied, isTrue);
        _expectPainted(tester, result, text);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('calculated native offsets retain painted source geometry', (
    tester,
  ) async {
    final controller = TextAutoWrapController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap(
          'aa  bb',
          model: offsetModel([4]),
          strategy: offsetStrategy([4]),
          controller: controller,
        ),
        width: 20,
      ),
    );
    final result = controller.result!;
    expect(result.reason, 'calculatedSelected');
    expect(result.source, TextWrapSelectionSource.calculated);
    expect(result.applied, isFalse);
    expect(result.lines, ['aa  ', 'bb']);
    expect(result.ranges.map((range) => (range.start, range.end)), [
      (0, 4),
      (4, 6),
    ]);
    expect(result.widths, [20, 20]);
    _expectPainted(tester, result, 'aa  bb');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('preserved whitespace that adds painted lines still falls back', (
    tester,
  ) async {
    final controller = TextAutoWrapController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap(
          'aa    bb',
          model: offsetModel([3]),
          strategy: offsetStrategy([3]),
          controller: controller,
        ),
        width: 20,
      ),
    );
    final result = controller.result!;
    expect(result.reason, 'invalidRuntimeMeasurement');
    expect(result.applied, isFalse);
    expect(result.source, TextWrapSelectionSource.native);
    expect(
      _paragraph(tester).text.toPlainText(includeSemanticsLabels: false),
      'aa    bb',
    );
    _expectPainted(tester, result, 'aa    bb');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

RenderParagraph _paragraph(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderParagraph>().toSet().single;

void _expectPainted(WidgetTester tester, TextWrapResult result, String source) {
  final paragraph = _paragraph(tester);
  final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
  var restored = text;
  if (result.applied) {
    expect(result.breakOffsets, isNotEmpty);
    for (var index = result.breakOffsets.length - 1; index >= 0; index--) {
      final offset = result.breakOffsets[index] + index;
      expect(restored.substring(offset, offset + 1), '\n');
      restored = restored.substring(0, offset) + restored.substring(offset + 1);
    }
  }
  expect(restored, source);
  expect(result.sourceText, source);
  final painter = TextPainter(
    text: paragraph.text,
    textAlign: paragraph.textAlign,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    maxLines: paragraph.maxLines,
    locale: paragraph.locale,
    strutStyle: paragraph.strutStyle,
    textWidthBasis: paragraph.textWidthBasis,
    textHeightBehavior: paragraph.textHeightBehavior,
  );
  try {
    painter.layout(
      minWidth: paragraph.constraints.minWidth,
      maxWidth: paragraph.constraints.maxWidth,
    );
    final metrics = painter.computeLineMetrics();
    expect(result.lineCount, metrics.length);
    for (var i = 0; i < metrics.length; i++) {
      expect(result.widths[i], closeTo(metrics[i].width, 0.001));
      if (result.applied) {
        expect(
          result.widths[i],
          lessThanOrEqualTo(paragraph.constraints.maxWidth),
        );
      }
      expect(
        source.substring(result.ranges[i].start, result.ranges[i].end),
        result.lines[i],
      );
    }
  } finally {
    painter.dispose();
  }
  expect(tester.takeException(), isNull);
}
