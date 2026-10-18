// Explicit opt-in validation; not part of the default synthetic-font suite.
// python3 tool/serve_test_font.py /path/to/PretendardVariable.ttf
// flutter test test/real_font_review.dart --platform chrome
import 'dart:js_interop';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import 'support/flutter_wrap.dart';
import 'support/real_font_environment.dart';

const _fontUrl = String.fromEnvironment(
  'TAW_FONT_URL',
  defaultValue: 'http://127.0.0.1:8768/font.ttf',
);

void main() {
  testWidgets('real font preserves twelve negative-spacing pixel fixtures', (
    tester,
  ) async {
    final restore = enableRealFontLoading();
    addTearDown(restore);
    await _loadFont(tester);
    for (final source in [
      '1111\n\u00ad\n3333',
      '가\u00ad나',
      '\u00ad\u00ad\u00ad',
      'A\u200dB',
    ]) {
      for (final spacing in [-0.2, -1.0, -8.0]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                for (final actual in [true, false])
                  RepaintBoundary(
                    key: ValueKey(actual),
                    child: ColoredBox(
                      color: Colors.white,
                      child: SizedBox(
                        width: 240,
                        height: 120,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: actual
                                ? TextAutoWrap(
                                    source,
                                    style: _style(spacing),
                                    model: offsetModel([]),
                                    strategy: offsetStrategy([]),
                                  )
                                : Text(source, style: _style(spacing)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(wrapRender(tester).failures, isEmpty);
        expect(await _pixels(tester, true), await _pixels(tester, false));
      }
    }
  });

  testWidgets('real font selection copy semantics survive repeated resizing', (
    tester,
  ) async {
    final restore = enableRealFontLoading();
    addTearDown(restore);
    await _loadFont(tester);
    final semantics = tester.ensureSemantics();
    final width = ValueNotifier<double>(300);
    addTearDown(width.dispose);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    SelectedContent? selection;
    try {
      const source = '매출 12,345원 안내(필독)';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionArea(
              onSelectionChanged: (value) => selection = value,
              child: ValueListenableBuilder<double>(
                valueListenable: width,
                builder: (_, value, _) => wrapHost(
                  TextAutoWrap(
                    source,
                    style: _style(-0.2),
                    model: offsetModel([3]),
                    strategy: offsetStrategy([3]),
                    textScaler: TextScaler.linear(1.5),
                  ),
                  width: value,
                ),
              ),
            ),
          ),
        ),
      );
      final render = wrapRender(tester);
      expect(render.result!.applied, isTrue);
      const expected = '매출 \n12,345원 안내(필독)';
      expect(render.effectiveText.toPlainText(), expected);
      expect(find.bySemanticsLabel(expected), findsOneWidget);
      for (final value in [300.0, 280.0, 320.0, 300.0]) {
        width.value = value;
        await tester.pump();
        expect(wrapRender(tester), same(render));
        expect(render.failures, isEmpty);
        final region = tester.state<SelectableRegionState>(
          find.byType(SelectableRegion),
        );
        region.selectAll();
        await tester.pump();
        expect(selection!.plainText, expected);
        // Exercise the platform copy payload without depending on a toolbar UI.
        // ignore: deprecated_member_use
        region.copySelection(SelectionChangedCause.toolbar);
        await tester.pump();
        expect(copied, expected);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      semantics.dispose();
    }
    expect(tester.takeException(), isNull);
  });
}

TextStyle _style(double spacing) => TextStyle(
  fontFamily: 'TawRealFont',
  fontSize: 16,
  height: 1.5,
  letterSpacing: spacing,
  color: Colors.black,
  fontVariations: const [ui.FontVariation('wght', 400)],
  fontFeatures: const [
    ui.FontFeature.disable('liga'),
    ui.FontFeature.disable('clig'),
  ],
);

Future<void> _loadFont(WidgetTester tester) async {
  await tester.runAsync(() async {
    final response = await _fetch(_fontUrl).toDart;
    final bytes = ByteData.view((await response.arrayBuffer().toDart).toDart);
    await (FontLoader('TawRealFont')..addFont(Future.value(bytes))).load();
    await waitForFontRegistrationFrame();
  });
}

Future<Uint8List> _pixels(WidgetTester tester, bool actual) async =>
    (await tester.runAsync(() async {
      final render = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(ValueKey(actual)),
      );
      final image = await render.toImage();
      try {
        return (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;

@JS('fetch')
external JSPromise<_Response> _fetch(String url);
extension type _Response(JSObject _) implements JSObject {
  external JSPromise<JSArrayBuffer> arrayBuffer();
}
