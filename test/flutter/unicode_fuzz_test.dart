import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

// Keep this corpus and generator stable: a failure's seed, case and UTF-16
// units are sufficient to reproduce it on engines with different fonts.
const _seed = 0x554e4943;
const _atoms = [
  'a',
  'English ',
  '한글',
  '한',
  'العربية',
  'עברית',
  'e\u0301',
  '\u0301',
  '👩🏽‍💻',
  '👨‍👩‍👧‍👦',
  '🇰🇷',
  '1️⃣',
  '🏴\u{e0067}\u{e0062}\u{e007f}',
  '\ud800',
  '\udfff',
  '\u00ad',
  '\u200b',
  '\u200c',
  '\u200d',
  '\u2060',
  '\ufeff',
  '\u00a0',
  '\u202f',
  ' ',
  '\t',
  '\n',
  '\r',
  '\r\n',
  '\u2028',
  '\u2029',
  '\u2067',
  '\u2069',
  '\ufe0f',
  '\u034f',
];

String _caseText(Random random, int index) {
  final atom = _atoms[index % _atoms.length];
  if (index < _atoms.length) {
    return '$atom$atom${_atoms.reversed.elementAt(index)}$atom';
  }
  return List.generate(
    3 + random.nextInt(9),
    (_) => _atoms[random.nextInt(_atoms.length)],
  ).join();
}

String _replay(int index, String text) =>
    'seed=0x${_seed.toRadixString(16)} case=$index '
    'UTF-16=[${text.codeUnits.map((unit) => '0x${unit.toRadixString(16)}').join(',')}]';

Set<int> _graphemeEdges(String text) {
  var offset = 0;
  return {0, for (final grapheme in text.characters) offset += grapheme.length};
}

void _invariants(TextWrapResult result, String text, String replay) {
  expect(result.sourceText, text, reason: replay);
  expect(result.lines.length, result.ranges.length, reason: replay);
  expect(result.widths.length, result.ranges.length, reason: replay);
  expect(
    result.widths.every((width) => width.isFinite && width >= 0),
    isTrue,
    reason: replay,
  );
  expect(result.layout.imbalance.isFinite, isTrue, reason: replay);
  final edges = _graphemeEdges(text);
  var previousEnd = 0;
  for (var i = 0; i < result.ranges.length; i++) {
    final range = result.ranges[i];
    expect(
      range.start,
      inInclusiveRange(previousEnd, text.length),
      reason: replay,
    );
    expect(
      range.end,
      inInclusiveRange(range.start, text.length),
      reason: replay,
    );
    expect(
      edges.contains(range.start),
      isTrue,
      reason: '$replay start=${range.start}',
    );
    expect(
      edges.contains(range.end),
      isTrue,
      reason: '$replay end=${range.end}',
    );
    // The only source units absent from line ranges may be hard separators.
    expect(
      text
          .substring(previousEnd, range.start)
          .replaceAll(RegExp('[\r\n\u2028\u2029]'), ''),
      isEmpty,
      reason: replay,
    );
    expect(
      result.lines[i],
      text.substring(range.start, range.end),
      reason: replay,
    );
    previousEnd = range.end;
  }
  expect(
    text.substring(previousEnd).replaceAll(RegExp('[\r\n\u2028\u2029]'), ''),
    isEmpty,
    reason: replay,
  );
  expect(result.breakOffsets.every(edges.contains), isTrue, reason: replay);
}

Widget _frame(Widget child, double width, TextDirection direction) =>
    width.isInfinite
    ? wrapHost(
        OverflowBox(
          minWidth: 0,
          maxWidth: double.infinity,
          alignment: Alignment.topLeft,
          child: child,
        ),
        direction: direction,
      )
    : wrapHost(child, width: width, direction: direction);

List<Object?> _geometry(RenderParagraph paragraph, int length) => [
  paragraph.size,
  for (final box in paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: length),
  ))
    [box.left, box.top, box.right, box.bottom, box.direction],
  for (
    var child = paragraph.firstChild;
    child != null;
    child = paragraph.childAfter(child)
  )
    [(child.parentData! as TextParentData).offset, child.size],
];

bool _engineAccepts(String text, String replay) {
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle());
  try {
    builder.addText(text);
    final paragraph = builder.build();
    paragraph.layout(const ui.ParagraphConstraints(width: 600));
    paragraph.dispose();
    return true;
  } on ArgumentError catch (error) {
    var malformed = false;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (i + 1 >= text.length ||
            text.codeUnitAt(i + 1) < 0xdc00 ||
            text.codeUnitAt(i + 1) > 0xdfff) {
          malformed = true;
          break;
        }
        i++;
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        malformed = true;
        break;
      }
    }
    expect(
      malformed,
      isTrue,
      reason: '$replay native engine rejection: $error',
    );
    return false;
  }
}

