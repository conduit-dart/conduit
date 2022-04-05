import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:conduit_isolate_exec/src/executable.dart';
import 'package:conduit_isolate_exec/src/source_generator.dart';

class IsolateExecutor<U> {
  IsolateExecutor(
    this.generator, {
    this.packageConfigURI,
    this.message = const {},
  });

  final SourceGenerator generator;
  final Map<String, dynamic> message;
  final Uri? packageConfigURI;
  final Completer completer = Completer();

  Stream<dynamic> get events => _eventListener.stream;

  Stream<String> get console => _logListener.stream;

  final StreamController<String> _logListener = StreamController<String>();
  final StreamController<dynamic> _eventListener = StreamController<dynamic>();

  Future<U> execute() async {
    if (packageConfigURI != null &&
        !File.fromUri(packageConfigURI!).existsSync()) {
      throw StateError(
        "Package file '$packageConfigURI' not found. Run 'pub get' and retry.",
      );
    }

    final scriptSource = Uri.encodeComponent(await generator.scriptSource);

    final onErrorPort = ReceivePort()
      ..listen((err) async {
        if (err is List) {
          final stack =
              StackTrace.fromString(err.last.replaceAll(scriptSource, ""));

          completer.completeError(StateError(err.first), stack);
        } else {
          completer.completeError(err);
        }
      });

    final controlPort = ReceivePort()
      ..listen((results) {
        if (results is Map && results.length == 1) {
          if (results.containsKey("_result")) {
            completer.complete(results['_result']);
            return;
          } else if (results.containsKey("_line_")) {
            _logListener.add(results["_line_"]);
            return;
          }
        }
        _eventListener.add(results);
      });
    try {
      message["_sendPort"] = controlPort.sendPort;

      final dataUri = Uri.parse(
        "data:application/dart;charset=utf-8,$scriptSource",
      );
      if (packageConfigURI != null) {
        await Isolate.spawnUri(
          dataUri,
          [],
          message,
          onError: onErrorPort.sendPort,
          packageConfig: packageConfigURI,
        );
      } else {
        await Isolate.spawnUri(
          dataUri,
          [],
          message,
          onError: onErrorPort.sendPort,
          automaticPackageResolution: true,
        );
      }
      return await completer.future;
    } finally {
      onErrorPort.close();
      controlPort.close();
      _eventListener.close();
      _logListener.close();
    }
  }

  static Future<T> run<T>(
    Executable<T> executable, {
    List<String> imports = const [],
    Uri? packageConfigURI,
    String? additionalContents,
    List<Type> additionalTypes = const [],
    void Function(dynamic event)? eventHandler,
    void Function(String line)? logHandler,
  }) async {
    final source = SourceGenerator(
      executable.runtimeType,
      imports: imports,
      additionalContents: additionalContents,
      additionalTypes: additionalTypes,
    );

    final executor = IsolateExecutor<T>(
      source,
      packageConfigURI: packageConfigURI,
      message: executable.message,
    );

    if (eventHandler != null) {
      executor.events.listen(eventHandler);
    }

    if (logHandler != null) {
      executor.console.listen(logHandler);
    }

    return executor.execute();
  }
}
