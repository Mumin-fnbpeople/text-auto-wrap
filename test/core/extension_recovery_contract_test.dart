import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

PhraseModel _model(BoundaryPredictor predictor) => PhraseModel(
  levels: [PhraseModelLevel(name: 'p', predictor: predictor, penalty: 0)],
  fallbackPenalty: 1,
);

final class _Predictor implements BoundaryPredictor {
  _Predictor(this.callback);
  final List<int> Function(String) callback;
  @override
  List<int> predict(String text) => callback(text);
}

final class _Aggregator implements PredictionAggregator {
  int calls = 0;
  @override
  PredictionSnapshot aggregate(
    PredictionContext context, {
    List<BreakPrediction>? predictions,
  }) {
    if (++calls == 1) throw StateError('aggregation fails once');
    return lowestPenalty().aggregate(context, predictions: predictions);
  }
}

final class _Selector implements LayoutSelector {
  _Selector(this.callback);
  final LayoutSelectionDecision Function(LayoutSelectionContext) callback;
  @override
  LayoutSelectionDecision select(LayoutSelectionContext context) =>
      callback(context);
}

final class _MetadataCalculator implements LayoutCalculator {
  _MetadataCalculator(this.field);
  final String field;
  bool invalid = true;

  @override
  LayoutCalculationResult calculate({
    required String text,
    required List<BreakCandidate> candidates,
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? baseline,
  }) {
    final original = candidates.single;
    final copy = BreakCandidate(
      offset: original.offset,
      penalty: invalid && field == 'penalty'
          ? original.penalty + 1
          : original.penalty,
      levelName: invalid && field == 'levelName'
          ? 'forged'
          : original.levelName,
      consensusCount: invalid && field == 'consensusCount'
          ? original.consensusCount + 1
          : original.consensusCount,
      isFallback: invalid && field == 'isFallback'
          ? !original.isFallback
          : original.isFallback,
    );
    return LayoutCalculationSuccess([
      LineBreakLayoutCandidate(
        sourceText: text,
        selectedCandidates: [copy],
      ).measure(maxWidth: maxWidth, measureRange: measureRange),
    ]);
  }
}

