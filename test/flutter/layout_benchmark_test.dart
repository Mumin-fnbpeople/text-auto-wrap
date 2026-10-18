import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../support/layout_benchmark_harness.dart';

void main() {
  testWidgets(
    'renderer benchmark records real rich scenarios and warm cache reuse',
    (tester) async {
      List<Map<String, Object?>>? rows;

      await tester.pumpWidget(
        BenchmarkHarness(
          iterations: const int.fromEnvironment(
            'TEXT_AUTO_WRAP_BENCHMARK_ITERATIONS',
            defaultValue: 2,
          ),
          onComplete: (value) => rows = value,
        ),
      );
      await tester.pumpAndSettle();

      expect(rows, hasLength(24));
      final completed = rows!;
      if (const bool.fromEnvironment('TEXT_AUTO_WRAP_BENCHMARK_REPORT')) {
        for (final row in completed) {
          // ignore: avoid_print
          print(jsonEncode(row));
        }
      }
      expect(
        completed.map((row) => row['scenario']),
        containsAll(<String>[
          'nested-100-spans',
          'placeholders-20',
          'intrinsic-timeline-12',
          'intrinsic-table-12',
          'survey-grid-12',
          'rich-search-list-12',
          'scaled-widget-spans-12',
          'equal-height-three-passes-12',
        ]),
      );
      expect(
        completed.singleWhere(
          (row) =>
              row['scenario'] == 'nested-100-spans' && row['cache'] == 'warm',
        )['richSpanCount'],
        100,
      );
      expect(
        completed.singleWhere(
          (row) =>
              row['scenario'] == 'placeholders-20' && row['cache'] == 'warm',
        )['placeholderCount'],
        20,
      );
      for (final row in completed.where((row) => row['cache'] == 'warm')) {
        expect(row['cacheHits'], greaterThan(0));
      }
      for (final row in completed.where(
        (row) => (row['scenario']! as String).endsWith('-12'),
      )) {
        expect(row['rendererCount'], 12);
      }
      expect(
        completed.singleWhere(
          (row) =>
              row['scenario'] == 'scaled-widget-spans-12' &&
              row['cache'] == 'warm',
        )['textScale'],
        1.5,
      );
    },
  );
}
