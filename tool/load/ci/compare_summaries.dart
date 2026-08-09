/// Compares two k6 `--summary-export` JSON files from the load-smoke lane
/// (ci/load-smoke.sh) and prints the endpoints' latency percentiles side by
/// side. Informational by design: hard pass/fail lives in the k6 thresholds
/// inside each run, so shared-runner noise can't flake the build here.
///
///   dart tool/load/ci/compare_summaries.dart summary-pool1.json summary-pool8.json
library;

import 'dart:convert';
import 'dart:io';

const trackedMetrics = [
  "http_req_duration{endpoint:slow}",
  "http_req_duration{endpoint:tx}",
  "http_req_duration{endpoint:items_read}",
  "dart_isolate_heap_bytes",
];

Map<String, dynamic> _metrics(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  return (decoded as Map<String, dynamic>)["metrics"] as Map<String, dynamic>;
}

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln("usage: compare_summaries.dart <baseline.json> <pooled.json>");
    exit(64);
  }

  final baseline = _metrics(args[0]);
  final pooled = _metrics(args[1]);

  print("");
  print("metric".padRight(45) +
      "pool=1 p95".padLeft(14) +
      "pool=8 p95".padLeft(14) +
      "  delta");
  print("-" * 85);

  double? p95(Map<String, dynamic> m, String key) {
    final entry = m[key];
    if (entry is! Map<String, dynamic>) return null;
    final v = entry["p(95)"] ?? entry["max"];
    return v is num ? v.toDouble() : null;
  }

  var slowRegressed = false;
  var slowMissing = true;
  for (final key in trackedMetrics) {
    final a = p95(baseline, key);
    final b = p95(pooled, key);
    if (a == null || b == null) {
      print("${key.padRight(45)}${"-".padLeft(14)}${"-".padLeft(14)}");
      continue;
    }
    if (key.contains("endpoint:slow")) {
      slowMissing = false;
    }
    final delta = a == 0 ? 0.0 : ((b - a) / a) * 100.0;
    print(key.padRight(45) +
        a.toStringAsFixed(1).padLeft(14) +
        b.toStringAsFixed(1).padLeft(14) +
        "  ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%");
    if (key.contains("endpoint:slow") && b >= a) {
      slowRegressed = true;
    }
  }

  print("");
  if (slowMissing) {
    print("WARN: slow-query submetric absent from one or both summaries — "
        "no pooling verdict. (k6 only exports submetrics that have "
        "thresholds; check the script's thresholds block.)");
  } else if (slowRegressed) {
    print("WARN: pooled slow-query p95 is not better than single-connection "
        "baseline. Expected pooling to raise slow-query capacity — check "
        "target logs and heap samples before trusting this run.");
  } else {
    print("OK: pooled slow-query p95 improved over the single-connection "
        "baseline.");
  }
}
