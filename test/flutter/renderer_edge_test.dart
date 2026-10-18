import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  testWidgets('calculated source ranges follow actual painted line boundaries', (
    tester,
  ) async {
    const source = 'aa    bb\rcc dd';
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap(
          source,
          model: offsetModel([3, 12]),
          strategy: offsetStrategy([3, 12]),
        ),
        width: 50,
      ),
    );
    final render = wrapRender(tester);
    final result = render.result!;
    expect(result.applied, isTrue);
    final effective = render.effectiveText.toPlainText(
      includeSemanticsLabels: false,
    );
    final painter = TextPainter(
      text: render.effectiveText,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 50);
    addTearDown(painter.dispose);
    var offset = 0;
    final ranges = <TextRange>[];
    for (final line in painter.computeLineMetrics()) {
      var boundary = painter.getLineBoundary(TextPosition(offset: offset));
      if (boundary.end == offset && boundary.start < offset) {
        boundary = painter.getLineBoundary(
          TextPosition(offset: offset + 1, affinity: TextAffinity.upstream),
        );
      }
      ranges.add(boundary);
      offset = boundary.end;
      if (line.hardBreak &&
          offset < effective.length &&
          (effective.codeUnitAt(offset) == 10 ||
              effective.codeUnitAt(offset) == 13)) {
        offset++;
      }
    }
    int sourceOffset(int effectiveOffset) {
      if (!result.applied) return effectiveOffset;
      var inserted = 0;
      for (var index = 0; index < result.breakOffsets.length; index++) {
        if (result.breakOffsets[index] + index < effectiveOffset) inserted++;
      }
      return effectiveOffset - inserted;
    }

    expect(
      result.ranges.map((range) => (range.start, range.end)),
      ranges.map(
        (range) => (sourceOffset(range.start), sourceOffset(range.end)),
      ),
      reason:
          'Each committed source range must match the actual painted line, including a CR that the engine retains.',
    );
    expect(
      result.lines[1],
      effective.substring(ranges[1].start, ranges[1].end),
    );
    expect(
      result.widths,
      painter.computeLineMetrics().map((line) => math.max(0.0, line.width)),
    );
  });
  testWidgets('ellipsis-only native line retains measurable empty source range', (
    tester,
  ) async {
    const source = 'ab cd ef\ngh ij kl\n';
    final painter = TextPainter(
      text: const TextSpan(text: source, style: wrapStyle),
      textDirection: TextDirection.ltr,
      ellipsis: '\u2026',
    )..layout(maxWidth: 11);
    addTearDown(painter.dispose);
    final metrics = painter.computeLineMetrics();
    final boundary = painter.getLineBoundary(const TextPosition(offset: 0));
    expect(painter.didExceedMaxLines, isTrue);
    expect(painter.ellipsis, isNotNull);
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap(
          source,
          overflow: TextOverflow.ellipsis,
          model: offsetModel([3]),
          strategy: offsetStrategy([3]),
        ),
        width: 11,
      ),
    );
    expect(tester.takeException(), isNull);
    final render = wrapRender(tester);
    expect(
      render.result,
      isNotNull,
      reason:
          'An engine-truncated ellipsis-only line has valid empty source geometry.',
    );
    expect(
      render.result!.widths,
      metrics.map((line) => math.max(0.0, line.width)),
    );
    expect(render.result!.ranges.map((range) => (range.start, range.end)), [
      (boundary.start, boundary.end),
    ]);
    expect(render.didExceedMaxLines, painter.didExceedMaxLines);
  });
}