void _confirmNativeFailure(
  RenderTextAutoWrap render,
  double width,
  TextDirection direction,
  TextScaler scaler,
  String replay,
) {
  expect(render.failures, isNotEmpty, reason: replay);
  expect(
    render.failures.last.stage,
    TextWrapFailureStage.nativeMeasurement,
    reason: replay,
  );
  expect(
    render.failures.last.error,
    isA<TextRangeMeasurementException>(),
    reason: replay,
  );
  final source = render.effectiveText.toPlainText(
    includeSemanticsLabels: false,
  );
  final painter = TextPainter(
    text: render.effectiveText,
    textDirection: direction,
    textScaler: scaler,
  );
  final placeholders = <PlaceholderDimensions>[];
  final spans = <WidgetSpan>[];
  render.effectiveText.visitChildren((span) {
    if (span is WidgetSpan) spans.add(span);
    return true;
  });
  var child = render.firstChild;
  for (final span in spans) {
    placeholders.add(
      PlaceholderDimensions(
        size: child!.size,
        alignment: span.alignment,
        baseline: span.baseline,
      ),
    );
    child = render.childAfter(child);
  }
  painter.setPlaceholderDimensions(placeholders);
  try {
    painter.layout(maxWidth: width);
    final edges = _graphemeEdges(source);
    var offset = 0;
    var invalid = false;
    for (final line in painter.computeLineMetrics()) {
      if (offset >= source.length) break;
      final boundary = painter.getLineBoundary(TextPosition(offset: offset));
      var end = boundary.end;
      var next = end;
      if (end < 0 || end > source.length || boundary.start != offset) {
        invalid = true;
        break;
      }
      if (line.hardBreak) {
        if (end > boundary.start && _separator(source.codeUnitAt(end - 1))) {
          end--;
        }
        if (end < source.length &&
            end > boundary.start &&
            source.codeUnitAt(end) == 10 &&
            source.codeUnitAt(end - 1) == 13) {
          end--;
        }
        next = end;
        if (next < source.length && _separator(source.codeUnitAt(next))) {
          final cr = source.codeUnitAt(next) == 13;
          next++;
          if (cr && next < source.length && source.codeUnitAt(next) == 10) {
            next++;
          }
        }
      }
      if (!edges.contains(boundary.start) ||
          !edges.contains(end) ||
          !edges.contains(next) ||
          next <= offset) {
        invalid = true;
        break;
      }
      offset = next;
    }
    expect(
      invalid || offset < source.length,
      isTrue,
      reason:
          '$replay native engine must independently exhibit invalid geometry',
    );
  } finally {
    painter.dispose();
  }
}

bool _separator(int unit) => const [10, 13, 0x2028, 0x2029].contains(unit);

class _RunCounts {
  var successes = 0;
  final rejected = <int>[];
  final unavailable = <int>[];
  void verify(String name) {
    expect(
      successes,
      greaterThan(10),
      reason: '$name must exercise genuine successful geometry',
    );
    debugPrint(
      '$name seed=0x${_seed.toRadixString(16)} successes=$successes nativeRejected=$rejected nativeGeometryUnavailable=$unavailable',
    );
  }
}

