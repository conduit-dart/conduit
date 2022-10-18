import 'dart:io';

import 'package:conduit_runtime/src/analyzer.dart';
import 'package:test/test.dart';
import 'package:fs_test_agent/dart_project_agent.dart';

void main() {
  test("ProjectAnalyzer can find a specific class declaration in project",
      () async {
    final terminal = DartProjectAgent.existing(Directory.current.uri
        .resolve("../")
        .resolve("runtime_test_packages/")
        .resolve("application/"));
    await terminal.getDependencies();

    final path = terminal.workingDirectory.absolute.uri;
    final p = CodeAnalyzer(path);
    final klass = p.getClassFromFile("ConsumerSubclass",
        terminal.libraryDirectory.absolute.uri.resolve("application.dart"));
    expect(klass, isNotNull);
    expect(klass!.name.value(), "ConsumerSubclass");
    expect(klass.extendsClause!.superclass.name.name, "Consumer");
  });
}
