/// Per-isolate resource monitor for load tests (see tool/load/README.md).
///
/// Attaches to a Dart VM service (the target app must be started with
/// --enable-vm-service), samples every isolate's heap statistics on an
/// interval, and:
///
///   1. serves the latest sample as JSON on http://0.0.0.0:<port>/metrics.json
///      — the k6 `isolate_monitor` scenario polls this and feeds the values
///      into k6 Trend metrics, so isolate resources appear in k6's own
///      output and can gate thresholds;
///   2. appends every sample to a JSONL file for offline analysis.
///
/// Usage:
///   dart run bin/isolate_monitor.dart \
///     [--vm ws://127.0.0.1:8181/ws] [--port 9091] \
///     [--interval-ms 1000] [--out samples.jsonl]
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

String _arg(List<String> args, String name, String fallback) {
  final i = args.indexOf(name);
  if (i == -1 || i + 1 >= args.length) return fallback;
  return args[i + 1];
}

Future<void> main(List<String> args) async {
  final vmUri = _arg(args, "--vm", "ws://127.0.0.1:8181/ws");
  final port = int.parse(_arg(args, "--port", "9091"));
  final intervalMs = int.parse(_arg(args, "--interval-ms", "1000"));
  final outPath = _arg(args, "--out", "samples.jsonl");

  final out = File(outPath).openWrite(mode: FileMode.append);
  Map<String, dynamic> latest = {"ts": null, "isolates": []};

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  server.listen((req) {
    req.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(latest));
    req.response.close();
  });
  stderr.writeln("isolate_monitor serving :$port, sampling $vmUri");

  VmService? service;
  while (true) {
    try {
      service ??= await vmServiceConnectUri(vmUri);
      final vm = await service.getVM();

      final isolates = <Map<String, dynamic>>[];
      for (final ref in vm.isolates ?? <IsolateRef>[]) {
        try {
          final mem = await service.getMemoryUsage(ref.id!);
          isolates.add({
            "id": ref.id,
            "name": ref.name,
            "heapUsage": mem.heapUsage,
            "heapCapacity": mem.heapCapacity,
            "externalUsage": mem.externalUsage,
          });
        } on SentinelException {
          // Isolate exited between getVM and getMemoryUsage.
        }
      }

      latest = {
        "ts": DateTime.now().toUtc().toIso8601String(),
        "pid": vm.pid,
        "isolateCount": isolates.length,
        "isolates": isolates,
      };
      out.writeln(jsonEncode(latest));
    } catch (e) {
      stderr.writeln("sample failed ($e); reconnecting");
      service = null;
    }

    await Future<void>.delayed(Duration(milliseconds: intervalMs));
  }
}
