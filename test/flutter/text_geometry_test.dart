import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/text_geometry.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  test('negative tracking produces a signed advance, not a negative range', () {
    const source = '1111\n\u00ad\n3333';
    final painter = TextPainter(
      text: const TextSpan(
        text: source,
        style: TextStyle(fontSize: 10, letterSpacing: -0.2),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 100);
    addTearDown(painter.dispose);
    final raw = painter.computeLineMetrics();
    expect(raw[1].width, closeTo(-0.2, 0.001));
    final measured = measureNativeTextLayout(painter, source, 100);
    expect(measured.ranges.map((r) => (r.start, r.end)), [
      (0, 4),
      (5, 6),
      (7, 11),
    ]);
    expect(measured.widths[1], 0);
  });

  test('strips a hard CRLF before validating grapheme endpoints', () {
    final painter = TextPainter(
      text: const TextSpan(text: 'a\r\n\r\nb', style: TextStyle(fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 100);
    addTearDown(painter.dispose);
    final layout = measureNativeTextLayout(painter, 'a\r\n\r\nb', 100);
    expect(layout.ranges.map((r) => (r.start, r.end)), [
      (0, 1),
      (3, 3),
      (5, 6),
    ]);
    expect(layout.widths, [10, 0, 10]);
  });

  test('rejects fabricated trailing lines after fully consumed text', () {
    final painter = _EngineResponse([
      const TextRange(start: 0, end: 3),
      const TextRange(start: 3, end: 3),
    ]);
    addTearDown(painter.dispose);
    expect(
      () => measureNativeTextLayout(painter, 'abc', 100),
      throwsA(isA<TextRangeMeasurementException>()),
    );
  });

  for (final boundary in [
    const TextRange(start: -1, end: -1),
    const TextRange(start: -1, end: 2),
    const TextRange(start: 0, end: 99),
    const TextRange(start: 2, end: 1),
    const TextRange(start: 1, end: 2),
    const TextRange(start: 0, end: 0),
  ]) {
    test('rejects malformed engine line boundary $boundary', () {
      final painter = _EngineResponse([boundary]);
      addTearDown(painter.dispose);
      expect(
        () => measureNativeTextLayout(painter, 'abc', 100),
        throwsA(isA<TextRangeMeasurementException>()),
      );
    });
  }

  test('rejects repeated soft line boundaries instead of losing coverage', () {
    final painter = _EngineResponse([
      const TextRange(start: 0, end: 2),
      const TextRange(start: 0, end: 2),
    ]);
    addTearDown(painter.dispose);
    expect(
      () => measureNativeTextLayout(painter, 'abcd', 100),
      throwsA(isA<TextRangeMeasurementException>()),
    );
  });

  test(
    'handles legacy web affinity at a soft wrap without losing semantics',
    () {
      final painter = _LegacyAffinityResponse();
      addTearDown(painter.dispose);
      final layout = measureNativeTextLayout(painter, 'abcd', 20);
      expect(layout.ranges.map((r) => (r.start, r.end)), [(0, 2), (2, 4)]);
      expect(painter.positions.map((p) => p.offset), [0, 2, 3]);
      expect(painter.positions.last.affinity, TextAffinity.upstream);
    },
  );

  test('does not retry or repair a negative engine source index', () {
    final painter = _EngineResponse([
      const TextRange(start: -1, end: 0),
      const TextRange(start: 0, end: 3),
    ], metricCount: 1);
    addTearDown(painter.dispose);
    expect(
      () => measureNativeTextLayout(painter, 'abc', 100),
      throwsA(isA<TextRangeMeasurementException>()),
    );
    expect(painter.index, 1);
  });

  test('rejects missing metrics for nonempty text', () {
    final painter = _EngineResponse([]);
    addTearDown(painter.dispose);
    expect(
      () => measureNativeTextLayout(painter, 'abc', 100),
      throwsA(isA<TextRangeMeasurementException>()),
    );
  });

  test('rejects incomplete source coverage without native truncation', () {
    final painter = _EngineResponse([const TextRange(start: 0, end: 2)]);
    addTearDown(painter.dispose);
    expect(
      () => measureNativeTextLayout(painter, 'abcd', 100),
      throwsA(isA<TextRangeMeasurementException>()),
    );
  });

  for (final text in ['😀x', 'e\u0301x', '👩‍💻x', '🇰🇷x']) {
    test('rejects an engine boundary inside the grapheme $text', () {
      final painter = _EngineResponse([const TextRange(start: 0, end: 1)]);
      addTearDown(painter.dispose);
      expect(
        () => measureNativeTextLayout(painter, text, 100),
        throwsA(isA<TextRangeMeasurementException>()),
      );
    });
  }
}

// Model the engine's response at the adapter boundary. No shaping or widget
// behavior is mocked: these tests verify validation of untrusted engine data.
class _EngineResponse extends TextPainter {
  _EngineResponse(this.boundaries, {this.metricCount});
  final List<TextRange> boundaries;
  final int? metricCount;
  var index = 0;

  @override
  bool get didExceedMaxLines => false;

  @override
  List<ui.LineMetrics> computeLineMetrics() => [
    for (var i = 0; i < (metricCount ?? boundaries.length); i++)
      ui.LineMetrics(
        hardBreak: false,
        ascent: 8,
        descent: 2,
        unscaledAscent: 8,
        height: 10,
        width: 20,
        left: 0,
        baseline: 8,
        lineNumber: i,
      ),
  ];

  @override
  TextRange getLineBoundary(TextPosition position) =>
      boundaries[index < boundaries.length ? index++ : boundaries.length - 1];
}

class _LegacyAffinityResponse extends _EngineResponse {
  _LegacyAffinityResponse()
    : super([
        const TextRange(start: 0, end: 2),
        const TextRange(start: 2, end: 4),
      ]);

  final positions = <TextPosition>[];

  @override
  TextRange getLineBoundary(TextPosition position) {
    positions.add(position);
    return position.offset <= 2 ? boundaries.first : boundaries.last;
  }
}