void main() {
  testWidgets(
    'seeded Unicode replacements and resizing preserve source ranges',
    (tester) async {
      final random = Random(_seed);
      Object? firstRender;
      final counts = _RunCounts();
      for (var index = 0; index < 96; index++) {
        final text = _caseText(random, index);
        final replay = _replay(index, text);
        if (!_engineAccepts(text, replay)) {
          counts.rejected.add(index);
          firstRender = null;
          continue;
        }
        final width = [0.0, 1.0, 23.0, 80.0, 220.0, double.infinity][index % 6];
        await tester.pumpWidget(
          _frame(
            TextAutoWrap(
              text,
              style: const TextStyle(letterSpacing: -0.2),
              textScaler: TextScaler.linear(index.isEven ? 1 : 1.7),
            ),
            width,
            index % 3 == 0 ? TextDirection.rtl : TextDirection.ltr,
          ),
        );
        expect(tester.takeException(), isNull, reason: replay);
        final render = wrapRender(tester);
        // Finite width updates keep the same renderer, exercising cached state.
        if (firstRender != null && index % 6 != 0 && index % 6 != 5) {
          expect(render, same(firstRender), reason: replay);
        }
        firstRender = render;
        if (render.result == null) {
          counts.unavailable.add(index);
          _confirmNativeFailure(
            render,
            width,
            index % 3 == 0 ? TextDirection.rtl : TextDirection.ltr,
            TextScaler.linear(index.isEven ? 1 : 1.7),
            replay,
          );
        } else {
          counts.successes++;
          _invariants(render.result!, text, replay);
        }
        expect(
          render.size.width.isFinite && render.size.height.isFinite,
          isTrue,
          reason: replay,
        );
      }
      counts.verify('replacement');
    },
  );

  testWidgets('seeded nested Unicode spans match native painted geometry', (
    tester,
  ) async {
    final random = Random(_seed);
    final counts = _RunCounts();
    for (var index = 0; index < 40; index++) {
      final text = _caseText(random, index + _atoms.length);
      final replay = _replay(index + _atoms.length, text);
      if (!_engineAccepts(text, replay)) {
        counts.rejected.add(index);
        continue;
      }
      final split = text.characters
          .take(text.characters.length ~/ 2)
          .toString()
          .length;
      final span = TextSpan(
        children: [
          TextSpan(
            text: text.substring(0, split),
            children: const [
              TextSpan(text: '\u200b', style: TextStyle(fontSize: 12)),
            ],
          ),
          const WidgetSpan(child: SizedBox(width: 7, height: 9)),
          TextSpan(children: [TextSpan(text: text.substring(split))]),
        ],
      );
      final source = span.toPlainText(includeSemanticsLabels: false);
      final direction = index.isEven ? TextDirection.ltr : TextDirection.rtl;
      final width = [1.0, 37.0, 140.0, double.infinity][index % 4];
      final scaler = TextScaler.linear(index.isEven ? 1 : 1.4);
      await tester.pumpWidget(
        _frame(
          TextAutoWrap.rich(
            span,
            style: const TextStyle(letterSpacing: -0.2),
            textScaler: scaler,
          ),
          width,
          direction,
        ),
      );
      expect(tester.takeException(), isNull, reason: replay);
      final render = wrapRender(tester);
      if (render.result == null) {
        counts.unavailable.add(index);
        _confirmNativeFailure(render, width, direction, scaler, replay);
      } else {
        counts.successes++;
        _invariants(render.result!, source, replay);
      }
      final effective = render.effectiveText;
      final geometry = _geometry(
        render,
        effective.toPlainText(includeSemanticsLabels: false).length,
      );
      await tester.pumpWidget(
        _frame(Text.rich(effective, textScaler: scaler), width, direction),
      );
      expect(tester.takeException(), isNull, reason: replay);
      final native = tester.allRenderObjects
          .whereType<RenderParagraph>()
          .toSet()
          .single;
      expect(
        _geometry(
          native,
          effective.toPlainText(includeSemanticsLabels: false).length,
        ),
        geometry,
        reason: replay,
      );
    }
    counts.verify('rich');
  });

  testWidgets('Unicode calculated breaks are applied and paint native geometry', (
    tester,
  ) async {
    final counts = _RunCounts();
    for (var index = 0; index < _atoms.length; index++) {
      final atom = _atoms[index];
      // Bare CR has engine-specific semantics, characterized below.
      if (atom == '\r') continue;
      // Break at a plain ASCII separator so this specifically exercises span
      // slicing and native shaping around adversarial Unicode, not a mock width.
      final prefix = 'ab $atom cd ';
      final suffix = 'ef $atom gh';
      final text = '$prefix$suffix';
      final replay = _replay(index, text);
      if (!_engineAccepts(text, replay)) {
        counts.rejected.add(index);
        continue;
      }
      final offset = prefix.length;
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap.rich(
            TextSpan(
              children: [
                TextSpan(text: 'ab $atom'),
                const TextSpan(text: ' cd '),
                TextSpan(children: [TextSpan(text: suffix)]),
              ],
            ),
            style: const TextStyle(letterSpacing: -0.2),
            model: offsetModel([offset]),
            strategy: offsetStrategy([offset]),
          ),
          width: 600,
        ),
      );
      expect(tester.takeException(), isNull, reason: replay);
      final render = wrapRender(tester);
      if ((index == 13 || index == 14) && render.result == null) {
        // Web engines may accept an unpaired surrogate for painting while
        // returning unusable source offsets. Prove that limitation directly.
        _confirmNativeFailure(
          render,
          600,
          TextDirection.ltr,
          TextScaler.noScaling,
          replay,
        );
        counts.unavailable.add(index);
        continue;
      }
      expect(
        render.result,
        isNotNull,
        reason:
            '$replay failures=${render.failures.map((failure) => failure.error).toList()}',
      );
      _invariants(render.result!, text, replay);
      if (!render.result!.applied) {
        debugPrint(
          '$replay reason=${render.result!.reason} failures=${render.failures.map((f) => f.error).toList()}',
        );
      }
      expect(
        render.result!.applied,
        isTrue,
        reason:
            '$replay reason=${render.result!.reason} failures=${render.failures.map((f) => f.error).toList()}',
      );
      counts.successes++;
      expect(
        render.result!.source,
        TextWrapSelectionSource.calculated,
        reason: replay,
      );
      final effective = render.effectiveText;
      expect(
        effective.toPlainText(includeSemanticsLabels: false),
        '${text.substring(0, offset)}\n${text.substring(offset)}',
        reason: replay,
      );
      final geometry = _geometry(
        render,
        effective.toPlainText(includeSemanticsLabels: false).length,
      );
      await tester.pumpWidget(wrapHost(Text.rich(effective), width: 600));
      expect(
        _geometry(
          tester.allRenderObjects.whereType<RenderParagraph>().toSet().single,
          effective.toPlainText(includeSemanticsLabels: false).length,
        ),
        geometry,
        reason: replay,
      );
    }
    counts.verify('applied');
  });
  testWidgets(
    'Unicode between widgets applies breaks across resize and scale',
    (tester) async {
      for (final index in [2, 4, 6, 8, 10, 11, 12, 19]) {
        final atom = _atoms[index];
        final prefix = 'ab\ufffc$atom\ufffc cd ';
        final source = '${prefix}ef gh';
        final replay = _replay(index, source);
        for (final width in [350.0, 600.0]) {
          final scaler = TextScaler.linear(width == 350 ? 1.3 : 1);
          await tester.pumpWidget(
            wrapHost(
              TextAutoWrap.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'ab'),
                    const WidgetSpan(child: SizedBox(width: 7, height: 9)),
                    TextSpan(children: [TextSpan(text: atom)]),
                    const WidgetSpan(child: SizedBox(width: 11, height: 12)),
                    const TextSpan(text: ' cd ef gh'),
                  ],
                ),
                style: const TextStyle(letterSpacing: -0.2),
                textScaler: scaler,
                model: offsetModel([prefix.length]),
                strategy: offsetStrategy([prefix.length]),
              ),
              width: width,
            ),
          );
          expect(tester.takeException(), isNull, reason: replay);
          final render = wrapRender(tester);
          expect(render.result, isNotNull, reason: replay);
          _invariants(render.result!, source, replay);
          expect(
            render.result!.applied,
            isTrue,
            reason: '$replay reason=${render.result!.reason}',
          );
          final effective = render.effectiveText;
          expect(
            effective.toPlainText(includeSemanticsLabels: false),
            '$prefix\nef gh',
            reason: replay,
          );
          final length = effective
              .toPlainText(includeSemanticsLabels: false)
              .length;
          final geometry = _geometry(render, length);
          await tester.pumpWidget(
            wrapHost(Text.rich(effective, textScaler: scaler), width: width),
          );
          expect(tester.takeException(), isNull, reason: replay);
          final native = tester.allRenderObjects
              .whereType<RenderParagraph>()
              .toSet()
              .single;
          expect(_geometry(native, length), geometry, reason: replay);
        }
      }
    },
  );
  testWidgets('bare CR follows native engine separator semantics', (
    tester,
  ) async {
    const text = 'ab \r cd ef \r gh';
    const offset = 8;
    const style = TextStyle(
      fontSize: 10,
      letterSpacing: -0.2,
      color: Color(0xff000000),
    );
    final painter = TextPainter(
      text: const TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 600);
    addTearDown(painter.dispose);
    final nativeMetrics = painter.computeLineMetrics();
    final nativeSeparatesCr = nativeMetrics.length > 1;
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap(
          text,
          style: style,
          model: offsetModel([offset]),
          strategy: offsetStrategy([offset]),
        ),
        width: 600,
      ),
    );
    expect(tester.takeException(), isNull);
    final render = wrapRender(tester);
    final result = render.result!;
    _invariants(result, text, 'bare CR nativeSeparatesCr=$nativeSeparatesCr');
    if (nativeSeparatesCr) {
      expect(result.applied, isTrue);
      expect(
        render.effectiveText.toPlainText(includeSemanticsLabels: false),
        '${text.substring(0, offset)}\n${text.substring(offset)}',
      );
    } else {
      // Core treats CR as a paragraph delimiter, but this native engine does
      // not. Its actual geometry wins over a calculated incompatible layout.
      expect(result.applied, isFalse);
      expect(result.reason, 'invalidRuntimeMeasurement');
      expect(result.source, TextWrapSelectionSource.native);
      expect(result.widths, nativeMetrics.map((line) => max(0.0, line.width)));
      expect(
        render.effectiveText.toPlainText(includeSemanticsLabels: false),
        text,
      );
    }
    final effective = render.effectiveText;
    final length = effective.toPlainText(includeSemanticsLabels: false).length;
    final geometry = _geometry(render, length);
    await tester.pumpWidget(wrapHost(Text.rich(effective), width: 600));
    expect(tester.takeException(), isNull);
    expect(
      _geometry(
        tester.allRenderObjects.whereType<RenderParagraph>().toSet().single,
        length,
      ),
      geometry,
    );
  });
}
