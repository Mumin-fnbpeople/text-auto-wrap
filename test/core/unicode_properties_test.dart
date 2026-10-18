import 'dart:math';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  for (final cluster in [
    'e\u0301',
    '✈\ufe0e',
    '✈\ufe0f',
    '🇰🇷',
    '1\ufe0f\u20e3',
    '👩🏽‍🚀',
    '👨‍👩‍👧‍👦',
    'क\u093f',
    'ཀ\u0f71\u0f72',
    '\u{1f3f4}\u{e0067}\u{e0062}\u{e0073}\u{e0063}\u{e0074}\u{e007f}',
  ]) {
    test('source cluster ${cluster.codeUnits} stays indivisible', () {
      expect(allowedBoundaries('x${cluster}y', BoundaryMode.characters), [
        1,
        cluster.length + 1,
      ]);
      final text = 'x${cluster}y';
      final layout =
          LineBreakLayoutCandidate(
            sourceText: text,
            selectedCandidates: [_candidate(1), _candidate(cluster.length + 1)],
          ).measure(
            maxWidth: 2,
            measureRange: (start, end) =>
                text.substring(start, end).characters.length.toDouble(),
          );
      expect(layout.lines, ['x', cluster, 'y']);
      expect(layout.lines.join().codeUnits, text.codeUnits);
      expect(layout.widths, [1, 1, 1]);
    });
  }

  test('every frozen GL/WJ scalar suppresses adjacent opportunities', () {
    // Independent fixture expanded from Unicode 16.0.0 LineBreak.txt GL/WJ.
    // https://www.unicode.org/Public/16.0.0/ucd/LineBreak.txt
    const glue =
        '\u00a0\u034f\u035c\u035d\u035e\u035f\u0360\u0361\u0362'
        '\u0f08\u0f0c\u0f12\u0fd9\u0fda\u180e\u1dcd\u1dfc'
        '\u2007\u2011\u202f\u2060\ufe20\ufe22\ufe24\ufe26\ufe27'
        '\ufe29\ufe2b\ufe2d\ufe2e\ufeff\u{1107f}'
        '\u{13430}\u{13431}\u{13432}\u{13433}\u{13434}\u{13435}\u{13436}'
        '\u{13439}\u{1343a}\u{1343b}\u{16fe4}';
    for (final rune in glue.runes) {
      final scalar = String.fromCharCode(rune);
      expect(
        allowedBoundaries('a${scalar}b', BoundaryMode.characters),
        isEmpty,
        reason: 'U+${rune.toRadixString(16)}',
      );
      expect(
        allowedBoundaries(
          'a $scalar'
          'b',
          BoundaryMode.spaces,
        ),
        isEmpty,
      );
    }
  });

  test('all basic combining marks never create a base-internal candidate', () {
    for (var mark = 0x0300; mark <= 0x036f; mark++) {
      final cluster = 'a${String.fromCharCode(mark)}';
      final boundaries = allowedBoundaries(
        '${cluster}b',
        BoundaryMode.characters,
      );
      expect(
        boundaries,
        isNot(contains(1)),
        reason: 'U+${mark.toRadixString(16)}',
      );
      expect(boundaries.every((offset) => offset == cluster.length), isTrue);
    }
  });

  test(
    'Unicode space source survives selected ranges without normalization',
    () {
      for (final rune in [...List.generate(11, (i) => 0x2000 + i), 0x3000]) {
        final space = String.fromCharCode(rune);
        final text = 'a${space}b';
        if (rune == 0x2007) {
          expect(allowedBoundaries(text, BoundaryMode.spaces), isEmpty);
        } else {
          expect(allowedBoundaries(text, BoundaryMode.spaces), [2]);
          final layout =
              LineBreakLayoutCandidate(
                sourceText: text,
                selectedCandidates: [_candidate(2)],
              ).measure(
                maxWidth: 1,
                measureRange: (start, end) => (end - start).toDouble(),
              );
          expect(layout.lines, ['a', 'b']);
          expect(layout.sourceText.codeUnits, [0x61, rune, 0x62]);
          expect(layout.ranges.map((r) => (r.start, r.end)), [(0, 1), (2, 3)]);
        }
      }
    },
  );

  test(
    'C0 and C1 controls retain exact source and finite range measurements',
    () {
      for (final unit in [
        ...List.generate(32, (i) => i),
        ...List.generate(33, (i) => 0x7f + i),
      ]) {
        final text = 'a${String.fromCharCode(unit)}b';
        final calls = <(int, int)>[];
        final layout =
            LineBreakLayoutCandidate(
              sourceText: text,
              selectedCandidates: const [],
            ).measure(
              maxWidth: 10,
              measureRange: (start, end) {
                expect(start, inInclusiveRange(0, text.length));
                expect(end, inInclusiveRange(start, text.length));
                calls.add((start, end));
                return (end - start).toDouble();
              },
            );
        expect(layout.sourceText.codeUnits, [0x61, unit, 0x62]);
        expect(layout.widths.every((w) => w.isFinite && w >= 0), isTrue);
        expect(calls, isNotEmpty);
        // Core paragraph delimiters remain in source, outside measured lines.
        expect(
          layout.lines.join().codeUnits,
          [10, 11, 12, 13, 0x85].contains(unit)
              ? [0x61, 0x62]
              : [0x61, unit, 0x62],
        );
      }
    },
  );

  test('seeded mixed scripts retain every non-whitespace source unit', () {
    final random = Random(0x160014);
    final tokens = [
      'a',
      '한',
      'क\u093f',
      'ཀ\u0f71',
      '👩🏽‍🚀',
      '🇰🇷',
      '1\ufe0f\u20e3',
      '✈\ufe0e',
      '\u200b',
      '\u2060',
      '\u00a0',
      '\u034f',
      '\u{13430}',
      String.fromCharCode(0xd800),
      String.fromCharCode(0xdc00),
      ' ',
      '  ',
    ];
    for (var sample = 0; sample < 80; sample++) {
      final text = List.generate(
        8 + random.nextInt(16),
        (_) => tokens[random.nextInt(tokens.length)],
      ).join();
      final endpoints = <int>{0};
      var offset = 0;
      for (final cluster in text.characters) {
        offset += cluster.length;
        endpoints.add(offset);
      }
      final candidates = allowedBoundaries(
        text,
        BoundaryMode.spaces,
      ).map(_candidate).toList();
      final width = (1 + random.nextInt(9)).toDouble();
      final result =
          greedy().calculate(
                text: text,
                candidates: candidates,
                maxWidth: width,
                measureRange: (start, end) {
                  expect(
                    endpoints.contains(start) && endpoints.contains(end),
                    isTrue,
                  );
                  expect(start <= end, isTrue);
                  return text
                      .substring(start, end)
                      .characters
                      .length
                      .toDouble();
                },
              )
              as LayoutCalculationSuccess;
      for (final layout in result.layouts) {
        expect(layout.sourceText.codeUnits, text.codeUnits);
        expect(layout.widths.every((w) => w.isFinite && w >= 0), isTrue);
        var consumed = 0;
        final recovered = <int>[];
        for (final range in layout.ranges) {
          final gap = text.substring(consumed, range.start);
          expect(
            gap.codeUnits.every((unit) => unit == 0x20),
            isTrue,
            reason: 'sample $sample removed ${gap.codeUnits}',
          );
          recovered.addAll(gap.codeUnits);
          recovered.addAll(text.substring(range.start, range.end).codeUnits);
          consumed = range.end;
        }
        recovered.addAll(text.substring(consumed).codeUnits);
        expect(consumed, text.length);
        expect(recovered, text.codeUnits);
      }
    }
  });

  test('dense fitting breaks exhaust state work deterministically', () {
    final text = List.filled(250, '한').join(' ');
    final model = PhraseModel(
      levels: [
        PhraseModelLevel(
          name: 'none',
          predictor: const _NoPredictions(),
          penalty: 0,
        ),
      ],
      fallbackPenalty: 1,
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      var calls = 0;
      final plan = createTextWrapPlan(
        text: text,
        model: model,
        strategy: LineBreakStrategy(calculator: greedy()),
      );
      final result = plan.select(
        maxWidth: 1,
        diagnostics: true,
        measureRange: (start, end) {
          calls++;
          return (end - start).toDouble();
        },
      );
      expect(result.reason, 'calculationLimit');
      expect(
        result.diagnostics!.calculationLimit!.kind,
        LayoutCalculationLimitKind.states,
      );
      expect(result.applied, isFalse);
      expect(result.layout.sourceText, text);
      expect(result.layout.lines.single, text);
      expect(calls, lessThanOrEqualTo(16385));
    }
  });

  test(
    'thousands of seeded Unicode units deterministically use budget fallback',
    () {
      final random = Random(0xc0de);
      final tokens = ['a', '한', '👩🏽‍🚀', '🇰🇷', 'e\u0301', '\u200b'];
      final text = List.generate(
        6000,
        (_) => tokens[random.nextInt(tokens.length)],
      ).join();
      final model = PhraseModel(
        levels: [
          PhraseModelLevel(
            name: 'none',
            predictor: const _NoPredictions(),
            penalty: 0,
          ),
        ],
        fallbackPenalty: 1,
        boundaryMode: BoundaryMode.characters,
      );
      final plan = createTextWrapPlan(text: text, model: model);
      for (var attempt = 0; attempt < 2; attempt++) {
        var calls = 0;
        final result = plan.select(
          maxWidth: 1,
          diagnostics: true,
          measureRange: (start, end) {
            calls++;
            expect((start, end), (0, text.length));
            return text.characters.length.toDouble();
          },
        );
        expect(result.applied, isFalse);
        expect(result.reason, 'calculationLimit');
        expect(
          result.diagnostics!.calculationLimit!.kind,
          LayoutCalculationLimitKind.candidates,
        );
        expect(result.layout.lines.single.codeUnits, text.codeUnits);
        expect(calls, 1);
      }
    },
  );
}

BreakCandidate _candidate(int offset) => BreakCandidate(
  offset: offset,
  penalty: 1,
  levelName: null,
  consensusCount: 0,
  isFallback: true,
);

final class _NoPredictions implements BoundaryPredictor {
  const _NoPredictions();
  @override
  List<int> predict(String text) => const [];
}
