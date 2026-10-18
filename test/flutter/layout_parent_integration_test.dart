import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  testWidgets('intrinsic table columns stay stable through repeated builds', (
    tester,
  ) async {
    final revision = ValueNotifier<int>(0);
    addTearDown(revision.dispose);
    final model = offsetModel([3]);
    const strategy = LineBreakStrategy();
    await tester.pumpWidget(
      wrapHost(
        ValueListenableBuilder<int>(
          valueListenable: revision,
          builder: (_, value, _) => Padding(
            padding: EdgeInsets.only(top: value.toDouble()),
            child: Table(
              columnWidths: const {0: IntrinsicColumnWidth()},
              children: [
                for (var i = 0; i < 6; i++)
                  TableRow(
                    children: [
                      TextAutoWrap('abcdef', model: model, strategy: strategy),
                      TextAutoWrap(
                        'abcdefghi',
                        model: model,
                        strategy: strategy,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        width: 240,
      ),
    );
    final initial = _renders(tester);
    expect(initial, hasLength(12));
    final sizes = [for (final render in initial) render.size];
    for (var repeat = 0; repeat < 4; repeat++) {
      revision.value++;
      await tester.pump();
      final renders = _renders(tester);
      expect([for (final render in renders) render.size], sizes);
      for (var i = 0; i < renders.length; i++) {
        expect(renders[i], same(initial[i]));
        expect(renders[i].failures, isEmpty);
        expect(
          renders[i].result!.sourceText,
          i.isEven ? 'abcdef' : 'abcdefghi',
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('survey intrinsic rows handle column and content changes', (
    tester,
  ) async {
    final columns = ValueNotifier<int>(2);
    addTearDown(columns.dispose);
    final model = offsetModel([3]);
    const strategy = LineBreakStrategy();
    await tester.pumpWidget(
      wrapHost(
        ValueListenableBuilder<int>(
          valueListenable: columns,
          builder: (_, count, _) => LayoutBuilder(
            builder: (_, constraints) => Column(
              children: [
                for (var row = 0; row < 6; row += count)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = row; i < row + count; i++)
                          Expanded(
                            child: Column(
                              children: [
                                const SizedBox(height: 40),
                                TextAutoWrap(
                                  count == 2 ? 'abcdef' : 'abcdefghi',
                                  key: ValueKey(i),
                                  model: model,
                                  strategy: strategy,
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        width: 360,
      ),
    );
    for (final count in [3, 2, 3]) {
      columns.value = count;
      await tester.pump();
      final renders = _renders(tester);
      expect(renders, hasLength(6));
      for (final render in renders) {
        expect(render.constraints.maxWidth, 360 / count);
        expect(render.result!.sourceText, count == 2 ? 'abcdef' : 'abcdefghi');
        expect(render.result!.lineCount, lessThanOrEqualTo(2));
        expect(render.failures, isEmpty);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'scaled WidgetSpan invalidates the warm layout in an intrinsic row',
    (tester) async {
      const source = TextSpan(
        text: 'ab',
        children: [
          WidgetSpan(child: SizedBox(width: 12, height: 8)),
          TextSpan(text: 'cdef'),
        ],
      );
      final model = offsetModel([3]);
      final strategy = offsetStrategy([3]);
      Future<void> show(double scale) => tester.pumpWidget(
        wrapHost(
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: TextAutoWrap.rich(
                    source,
                    model: model,
                    strategy: strategy,
                    textScaler: TextScaler.linear(scale),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await show(1);
      final render = wrapRender(tester);
      expect(render.result!.widths, [32, 40]);
      for (final scale in [1.5, 1.0, 1.5]) {
        await show(scale);
        expect(wrapRender(tester), same(render));
        expect(render.result!.widths, [32 * scale, 40 * scale]);
        expect(render.firstChild!.size.width, 12 * scale);
        expect(render.failures, isEmpty);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

List<RenderTextAutoWrap> _renders(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderTextAutoWrap>().toSet().toList();
