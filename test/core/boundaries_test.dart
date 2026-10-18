import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  group('allowedBoundaries', () {
    test('keeps emoji ZWJ sequences and combining characters indivisible', () {
      expect(allowedBoundaries('가👨‍👩‍👧‍👦é 나', BoundaryMode.characters), [
        1,
        12,
        14,
        15,
      ]);
    });

    test('returns only the end of each whitespace opportunity', () {
      expect(allowedBoundaries('가  나', BoundaryMode.spaces), [3]);
    });

    test('treats a widget placeholder as one character token', () {
      expect(allowedBoundaries('a\uFFFCb', BoundaryMode.characters), [1, 2]);
    });
  });

  for (final glue in [
    '\u00a0',
    '\u2007',
    '\u2011',
    '\u202f',
    '\ufeff',
    '\u2060',
  ]) {
    test('nonbreaking ${glue.codeUnitAt(0)} has no soft opportunities', () {
      expect(allowedBoundaries('a${glue}b', BoundaryMode.spaces), isEmpty);
      expect(allowedBoundaries('a${glue}b', BoundaryMode.characters), isEmpty);
      expect(
        allowedBoundaries(
          'a $glue'
          'b c',
          BoundaryMode.spaces,
        ),
        [5],
      );
    });
  }

  for (final rune in [
    0x034f,
    0x035c,
    0x0362,
    0x0f08,
    0x0f0c,
    0x0f12,
    0x0fd9,
    0x0fda,
    0x180e,
    0x1dcd,
    0x1dfc,
    0xfe20,
    0xfe22,
    0xfe24,
    0xfe26,
    0xfe27,
    0xfe29,
    0xfe2b,
    0xfe2d,
    0xfe2e,
    0x1107f,
    0x13430,
    0x13436,
    0x13439,
    0x1343b,
    0x16fe4,
  ]) {
    test(
      'Unicode16 glue U+${rune.toRadixString(16)} blocks neighboring breaks',
      () {
        final glue = String.fromCharCode(rune);
        expect(
          allowedBoundaries('a${glue}b', BoundaryMode.characters),
          isEmpty,
        );
        expect(
          allowedBoundaries(
            'a $glue'
            'b c',
            BoundaryMode.spaces,
          ),
          [glue.length + 4],
        );
      },
    );
  }

  test('nonbreaking bases retain glue across combining marks', () {
    expect(
      allowedBoundaries('a\u00a0\u0301b', BoundaryMode.characters),
      isEmpty,
    );
    expect(allowedBoundaries('a \u00a0\u0301b c', BoundaryMode.spaces), [6]);
  });

  test(
    'grapheme offsets preserve isolated surrogates and zero width controls',
    () {
      final text = String.fromCharCodes([0x61, 0xd800, 0x200b, 0xdc00, 0x62]);
      expect(allowedBoundaries(text, BoundaryMode.characters), [1, 2, 3, 4]);
      expect(allowedBoundaries(text, BoundaryMode.spaces), isEmpty);
    },
  );

  group('validateOffsets', () {
    test('rejects duplicate offsets', () {
      expect(
        () => validateOffsets('abc', [1, 1]),
        throwsA(isA<InvalidBoundaryException>()),
      );
    });

    test('rejects descending offsets', () {
      expect(
        () => validateOffsets('abc', [2, 1]),
        throwsA(isA<InvalidBoundaryException>()),
      );
    });

    test('rejects text endpoints', () {
      expect(
        () => validateOffsets('ab', [0]),
        throwsA(isA<InvalidBoundaryException>()),
      );
      expect(
        () => validateOffsets('ab', [2]),
        throwsA(isA<InvalidBoundaryException>()),
      );
    });

    test('rejects a UTF-16 offset inside a surrogate pair', () {
      expect(
        () => validateOffsets('😀', [1]),
        throwsA(isA<InvalidBoundaryException>()),
      );
    });
  });

  group('PhraseModel', () {
    test('freezes copied levels and validates its penalties', () {
      final levels = <PhraseModelLevel>[
        PhraseModelLevel(
          name: 'primary',
          predictor: _NoOpPredictor(),
          penalty: 1,
        ),
      ];

      final model = PhraseModel(levels: levels, fallbackPenalty: 2);
      levels.clear();

      expect(model.levels, hasLength(1));
      expect(
        () => model.levels.add(
          PhraseModelLevel(
            name: 'other',
            predictor: _NoOpPredictor(),
            penalty: 2,
          ),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => PhraseModel(levels: model.levels, fallbackPenalty: -1),
        throwsA(isA<InvalidModelConfigurationException>()),
      );
    });

    test('rejects empty and duplicate level names', () {
      final predictor = _NoOpPredictor();

      expect(
        () => PhraseModel(levels: const [], fallbackPenalty: 1),
        throwsA(isA<InvalidModelConfigurationException>()),
      );
      expect(
        () => PhraseModel(
          levels: [
            PhraseModelLevel(name: '', predictor: predictor, penalty: 1),
          ],
          fallbackPenalty: 1,
        ),
        throwsA(isA<InvalidModelConfigurationException>()),
      );
      expect(
        () => PhraseModel(
          levels: [
            PhraseModelLevel(name: 'same', predictor: predictor, penalty: 1),
            PhraseModelLevel(name: 'same', predictor: predictor, penalty: 2),
          ],
          fallbackPenalty: 1,
        ),
        throwsA(isA<InvalidModelConfigurationException>()),
      );
    });
  });
}

final class _NoOpPredictor implements BoundaryPredictor {
  @override
  List<int> predict(String text) => const [];
}
