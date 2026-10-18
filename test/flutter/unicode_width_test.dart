import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  for (final width in [30.0, 40.0]) {
    testWidgets(
      'soft hyphen retains native conditional-break geometry at $width',
      (tester) async {
        const source = 'ab\u00adcd';
        await tester.pumpWidget(
          wrapHost(
            TextAutoWrap(
              source,
              model: offsetModel([3]),
              strategy: offsetStrategy([3]),
            ),
            width: width,
          ),
        );
        expect(tester.takeException(), isNull);
        final render = wrapRender(tester);
        final result = render.result!;
        expect(result.reason, 'calculatedSelected');
        expect(result.applied, width == 40);
        expect(result.sourceText, source);
        expect(result.lines, ['ab\u00ad', 'cd']);
        expect(
          render.effectiveText.toPlainText(),
          width == 40 ? 'ab\u00ad\ncd' : source,
        );
        final native = TextPainter(
          text: const TextSpan(text: source, style: wrapStyle),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 30);
        try {
          expect(
            result.widths,
            native.computeLineMetrics().map((line) => line.width).toList(),
          );
        } finally {
          native.dispose();
        }
      },
    );
  }

  for (final fixture in [
    (text: '\u00ad', lines: ['\u00ad']),
    (text: '\u00ad\n', lines: ['\u00ad', '']),
    (text: '\n\u00ad', lines: ['', '\u00ad']),
    (text: 'a\u00adb', lines: ['a\u00adb']),
    (text: 'a', lines: ['a']),
  ]) {
    testWidgets('negative advances preserve ${fixture.lines.length} lines: '
        '${fixture.text.runes.toList()}', (tester) async {
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap(
            fixture.text,
            style: const TextStyle(letterSpacing: -20),
            model: offsetModel([]),
            strategy: offsetStrategy([]),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final result = wrapRender(tester).result!;
      expect(result.lines, fixture.lines);
      expect(result.widths, everyElement(0));
      expect(result.reason, 'calculatedSelected');
    });
  }

  // Exercise native shaping rather than mocking widths. Negative tracking can
  // make an otherwise zero-width line have a negative advance in Flutter.
  final controls = <String, String>{
    'soft hyphen': '\u00ad',
    'null': '\u0000',
    'tab': '\t',
    'combining grapheme joiner': '\u034f',
    'Arabic letter mark': '\u061c',
    'Mongolian vowel separator': '\u180e',
    'zero width space': '\u200b',
    'zero width non-joiner': '\u200c',
    'zero width joiner': '\u200d',
    'left-to-right mark': '\u200e',
    'right-to-left mark': '\u200f',
    'left-to-right embedding': '\u202a',
    'right-to-left embedding': '\u202b',
    'pop directional formatting': '\u202c',
    'left-to-right override': '\u202d',
    'right-to-left override': '\u202e',
    'word joiner': '\u2060',
    'function application': '\u2061',
    'invisible times': '\u2062',
    'invisible separator': '\u2063',
    'invisible plus': '\u2064',
    'left-to-right isolate': '\u2066',
    'right-to-left isolate': '\u2067',
    'first strong isolate': '\u2068',
    'pop directional isolate': '\u2069',
    'variation selector': '\ufe0f',
    'byte order mark': '\ufeff',
    'interlinear annotation anchor': '\ufff9',
    'interlinear annotation separator': '\ufffa',
    'interlinear annotation terminator': '\ufffb',
    'language tag': '\u{e0001}',
    'tag character': '\u{e0061}',
    'supplementary variation selector': '\u{e0100}',
    'repeated controls': '\u00ad\u200b\u2060\ufeff',
  };

  for (final fixture in controls.entries) {
    for (final rich in [false, true]) {
      for (final mode in ['native', 'calculated', 'applied', 'fallback']) {
        testWidgets('${fixture.key} rich=$rich mode=$mode', (tester) async {
          final applied = mode == 'applied';
          final firstLine = applied ? '11 11' : '1111';
          final text = '$firstLine\n${fixture.value}\n3333';
          final offsets = applied ? [3] : <int>[];
          const style = TextStyle(letterSpacing: -1);
          final model = mode == 'calculated' || applied
              ? offsetModel(offsets)
              : null;
          final strategy = mode == 'calculated' || applied
              ? offsetStrategy(offsets)
              : const LineBreakStrategy();
          await tester.pumpWidget(
            wrapHost(
              rich
                  ? TextAutoWrap.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '$firstLine\n'),
                          TextSpan(text: fixture.value),
                          const TextSpan(text: '\n3333'),
                        ],
                      ),
                      style: style,
                      model: model,
                      strategy: strategy,
                      softWrap: mode != 'fallback',
                    )
                  : TextAutoWrap(
                      text,
                      style: style,
                      model: model,
                      strategy: strategy,
                      softWrap: mode != 'fallback',
                    ),
            ),
          );

          expect(tester.takeException(), isNull);
          final render = wrapRender(tester);
          final result = render.result!;
          if (fixture.key == 'null' ||
              fixture.key == 'variation selector' ||
              fixture.key == 'supplementary variation selector') {
            // CanvasKit can absorb the LF following NUL into the same painted
            // line. Verify its actual source geometry instead of inventing an
            // empty line or forcing a transformation the engine cannot paint.
            // Flutter 3.38 can similarly attach a VS after LF to the prior line.
            final native = TextPainter(
              text: TextSpan(text: text, style: wrapStyle.merge(style)),
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: 100);
            try {
              final metrics = native.computeLineMetrics();
              if (metrics.length == 2) {
                expect(result.sourceText, text);
                expect(
                  result.lines,
                  fixture.key == 'null'
                      ? [firstLine, '\u0000\n3333']
                      : ['$firstLine\n${fixture.value}', '3333'],
                );
                expect(result.lineCount, metrics.length);
                expect(
                  result.widths,
                  metrics.map((line) => line.width).toList(),
                );
                expect(result.applied, isFalse);
                expect(render.effectiveText, same(render.sourceText));
                expect(render.effectiveText.toPlainText(), text);
                if (mode == 'calculated' || applied) {
                  expect(result.reason, 'invalidRuntimeMeasurement');
                  expect(
                    render.failures.single.stage,
                    TextWrapFailureStage.semanticLayout,
                  );
                }
                return;
              }
            } finally {
              native.dispose();
            }
          }
          expect(result.sourceText, text);
          expect(result.lines, [
            if (applied) ...['11 ', '11'] else '1111',
            fixture.value,
            '3333',
          ]);
          expect(result.ranges.map((range) => (range.start, range.end)), [
            if (applied) ...[(0, 3), (3, 5)] else (0, 4),
            (firstLine.length + 1, firstLine.length + 1 + fixture.value.length),
            (firstLine.length + 2 + fixture.value.length, text.length),
          ]);
          expect(result.lineCount, applied ? 4 : 3);
          expect(result.widths.every((w) => w.isFinite && w >= 0), isTrue);
          expect(result.layout.maxLineWidth, greaterThan(0));
          if (fixture.key == 'soft hyphen' && !applied) {
            expect(result.widths, [36, 0, 36]);
          }
          expect(result.layout.imbalance, inInclusiveRange(0, 1));
          expect(
            render.effectiveText.toPlainText(),
            applied ? '11 \n11\n${fixture.value}\n3333' : text,
          );
          expect(result.applied, applied);
          if (mode == 'calculated' || applied) {
            expect(result.reason, 'calculatedSelected');
            expect(result.source, TextWrapSelectionSource.calculated);
          } else if (mode == 'fallback') {
            expect(result.reason, 'softWrapDisabled');
          }
        });
      }
    }
  }
}
