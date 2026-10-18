import 'package:characters/characters.dart';

import 'exceptions.dart';

/// The boundary opportunities accepted from a phrase model.
enum BoundaryMode {
  /// Grapheme boundaries filtered by glue, joiner, numeric, and bracket rules.
  characters,

  /// Only the end of a contiguous whitespace sequence is an opportunity.
  spaces,
}

/// Returns sorted, interior UTF-16 offsets permitted by [mode].
///
/// Grapheme segmentation prevents offsets inside surrogate pairs, combining
/// sequences, emoji ZWJ sequences, and U+FFFC widget placeholders.
List<int> allowedBoundaries(String text, BoundaryMode mode) {
  final boundaries = <int>[];
  var offset = 0;
  var inWhitespace = false;
  var previousGlue = false;
  var previousEndsWithJoiner = false;
  var afterOpening = false;
  // Keep decimal/grouped numbers intact without joining surrounding prose.
  final numbers = _numericGroups.allMatches(text).iterator;
  Match? number = numbers.moveNext() ? numbers.current : null;

  for (final grapheme in text.characters) {
    final isWhitespace = isBreakableWhitespace(grapheme);
    final glue = grapheme.runes.any(_isNonbreakingRune);
    while (number != null && offset >= number.end) {
      number = numbers.moveNext() ? numbers.current : null;
    }
    final insideNumber = number != null && offset > number.start;
    final closes = _closingPunctuation.contains(grapheme.runes.first);
    if (offset > 0 &&
        !previousGlue &&
        !glue &&
        !previousEndsWithJoiner &&
        !afterOpening &&
        !closes &&
        !insideNumber) {
      switch (mode) {
        case BoundaryMode.characters:
          boundaries.add(offset);
        case BoundaryMode.spaces:
          if (inWhitespace && !isWhitespace) boundaries.add(offset);
      }
    }
    offset += grapheme.length;
    inWhitespace = isWhitespace;
    previousGlue = glue;
    previousEndsWithJoiner = grapheme.codeUnitAt(grapheme.length - 1) == 0x200d;
    if (!isWhitespace) {
      afterOpening = _openingPunctuation.contains(grapheme.runes.first);
    }
  }

  return List<int>.unmodifiable(boundaries);
}

/// Ensures [offsets] are strictly ascending, interior, and legal for [mode].
void validateOffsets(
  String text,
  List<int> offsets, {
  BoundaryMode mode = BoundaryMode.characters,
}) {
  if (offsets.isEmpty) return;
  final permitted = allowedBoundaries(text, mode).toSet();
  var previous = -1;

  for (final offset in offsets) {
    if (offset <= previous) {
      throw InvalidBoundaryException(
        'Offsets must be strictly ascending; received $offset after $previous.',
      );
    }
    if (offset <= 0 || offset >= text.length) {
      throw InvalidBoundaryException(
        'Offset $offset must be inside the UTF-16 text range.',
      );
    }
    if (!permitted.contains(offset)) {
      throw InvalidBoundaryException(
        'Offset $offset is not a permitted $mode boundary.',
      );
    }
    previous = offset;
  }
}

/// Whitespace that may be removed at a selected soft boundary.
/// Nonbreaking spaces and joiners retain their source and joining semantics.
bool isBreakableWhitespace(String grapheme) =>
    grapheme.trim().isEmpty && !grapheme.runes.any(_isNonbreakingRune);

// Frozen Unicode 16.0.0 Line_Break=GL or WJ ranges. These protect glue
// at soft opportunities; this is not a complete UAX #14 line-break algorithm.
// Source: https://www.unicode.org/Public/16.0.0/ucd/LineBreak.txt
const _nonbreakingRanges = <(int, int)>[
  (0x00A0, 0x00A0),
  (0x034F, 0x034F),
  (0x035C, 0x0362),
  (0x0F08, 0x0F08),
  (0x0F0C, 0x0F0C),
  (0x0F12, 0x0F12),
  (0x0FD9, 0x0FDA),
  (0x180E, 0x180E),
  (0x1DCD, 0x1DCD),
  (0x1DFC, 0x1DFC),
  (0x2007, 0x2007),
  (0x2011, 0x2011),
  (0x202F, 0x202F),
  (0x2060, 0x2060),
  (0xFE20, 0xFE20),
  (0xFE22, 0xFE22),
  (0xFE24, 0xFE24),
  (0xFE26, 0xFE27),
  (0xFE29, 0xFE29),
  (0xFE2B, 0xFE2B),
  (0xFE2D, 0xFE2E),
  (0xFEFF, 0xFEFF),
  (0x1107F, 0x1107F),
  (0x13430, 0x13436),
  (0x13439, 0x1343B),
  (0x16FE4, 0x16FE4),
];

bool _isNonbreakingRune(int rune) {
  if (rune < 0x00A0) return false;
  var low = 0;
  var high = _nonbreakingRanges.length - 1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    final range = _nonbreakingRanges[middle];
    if (rune < range.$1) {
      high = middle - 1;
    } else if (rune > range.$2) {
      low = middle + 1;
    } else {
      return true;
    }
  }
  return false;
}

/// Source grapheme endpoints, independent of permitted soft-break rules.
Set<int> graphemeEndpoints(String text) {
  final result = <int>{0};
  var offset = 0;
  for (final grapheme in text.characters) {
    offset += grapheme.length;
    result.add(offset);
  }
  return result;
}

// Targeted numeric/punctuation protection; deliberately not full UAX #14.
final _numericGroups = RegExp(
  r'[0-9\u0660-\u0669\u06f0-\u06f9\uff10-\uff19]+(?:[,.\u066b\u066c\uff0c\uff0e][0-9\u0660-\u0669\u06f0-\u06f9\uff10-\uff19]+)*',
);
const _openingPunctuation = {
  0x28,
  0x5b,
  0x7b,
  0x0f3a,
  0x0f3c,
  0x201a,
  0x201e,
  0x3008,
  0x300a,
  0x300c,
  0x300e,
  0x3010,
  0x3014,
  0x3016,
  0x3018,
  0x301a,
  0xff08,
  0xff3b,
  0xff5b,
  0xff5f,
  0xff62,
};
const _closingPunctuation = {
  0x29,
  0x5d,
  0x7d,
  0x0f3b,
  0x0f3d,
  0x3009,
  0x300b,
  0x300d,
  0x300f,
  0x3011,
  0x3015,
  0x3017,
  0x3019,
  0x301b,
  0xff09,
  0xff3d,
  0xff5d,
  0xff60,
  0xff63,
};

/// Delimiters shared by core ranges, span insertion, and native geometry.
final hardBreakPattern = RegExp(r'\r\n|[\n\r\u000b\u000c\u0085\u2028\u2029]');

bool isHardBreak(int unit) =>
    unit == 0x0a ||
    unit == 0x0d ||
    unit == 0x0b ||
    unit == 0x0c ||
    unit == 0x85 ||
    unit == 0x2028 ||
    unit == 0x2029;
