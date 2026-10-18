import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import '../test/support/layout_benchmark_harness.dart';

export '../test/support/layout_benchmark_harness.dart' show BenchmarkHarness;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    BenchmarkHarness(
      onComplete: (rows) {
        for (final row in rows) {
          print(jsonEncode(row));
        }
        exit(0);
      },
    ),
  );
}
