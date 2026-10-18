import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/span_codec.dart';

void main() {
  test('partitioned rich-span slices agree with independent native spans', () {
    // All 5^4 sequences. Token endpoints are known independently of the codec;
    // text leaves deliberately split combining graphemes across span boundaries.
    const values = ['a', 'e\u0301', '😀', '\uFFFC', '\uFFFC'];
    const widget = WidgetSpan(child: SizedBox(width: 7, height: 9));
    const dimensions = PlaceholderDimensions(
      size: Size(7, 9),
      alignment: PlaceholderAlignment.bottom,
    );
    const style = TextStyle(fontSize: 10);
    for (var caseNumber = 0; caseNumber < 625; caseNumber++) {
      var code = caseNumber;
      final kinds = <int>[];
      final endpoints = [0];
      final sourceBuffer = StringBuffer();
      final sourceChildren = <InlineSpan>[];
      for (var i = 0; i < 4; i++) {
        final kind = code % 5;
        code ~/= 5;
        kinds.add(kind);
        sourceBuffer.write(values[kind]);
        endpoints.add(sourceBuffer.length);
        if (kind == 3) {
          sourceChildren.add(widget);
        } else {
          final value = values[kind];
          final split = kind == 2 ? value.length : 1;
          sourceChildren.add(
            TextSpan(
              text: value.substring(0, split),
              semanticsLabel: 'token $i',
              locale: const Locale('ko'),
              spellOut: true,
              children: [
                TextSpan(children: [TextSpan(text: value.substring(split))]),
              ],
            ),
          );
        }
      }
      final source = TextSpan(style: style, children: sourceChildren);
      final text = sourceBuffer.toString();
      final encoded = encodeInlineSpan(source);
      expect(encoded.text, text);
      expect(encoded.placeholderSpans, [
        for (final kind in kinds)
          if (kind == 3) same(widget),
      ]);
      for (var first = 0; first < 4; first++) {
        for (var last = first + 1; last <= 4; last++) {
          final start = endpoints[first];
          final end = endpoints[last];
          final reason =
              'case=$caseNumber UTF16=${text.codeUnits} range=[$start,$end)';
          final slice = sliceInlineSpanForMeasurement(encoded, start, end);
          expect(
            slice.span.toPlainText(includeSemanticsLabels: false),
            text.substring(start, end),
            reason: reason,
          );
          var occurrence = 0;
          final expectedIndices = <int>[];
          for (var i = 0; i < 4; i++) {
            if (kinds[i] == 3) {
              if (i >= first && i < last) expectedIndices.add(occurrence);
              occurrence++;
            }
          }
          expect(slice.placeholderIndices, expectedIndices, reason: reason);
          // Build an independent flat span directly from the selected tokens.
          final expected = TextSpan(
            style: style,
            children: [
              for (var i = first; i < last; i++)
                if (kinds[i] == 3) widget else TextSpan(text: values[kinds[i]]),
            ],
          );
          final actualPainter = TextPainter(
            text: slice.span,
            textDirection: TextDirection.ltr,
          );
          final expectedPainter = TextPainter(
            text: expected,
            textDirection: TextDirection.ltr,
          );
          try {
            final selectedDimensions = [
              for (final _ in expectedIndices) dimensions,
            ];
            actualPainter
              ..setPlaceholderDimensions(selectedDimensions)
              ..layout();
            expectedPainter
              ..setPlaceholderDimensions(selectedDimensions)
              ..layout();
            expect(actualPainter.size, expectedPainter.size, reason: reason);
          } finally {
            actualPainter.dispose();
            expectedPainter.dispose();
          }
        }
      }
      final allCuts = endpoints.sublist(1, 4);
      final rewritten = insertLineBreaks(encoded, allCuts);
      expect(
        rewritten.toPlainText(includeSemanticsLabels: false),
        [for (final kind in kinds) values[kind]].join('\n'),
        reason: 'case=$caseNumber UTF16=${text.codeUnits}',
      );
      expect(source.toPlainText(includeSemanticsLabels: false), text);
      expect(
        encoded.placeholderSpans.length,
        kinds.where((v) => v == 3).length,
      );
    }
  });
}
