import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  for (final source in [
    '1111\n\u00ad\n3333',
    '가\u00ad나',
    '\u00ad\u00ad\u00ad',
    'A\u200dB',
  ]) {
    for (final spacing in [-0.2, -1.0, -8.0]) {
      testWidgets(
        'native paint preserves ${source.codeUnits} spacing=$spacing',
        (tester) async {
          final style = TextStyle(
            fontSize: 10,
            letterSpacing: spacing,
            color: const Color(0xff123456),
          );
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  for (final actual in [true, false])
                    RepaintBoundary(
                      key: ValueKey(actual),
                      child: ColoredBox(
                        color: const Color(0xffffffff),
                        child: SizedBox(
                          width: 200,
                          height: 80,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: actual
                                ? TextAutoWrap(
                                    source,
                                    style: style,
                                    model: offsetModel([]),
                                    strategy: offsetStrategy([]),
                                  )
                                : Text(source, style: style),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(wrapRender(tester).failures, isEmpty);
          final actual = await _pixels(tester, true);
          final native = await _pixels(tester, false);
          expect(actual, native);
          if (source.startsWith('1111') ||
              (source != '\u00ad\u00ad\u00ad' && spacing > -8)) {
            expect(
              actual.any((byte) => byte != 255),
              isTrue,
              reason: 'captures must include painted glyphs',
            );
          }
        },
      );
    }
  }

  for (final delimiter in ['\u0085', '\u000b', '\u000c']) {
    for (final source in [
      'a${delimiter}b',
      'a$delimiter',
      '$delimiter$delimiter',
    ]) {
      testWidgets('native hard break fidelity ${source.codeUnits}', (
        tester,
      ) async {
        await tester.pumpWidget(
          wrapHost(
            TextAutoWrap(
              source,
              model: offsetModel([]),
              strategy: offsetStrategy([]),
            ),
          ),
        );
        final actual = wrapRender(tester);
        final native = TextPainter(
          text: TextSpan(text: source, style: wrapStyle),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 100);
        try {
          expect(tester.takeException(), isNull);
          expect(actual.size.height, native.height);
          expect(actual.result, isNotNull);
          expect(actual.result!.sourceText, source);
          expect(actual.result!.lineCount, native.computeLineMetrics().length);
          if (delimiter == '\u0085' &&
              native.computeLineMetrics().length == 1) {
            // This engine does not implement NEL as a paragraph delimiter.
            expect(actual.result!.applied, isFalse);
            expect(actual.effectiveText.toPlainText(), source);
            expect(
              actual.failures.single.error,
              isA<TextRangeMeasurementException>(),
            );
          } else {
            expect(actual.failures, isEmpty);
          }
        } finally {
          native.dispose();
        }
      });
    }
  }

  testWidgets('oversized native-only source also avoids diagnostic shaping', (
    tester,
  ) async {
    var builds = 0;
    final source = _LargeSource(() => builds++, 'a' * 1000000);
    await tester.pumpWidget(
      wrapHost(TextAutoWrap.rich(source, softWrap: false)),
    );
    final render = wrapRender(tester);
    expect(tester.takeException(), isNull);
    expect(builds, 1);
    expect(render.result, isNull);
    expect(render.failures.single.error, isA<TextWrapInputLimitException>());
  });

  testWidgets(
    'oversized source bypasses semantic and diagnostic shaping before native paint',
    (tester) async {
      var builds = 0;
      final source = _LargeSource(() => builds++, 'a' * 1000000);
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap.rich(
            source,
            model: offsetModel([]),
            strategy: offsetStrategy([]),
          ),
        ),
      );
      final render = wrapRender(tester);
      expect(tester.takeException(), isNull);
      expect(identical(render.effectiveText, render.sourceText), isTrue);
      expect(
        builds,
        1,
        reason: 'Only RenderParagraph should shape oversized source',
      );
      expect(render.result, isNull);
      expect(render.failures.single.error, isA<TextWrapInputLimitException>());
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap(
            'abcdef',
            model: offsetModel([3]),
            strategy: offsetStrategy([3]),
          ),
        ),
      );
      expect(wrapRender(tester).result!.applied, isTrue);
      expect(wrapRender(tester).failures, isEmpty);
    },
  );

  testWidgets(
    'a custom source invalidates cached dry geometry when marked dirty',
    (tester) async {
      final size = ValueNotifier<double>(10);
      addTearDown(size.dispose);
      final source = TextSpan(
        children: [
          _MutableSizeSpan(size),
          const TextSpan(text: 'def'),
        ],
      );
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
      expect(
        render.computeDryLayout(const BoxConstraints(maxWidth: 100)).width,
        60,
      );
      size.value = 20;
      render.markNeedsLayout();
      expect(
        render.computeDryLayout(const BoxConstraints(maxWidth: 100)).width,
        90,
      );
    },
  );

  testWidgets('source measurements reuse shaping across parent queries', (
    tester,
  ) async {
    final builds = <int>[0];
    final source = _BuildCountSpan(builds);
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap.rich(
          TextSpan(
            children: [
              source,
              const TextSpan(text: 'def'),
            ],
          ),
          model: offsetModel([3]),
          strategy: offsetStrategy([3]),
        ),
      ),
    );
    final render = wrapRender(tester);
    expect(render.result!.applied, isTrue);
    for (final width in [100.0, 80.0, 120.0]) {
      render.computeDryLayout(BoxConstraints(maxWidth: width));
    }
    final built = builds.single;
    for (var repeat = 0; repeat < 20; repeat++) {
      for (final width in [100.0, 80.0, 120.0]) {
        expect(render.computeMinIntrinsicHeight(width), 10);
        expect(render.computeMaxIntrinsicHeight(width), 10);
        expect(
          render.computeDryLayout(BoxConstraints(maxWidth: width)),
          const Size(60, 10),
        );
        render.computeDryBaseline(
          BoxConstraints(maxWidth: width),
          TextBaseline.alphabetic,
        );
      }
    }
    expect(
      builds.single,
      built,
      reason: 'warm queries must not rebuild the source paragraph',
    );
  });
}

