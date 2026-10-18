import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  test('existing limit enum and invalid-input switches remain exhaustive', () {
    expect(_describeLimit(LayoutCalculationLimitKind.candidates), 'candidates');
    expect(_describeLimit(LayoutCalculationLimitKind.states), 'states');
    for (final exception in <TextWrapException>[
      const InvalidBoundaryException('boundary'),
      const InvalidModelConfigurationException('model'),
      const TextRangeMeasurementException('range'),
      const UnsupportedSpanTransformationException('span'),
    ]) {
      expect(_describeInputFailure(exception), exception.message);
    }
  });

  test('input resource exception preserves its independent typed contract', () {
    const error = TextWrapInputLimitException('resource limit');
    expect(error, isA<Exception>());
    expect(error, isNot(isA<TextWrapException>()));
    expect(error.message, 'resource limit');
    expect(error.toString(), 'TextWrapInputLimitException: resource limit');
  });
}

String _describeLimit(LayoutCalculationLimitKind kind) => switch (kind) {
  LayoutCalculationLimitKind.candidates => 'candidates',
  LayoutCalculationLimitKind.states => 'states',
};

String _describeInputFailure(TextWrapException exception) =>
    switch (exception) {
      InvalidBoundaryException(:final message) => message,
      InvalidModelConfigurationException(:final message) => message,
      TextRangeMeasurementException(:final message) => message,
      UnsupportedSpanTransformationException(:final message) => message,
    };
