import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  for (final (name, first, changed) in <(String, RangeError, RangeError)>[
    (
      'minimum bound',
      RangeError.range(-1, 0, 5, 'offset'),
      RangeError.range(-1, 1, 5, 'offset'),
    ),
    (
      'maximum bound',
      RangeError.range(5, 0, 3, 'offset'),
      RangeError.range(5, 0, 4, 'offset'),
    ),
    (
      'indexable length',
      IndexError.withLength(5, 3, name: 'offset'),
      IndexError.withLength(5, 4, name: 'offset'),
    ),
  ]) {
    testWidgets('changed $name notifies failure observers', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final controller = TextAutoWrapController();
      addTearDown(controller.dispose);
      final owner = Object();
      final observedBounds = <(num?, num?)>[];
      controller.addListener(() {
        final error = controller.failures.single.error as RangeError;
        observedBounds.add((error.start, error.end));
      });

      for (final error in [first, changed]) {
        controller.clearResult(owner, failures: [_failure(error)]);
        tester.binding.scheduleFrame();
        await tester.pump();
      }

      expect(observedBounds, [
        (first.start, first.end),
        (changed.start, changed.end),
      ]);

      // A fresh equivalent error must still avoid a notification/layout loop.
      final equivalent = changed is IndexError
          ? IndexError.withLength(5, 4, name: 'offset')
          : RangeError.range(
              changed.invalidValue!,
              changed.start as int?,
              changed.end as int?,
              'offset',
            );
      controller.clearResult(owner, failures: [_failure(equivalent)]);
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(observedBounds, hasLength(2));
    });
  }
}

TextWrapFailure _failure(Object error) => TextWrapFailure(
  stage: TextWrapFailureStage.semanticLayout,
  reason: 'invalidRuntimeMeasurement',
  error: error,
  stackTrace: StackTrace.current,
);
