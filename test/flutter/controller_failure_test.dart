import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  testWidgets('changed failure messages notify after the frame', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final controller = TextAutoWrapController();
    addTearDown(controller.dispose);
    final owner = Object();
    var notifications = 0;
    controller.addListener(() => notifications++);
    List<TextWrapFailure> failure(Object error) => [
      TextWrapFailure(
        stage: TextWrapFailureStage.nativeMeasurement,
        reason: 'invalidRuntimeMeasurement',
        error: error,
        stackTrace: StackTrace.current,
      ),
    ];

    controller.clearResult(
      owner,
      failures: failure(
        const TextRangeMeasurementException('invalid boundary'),
      ),
    );
    expect(notifications, 0);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(notifications, 1);

    controller.clearResult(
      owner,
      failures: failure(const TextRangeMeasurementException('no line metrics')),
    );
    expect(notifications, 1);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(notifications, 2);

    controller.clearResult(
      owner,
      failures: failure(const TextRangeMeasurementException('no line metrics')),
    );
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(notifications, 2);
    expect(controller.result, isNull);
  });

  for (final withResult in [false, true]) {
    for (final detachFirst in [false, true]) {
      testWidgets(
        'equivalent ${withResult ? 'result' : 'failure'} retains pending '
        'notification across owner switch detachFirst=$detachFirst',
        (tester) async {
          await tester.pumpWidget(const SizedBox());
          final controller = TextAutoWrapController();
          addTearDown(controller.dispose);
          final firstOwner = Object();
          final nextOwner = Object();
          var notifications = 0;
          controller.addListener(() => notifications++);
          void publish(Object owner) {
            if (withResult) {
              controller.commitResult(owner, _result());
            } else {
              controller.clearResult(
                owner,
                failures: [_failure(StateError('same'))],
              );
            }
          }

          publish(firstOwner);
          if (detachFirst) controller.detachOwner(firstOwner);
          publish(nextOwner);
          if (!detachFirst) controller.detachOwner(firstOwner);
          expect(notifications, 0);
          tester.binding.scheduleFrame();
          await tester.pump();
          expect(notifications, 1);
          publish(nextOwner);
          tester.binding.scheduleFrame();
          await tester.pump();
          expect(notifications, 1);
        },
      );
    }
  }

  testWidgets('same owner reattachment recovers a cancelled pending callback', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final controller = TextAutoWrapController();
    addTearDown(controller.dispose);
    final owner = Object();
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.clearResult(owner, failures: [_failure(StateError('same'))]);
    controller.detachOwner(owner);
    controller.clearResult(owner, failures: [_failure(StateError('same'))]);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(notifications, 1);
  });

  testWidgets('reentrant listener changes notify on the next frame', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final controller = TextAutoWrapController();
    addTearDown(controller.dispose);
    final owner = Object();
    var notifications = 0;
    controller.addListener(() {
      notifications++;
      controller.clearResult(owner, failures: [_failure(StateError('second'))]);
    });
    controller.clearResult(owner, failures: [_failure(StateError('first'))]);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(notifications, 1);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(notifications, 2);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(notifications, 2);
  });

  testWidgets('detached owner without a new commit remains silent', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final controller = TextAutoWrapController();
    addTearDown(controller.dispose);
    final owner = Object();
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.clearResult(owner, failures: [_failure(StateError('first'))]);
    controller.detachOwner(owner);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(notifications, 0);
  });

  for (final fixture in <(String, Object Function(String))>[
    ('StateError', StateError.new),
    ('ArgumentError', (message) => ArgumentError.value(1, 'width', message)),
  ]) {
    testWidgets('${fixture.$1} message changes notify; equivalents do not', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      final controller = TextAutoWrapController();
      addTearDown(controller.dispose);
      final owner = Object();
      var notifications = 0;
      controller.addListener(() => notifications++);
      for (final message in ['first', 'second', 'second']) {
        controller.clearResult(
          owner,
          failures: [_failure(fixture.$2(message))],
        );
        tester.binding.scheduleFrame();
        await tester.pump();
      }
      expect(notifications, 2);
    });
  }

  testWidgets('opaque errors do not invoke arbitrary string conversion', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final controller = TextAutoWrapController();
    addTearDown(controller.dispose);
    final owner = Object();
    var notifications = 0;
    controller.addListener(() => notifications++);
    for (var i = 0; i < 2; i++) {
      controller.clearResult(owner, failures: [_failure(_OpaqueError())]);
      tester.binding.scheduleFrame();
      await tester.pump();
    }
    expect(notifications, 1);
  });

  testWidgets('detachment invalidates pending failure notification', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final controller = TextAutoWrapController();
    addTearDown(controller.dispose);
    final owner = Object();
    final nextOwner = Object();
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.clearResult(owner, failures: [_failure(StateError('first'))]);
    controller.detachOwner(owner);
    controller.clearResult(
      nextOwner,
      failures: [_failure(StateError('second'))],
    );
    expect(notifications, 0);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(notifications, 1);
    expect((controller.failures.single.error as StateError).message, 'second');
  });
}

TextWrapFailure _failure(Object error) => TextWrapFailure(
  stage: TextWrapFailureStage.nativeMeasurement,
  reason: 'invalidRuntimeMeasurement',
  error: error,
  stackTrace: StackTrace.current,
);

class _OpaqueError {
  @override
  String toString() => throw StateError('must not stringify opaque errors');
}

TextWrapResult _result() => TextWrapResult(
  layout: LineBreakLayout(
    sourceText: 'a',
    ranges: [const TextLineRange(0, 1)],
    widths: [10],
    maxWidth: 100,
  ),
  applied: false,
  reason: 'native',
  source: TextWrapSelectionSource.native,
);