void main() {
  for (final field in [
    'penalty',
    'levelName',
    'consensusCount',
    'isFallback',
  ]) {
    test('rejects changed $field and recovers with equal-value copies', () {
      final calculator = _MetadataCalculator(field);
      final plan = createTextWrapPlan(
        text: 'aa bb',
        model: _model(_Predictor((_) => [3])),
        strategy: LineBreakStrategy(calculator: calculator),
      );
      expect(
        () => plan.select(
          maxWidth: 2,
          measureRange: (start, end) => (end - start).toDouble(),
        ),
        throwsA(isA<InvalidModelConfigurationException>()),
      );
      calculator.invalid = false;
      final recovered = plan.select(
        maxWidth: 2,
        measureRange: (start, end) => (end - start).toDouble(),
      );
      expect(recovered.applied, isTrue);
      expect(recovered.lines, ['aa', 'bb']);
      expect(recovered.layout.selectedCandidates.single.levelName, 'p');
      expect(recovered.layout.totalModelCost, 0);
    });
  }

  test('a failed prediction publishes no partial level snapshot', () {
    var firstCalls = 0;
    var secondCalls = 0;
    final plan = createTextWrapPlan(
      text: 'aa bb cc',
      model: PhraseModel(
        levels: [
          PhraseModelLevel(
            name: 'first',
            predictor: _Predictor((_) {
              firstCalls++;
              return [3];
            }),
            penalty: 0,
          ),
          PhraseModelLevel(
            name: 'second',
            predictor: _Predictor((_) {
              if (++secondCalls == 1) throw StateError('prediction fails once');
              return [6];
            }),
            penalty: 1,
          ),
        ],
        fallbackPenalty: 2,
      ),
    );
    expect(plan.predict, throwsStateError);
    final predictions = plan.predict();
    expect(predictions.map((p) => p.offsets), [
      [3],
      [6],
    ]);
    expect(firstCalls, 2);
    expect(secondCalls, 2);
    expect(identical(plan.predict(), predictions), isTrue);
    final result = plan.select(
      maxWidth: 2,
      measureRange: (start, end) => (end - start).toDouble(),
      diagnostics: true,
    );
    expect(result.applied, isTrue);
    expect(result.lines, ['aa', 'bb', 'cc']);
    expect(result.diagnostics!.cache.predictionRuns, 1);
  });

  test(
    'aggregation failure retains only the successful prediction snapshot',
    () {
      var predictionCalls = 0;
      final aggregator = _Aggregator();
      final plan = createTextWrapPlan(
        text: 'aa bb',
        model: _model(
          _Predictor((_) {
            predictionCalls++;
            return [3];
          }),
        ),
        strategy: LineBreakStrategy(aggregator: aggregator),
      );
      expect(plan.aggregate, throwsStateError);
      final result = plan.select(
        maxWidth: 2,
        measureRange: (start, end) => (end - start).toDouble(),
        diagnostics: true,
      );
      expect(result.applied, isTrue);
      expect(result.lines, ['aa', 'bb']);
      expect(predictionCalls, 1);
      expect(aggregator.calls, 2);
      expect(result.diagnostics!.cache.aggregationRuns, 1);
    },
  );

  test('failed nested measurement preserves each cache generation', () {
    final plan = createTextWrapPlan(
      text: 'aa bb',
      model: _model(_Predictor((_) => [3])),
    );
    final outerKey = Object();
    final innerKey = Object();
    var reentered = false;
    var innerCalls = 0;
    double innerMeasure(int start, int end) {
      if (++innerCalls == 2) throw StateError('nested measurement fails once');
      return (end - start) * 2.0;
    }

    final outer = plan.select(
      maxWidth: 5,
      measurementCacheKey: outerKey,
      measureRange: (start, end) {
        if (!reentered) {
          reentered = true;
          expect(
            () => plan.select(
              maxWidth: 5,
              measurementCacheKey: innerKey,
              measureRange: innerMeasure,
            ),
            throwsStateError,
          );
        }
        return (end - start).toDouble();
      },
    );
    expect(outer.lines, ['aa bb']);
    expect(outer.widths, [5]);
    final inner = plan.select(
      maxWidth: 5,
      measurementCacheKey: innerKey,
      measureRange: innerMeasure,
    );
    expect(inner.applied, isTrue);
    expect(inner.lines, ['aa', 'bb']);
    expect(inner.widths, [4, 4]);
    final measured = innerCalls;
    plan.select(
      maxWidth: 5,
      measurementCacheKey: innerKey,
      measureRange: innerMeasure,
    );
    expect(innerCalls, measured);
  });

  test(
    'selector failure after reentry preserves nested selection and cache',
    () {
      late TextWrapPlan plan;
      var nesting = false;
      var fail = true;
      TextWrapResult? nested;
      final innerKey = Object();
      final outerKey = Object();
      var innerCalls = 0;
      plan = createTextWrapPlan(
        text: 'aa bb',
        model: _model(_Predictor((_) => [3])),
        strategy: LineBreakStrategy(
          selector: _Selector((context) {
            if (!nesting && fail) {
              nesting = true;
              try {
                nested = plan.select(
                  maxWidth: 5,
                  measurementCacheKey: innerKey,
                  measureRange: (start, end) {
                    innerCalls++;
                    return (end - start) * 2.0;
                  },
                );
              } finally {
                nesting = false;
              }
              fail = false;
              throw StateError('selector fails after nested success');
            }
            return const BalanceStrategy().select(context);
          }),
        ),
      );
      expect(
        () => plan.select(
          maxWidth: 5,
          measurementCacheKey: outerKey,
          measureRange: (start, end) => (end - start).toDouble(),
        ),
        throwsStateError,
      );
      expect(nested!.applied, isTrue);
      expect(nested!.widths, [4, 4]);
      final measured = innerCalls;
      final recovered = plan.select(
        maxWidth: 5,
        measurementCacheKey: innerKey,
        measureRange: (start, end) {
          innerCalls++;
          return (end - start) * 2.0;
        },
        diagnostics: true,
      );
      expect(recovered.applied, isTrue);
      expect(recovered.widths, [4, 4]);
      expect(innerCalls, measured);
      expect(recovered.diagnostics!.cache.selectionRuns, 2);
    },
  );
}
