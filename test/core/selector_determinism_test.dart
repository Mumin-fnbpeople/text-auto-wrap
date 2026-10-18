import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  test('near-equal model costs select consistently across candidate order', () {
    final layouts = [_layout(3, 0), _layout(2, 0.75e-9), _layout(1, 1.5e-9)];
    final choices = <String>{};
    for (final order in [
      [0, 1, 2],
      [0, 2, 1],
      [1, 0, 2],
      [1, 2, 0],
      [2, 0, 1],
      [2, 1, 0],
    ]) {
      final supplied = [for (final index in order) layouts[index]];
      final decision = const BalanceStrategy().select(
        LayoutSelectionContext(calculatedLayouts: supplied),
      );
      choices.add(supplied[decision.index!].breakOffsets.join(','));
    }
    expect(choices, {'2'});
  });

  test('near-equal balance uses a common minimum across candidate order', () {
    final layouts = [
      _layout(3, 0, imbalance: 0),
      _layout(2, 0, imbalance: 0.75e-9),
      _layout(1, 0, imbalance: 1.5e-9),
    ];
    for (final order in _orders) {
      final supplied = [for (final index in order) layouts[index]];
      final decision = const BalanceStrategy().select(
        LayoutSelectionContext(calculatedLayouts: supplied),
      );
      expect(supplied[decision.index!].breakOffsets, [2], reason: '$order');
    }
  });

  test('tiny finite costs retain the existing epsilon tie behavior', () {
    final decision = const BalanceStrategy().select(
      LayoutSelectionContext(
        calculatedLayouts: [_layout(3, 0), _layout(1, 1e-320)],
      ),
    );
    expect(decision.index, 1);
    final large = const BalanceStrategy().select(
      LayoutSelectionContext(
        calculatedLayouts: [_layout(3, 0), _layout(1, 1e308)],
      ),
    );
    expect(large.index, 0);
  });

  test('native model improvement retains its absolute epsilon boundary', () {
    for (final (cost, expected) in [
      (2e-9, TextWrapSelectionSource.native),
      (2.5e-9, TextWrapSelectionSource.calculated),
    ]) {
      final decision = const BalanceStrategy().select(
        LayoutSelectionContext(
          nativeLayout: _layout(1, cost),
          calculatedLayouts: [_layout(3, 1.25e-9)],
        ),
      );
      expect(decision.source, expected);
    }
  });
}

const _orders = [
  [0, 1, 2],
  [0, 2, 1],
  [1, 0, 2],
  [1, 2, 0],
  [2, 0, 1],
  [2, 1, 0],
];

LineBreakLayout _layout(int offset, double cost, {double imbalance = 0}) =>
    LineBreakLayout(
      sourceText: 'abcd',
      ranges: [TextLineRange(0, offset), TextLineRange(offset, 4)],
      widths: [1, 1 - imbalance],
      maxWidth: 10,
      selectedCandidates: [
        BreakCandidate(
          offset: offset,
          penalty: cost,
          levelName: 'near-equal',
          consensusCount: 1,
          isFallback: false,
        ),
      ],
    );
