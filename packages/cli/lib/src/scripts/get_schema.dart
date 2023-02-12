import 'dart:async';

import 'package:conduit/src/command.dart';
import 'package:conduit/src/mixins/project.dart';
import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_isolate_exec/conduit_isolate_exec.dart';

class GetSchemaExecutable extends Executable<Map<String, dynamic>> {
  GetSchemaExecutable(super.message);

  @override
  Future<Map<String, dynamic>> execute() async {
    try {
      final dataModel = ManagedDataModel.fromCurrentMirrorSystem();
      final schema = Schema.fromDataModel(dataModel);
      return schema.asMap();
    } on SchemaException catch (e) {
      return {"error": e.message};
    } on ManagedDataModelError catch (e) {
      return {"error": e.message};
    }
  }

  static List<String> importsForPackage(String? packageName) => [
        "package:conduit_core/conduit_core.dart",
        "package:$packageName/$packageName.dart",
        "package:conduit_runtime/runtime.dart"
      ];
}

Future<Schema> getProjectSchema(CLIProject project) async {
  final response = await IsolateExecutor.run(
    GetSchemaExecutable({}),
    imports: GetSchemaExecutable.importsForPackage(project.libraryName),
    packageConfigURI: project.packageConfigUri,
    logHandler: project.displayProgress,
  );

  if (response.containsKey("error")) {
    throw CLIException(response["error"] as String?);
  }

  return Schema.fromMap(response);
}
