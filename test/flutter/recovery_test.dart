import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  for (final softWrap in [true, false]) {
    testWidgets('unavailable native diagnostics do not prevent painting '
        'softWrap=$softWrap', (tester) async {
      final controller = TextAutoWrapController();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      Widget frame(InlineSpan source) => wrapHost(
        TextAutoWrap.rich(source, controller: controller, softWrap: softWrap),
      );
      await tester.pumpWidget(frame(const TextSpan(text: 'previous')));
      final render = wrapRender(tester);
      expect(controller.result!.sourceText, 'previous');
      expect(notifications, 1);

      // Native shaping can paint this span, but its source map disagrees with
      // native line boundaries, simulating an invalid engine range response.
      var builds = 0;
      final malformed = _MisreportedSpan(() => builds++);
      await tester.pumpWidget(frame(malformed));
      expect(tester.takeException(), isNull);
      expect(wrapRender(tester), same(render));
      expect(render.hasSize, isTrue);
      expect(render.size.height, 10);
      expect(render.effectiveText, same(render.sourceText));
      expect(render.result, isNull);
      expect(controller.result, isNull);
      // One diagnostic shaping attempt and one actual native paragraph. The
      // failed diagnostic layout must not be measured again in fallback.
      expect(builds, 2);
      expect(controller.failures, hasLength(1));
      expect(
        controller.failures.single.stage,
        TextWrapFailureStage.nativeMeasurement,
      );
      expect(
        controller.failures.single.error,
        isA<TextRangeMeasurementException>(),
      );
      expect(notifications, 2);

      await tester.pumpWidget(frame(const TextSpan(text: 'recovered')));
      expect(tester.takeException(), isNull);
      expect(controller.result!.sourceText, 'recovered');
      expect(controller.failures, isEmpty);
      expect(notifications, 3);
    });
  }
}

class _MisreportedSpan extends TextSpan {
  const _MisreportedSpan(this.onBuild) : super(text: 'abc');

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

  @override
  void computeToPlainText(
    StringBuffer buffer, {
    bool includeSemanticsLabels = true,
    bool includePlaceholders = true,
  }) => buffer.write('a');
}
