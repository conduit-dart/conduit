// ignore: unnecessary_const
@Tags(["cli"])
import 'package:fs_test_agent/dart_project_agent.dart';
import 'package:fs_test_agent/working_directory_agent.dart';
import 'package:test/test.dart';

import '../not_tests/cli_helpers.dart';

void main() {
  late CLIClient cli;

  // This group handles checking the tool itself,
  // not the behavior of creating the appropriate migration file given schemas
  setUp(() async {
    cli = await CLIClient(
      WorkingDirectoryAgent(DartProjectAgent.projectsDirectory),
    ).createTestProject();
    await cli.agent.getDependencies(offline: true);
    cli.agent.addOrReplaceFile("lib/application_test.dart", """
import 'package:conduit/conduit.dart';

class TestObject extends ManagedObject<_TestObject> {}

class _TestObject {
  @primaryKey
  int? id;

  String? foo;
}
      """);
  });

  tearDown(DartProjectAgent.tearDownAll);

  test("Ensure migration directory will get created on generation", () async {
    var res = await cli.run("db", ["schema"]);
    expect(res, 0);
    expect(cli.output, contains("_TestObject"));
  });
}
