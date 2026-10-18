import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  for (final unavailableGeometry in [false, true]) {
    testWidgets('clean renderer reattachment delivers pending '
        '${unavailableGeometry ? 'failure' : 'selection'} once', (
      tester,
    ) async {
      final controller = TextAutoWrapController();
      addTearDown(controller.dispose);
      final observed = <TextWrapResult?>[];
      controller.addListener(() => observed.add(controller.result));
      final fixture = _PipelineFixture(
        tester,
        controller,
        source: unavailableGeometry ? const _MisreportedSpan() : null,
      );
      if (unavailableGeometry) {
        expect(controller.result, isNull);
        expect(
          controller.failures.single.stage,
          TextWrapFailureStage.nativeMeasurement,
        );
        expect(
          controller.failures.single.error,
          isA<TextRangeMeasurementException>(),
        );
        expect(fixture.render.effectiveText, same(fixture.render.sourceText));
      } else {
        expect(controller.result!.applied, isTrue);
        expect(controller.result!.lines, ['abc', 'def']);
      }
      expect(fixture.render.debugNeedsLayout, isFalse);
      expect(observed, isEmpty);

      fixture.reattach();
      fixture.reattach();
      // Reattachment need not run performLayout on a clean paragraph.
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(observed, hasLength(1));
      if (unavailableGeometry) {
        expect(observed.single, isNull);
        expect(controller.failures, hasLength(1));
      } else {
        expect(observed.single!.lines, ['abc', 'def']);
      }
      // Already delivered snapshots must not restart notification loops.
      fixture.reattach();
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(observed, hasLength(1));
    });
  }

  testWidgets('renderer controller replacement from a listener is deferred', (
    tester,
  ) async {
    final first = TextAutoWrapController();
    final second = TextAutoWrapController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final fixture = _PipelineFixture(tester, first);
    final observed = <String>[];
    first.addListener(() {
      observed.add('first');
      fixture.render.controller = second;
      expect(second.result!.lines, ['abc', 'def']);
      expect(observed, ['first']);
    });
    second.addListener(() => observed.add('second'));
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(observed, ['first']);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(observed, ['first', 'second']);
    fixture.reattach();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(observed, ['first', 'second']);
  });

  testWidgets('disposed controller ignores renderer pending and attach hooks', (
    tester,
  ) async {
    final controller = TextAutoWrapController();
    var notifications = 0;
    controller.addListener(() => notifications++);
    final fixture = _PipelineFixture(tester, controller);
    expect(controller.result!.applied, isTrue);
    controller.dispose();
    fixture.reattach();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(notifications, 0);
    expect(tester.takeException(), isNull);
  });
}

final class _PipelineFixture {
  _PipelineFixture(
    WidgetTester tester,
    TextAutoWrapController controller, {
    InlineSpan? source,
  }) {
    render = RenderTextAutoWrap(
      sourceText:
          source ??
          const TextSpan(
            text: 'abcdef',
            style: TextStyle(fontSize: 10, fontFamily: 'Ahem'),
          ),
      model: offsetModel([3]),
      strategy: offsetStrategy([3]),
      controller: controller,
      textDirection: TextDirection.ltr,
    );
    root = RenderView(
      view: tester.view,
      configuration: ViewConfiguration.fromView(tester.view),
      child: render,
    );
    owner.rootNode = root;
    addTearDown(() {
      owner.rootNode = null;
      root.child = null;
      render.dispose();
      root.dispose();
      owner.dispose();
    });
    root.prepareInitialFrame();
    owner.flushLayout();
  }

  final owner = PipelineOwner();
  late final RenderTextAutoWrap render;
  late final RenderView root;

  void reattach() {
    root.detach();
    root.attach(owner);
    owner.flushLayout();
  }
}

// The native paragraph paints "abc", while the custom source map reports "a".
// This injects unavailable diagnostic geometry without failing native painting.
final class _MisreportedSpan extends TextSpan {
  const _MisreportedSpan()
    : super(text: 'abc', style: const TextStyle(fontSize: 10));

  @override
  void computeToPlainText(
    StringBuffer buffer, {
    bool includeSemanticsLabels = true,
    bool includePlaceholders = true,
  }) => buffer.write('a');
}
