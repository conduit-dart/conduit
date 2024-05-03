import 'dart:io';
import 'dart:mirrors';

import 'package:conduit_config/src/configuration.dart';
import 'package:conduit_config/src/runtime.dart';
import 'package:conduit_runtime/runtime.dart';

class ConfigurationCompiler extends Compiler {
  @override
  Map<String, Object> compile(MirrorContext context) {
    return Map.fromEntries(
      context.getSubclassesOf(Configuration).map((c) {
        return MapEntry(
          MirrorSystem.getName(c.simpleName),
          ConfigurationRuntimeImpl(c),
        );
      }),
    );
  }

  @override
  void deflectPackage(Directory destinationDirectory) {
    final libFile = File.fromUri(
      destinationDirectory.uri.resolve("lib/").resolve("conduit_config.dart"),
    );
    final contents = libFile.readAsStringSync();
    libFile.writeAsStringSync(
      contents.replaceFirst(
          "export 'package:conduit_config/src/compiler.dart';", ""),
    );
  }
}
