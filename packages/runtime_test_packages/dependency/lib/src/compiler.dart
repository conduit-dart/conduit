import 'dart:io';
import 'dart:mirrors';

import 'package:conduit_runtime/runtime.dart';

import '../dependency.dart';

class DependencyCompiler extends Compiler {
  @override
  Map<String, dynamic> compile(MirrorContext context) {
    return Map.fromEntries(context.getSubclassesOf(Consumer).map((c) {
      return MapEntry(
        MirrorSystem.getName(c.simpleName),
        ConsumerRuntimeImpl(),
      );
    }))
      ..addAll({"Consumer": ConsumerRuntimeImpl()});
  }

  @override
  void deflectPackage(Directory destinationDirectory) {
    final libFile = File.fromUri(
      destinationDirectory.uri.resolve("lib/").resolve("dependency.dart"),
    );
    var contents = libFile.readAsStringSync();
    contents = contents.replaceFirst("export 'src/compiler.dart';", "");
    libFile.writeAsStringSync(contents);
  }
}

class ConsumerRuntimeImpl extends ConsumerRuntime implements SourceCompiler {
  @override
  String get message => "mirrored";

  @override
  Future<String> compile(BuildContext ctx) async => """
import 'package:dependency/dependency.dart';

final instance = ConsumerRuntimeImpl();

class ConsumerRuntimeImpl extends ConsumerRuntime {
  @override
  String get message => "generated";
}
  """;
}
