import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

/// Drives the renderer through cold and warm layouts for each rich scenario.
///
/// The harness intentionally reports observations only. Shared machines vary
/// too much for an absolute duration to be a correctness threshold.
class BenchmarkHarness extends StatefulWidget {
  const BenchmarkHarness({
    required this.onComplete,
    this.iterations = 20,
    super.key,
  }) : assert(iterations > 0);

  final int iterations;
  final ValueChanged<List<Map<String, Object?>>> onComplete;

  @override
  State<BenchmarkHarness> createState() => _BenchmarkHarnessState();
}

class _BenchmarkHarnessState extends State<BenchmarkHarness> {
  late final List<_BenchmarkScenario> _scenarios = [
    _makeScenario('short-20', TextSpan(text: 'word ' * 4)),
    _makeScenario('medium-100', TextSpan(text: 'word ' * 20)),
    _makeScenario('long-1000', TextSpan(text: 'word ' * 200)),
    _makeScenario('nested-100-spans', _nestedSpans(100), richSpanCount: 100),
    _makeScenario(
      'placeholders-20',
      _placeholderSpans(20),
      placeholderCount: 20,
    ),
    _makeScenario(
      'worst-case-boundaries',
      TextSpan(text: 'a' * 1000),
      worstCase: true,
    ),
    for (final (name, parent, span, scale) in [
      (
        'intrinsic-timeline-12',
        _Parent.timeline,
        TextSpan(text: 'word ' * 20),
        1.0,
      ),
      ('intrinsic-table-12', _Parent.table, TextSpan(text: 'word ' * 20), 1.0),
      ('survey-grid-12', _Parent.grid, TextSpan(text: 'word ' * 20), 1.0),
      ('rich-search-list-12', _Parent.list, _nestedSpans(20), 1.0),
      ('scaled-widget-spans-12', _Parent.list, _placeholderSpans(2), 1.5),
      (
        'equal-height-three-passes-12',
        _Parent.threePasses,
        TextSpan(text: 'word ' * 20),
        1.0,
      ),
    ])
      _makeScenario(
        name,
        span,
        parent: parent,
        itemCount: 12,
        textScale: scale,
        richSpanCount: name == 'rich-search-list-12' ? 20 : 1,
        placeholderCount: scale == 1.5 ? 2 : 0,
      ),
  ];
  final _rows = <Map<String, Object?>>[];
  var _scenarioIndex = 0;
  var _warm = false;
  var _iteration = 0;
  var _complete = false;
  GlobalKey _renderKey = GlobalKey();
  late List<TextAutoWrapController> _controllers;
  final Stopwatch _stopwatch = Stopwatch();

  _BenchmarkScenario get _scenario => _scenarios[_scenarioIndex];

  @override
  void initState() {
    super.initState();
    _controllers = _newControllers();
    _stopwatch.start();
    WidgetsBinding.instance.addPostFrameCallback(_afterFrame);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: DefaultTextStyle(
      style: const TextStyle(fontSize: 10, color: Color(0xff000000)),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: _scenario.parent == _Parent.single ? 120 : 360,
          child: KeyedSubtree(
            key: _renderKey,
            child: SingleChildScrollView(child: _buildParent()),
          ),
        ),
      ),
    ),
  );

  List<TextAutoWrapController> _newControllers() => [
    for (var index = 0; index < _scenario.itemCount; index++)
      TextAutoWrapController(),
  ];

  Widget _text(int index) => TextAutoWrap.rich(
    key: ValueKey(index),
    _scenario.parent == _Parent.table && index.isEven
        ? TextSpan(text: 'Label $index')
        : _sourceForIteration(),
    model: _scenario.model,
    strategy: _scenario.strategy,
    controller: _controllers[index],
    textScaler: TextScaler.linear(_scenario.textScale),
    // Exercise range/plan reuse on the last warm pass as well as complete
    // selection reuse. Grid choices keep their real two-line limit.
    maxLines: _scenario.parent == _Parent.grid
        ? 2
        : _warm && _iteration == widget.iterations - 1
        ? 1000
        : null,
  );

  Widget _buildParent() {
    final children = [for (var i = 0; i < _scenario.itemCount; i++) _text(i)];
    return switch (_scenario.parent) {
      _Parent.single => children.single,
      _Parent.list => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
      _Parent.timeline => Column(
        children: [
          for (final child in children)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(width: 20),
                  Expanded(child: child),
                ],
              ),
            ),
        ],
      ),
      _Parent.table => Table(
        columnWidths: const {0: IntrinsicColumnWidth()},
        children: [
          for (var i = 0; i < children.length; i += 2)
            TableRow(children: [children[i], children[i + 1]]),
        ],
      ),
      _Parent.grid => Column(
        children: [
          for (var i = 0; i < children.length; i += 3)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = i; j < i + 3; j++)
                    Expanded(
                      child: Column(
                        children: [const SizedBox(height: 40), children[j]],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
      _Parent.threePasses => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in children) _ThreePassLayout(child: child),
        ],
      ),
    };
  }

  InlineSpan _sourceForIteration() {
    if (_warm) return _scenario.span;
    return TextSpan(
      semanticsIdentifier: '${_scenario.name}:$_iteration',
      children: [_scenario.span],
    );
  }

  void _afterFrame(Duration _) {
    if (_complete) return;
    for (final controller in _controllers) {
      if (controller.failures.isNotEmpty) {
        throw StateError(
          'Benchmark renderer failed: '
          '${controller.failures.map((failure) => failure.reason).join(', ')}',
        );
      }
    }
    final results = [for (final controller in _controllers) controller.result];
    if (results.any((result) => result == null)) {
      WidgetsBinding.instance.scheduleFrame();
      WidgetsBinding.instance.addPostFrameCallback(_afterFrame);
      return;
    }
    if (_iteration + 1 < widget.iterations) {
      setState(() => _iteration++);
      WidgetsBinding.instance.addPostFrameCallback(_afterFrame);
      return;
    }

    _stopwatch.stop();
    final diagnostics = [for (final result in results) result!.diagnostics!];
    final caches = [for (final diagnostic in diagnostics) diagnostic.cache];
    _rows.add({
      'scenario': _scenario.name,
      'cache': _warm ? 'warm' : 'cold',
      'iterations': widget.iterations,
      'candidateCount': diagnostics.fold<int>(
        0,
        (sum, value) => sum + value.candidates.length,
      ),
      'measurements': caches.fold<int>(
        0,
        (sum, cache) => sum + cache.measurementRuns,
      ),
      'cacheHits': caches.fold<int>(
        0,
        (sum, cache) =>
            sum +
            cache.selectionCacheHits +
            cache.planHits +
            cache.measurementHits,
      ),
      'elapsedMicroseconds': _stopwatch.elapsedMicroseconds,
      'fallback': results.first!.reason,
      'richSpanCount': _scenario.richSpanCount,
      'placeholderCount': _scenario.placeholderCount,
      'rendererCount': _scenario.itemCount,
      'textScale': _scenario.textScale,
    });

    if (_warm) {
      _scenarioIndex++;
      _warm = false;
    } else {
      _warm = true;
    }
    if (_scenarioIndex == _scenarios.length) {
      _complete = true;
      widget.onComplete(List.unmodifiable(_rows));
      return;
    }
    setState(() {
      _iteration = 0;
      // Each row begins with a fresh renderer; frames within the row are the
      // cold or warm sequence being measured.
      _renderKey = GlobalKey();
      for (final controller in _controllers) {
        controller.dispose();
      }
      _controllers = _newControllers();
      _stopwatch
        ..reset()
        ..start();
    });
    WidgetsBinding.instance.addPostFrameCallback(_afterFrame);
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }
}

