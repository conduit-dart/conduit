// Microbenchmark for `slow_coerce.cast<T>` over the type variants the
// runtime hits hottest in real apps: `List<int>`, `List<Map<String,
// dynamic>>`, and `Map<String, dynamic>`. Captures a baseline so PRs
// touching the cast path (e.g. PR #259's AOT specialization) have
// numbers to compare against.
//
// Run: `dart run bench/coerce_bench.dart`
//
// This is a baseline harness — not a regression gate. Add CI assertions
// in a follow-up PR once the noise floor is measured across a few
// hosts.
library;

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:conduit_runtime/slow_coerce.dart' as coerce;

class _CastListIntBench extends BenchmarkBase {
  _CastListIntBench(this.fixture) : super('cast<List<int>> (n=${fixture.length})');
  final List<dynamic> fixture;

  @override
  void run() {
    coerce.cast<List<int>>(fixture);
  }
}

class _CastListMapBench extends BenchmarkBase {
  _CastListMapBench(this.fixture)
      : super('cast<List<Map<String, dynamic>>> (n=${fixture.length})');
  final List<dynamic> fixture;

  @override
  void run() {
    coerce.cast<List<Map<String, dynamic>>>(fixture);
  }
}

class _CastMapStringDynamicBench extends BenchmarkBase {
  _CastMapStringDynamicBench(this.fixture)
      : super('cast<Map<String, dynamic>> (keys=${fixture.length})');
  final Map<String, dynamic> fixture;

  @override
  void run() {
    coerce.cast<Map<String, dynamic>>(fixture);
  }
}

void main() {
  // Realistic small-payload sizes: a 100-element int list, a 50-row
  // table-shaped list, and a 20-key flat map. Larger sizes scale linearly
  // through `from(...)` and don't reveal anything new.
  final intList = List<dynamic>.generate(100, (i) => i);
  final mapList = List<dynamic>.generate(
    50,
    (i) => <String, dynamic>{'id': i, 'name': 'row-$i', 'active': i.isEven},
  );
  final flatMap = <String, dynamic>{
    for (var i = 0; i < 20; i++) 'k$i': i.isEven ? i : 'v$i',
  };

  _CastListIntBench(intList).report();
  _CastListMapBench(mapList).report();
  _CastMapStringDynamicBench(flatMap).report();
}
