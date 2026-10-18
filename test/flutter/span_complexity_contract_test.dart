// Counting equality calls leaves inherited TextStyle hashing unchanged.
// ignore_for_file: hash_and_equals

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/span_codec.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  test('oversized span count stops preprocessing with a typed limit', () {
    final source = TextSpan(
      children: List.filled(17000, const TextSpan(text: 'a')),
    );
    expect(
      () => encodeInlineSpan(source),
      throwsA(isA<TextWrapInputLimitException>()),
    );
  });

  test('oversized span depth stops preprocessing with a typed limit', () {
    final source = _nested(const TextSpan(text: 'abcdef'), 2000);
    expect(
      () => encodeInlineSpan(source),
      throwsA(isA<TextWrapInputLimitException>()),
    );
  });

  test('equivalent source replacement avoids repeated subtree comparisons', () {
    const depth = 80;
    final first = _countedTree(depth);
    final second = _countedTree(depth);
    _CountingStyle.comparisons = 0;
    expect(first == second, isTrue);
    final nativeComparisons = _CountingStyle.comparisons;
    expect(nativeComparisons, depth + 1);
    final render = RenderTextAutoWrap(
      sourceText: first,
      model: offsetModel([3]),
      strategy: offsetStrategy([3]),
      textDirection: TextDirection.ltr,
    );
    addTearDown(render.dispose);
    _CountingStyle.comparisons = 0;
    render.sourceText = second;
    expect(render.sourceText, same(second));
    expect(
      _CountingStyle.comparisons,
      lessThanOrEqualTo(2 * nativeComparisons),
      reason: 'Source equality must not rescan the subtree at every ancestor.',
    );
  });

  test(
    'deep span slices preserve metadata and repeated widget occurrences',
    () {
      final recognizer = TapGestureRecognizer();
      addTearDown(recognizer.dispose);
      const widget = WidgetSpan(child: SizedBox(width: 3, height: 4));
      final leaf = TextSpan(
        text: 'ab',
        semanticsLabel: 'letters',
        locale: const Locale('en'),
        spellOut: true,
        recognizer: recognizer,
        style: const TextStyle(fontSize: 10),
        children: const [
          widget,
          TextSpan(text: 'c'),
          widget,
          TextSpan(text: 'd'),
        ],
      );
      final source = _nested(leaf, 600);
      const dimensions = [
        PlaceholderDimensions(
          size: Size(3, 4),
          alignment: PlaceholderAlignment.bottom,
        ),
        PlaceholderDimensions(
          size: Size(7, 8),
          alignment: PlaceholderAlignment.bottom,
        ),
      ];
      final native = _painter(source, dimensions);
      addTearDown(native.dispose);
      expect(native.width, 50);

      final encoded = encodeInlineSpan(source);
      expect(encoded.text, 'ab\uFFFCc\uFFFCd');
      expect(encoded.placeholderSpans, [same(widget), same(widget)]);
      final slice = sliceInlineSpanForMeasurement(encoded, 3, 5);
      expect(slice.placeholderIndices, [1]);
      final sliced = _painter(slice.span, [dimensions[1]]);
      addTearDown(sliced.dispose);
      expect(sliced.width, 17);
      var retained = slice.span as TextSpan;
      for (var level = 0; level < 600; level++) {
        retained = retained.children!.single as TextSpan;
      }
      expect(retained.text, '');
      expect(retained.semanticsLabel, 'letters');
      expect(retained.locale, const Locale('en'));
      expect(retained.spellOut, isTrue);
      expect(retained.recognizer, same(recognizer));
      expect(retained.children![1], same(widget));

      final transformed = insertLineBreaks(encoded, [2]);
      final painted = _painter(transformed, dimensions);
      addTearDown(painted.dispose);
      expect(painted.width, 30);
      expect(painted.computeLineMetrics(), hasLength(2));
      expect(encodeInlineSpan(transformed).text, 'ab\n\uFFFCc\uFFFCd');
      expect(encoded.text, 'ab\uFFFCc\uFFFCd');
    },
  );

  testWidgets(
    'deep source replacement keeps semantic rendering and style restoration',
    (tester) async {
      for (final fontSize in [10.0, 10.0, 12.0, 10.0]) {
        final source = _nested(
          TextSpan(
            text: 'abcdef',
            style: TextStyle(fontSize: fontSize),
          ),
          600,
        );
        final native = _painter(source, const []);
        expect(native.width, closeTo(6 * fontSize, 0.001));
        native.dispose();
        await tester.pumpWidget(
          wrapHost(
            TextAutoWrap.rich(
              source,
              model: offsetModel([3]),
              strategy: offsetStrategy([3]),
            ),
          ),
        );
        final render = wrapRender(tester);
        expect(render.result!.applied, isTrue);
        expect(render.result!.lines, ['abc', 'def']);
        expect(
          render.result!.widths,
          everyElement(closeTo(3 * fontSize, 0.001)),
        );
        expect(encodeInlineSpan(render.effectiveText).text, 'abc\ndef');
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('four thousand text spans retain calculated line rendering', (
    tester,
  ) async {
    final source = TextSpan(
      style: const TextStyle(fontSize: 0.125),
      children: List.generate(4000, (_) => const TextSpan(text: 'a')),
    );
    final native = _painter(source, const []);
    expect(native.width, 500);
    native.dispose();
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap.rich(
          source,
          model: offsetModel([2000]),
          strategy: offsetStrategy([2000]),
        ),
        width: 600,
      ),
    );
    final render = wrapRender(tester);
    expect(render.result!.applied, isTrue);
    expect(render.result!.lineCount, 2);
    expect(render.result!.breakOffsets, [2000]);
    expect(render.result!.widths, everyElement(250));
    expect(
      encodeInlineSpan(render.effectiveText).text,
      '${'a' * 2000}\n${'a' * 2000}',
    );
    expect(tester.takeException(), isNull);
  });
}

InlineSpan _nested(InlineSpan leaf, int depth) {
  var span = leaf;
  for (var level = 0; level < depth; level++) {
    span = TextSpan(children: [span]);
  }
  return span;
}

TextPainter _painter(InlineSpan text, List<PlaceholderDimensions> dimensions) =>
    TextPainter(text: text, textDirection: TextDirection.ltr)
      ..setPlaceholderDimensions(dimensions)
      ..layout();

TextSpan _countedTree(int depth) {
  var span = TextSpan(text: 'abcdef', style: _CountingStyle());
  for (var level = 0; level < depth; level++) {
    span = TextSpan(style: _CountingStyle(), children: [span]);
  }
  return span;
}

class _CountingStyle extends TextStyle {
  _CountingStyle() : super(fontSize: 10);

  static int comparisons = 0;

  // Only count comparisons; equality and hashing retain TextStyle semantics.
  @override
  bool operator ==(Object other) {
    comparisons++;
    return super == other;
  }
}