_BenchmarkScenario _makeScenario(
  String name,
  InlineSpan span, {
  int richSpanCount = 1,
  int placeholderCount = 0,
  bool worstCase = false,
  _Parent parent = _Parent.single,
  int itemCount = 1,
  double textScale = 1,
}) => _BenchmarkScenario(
  name: name,
  span: span,
  richSpanCount: richSpanCount,
  placeholderCount: placeholderCount,
  parent: parent,
  itemCount: itemCount,
  textScale: textScale,
  model: PhraseModel(
    levels: [
      PhraseModelLevel(
        name: 'benchmark-boundaries',
        predictor: _Boundaries(worstCase: worstCase),
        penalty: 0,
      ),
    ],
    fallbackPenalty: 1,
    boundaryMode: BoundaryMode.characters,
  ),
  strategy: LineBreakStrategy(
    calculator: worstCase ? optimalLayouts() : greedy(),
  ),
);

InlineSpan _nestedSpans(int count) {
  InlineSpan span = const TextSpan(text: 'word ');
  for (var index = 1; index < count; index++) {
    span = TextSpan(text: 'word ', children: [span]);
  }
  return span;
}

InlineSpan _placeholderSpans(int count) => TextSpan(
  children: [
    for (var index = 0; index < count; index++) ...[
      const TextSpan(text: 'word '),
      const WidgetSpan(child: SizedBox(width: 12, height: 12)),
    ],
  ],
);

final class _BenchmarkScenario {
  const _BenchmarkScenario({
    required this.name,
    required this.span,
    required this.model,
    required this.strategy,
    required this.richSpanCount,
    required this.placeholderCount,
    required this.parent,
    required this.itemCount,
    required this.textScale,
  });

  final String name;
  final InlineSpan span;
  final PhraseModel model;
  final LineBreakStrategy strategy;
  final int richSpanCount;
  final int placeholderCount;
  final _Parent parent;
  final int itemCount;
  final double textScale;
}

enum _Parent { single, timeline, table, grid, list, threePasses }

// Synthetic equal-height parent: natural layout followed by two minimum-height
// adjustments at the same width, as used by multi-column list rows.
class _ThreePassLayout extends SingleChildRenderObjectWidget {
  const _ThreePassLayout({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderThreePassLayout();
}

class _RenderThreePassLayout extends RenderProxyBox {
  @override
  void performLayout() {
    child!.layout(constraints, parentUsesSize: true);
    final naturalHeight = child!.size.height;
    for (var pass = 1; pass <= 2; pass++) {
      child!.layout(
        constraints.copyWith(minHeight: naturalHeight + pass),
        parentUsesSize: true,
      );
    }
    size = constraints.constrain(child!.size);
  }
}

final class _Boundaries implements BoundaryPredictor {
  const _Boundaries({required this.worstCase});

  final bool worstCase;

  @override
  List<int> predict(String text) => [
    for (
      var offset = worstCase ? 1 : 5;
      offset < text.length;
      offset += worstCase ? 1 : 5
    )
      offset,
  ];
}
