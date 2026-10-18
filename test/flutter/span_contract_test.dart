import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/span_codec.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  const source = TextSpan(
    text: 'ab',
    semanticsLabel: 'first letters',
    style: TextStyle(fontSize: 10),
    children: [TextSpan(text: 'cdef')],
  );

  test('child-only measurement retains a valid labeled ancestor', () {
    final slice = sliceInlineSpanForMeasurement(encodeInlineSpan(source), 2, 6);
    expect(slice.span.toPlainText(includeSemanticsLabels: false), 'cdef');
    final painter = TextPainter(
      text: slice.span,
      textDirection: TextDirection.ltr,
    )..layout();
    addTearDown(painter.dispose);
    expect(painter.width, 40);
    expect(source.toPlainText(), 'first letterscdef');
  });

  testWidgets('labeled parent text allows calculated child-only lines', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap.rich(
          source,
          model: offsetModel([2]),
          strategy: offsetStrategy([2]),
        ),
      ),
    );
    final render = wrapRender(tester);
    expect(render.result!.applied, isTrue);
    expect(render.result!.widths, [20, 40]);
    expect(
      render.effectiveText.toPlainText(includeSemanticsLabels: false),
      'ab\ncdef',
    );
    expect(render.effectiveText.toPlainText(), 'first letters\ncdef');
  });
}
