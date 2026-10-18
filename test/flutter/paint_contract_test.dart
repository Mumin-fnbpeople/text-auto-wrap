import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  for (final direction in TextDirection.values) {
    for (final overflow in TextOverflow.values) {
      for (final maxLines in <int?>[null, 1]) {
        testWidgets('$direction $overflow maxLines=$maxLines rich paint', (
          tester,
        ) async {
          var taps = 0;
          final recognizer = TapGestureRecognizer()..onTap = () => taps++;
          addTearDown(recognizer.dispose);
          final shared = WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _PaintBox(const Size(12, 17), 11),
          );
          TextSpan source({required bool breaks}) => TextSpan(
            text: 'אב',
            recognizer: recognizer,
            semanticsLabel: 'first letters',
            style: const TextStyle(color: Color(0xff102080)),
            children: [
              shared,
              TextSpan(
                text: breaks ? '\ncd' : 'cd',
                locale: const Locale('en'),
                spellOut: true,
                style: const TextStyle(
                  color: Color(0xff802010),
                  decoration: TextDecoration.underline,
                ),
              ),
              shared,
              const TextSpan(text: 'הוזחטיכל'),
            ],
          );
          await tester.pumpWidget(
            _pair(
              TextAutoWrap.rich(
                source(breaks: false),
                overflow: overflow,
                maxLines: maxLines,
                model: offsetModel([3]),
                strategy: maxLines == null
                    ? offsetStrategy([3])
                    : const LineBreakStrategy(),
              ),
              Text.rich(
                source(breaks: maxLines == null),
                overflow: overflow,
                maxLines: maxLines,
              ),
              direction: direction,
              height: 18,
            ),
          );
          final actual = wrapRender(tester);
          expect(actual.result!.applied, maxLines == null);
          expect(actual.didExceedMaxLines, maxLines != null);
          expect(actual.failures, isEmpty);
          final native = tester.allRenderObjects
              .whereType<RenderParagraph>()
              .where((render) => !identical(render, actual))
              .toSet()
              .single;
          expect(_geometry(actual), _geometry(native));
          expect(actual.debugHasOverflowShader, native.debugHasOverflowShader);
          await _expectPaintMatches(tester);
          final glyph = actual
              .getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: 1),
              )
              .single;
          await tester.tapAt(actual.localToGlobal(glyph.toRect().center));
          expect(taps, 1);
        });
      }
    }
  }

  testWidgets('repeated placeholders repaint after size and baseline changes', (
    tester,
  ) async {
    final dimensions = ValueNotifier<(Size, double)>((const Size(12, 17), 11));
    addTearDown(dimensions.dispose);
    final shared = WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: ValueListenableBuilder<(Size, double)>(
        valueListenable: dimensions,
        builder: (_, value, _) => _PaintBox(value.$1, value.$2),
      ),
    );
    TextSpan source({required bool breaks}) => TextSpan(
      text: 'ab',
      children: [
        shared,
        TextSpan(text: breaks ? '\ncd' : 'cd'),
        shared,
        const TextSpan(text: 'ef'),
      ],
    );
    await tester.pumpWidget(
      _pair(
        TextAutoWrap.rich(
          source(breaks: false),
          model: offsetModel([3]),
          strategy: offsetStrategy([3]),
        ),
        Text.rich(source(breaks: true)),
        height: 80,
      ),
    );
    final actual = wrapRender(tester);
    final first = actual.firstChild;
    final second = actual.lastChild;
    final initialCache = actual.result!.diagnostics!.cache;
    var priorMisses = initialCache.selectionCacheMisses;
    var priorDimensions = dimensions.value;
    for (final value in [
      (const Size(12, 17), 11.0),
      (const Size(26, 31), 23.0),
      (const Size(26, 31), 7.0),
      (const Size(12, 17), 11.0),
    ]) {
      dimensions.value = value;
      await tester.pump();
      final cache = actual.result!.diagnostics!.cache;
      expect(cache.planMisses, initialCache.planMisses);
      if (value != priorDimensions) {
        expect(cache.selectionCacheMisses, priorMisses + 1);
      }
      priorMisses = cache.selectionCacheMisses;
      priorDimensions = value;
      expect(wrapRender(tester), same(actual));
      expect(actual.firstChild, same(first));
      expect(actual.lastChild, same(second));
      expect(first, isNot(same(second)));
      expect(actual.result!.applied, isTrue);
      expect(actual.failures, isEmpty);
      expect(actual.result!.widths, [20 + value.$1.width, 40 + value.$1.width]);
      final native = tester.allRenderObjects
          .whereType<RenderParagraph>()
          .where((render) => !identical(render, actual))
          .toSet()
          .single;
      expect(_geometry(actual), _geometry(native));
      await _expectPaintMatches(tester);
    }
    expect(
      actual.result!.diagnostics!.cache.selectionCacheMisses,
      greaterThan(initialCache.selectionCacheMisses),
    );
  });

  testWidgets('shared span occurrences retain distinct changing geometry', (
    tester,
  ) async {
    final dimensions = ValueNotifier<List<(Size, double)>>([
      (const Size(12, 17), 11),
      (const Size(25, 29), 18),
    ]);
    addTearDown(dimensions.dispose);
    final shared = WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: ValueListenableBuilder<List<(Size, double)>>(
        valueListenable: dimensions,
        builder: (context, values, _) {
          final tag =
              context
                      .findAncestorWidgetOfExactType<Semantics>()!
                      .properties
                      .tagForChildren!
                  as PlaceholderSpanIndexSemanticsTag;
          final value = values[tag.index];
          return _PaintBox(value.$1, value.$2);
        },
      ),
    );
    TextSpan source(bool breaks) => TextSpan(
      text: 'ab',
      children: [
        shared,
        TextSpan(text: breaks ? '\ncd' : 'cd'),
        shared,
        const TextSpan(text: 'ef'),
      ],
    );
    await tester.pumpWidget(
      _pair(
        TextAutoWrap.rich(
          source(false),
          model: offsetModel([3]),
          strategy: offsetStrategy([3]),
        ),
        Text.rich(source(true)),
        height: 80,
      ),
    );
    final actual = wrapRender(tester);
    final first = actual.firstChild;
    final second = actual.lastChild;
    for (final values in [
      [(const Size(12, 17), 11.0), (const Size(25, 29), 18.0)],
      [(const Size(12, 17), 11.0), (const Size(31, 35), 6.0)],
      [(const Size(27, 23), 15.0), (const Size(31, 35), 6.0)],
    ]) {
      dimensions.value = values;
      await tester.pump();
      expect(actual.firstChild, same(first));
      expect(actual.lastChild, same(second));
      expect((first!.parentData! as TextParentData).span, same(shared));
      expect((second!.parentData! as TextParentData).span, same(shared));
      expect(actual.result!.applied, isTrue);
      expect(actual.failures, isEmpty);
      expect(actual.result!.widths, [
        20 + values[0].$1.width,
        40 + values[1].$1.width,
      ]);
      final native = tester.allRenderObjects
          .whereType<RenderParagraph>()
          .where((render) => !identical(render, actual))
          .toSet()
          .single;
      expect(_geometry(actual), _geometry(native));
      await _expectPaintMatches(tester);
    }
  });
}

