import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  test(
    'greedy and forced-overflow strategies match independent source cuts',
    () {
      const seed = 0x4f564552;
      final random = math.Random(seed);
      var overlappingCases = 0;
      for (var trial = 0; trial < 1800; trial++) {
        final tokens = <String>[
          for (var i = 0; i < 2 + random.nextInt(7); i++)
            ['a', ' ', '\t', '\n', '\r\n'][random.nextInt(5)],
        ];
        final text = tokens.join();
        final offsets = <int>[];
        var position = 0;
        for (final token in tokens) {
          position += token.length;
          if (position < text.length) offsets.add(position);
        }
        final candidates = [
          for (final offset in offsets)
            BreakCandidate(
              offset: offset,
              penalty: random.nextInt(5).toDouble(),
              levelName: 'overflow-oracle',
              consensusCount: 1,
              isFallback: false,
            ),
        ];
        final forcedOverflow = trial.isEven;
        final maxWidth = trial % 3 == 0 ? 0.0 : 7.0;
        final widths = <(int, int), double>{
          for (var start = 0; start <= text.length; start++)
            for (var end = start; end <= text.length; end++)
              (start, end): forcedOverflow
                  ? [8.0, 1e308][random.nextInt(2)]
                  : [0.0, 1e-320, 1.0, 7.0, 8.0, 1e308][random.nextInt(6)],
        };
        final expectedRanges = <(int, int)>[];
        final expectedCuts = <int>[];
        var paragraphStart = 0;
        final hardBreaks = RegExp(r'\r\n|\n').allMatches(text).toList();
        for (var paragraph = 0; paragraph <= hardBreaks.length; paragraph++) {
          final paragraphEnd = paragraph == hardBreaks.length
              ? text.length
              : hardBreaks[paragraph].start;
          final available = offsets
              .where(
                (offset) => offset > paragraphStart && offset < paragraphEnd,
              )
              .toList();
          var start = paragraphStart;
          var firstIndex = 0;
          while (true) {
            final options = <({int index, int end, int next, int? cut})>[];
            for (var index = firstIndex; index <= available.length; index++) {
              final cut = index == available.length ? null : available[index];
              var end = cut ?? paragraphEnd;
              var next = end;
              if (cut != null) {
                while (end > paragraphStart &&
                    _space(text.codeUnitAt(end - 1))) {
                  end--;
                }
                while (next < paragraphEnd && _space(text.codeUnitAt(next))) {
                  next++;
                }
              }
              if (end < start) {
                overlappingCases++;
                continue;
              }
              options.add((index: index, end: end, next: next, cut: cut));
            }
            final fitting = options.where(
              (o) => widths[(start, o.end)]! <= maxWidth,
            );
            final choice = fitting.isEmpty ? options.first : fitting.last;
            expectedRanges.add((start, choice.end));
            if (choice.cut == null) break;
            expectedCuts.add(choice.cut!);
            start = choice.next;
            firstIndex = choice.index + 1;
          }
          if (paragraph < hardBreaks.length) {
            paragraphStart = hardBreaks[paragraph].end;
          }
        }
        final reason = 'seed $seed trial $trial UTF-16 ${text.codeUnits}';
        for (final calculator in [
          greedy(),
          if (forcedOverflow) optimalLayouts(),
          nearbyLayouts(radius: 0),
        ]) {
          final requested = <(int, int)>{};
          final result = calculator.calculate(
            text: text,
            candidates: candidates,
            maxWidth: maxWidth,
            measureRange: (start, end) {
              expect(start, lessThanOrEqualTo(end), reason: reason);
              expect(
                text.substring(start, end).contains(RegExp(r'[\r\n]')),
                isFalse,
                reason: reason,
              );
              expect(requested.add((start, end)), isTrue, reason: reason);
              return widths[(start, end)]!;
            },
          );
          expect(result, isA<LayoutCalculationSuccess>(), reason: reason);
          final actual = (result as LayoutCalculationSuccess).layouts.single;
          expect(
            actual.ranges.map((r) => (r.start, r.end)).toList(),
            expectedRanges,
            reason: reason,
          );
          expect(actual.breakOffsets, expectedCuts, reason: reason);
          expect(
            actual.widths,
            expectedRanges.map((r) => widths[r]).toList(),
            reason: reason,
          );
          expect(actual.totalModelCost.isFinite, isTrue, reason: reason);
          expect(actual.imbalance.isFinite, isTrue, reason: reason);
          expect(
            actual.overflow,
            expectedRanges.any((r) => widths[r]! > maxWidth),
            reason: reason,
          );
        }
      }
      expect(overlappingCases, greaterThan(100));
    },
  );
}

bool _space(int unit) => unit == 0x20 || unit == 0x09;
