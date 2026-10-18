import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  testWidgets(
    'equivalent source replacement retains the latest source identity',
    (tester) async {
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap(
            'abcdef',
            model: offsetModel([3]),
            strategy: offsetStrategy([3]),
          ),
        ),
      );
      final render = wrapRender(tester);
      expect(render.result!.applied, isTrue);
      final previous = render.sourceText as TextSpan;
      final effective = render.effectiveText;
      final replacement = TextSpan(
        text: previous.text,
        style: previous.style,
        locale: previous.locale,
        children: previous.children,
      );
      expect(replacement, previous);
      expect(identical(replacement, previous), isFalse);
      render.sourceText = replacement;
      expect(render.sourceText, same(replacement));
      expect(render.effectiveText, same(effective));
      await tester.pump();
      expect(render.result!.applied, isTrue);
      expect(render.effectiveText.toPlainText(), 'abc\ndef');
    },
  );

  testWidgets(
    'rich selection and semantics match native through updates and moves',
    (tester) async {
      final semantics = tester.ensureSemantics();

      Future<List<Object?>> exercise(bool semanticWrap) async {
        final stage = ValueNotifier(0);
        final first = TextAutoWrapController();
        final second = TextAutoWrapController();
        final key = GlobalKey();
        final paintKey = GlobalKey();
        final taps = <int>[];
        final beforeTap = TapGestureRecognizer()..onTap = () => taps.add(0);
        final afterTap = TapGestureRecognizer()..onTap = () => taps.add(1);
        final model = offsetModel([3]);
        final strategy = offsetStrategy([3]);
        SelectedContent? selected;
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SelectionArea(
                  onSelectionChanged: (value) => selected = value,
                  child: DefaultTextStyle(
                    style: wrapStyle,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ValueListenableBuilder<int>(
                        valueListenable: stage,
                        builder: (_, current, _) {
                          final changed = current > 0;
                          final leaf = TextSpan(
                            text: changed ? 'uvw' : 'abc',
                            semanticsLabel: changed ? 'new first' : 'old first',
                            recognizer: changed ? afterTap : beforeTap,
                            locale: changed
                                ? const Locale('fr', 'FR')
                                : const Locale('en', 'US'),
                            spellOut: changed,
                          );
                          final source = TextSpan(
                            style: TextStyle(
                              fontSize: changed ? 12 : 10,
                              color: changed ? Colors.blue : Colors.black,
                            ),
                            children: [
                              leaf,
                              if (!semanticWrap) const TextSpan(text: '\n'),
                              TextSpan(
                                text: changed ? 'xyz' : 'def',
                                semanticsLabel: changed
                                    ? 'new last'
                                    : 'old last',
                              ),
                            ],
                          );
                          final target = semanticWrap
                              ? TextAutoWrap.rich(
                                  source,
                                  key: key,
                                  controller: changed ? second : first,
                                  model: model,
                                  strategy: strategy,
                                )
                              : Text.rich(source, key: key);
                          return RepaintBoundary(
                            key: paintKey,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 100,
                                  child: current < 2 ? target : null,
                                ),
                                SizedBox(
                                  width: 100,
                                  child: current == 2 ? target : null,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          RenderParagraph paragraph() => tester.allRenderObjects
              .whereType<RenderParagraph>()
              .toSet()
              .single;
          final initial = paragraph();
          final traces = <Object?>[];
          for (var current = 0; current < 3; current++) {
            if (current > 0) {
              stage.value = current;
              await tester.pump();
            }
            final render = paragraph();
            expect(render, same(initial));
            if (semanticWrap) {
              expect((render as RenderTextAutoWrap).result!.applied, isTrue);
              expect(render.failures, isEmpty);
            }
            // Record the active selection before issuing a new selection event.
            traces.add(List.of(render.selections));
            tester
                .state<SelectableRegionState>(find.byType(SelectableRegion))
                .selectAll();
            await tester.pump();
            expect(selected!.plainText, current == 0 ? 'abc\ndef' : 'uvw\nxyz');
            traces.add(selected!.plainText);
            traces.add(List.of(render.selections));
            traces.add(render.size);
            traces.add([
              for (var offset = 0; offset < 7; offset++)
                render
                    .getBoxesForSelection(
                      TextSelection(
                        baseOffset: offset,
                        extentOffset: offset + 1,
                      ),
                    )
                    .map((box) => box.toRect())
                    .toList(),
            ]);
            traces.add(_semanticLabels(tester));
            traces.add(await _pixels(tester, paintKey));
            final box = render
                .getBoxesForSelection(
                  const TextSelection(baseOffset: 0, extentOffset: 1),
                )
                .single;
            await tester.tapAt(render.localToGlobal(box.toRect().center));
            traces.add(List.of(taps));
            // Leave a noncollapsed selection active during the next rebuild.
            tester
                .state<SelectableRegionState>(find.byType(SelectableRegion))
                .selectAll();
            await tester.pump();
          }
          expect(taps, [0, 1, 1]);
          return traces;
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          stage.dispose();
          first.dispose();
          second.dispose();
          beforeTap.dispose();
          afterTap.dispose();
        }
      }

      try {
        final native = await exercise(false);
        expect(await exercise(true), native);
      } finally {
        semantics.dispose();
      }
    },
  );

  for (final partial in [false, true]) {
    testWidgets(
      'controller-only rebuild preserves native active selection (partial=$partial)',
      (tester) async {
        Future<List<TextSelection>> exercise(bool semanticWrap) async {
          final first = TextAutoWrapController();
          final second = TextAutoWrapController();
          final controller = ValueNotifier(first);
          final model = offsetModel([3]);
          final strategy = offsetStrategy([3]);
          try {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: SelectionArea(
                    child: ValueListenableBuilder<TextAutoWrapController>(
                      valueListenable: controller,
                      builder: (_, value, _) => wrapHost(
                        semanticWrap
                            ? TextAutoWrap(
                                'abcdef',
                                controller: value,
                                model: model,
                                strategy: strategy,
                              )
                            : const Text('abc\ndef'),
                      ),
                    ),
                  ),
                ),
              ),
            );
            final render = tester.allRenderObjects
                .whereType<RenderParagraph>()
                .toSet()
                .single;
            if (semanticWrap) {
              expect((render as RenderTextAutoWrap).result!.applied, isTrue);
            }
            if (partial) {
              await _dragSelection(tester, render, 4, 7);
            } else {
              tester
                  .state<SelectableRegionState>(find.byType(SelectableRegion))
                  .selectAll();
            }
            await tester.pump();
            expect(render.selections, [
              TextSelection(baseOffset: partial ? 4 : 0, extentOffset: 7),
            ]);
            controller.value = second;
            await tester.pump();
            if (semanticWrap) {
              expect((render as RenderTextAutoWrap).result!.applied, isTrue);
              expect(second.result!.applied, isTrue);
            }
            return List.of(render.selections);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            controller.dispose();
            first.dispose();
            second.dispose();
          }
        }

        final native = await exercise(false);
        expect(native, [
          TextSelection(baseOffset: partial ? 4 : 0, extentOffset: 7),
        ]);
        expect(await exercise(true), native);
      },
    );
  }
}

Future<void> _dragSelection(
  WidgetTester tester,
  RenderParagraph render,
  int start,
  int end,
) async {
  Offset position(int offset) => render.localToGlobal(
    render.getOffsetForCaret(TextPosition(offset: offset), Rect.zero) +
        const Offset(0, 5),
  );
  final gesture = await tester.startGesture(
    position(start),
    kind: PointerDeviceKind.mouse,
  );
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(position(end));
  await gesture.up();
  await tester.pump();
}

List<Object> _semanticLabels(WidgetTester tester) {
  final labels = <Object>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.label.isNotEmpty) {
      labels.add([
        data.label,
        data.actions,
        data.attributedLabel.attributes.map((attribute) {
          return switch (attribute) {
            ui.LocaleStringAttribute() => [
              'locale',
              attribute.range.start,
              attribute.range.end,
              attribute.locale.toString(),
            ],
            ui.SpellOutStringAttribute() => [
              'spellOut',
              attribute.range.start,
              attribute.range.end,
              '',
            ],
            _ => ['other', attribute.range.start, attribute.range.end, ''],
          };
        }).toList(),
      ]);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return labels;
}

Future<List<int>> _pixels(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      try {
        return (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;
