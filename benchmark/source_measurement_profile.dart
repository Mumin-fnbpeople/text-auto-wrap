// Direct compute calls intentionally bypass RenderBox query caches to measure
// the source-query path, and inspect the selected renderer snapshot.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

// Run from a Flutter app with:
// flutter build web --profile --target ../benchmark/source_measurement_profile.dart
// Optional: --dart-define=TAW_PROFILE_FONT_ASSET=assets/PretendardVariable.ttf
import 'dart:convert';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const fontAsset = String.fromEnvironment('TAW_PROFILE_FONT_ASSET');
  if (fontAsset.isNotEmpty) {
    await (FontLoader(
      'TawProfile',
    )..addFont(rootBundle.load(fontAsset))).load();
  }
  final key = GlobalKey();
  const source = TextSpan(
    text: 'abcdef',
    style: TextStyle(
      fontSize: 10,
      fontFamily: 'TawProfile',
      letterSpacing: -0.2,
      height: 1.5,
      fontVariations: [FontVariation('wght', 400)],
      fontFeatures: [FontFeature.disable('liga'), FontFeature.disable('clig')],
    ),
  );
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 200,
          child: _Probe(key: key, source: source),
        ),
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final render =
        key.currentContext!.findRenderObject()! as RenderTextAutoWrap;
    final native = RenderParagraph(source, textDirection: TextDirection.ltr);
    final expected = _queries(native);
    _queries(render); // Warm all parent widths before timing.
    final samples = <double>[];
    var checksum = 0.0;
    for (var sample = 0; sample < 7; sample++) {
      final watch = Stopwatch()..start();
      checksum = _queries(render);
      watch.stop();
      samples.add(watch.elapsedMicroseconds / 1000);
    }
    native.dispose();
    final result = {
      'samplesMs': samples,
      'queriesPerSample': 1200,
      'checksum': checksum,
      'nativeChecksum': expected,
      'applied': render.result?.applied,
      'failures': render.failures.length,
      'fontAsset': fontAsset,
      'failureDetails': render.failures.map((f) => f.error.toString()).toList(),
    };
    print('TAW_PROFILE ${jsonEncode(result)}');
    if (checksum != expected ||
        render.result?.applied != true ||
        render.failures.isNotEmpty) {
      throw StateError(
        'Source profile geometry differs from independent RenderParagraph: $result',
      );
    }
  });
}

double _queries(RenderParagraph render) {
  var checksum = 0.0;
  for (var repeat = 0; repeat < 300; repeat++) {
    final width = [100.0, 80.0, 120.0][repeat % 3];
    final constraints = BoxConstraints(maxWidth: width);
    checksum += render.computeMinIntrinsicHeight(width);
    checksum += render.computeMaxIntrinsicHeight(width);
    final size = render.computeDryLayout(constraints);
    checksum += size.width + size.height;
    checksum += render.computeDryBaseline(constraints, TextBaseline.alphabetic);
  }
  return checksum;
}

class _Probe extends LeafRenderObjectWidget {
  const _Probe({super.key, required this.source});
  final TextSpan source;
  @override
  RenderTextAutoWrap createRenderObject(
    BuildContext context,
  ) => RenderTextAutoWrap(
    sourceText: source,
    textDirection: TextDirection.ltr,
    model: PhraseModel(
      levels: [
        PhraseModelLevel(name: 'cut', predictor: const _Offsets(), penalty: 0),
      ],
      fallbackPenalty: 1,
      boundaryMode: BoundaryMode.characters,
    ),
    strategy: const LineBreakStrategy(calculator: _Cut(), selector: _Select()),
  );
}

class _Offsets implements BoundaryPredictor {
  const _Offsets();
  @override
  List<int> predict(String text) => [3];
}

class _Cut implements LayoutCalculator {
  const _Cut();
  @override
  LayoutCalculationResult calculate({
    required String text,
    required List<BreakCandidate> candidates,
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? baseline,
  }) => LayoutCalculationSuccess([
    LineBreakLayoutCandidate(
      sourceText: text,
      selectedCandidates: [candidates.singleWhere((c) => c.offset == 3)],
    ).measure(maxWidth: maxWidth, measureRange: measureRange),
  ]);
}

class _Select implements LayoutSelector {
  const _Select();
  @override
  LayoutSelectionDecision select(LayoutSelectionContext context) =>
      const LayoutSelectionDecision.calculated(0);
}
