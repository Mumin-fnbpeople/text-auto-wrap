import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  testWidgets(
    'equivalent NaN argument failures do not notify on every layout',
    (tester) async {
      final controller = TextAutoWrapController();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final model = PhraseModel(
        levels: [
          PhraseModelLevel(
            name: 'invalid score',
            predictor: const _NumericFailure(double.nan),
            penalty: 0,
          ),
        ],
        fallbackPenalty: 100,
        boundaryMode: BoundaryMode.characters,
      );
      Widget frame(double width) => wrapHost(
        TextAutoWrap('abcdef', model: model, controller: controller),
        width: width,
      );
      await tester.pumpWidget(frame(100));
      expect(controller.result!.sourceText, 'abcdef');
      expect(controller.failures.single.error, isA<ArgumentError>());
      expect(notifications, 1);
      await tester.pumpWidget(frame(110));
      expect(controller.failures.single.error, isA<ArgumentError>());
      expect(notifications, 1);
      await tester.pumpWidget(frame(100));
      expect(notifications, 1);
      final changedModel = PhraseModel(
        levels: [
          PhraseModelLevel(
            name: 'invalid score',
            predictor: const _NumericFailure(7),
            penalty: 0,
          ),
        ],
        fallbackPenalty: 100,
        boundaryMode: BoundaryMode.characters,
      );
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap('abcdef', model: changedModel, controller: controller),
        ),
      );
      expect(
        (controller.failures.single.error as ArgumentError).invalidValue,
        7,
      );
      expect(notifications, 2);
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap(
            'abcdef',
            model: offsetModel([3]),
            strategy: offsetStrategy([3]),
            controller: controller,
          ),
        ),
      );
      expect(controller.result!.applied, isTrue);
      expect(controller.result!.lines, ['abc', 'def']);
      expect(controller.failures, isEmpty);
      expect(notifications, 3);
    },
  );
}

final class _NumericFailure implements BoundaryPredictor {
  const _NumericFailure(this.value);
  final double value;
  @override
  List<int> predict(String text) {
    throw ArgumentError.value(value, 'score', 'must be finite');
  }
}
