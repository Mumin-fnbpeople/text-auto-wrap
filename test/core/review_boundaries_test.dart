import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  test('a grapheme endpoint after ZWJ is not a soft break', () {
    expect(allowedBoundaries('가\u200d나', BoundaryMode.characters), isEmpty);
    expect(
      () => validateOffsets('가\u200d나', [2]),
      throwsA(isA<InvalidBoundaryException>()),
    );
    expect(allowedBoundaries('A\u200bB', BoundaryMode.characters), contains(2));
  });

  test('numeric groups and opening and closing punctuation stay together', () {
    const text = '가격은 12,345원입니다';
    final offsets = allowedBoundaries(text, BoundaryMode.characters);
    for (final offset in [5, 6, 7, 8, 9]) {
      expect(offsets, isNot(contains(offset)));
    }
    expect(allowedBoundaries('안내(필독)', BoundaryMode.characters), [1, 2, 4]);
    expect(allowedBoundaries('안내（필독）', BoundaryMode.characters), [1, 2, 4]);
    expect(allowedBoundaries('가(  나)', BoundaryMode.spaces), isEmpty);
  });

  for (final delimiter in ['\u0085', '\u000b', '\u000c']) {
    test(
      'core hard break ${delimiter.codeUnitAt(0)} never reaches shaping',
      () {
        final text = 'a${delimiter}b';
        final layout =
            LineBreakLayoutCandidate(
              sourceText: text,
              selectedCandidates: const [],
            ).measure(
              maxWidth: 100,
              measureRange: (start, end) {
                expect(text.substring(start, end), isNot(contains(delimiter)));
                return (end - start).toDouble();
              },
            );
        expect(layout.lines, ['a', 'b']);
        expect(layout.ranges.map((range) => (range.start, range.end)), [
          (0, 1),
          (2, 3),
        ]);
      },
    );
  }

  test(
    'native emergency breaks are not relabeled as semantic opportunities',
    () {
      final native = LineBreakLayout(
        sourceText: '12',
        ranges: const [TextLineRange(0, 1), TextLineRange(1, 2)],
        widths: [1, 1],
        maxWidth: 1,
      );
      final plan = createTextWrapPlan(
        text: '12',
        model: PhraseModel(
          levels: [
            PhraseModelLevel(
              name: 'none',
              predictor: _CountingPredictor(),
              penalty: 0,
            ),
          ],
          fallbackPenalty: 1,
          boundaryMode: BoundaryMode.characters,
        ),
      );
      final result = plan.select(
        maxWidth: 1,
        nativeLayout: native,
        measureRange: (start, end) => (end - start).toDouble(),
      );
      expect(result.source, TextWrapSelectionSource.native);
      expect(result.lines, ['1', '2']);
      expect(result.breakOffsets, isEmpty);
    },
  );

  test('million code units bypass predictors and all semantic measurement', () {
    for (final text in ['가' * 1000000, '가${' ' * 1000000}나']) {
      final predictor = _CountingPredictor();
      final plan = createTextWrapPlan(
        text: text,
        model: PhraseModel(
          levels: [
            PhraseModelLevel(name: 'probe', predictor: predictor, penalty: 0),
          ],
          fallbackPenalty: 1,
        ),
      );
      var measurements = 0;
      expect(
        () => plan.calculate(
          maxWidth: 100,
          measureRange: (_, _) {
            measurements++;
            throw StateError('must not shape oversized semantic input');
          },
        ),
        throwsA(
          isA<TextWrapInputLimitException>().having(
            (error) => error.message,
            'message',
            contains('65536'),
          ),
        ),
      );
      expect(plan.text, same(text));
      expect(predictor.calls, 0);
      expect(measurements, 0);
    }
  });

  test('oversized prediction and selection guard before user callbacks', () {
    final text = 'a' * (maxSemanticTextLength + 1);
    final predictor = _CountingPredictor();
    final plan = createTextWrapPlan(
      text: text,
      model: PhraseModel(
        levels: [
          PhraseModelLevel(name: 'probe', predictor: predictor, penalty: 0),
        ],
        fallbackPenalty: 1,
      ),
    );
    for (final action in <Object? Function()>[plan.predict, plan.aggregate]) {
      expect(action, throwsA(isA<TextWrapInputLimitException>()));
    }
    var measurements = 0;
    double measure(int start, int end) {
      measurements++;
      return 1;
    }

    for (final calculator in [optimalLayouts(), greedy(), nearbyLayouts()]) {
      expect(
        () => calculator.calculate(
          text: text,
          candidates: const [],
          maxWidth: 10,
          measureRange: measure,
        ),
        throwsA(isA<TextWrapInputLimitException>()),
      );
    }
    expect(
      () => plan.select(maxWidth: 10, measureRange: measure),
      throwsA(isA<TextWrapInputLimitException>()),
    );
    final native = LineBreakLayout(
      sourceText: text,
      ranges: [TextLineRange(0, text.length)],
      widths: [3],
      maxWidth: 10,
    );
    final result = plan.select(
      maxWidth: 10,
      measureRange: measure,
      nativeLayout: native,
      diagnostics: true,
    );
    expect(result.layout, same(native));
    expect(result.sourceText, same(text));
    expect(result.reason, 'inputLimit');
    expect(result.source, TextWrapSelectionSource.native);
    expect(result.applied, isFalse);
    expect(result.diagnostics!.calculationLimit, isNull);
    expect(result.diagnostics!.candidates, isEmpty);
    expect(predictor.calls, 0);
    expect(measurements, 0);
  });

  test('semantic input at the existing length ceiling remains calculable', () {
    expect(maxSemanticTextLength, 65536);
    final text = 'a' * maxSemanticTextLength;
    for (final calculator in [optimalLayouts(), greedy(), nearbyLayouts()]) {
      var measurements = 0;
      final result = calculator.calculate(
        text: text,
        candidates: const [],
        maxWidth: 10,
        measureRange: (_, _) {
          measurements++;
          return 1;
        },
      );
      expect(result, isA<LayoutCalculationSuccess>());
      final layout = (result as LayoutCalculationSuccess).layouts.single;
      expect(layout.sourceText, same(text));
      expect(layout.lines, [text]);
      expect(layout.widths, [1]);
      expect(layout.overflow, isFalse);
      expect(measurements, 1);
    }
  });
}

class _CountingPredictor implements BoundaryPredictor {
  int calls = 0;
  @override
  List<int> predict(String text) {
    calls++;
    return [];
  }
}
