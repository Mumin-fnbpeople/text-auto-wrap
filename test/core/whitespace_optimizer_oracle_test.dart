import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  test(
    'whitespace and hard-break optimizer matches independent source cuts',
    () {
      final random = math.Random(0x57535043);
      var fittingCases = 0;
      var trial = 0;
      for (final source in _sources(random)) {
        trial++;
        final text = source.$1;
        final length = text.length;
        final candidates = [
          for (final offset in source.$2)
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
              (start, end): random.nextInt(13).toDouble(),
        };
        final eligible = candidates
            .where(
              (c) =>
                  text[c.offset - 1] != '\n' &&
                  text[c.offset] != '\n' &&
                  text[c.offset] != '\r',
            )
            .toList();
        final fitting =
            <
              ({
                int lines,
                double cost,
                double imbalance,
                String ranges,
                String cuts,
              })
            >[];
        for (var mask = 0; mask < 1 << eligible.length; mask++) {
          final cuts = <int>{};
          var cost = 0.0;
          for (var i = 0; i < eligible.length; i++) {
            if (mask & (1 << i) != 0) {
              cuts.add(eligible[i].offset);
              cost += eligible[i].penalty;
            }
          }
          final measured = <double>[];
          final ranges = <(int, int)>[];
          var start = 0;
          var valid = true;
          for (var offset = 0; offset <= length; offset++) {
            if (offset == length ||
                text[offset] == '\n' ||
                text[offset] == '\r') {
              if (start > offset) {
                valid = false;
                break;
              }
              ranges.add((start, offset));
              measured.add(widths[(start, offset)]!);
              if (offset < length && text[offset] == '\r') offset++;
              start = offset + 1;
            } else if (cuts.contains(offset)) {
              var left = offset;
              var right = offset;
              while (left > 0 &&
                  (text[left - 1] == ' ' || text[left - 1] == '\t')) {
                left--;
              }
              while (right < length &&
                  (text[right] == ' ' || text[right] == '\t')) {
                right++;
              }
              if (left < start) {
                valid = false;
                break;
              }
              ranges.add((start, left));
              measured.add(widths[(start, left)]!);
              start = right;
            }
          }
          if (!valid || measured.any((w) => w > 7)) continue;
          final maximum = measured.reduce(math.max);
          fitting.add((
            lines: measured.length,
            ranges: ranges.join(','),
            cuts: cuts.join(','),
            cost: cost,
            imbalance: maximum == 0
                ? 0
                : (maximum - measured.reduce(math.min)) / maximum,
          ));
        }
        if (fitting.isEmpty) continue;
        fittingCases++;
        final minimum = fitting.map((e) => e.lines).reduce(math.min);
        final minimal = fitting.where((e) => e.lines == minimum).toList();
        final expected = minimal
            .where(
              (e) => !minimal.any(
                (o) =>
                    o.cost <= e.cost &&
                    o.imbalance <= e.imbalance &&
                    (o.cost < e.cost || o.imbalance < e.imbalance),
              ),
            )
            .map((e) => (e.cost, e.imbalance))
            .toSet();
        final result = optimalLayouts().calculate(
          text: text,
          candidates: candidates,
          maxWidth: 7,
          measureRange: (s, e) {
            final endpoints = {0, ...source.$2, length};
            expect(endpoints, contains(s));
            expect(endpoints, contains(e));
            expect(text.substring(s, e), isNot(contains(RegExp(r'[\r\n]'))));
            return widths[(s, e)]!;
          },
        );
        expect(
          result,
          isA<LayoutCalculationSuccess>(),
          reason: 'trial $trial ${text.codeUnits}',
        );
        final layouts = (result as LayoutCalculationSuccess).layouts;
        expect(
          layouts.every((l) => !l.overflow && l.lineCount == minimum),
          isTrue,
          reason: 'trial $trial ${text.codeUnits}',
        );
        expect(
          layouts.map((l) => (l.totalModelCost, l.imbalance)).toSet(),
          expected,
          reason: 'trial $trial ${text.codeUnits}',
        );
        expect(layouts.length, expected.length, reason: 'trial $trial ties');
        for (final layout in layouts) {
          final ranges = layout.ranges.map((r) => (r.start, r.end)).join(',');
          expect(
            fitting.any(
              (entry) =>
                  entry.ranges == ranges &&
                  entry.cuts == layout.breakOffsets.join(',') &&
                  entry.cost == layout.totalModelCost,
            ),
            isTrue,
            reason: 'trial $trial exact source ranges',
          );
        }
      }
      expect(trial, 3780);
      expect(fittingCases, greaterThan(300));
    },
  );
}

// Offsets come from the fixture tokens, independently of package segmentation.
// Exhaust every token string of lengths one through four, then add random
// whitespace-heavy inputs with many boundaries in the same whitespace run.
Iterable<(String, List<int>)> _sources(math.Random random) sync* {
  const alphabet = ['a', 'e\u0301', '👩‍💻', ' ', '\r\n'];
  for (var length = 1; length <= 4; length++) {
    final count = math.pow(alphabet.length, length).toInt();
    for (var encoded = 0; encoded < count; encoded++) {
      var value = encoded;
      final tokens = <String>[];
      for (var index = 0; index < length; index++) {
        tokens.add(alphabet[value % alphabet.length]);
        value ~/= alphabet.length;
      }
      final offsets = <int>[];
      var offset = 0;
      for (final token in tokens.take(tokens.length - 1)) {
        offset += token.length;
        offsets.add(offset);
      }
      yield (tokens.join(), offsets);
    }
  }
  for (var trial = 0; trial < 3000; trial++) {
    final length = 2 + random.nextInt(7);
    yield (
      List.generate(
        length,
        (_) => ['a', ' ', '\t', '\n'][random.nextInt(4)],
      ).join(),
      [for (var offset = 1; offset < length; offset++) offset],
    );
  }
}
