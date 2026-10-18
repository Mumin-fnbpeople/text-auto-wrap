import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  test(
    'many hard breaks reach a typed limit before shaping and allow reuse',
    () {
      final text = '${'a\r\n' * 18000}z';
      for (final calculator in [optimalLayouts(), greedy(), nearbyLayouts()]) {
        var measurements = 0;
        final result = calculator.calculate(
          text: text,
          candidates: const [],
          maxWidth: 10,
          measureRange: (start, end) {
            measurements++;
            return (end - start).toDouble();
          },
        );
        expect(result, isA<LayoutCalculationLimit>());
        final limit = result as LayoutCalculationLimit;
        expect(limit.kind, LayoutCalculationLimitKind.states);
        expect(limit.limit, 16384);
        expect(limit.observedCount, 16385);
        expect(measurements, 0);

        final recovered = calculator.calculate(
          text: 'abc',
          candidates: const [],
          maxWidth: 10,
          measureRange: (start, end) => (end - start).toDouble(),
        );
        expect(recovered, isA<LayoutCalculationSuccess>());
        final layout = (recovered as LayoutCalculationSuccess).layouts.single;
        expect(layout.sourceText, 'abc');
        expect(layout.lines, ['abc']);
        expect(layout.widths, [3]);
        expect(layout.overflow, isFalse);
      }
    },
  );
}