Widget _pair(
  Widget actual,
  Widget native, {
  TextDirection direction = TextDirection.ltr,
  required double height,
}) => Directionality(
  textDirection: direction,
  child: DefaultTextStyle(
    style: wrapStyle,
    child: Align(
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in [('actual', actual), ('native', native)])
            RepaintBoundary(
              key: ValueKey(entry.$1),
              child: ColoredBox(
                color: const Color(0xffffffff),
                child: SizedBox(
                  width: 180,
                  height: 100,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 120,
                      height: height,
                      child: entry.$2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  ),
);

List<Object?> _geometry(RenderParagraph render) => [
  render.size,
  render.didExceedMaxLines,
  for (
    var child = render.firstChild;
    child != null;
    child = render.childAfter(child)
  )
    ((child.parentData! as TextParentData).offset, child.size),
];

Future<void> _expectPaintMatches(WidgetTester tester) async {
  final actual = await _pixels(tester, 'actual');
  final native = await _pixels(tester, 'native');
  expect(actual, native);
  // Require actual painted placeholder pixels, so equal blank captures cannot
  // satisfy the native paint comparison.
  var greenPixels = 0;
  for (var i = 0; i < actual.length; i += 4) {
    if (actual[i] == 0x40 && actual[i + 1] == 0xb0 && actual[i + 2] == 0x30) {
      greenPixels++;
    }
  }
  expect(greenPixels, greaterThan(0));
}

Future<Uint8List> _pixels(WidgetTester tester, String key) async =>
    (await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(ValueKey(key)),
      );
      final image = await boundary.toImage();
      try {
        return (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;

class _PaintBox extends LeafRenderObjectWidget {
  const _PaintBox(this.size, this.baseline);
  final Size size;
  final double baseline;

  @override
  RenderBox createRenderObject(BuildContext context) =>
      _RenderPaintBox(size, baseline);

  @override
  void updateRenderObject(BuildContext context, _RenderPaintBox renderObject) {
    renderObject.update(size, baseline);
  }
}

class _RenderPaintBox extends RenderBox {
  _RenderPaintBox(this.desiredSize, this.baseline);
  Size desiredSize;
  double baseline;

  void update(Size newSize, double newBaseline) {
    if (desiredSize == newSize && baseline == newBaseline) return;
    desiredSize = newSize;
    baseline = newBaseline;
    markNeedsLayout();
  }

  @override
  void performLayout() => size = constraints.constrain(desiredSize);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(desiredSize);

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) =>
      this.baseline;

  @override
  double computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => this.baseline;

  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.drawRect(
      offset & size,
      Paint()..color = const Color(0xff40b030),
    );
    context.canvas.drawRect(
      Rect.fromLTWH(offset.dx, offset.dy + baseline, size.width, 1),
      Paint()..color = const Color(0xffa02090),
    );
  }
}
