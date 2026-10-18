// ignore_for_file: invalid_use_of_protected_member

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

const _source = TextSpan(
  text: 'abc',
  style: TextStyle(fontSize: 10),
  children: [TextSpan(text: 'def', style: TextStyle(fontSize: 30))],
);

class _Inputs {
  InlineSpan source = _source;
  TextAlign align = TextAlign.start;
  TextDirection direction = TextDirection.ltr;
  TextScaler scaler = TextScaler.noScaling;
  Locale? locale;
  StrutStyle? strut;
  ui.TextHeightBehavior? height;
  TextWidthBasis basis = TextWidthBasis.parent;
  int? lines;
  TextOverflow overflow = TextOverflow.clip;
  bool wrap = true;

  InlineSpan get root => TextSpan(style: wrapStyle, children: [source]);

  RenderParagraph oracle() => RenderParagraph(
    root,
    textAlign: align,
    textDirection: direction,
    textScaler: scaler,
    locale: locale,
    strutStyle: strut,
    textHeightBehavior: height,
    textWidthBasis: basis,
    maxLines: lines,
    overflow: overflow,
    softWrap: wrap,
  );
}

void main() {
  testWidgets(
    'warm queries track occurrence-specific dry placeholder changes',
    (tester) async {
      const shared = WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: _DryBox(),
      );
      const source = TextSpan(
        style: wrapStyle,
        text: 'ab',
        children: [
          shared,
          TextSpan(text: 'cd'),
          shared,
          TextSpan(text: 'ef'),
        ],
      );
      final controller = TextAutoWrapController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap.rich(
            source,
            controller: controller,
            model: offsetModel([3, 6]),
            strategy: offsetStrategy([3, 6]),
          ),
          width: 200,
        ),
      );
      final render = wrapRender(tester);
      expect(render.result!.applied, isTrue);
      final effective = render.effectiveText;
      final result = render.result;
      final committed = controller.result;
      final actualSize = render.size;
      final first = tester.renderObject<_DryChild>(find.byType(_DryBox).first);
      final second = tester.renderObject<_DryChild>(find.byType(_DryBox).last);
      expect(first, isNot(same(second)));
      final actualChildren = [first.size, second.size];
      for (final values in [
        [(const Size(12, 17), 11.0), (const Size(12, 17), 11.0)],
        [(const Size(26, 31), 23.0), (const Size(9, 21), 7.0)],
        [(const Size(26, 31), 7.0), (const Size(9, 21), 18.0)],
        [(const Size(12, 17), 11.0), (const Size(12, 17), 11.0)],
      ]) {
        first.updateQuery(values[0].$1, values[0].$2);
        second.updateQuery(values[1].$1, values[1].$2);
        for (final width in [160.0, 90.0, 40.0, 160.0]) {
          final children = [
            for (final value in values) _DryChild(value.$1, value.$2),
          ];
          final native = RenderParagraph(
            source,
            textDirection: TextDirection.ltr,
            children: children,
          );
          for (final child in children) {
            (child.parentData! as TextParentData).span = shared;
          }
          try {
            final bounds = BoxConstraints(maxWidth: width);
            expect(
              render.computeDryLayout(bounds),
              native.computeDryLayout(bounds),
            );
            expect(
              render.computeDryBaseline(bounds, TextBaseline.alphabetic),
              native.computeDryBaseline(bounds, TextBaseline.alphabetic),
            );
            expect(
              render.computeMinIntrinsicHeight(width),
              native.computeMinIntrinsicHeight(width),
            );
            expect(
              render.computeMaxIntrinsicHeight(width),
              native.computeMaxIntrinsicHeight(width),
            );
          } finally {
            native.dispose();
            for (final child in children) {
              child.dispose();
            }
          }
          expect(render.effectiveText, same(effective));
          expect(render.result, same(result));
          expect(controller.result, same(committed));
          expect(render.size, actualSize);
          expect([first.size, second.size], actualChildren);
        }
      }
    },
  );

  testWidgets('warm source queries follow changed inputs before layout', (
    tester,
  ) async {
    final controller = TextAutoWrapController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap.rich(
          _source,
          model: offsetModel([3]),
          strategy: offsetStrategy([3]),
          controller: controller,
        ),
        width: 200,
      ),
    );
    final render = wrapRender(tester);
    expect(render.result!.applied, isTrue);
    expect(render.effectiveText.toPlainText(), 'abc\ndef');
    final inputs = _Inputs();
    final changes = <(String, void Function())>[
      ('warm baseline', () {}),
      (
        'alignment',
        () {
          inputs.align = TextAlign.justify;
          render.textAlign = inputs.align;
        },
      ),
      (
        'RTL',
        () {
          inputs.direction = TextDirection.rtl;
          render.textDirection = inputs.direction;
        },
      ),
      (
        'scaler',
        () {
          inputs.scaler = const TextScaler.linear(1.6);
          render.textScaler = inputs.scaler;
        },
      ),
      (
        'locale',
        () {
          inputs.locale = const Locale('ja', 'JP');
          render.locale = inputs.locale!;
        },
      ),
      (
        'strut',
        () {
          inputs.strut = const StrutStyle(
            fontSize: 25,
            height: 1.5,
            forceStrutHeight: true,
          );
          render.strutStyle = inputs.strut;
        },
      ),
      (
        'height behavior',
        () {
          inputs.height = const ui.TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          );
          render.textHeightBehavior = inputs.height;
        },
      ),
      (
        'width basis',
        () {
          inputs.basis = TextWidthBasis.longestLine;
          render.textWidthBasis = inputs.basis;
        },
      ),
      (
        'line limit',
        () {
          inputs.lines = 1;
          render.maxLines = inputs.lines;
        },
      ),
      for (final overflow in TextOverflow.values)
        (
          'overflow $overflow',
          () {
            inputs.overflow = overflow;
            render.overflow = overflow;
          },
        ),
      (
        'soft wrap disabled',
        () {
          inputs.wrap = false;
          render.softWrap = false;
        },
      ),
      (
        'soft wrap restored',
        () {
          inputs.wrap = true;
          render.softWrap = true;
        },
      ),
      (
        'source and style',
        () {
          inputs.source = const TextSpan(
            text: 'uvwxyz',
            style: TextStyle(fontSize: 18, height: 1.3, letterSpacing: 2),
          );
          render.sourceText = inputs.root;
        },
      ),
      (
        'mixed source restored',
        () {
          inputs.source = _source;
          render.sourceText = inputs.root;
        },
      ),
    ];
    for (final (name, change) in changes) {
      change();
      final effective = render.effectiveText;
      final size = render.size;
      final result = render.result;
      final committed = controller.result;
      final failures = render.failures;
      // More than eight distinct bounds, then repeats, exercise cache eviction
      // and order changes without relying on the production painter as oracle.
      for (final index in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 3, 0, 9]) {
        final constraints = BoxConstraints(
          minWidth: index.isEven ? 0 : 12,
          maxWidth: 20 + index * 23.0,
          maxHeight: index == 5 ? 15 : double.infinity,
        );
        final native = inputs.oracle();
        try {
          final width = constraints.maxWidth;
          expect(
            render.computeDryBaseline(constraints, TextBaseline.ideographic),
            native.computeDryBaseline(constraints, TextBaseline.ideographic),
            reason: '$name bounds=$constraints ideographic baseline',
          );
          expect(
            render.computeDryLayout(constraints),
            native.computeDryLayout(constraints),
            reason: '$name bounds=$constraints dry layout',
          );
          expect(
            render.computeMinIntrinsicHeight(width),
            native.computeMinIntrinsicHeight(width),
            reason: '$name min height',
          );
          expect(
            render.computeMaxIntrinsicHeight(width),
            native.computeMaxIntrinsicHeight(width),
            reason: '$name max height',
          );
          expect(
            render.computeMinIntrinsicWidth(width),
            native.computeMinIntrinsicWidth(width),
            reason: '$name min width',
          );
          expect(
            render.computeMaxIntrinsicWidth(width),
            native.computeMaxIntrinsicWidth(width),
            reason: '$name max width',
          );
          expect(
            render.computeDryBaseline(constraints, TextBaseline.alphabetic),
            native.computeDryBaseline(constraints, TextBaseline.alphabetic),
            reason: '$name bounds=$constraints alphabetic baseline',
          );
        } finally {
          native.dispose();
        }
        expect(render.effectiveText, same(effective), reason: name);
        expect(render.size, size, reason: name);
        expect(render.result, same(result), reason: name);
        expect(controller.result, same(committed), reason: name);
        expect(render.failures, same(failures), reason: name);
      }
    }
  });
}

class _DryBox extends LeafRenderObjectWidget {
  const _DryBox();
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _DryChild(const Size(12, 17), 11);
}

class _DryChild extends RenderBox {
  _DryChild(this.querySize, this.queryBaseline);
  Size querySize;
  double queryBaseline;

  void updateQuery(Size nextSize, double nextBaseline) {
    querySize = nextSize;
    queryBaseline = nextBaseline;
    markNeedsLayout();
  }

  @override
  void performLayout() => size = constraints.constrain(querySize);
  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(querySize);
  @override
  double computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => queryBaseline;
  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) =>
      queryBaseline;
}
