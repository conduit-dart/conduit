// Microbenchmark for `dart:convert` JSON encode/decode at request-payload
// scales. Conduit doesn't ship its own JSON codec — it uses
// `dart:convert` directly — so this baseline measures the floor under
// every JSON-handling request the framework serves.
//
// Two payload shapes:
//   - 1000-element list of small flat maps (typical "list endpoint" body)
//   - 1 deep map with 20 keys (typical "single resource" body)
//
// Run: `dart run bench/json_codec_bench.dart`
library;

import 'dart:convert';

import 'package:benchmark_harness/benchmark_harness.dart';

class _EncodeListBench extends BenchmarkBase {
  _EncodeListBench(this.payload)
      : super('json.encode List[${(payload as List).length} maps]');
  final Object payload;

  @override
  void run() {
    json.encode(payload);
  }
}

class _DecodeListBench extends BenchmarkBase {
  _DecodeListBench(this.encoded) : super('json.decode List[1000 maps]');
  final String encoded;

  @override
  void run() {
    json.decode(encoded);
  }
}

class _EncodeMapBench extends BenchmarkBase {
  _EncodeMapBench(this.payload) : super('json.encode Map[20 keys]');
  final Object payload;

  @override
  void run() {
    json.encode(payload);
  }
}

class _DecodeMapBench extends BenchmarkBase {
  _DecodeMapBench(this.encoded) : super('json.decode Map[20 keys]');
  final String encoded;

  @override
  void run() {
    json.decode(encoded);
  }
}

void main() {
  final listPayload = List<Map<String, dynamic>>.generate(
    1000,
    (i) => {
      'id': i,
      'name': 'item-$i',
      'active': i.isEven,
      'score': i * 0.5,
    },
  );
  final encodedList = json.encode(listPayload);

  final mapPayload = <String, dynamic>{
    for (var i = 0; i < 20; i++) 'k$i': i.isEven ? i : 'v$i',
  };
  final encodedMap = json.encode(mapPayload);

  _EncodeListBench(listPayload).report();
  _DecodeListBench(encodedList).report();
  _EncodeMapBench(mapPayload).report();
  _DecodeMapBench(encodedMap).report();
}
