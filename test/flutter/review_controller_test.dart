import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  testWidgets(
    'success failure success in one frame publishes only the final snapshot',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final controller = TextAutoWrapController();
      addTearDown(controller.dispose);
      final owner = Object();
      final snapshots = <(String?, int)>[];
      controller.addListener(
        () => snapshots.add((
          controller.result?.sourceText,
          controller.failures.length,
        )),
      );
      controller.commitResult(owner, _result('a'));
      controller.clearResult(owner, failures: [_failure()]);
      controller.commitResult(owner, _result('b'));
      expect(controller.result!.sourceText, 'b');
      expect(snapshots, isEmpty);
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(snapshots, [('b', 0)]);
      controller.clearResult(owner, failures: [_failure()]);
      controller.clearResult(owner, failures: [_failure()]);
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(snapshots, [('b', 0), (null, 1)]);
      controller.clearResult(owner, failures: [_failure()]);
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(snapshots, hasLength(2));
    },
  );

  testWidgets(
    'shared controller uses last commit and ignores a stale owner detach',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final controller = TextAutoWrapController();
      addTearDown(controller.dispose);
      final first = Object(), second = Object();
      final observed = <String>[];
      controller.addListener(() => observed.add(controller.result!.sourceText));
      controller.commitResult(first, _result('a'));
      controller.commitResult(second, _result('b'));
      controller.detachOwner(first);
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(observed, ['b']);
      controller.commitResult(first, _result('c'));
      controller.detachOwner(second);
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(observed, ['b', 'c']);
    },
  );
}

TextWrapResult _result(String source) => TextWrapResult(
  layout: LineBreakLayout(
    sourceText: source,
    ranges: [TextLineRange(0, source.length)],
    widths: [10],
    maxWidth: 100,
  ),
  applied: false,
  reason: 'native',
  source: TextWrapSelectionSource.native,
);
TextWrapFailure _failure() => TextWrapFailure(
  stage: TextWrapFailureStage.nativeMeasurement,
  reason: 'invalidRuntimeMeasurement',
  error: StateError('same'),
  stackTrace: StackTrace.current,
);