Future<Uint8List> _pixels(WidgetTester tester, bool actual) async =>
    (await tester.runAsync(() async {
      final render = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(ValueKey(actual)),
      );
      final image = await render.toImage();
      try {
        return (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;

class _BuildCountSpan extends TextSpan {
  _BuildCountSpan(this.builds) : super(text: 'abc', style: wrapStyle);
  final List<int> builds;
  @override
  void build(
    ui.ParagraphBuilder builder, {
    TextScaler textScaler = TextScaler.noScaling,
    List<PlaceholderDimensions>? dimensions,
  }) {
    builds[0]++;
    super.build(builder, textScaler: textScaler, dimensions: dimensions);
  }
}

class _MutableSizeSpan extends TextSpan {
  const _MutableSizeSpan(this.size) : super(text: 'abc', style: wrapStyle);
  final ValueNotifier<double> size;
  @override
  void build(
    ui.ParagraphBuilder builder, {
    TextScaler textScaler = TextScaler.noScaling,
    List<PlaceholderDimensions>? dimensions,
  }) {
    builder.pushStyle(ui.TextStyle(fontSize: size.value));
    builder.addText('abc');
    builder.pop();
  }
}

class _LargeSource extends TextSpan {
  const _LargeSource(this.onBuild, String source)
    : super(text: source, style: const TextStyle(fontSize: 0.001));
  final VoidCallback onBuild;
  @override
  void build(
    ui.ParagraphBuilder builder, {
    TextScaler textScaler = TextScaler.noScaling,
    List<PlaceholderDimensions>? dimensions,
  }) {
    onBuild();
    super.build(builder, textScaler: textScaler, dimensions: dimensions);
  }
}
