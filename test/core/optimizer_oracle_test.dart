import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  test('optimal metrics match exhaustive short nonmonotonic layouts', () {
    final random = math.Random(0x50415245);
    var fittingCases = 0;
    for (var trial = 0; trial < 600; trial++) {
      final length = 2 + random.nextInt(6);
      final hardBreak = trial.isEven ? 1 + random.nextInt(length - 1) : -1;
      final text = List.generate(
        length,
        (i) => i == hardBreak ? '\n' : 'a',
      ).join();
      final candidates = [
        for (var offset = 1; offset < length; offset++)
          if (offset != hardBreak && offset != hardBreak + 1)
            BreakCandidate(
              offset: offset,
              penalty: random.nextInt(4).toDouble(),
              levelName: 'oracle',
              consensusCount: 1,
              isFallback: false,
            ),
      ];
      final widths = <(int, int), double>{
        for (var start = 0; start <= length; start++)
          for (var end = start; end <= length; end++)
            (start, end): start == end ? 0 : random.nextInt(13).toDouble(),
      };
      const maxWidth = 7.0;
      // Enumerate source cuts directly, without using the layout builder or
      // dynamic-programming implementation to construct expected results.
      final fitting = <({int lines, double cost, double imbalance})>[];
      for (var mask = 0; mask < 1 << candidates.length; mask++) {
        final cuts = <int>{};
        var cost = 0.0;
        for (var index = 0; index < candidates.length; index++) {
          if (mask & (1 << index) != 0) {
            cuts.add(candidates[index].offset);
            cost += candidates[index].penalty;
          }
        }
        final measured = <double>[];
        var start = 0;
        for (var offset = 0; offset <= length; offset++) {
          if (cuts.contains(offset) ||
              offset == length ||
              offset == hardBreak) {
            measured.add(widths[(start, offset)]!);
            start = offset == hardBreak ? offset + 1 : offset;
          }
        }
        if (measured.any((width) => width > maxWidth)) continue;
        final maximum = measured.reduce(math.max);
        fitting.add((
          lines: measured.length,
          cost: cost,
          imbalance: maximum == 0
              ? 0
              : (maximum - measured.reduce(math.min)) / maximum,
        ));
      }
      // Overflow fallback has a separate contract.
      if (fitting.isEmpty) {
        continue;
      }
      fittingCases++;
      final minimumLines = fitting.map((entry) => entry.lines).reduce(math.min);
      final minimal = fitting
          .where((entry) => entry.lines == minimumLines)
          .toList();
      final expected = minimal
          .where(
            (entry) => !minimal.any(
              (other) =>
                  other.cost <= entry.cost &&
                  other.imbalance <= entry.imbalance &&
                  (other.cost < entry.cost ||
                      other.imbalance < entry.imbalance),
            ),
          )
          .map((entry) => (entry.cost, entry.imbalance))
          .toSet();
      final result = optimalLayouts().calculate(
        text: text,
        candidates: candidates,
        maxWidth: maxWidth,
        measureRange: (start, end) => widths[(start, end)]!,
      );
      expect(result, isA<LayoutCalculationSuccess>(), reason: 'trial $trial');
      final actual = (result as LayoutCalculationSuccess).layouts;
      expect(
        actual.every(
          (layout) => !layout.overflow && layout.lineCount == minimumLines,
        ),
        isTrue,
        reason: 'trial $trial',
      );
      expect(actual.length, expected.length, reason: 'trial $trial ties');
      expect(
        actual
            .map((layout) => (layout.totalModelCost, layout.imbalance))
            .toSet(),
        expected,
        reason: 'trial $trial',
      );
    }
    expect(fittingCases, greaterThan(200));
  });
}
