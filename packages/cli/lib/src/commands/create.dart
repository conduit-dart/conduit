import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conduit/src/command.dart';
import 'package:conduit/src/commands/pub.dart';
import 'package:conduit/src/metadata.dart';
import 'package:path/path.dart' as path_lib;
import 'package:path/path.dart';
import 'package:yaml/yaml.dart';

/// Used internally.
class CLITemplateCreator extends CLICommand {
  CLITemplateCreator() {
    registerCommand(CLITemplateList());
  }

  @Option(
    "template",
    abbr: "t",
    help: "Name of the template to use",
    defaultsTo: "default",
  )
  String get templateName => decode("template");

  @Flag(
    "offline",
    negatable: false,
    help: "Will fetch dependencies from a local cache if they exist.",
    defaultsTo: false,
  )
  bool get offline => decode("offline");

  String? get projectName =>
      remainingArguments.isNotEmpty ? remainingArguments.first : null;

  @override
  Future<int> handle() async {
    if (projectName == null) {
      printHelp(parentCommandName: "conduit");
      return 1;
    }

    if (!isSnakeCase(projectName!)) {
      displayError("Invalid project name ($projectName is not snake_case).");
      return 1;
    }

    final destDirectory = destinationDirectoryFromPath(projectName!);
    if (destDirectory.existsSync()) {
      displayError("${destDirectory.path} already exists, stopping.");
      return 1;
    }

    destDirectory.createSync();
    Uri? globalPath = await findGlobalPath();
    if (globalPath != null) {
      Directory conduitLocation = Directory(globalPath.toString());
      try {
        if (!addDependencyOverridesToPackage(destDirectory.path, {
          "conduit_codable": _packageUri(conduitLocation, 'codable'),
          "conduit_common": _packageUri(conduitLocation, 'common'),
          "conduit_common_test": _packageUri(conduitLocation, 'common_test'),
          "conduit_config": _packageUri(conduitLocation, 'config'),
          "conduit_core": _packageUri(conduitLocation, 'core'),
          "conduit_isolate_exec": _packageUri(conduitLocation, 'isolate_exec'),
          "conduit_open_api": _packageUri(conduitLocation, 'open_api'),
          "conduit_password_hash":
              _packageUri(conduitLocation, 'password_hash'),
          "conduit_postgresql": _packageUri(conduitLocation, 'postgresql'),
          "conduit_runtime": _packageUri(conduitLocation, 'runtime'),
          "conduit_test": _packageUri(conduitLocation, 'test_harness'),
        })) {
          displayError(
            'You are running from a local source (pub global activate --source=path) version of conduit and are missing the source for some dependencies.',
          );
          throw StateError;
        }
      } catch (e) {
        displayError(e.toString());
        return 1;
      }
    } else {
      await cachePackages(['conduit'], (await toolVersion).toString());
    }

    final templateSourceDirectory = Directory.fromUri(await getTemplateLocation(
            templateName, (await toolVersion).toString()) ??
        Uri());
    if (!templateSourceDirectory.existsSync()) {
      displayError("No template at ${templateSourceDirectory.path}.");
      return 1;
    }

    displayProgress("Template source is: ${templateSourceDirectory.path}");
    displayProgress("See more templates with 'conduit create list-templates'");
    copyProjectFiles(destDirectory, templateSourceDirectory, projectName);

    createProjectSpecificFiles(destDirectory.path);

    displayInfo(
      "Fetching project dependencies (pub get ${offline ? "--offline" : ""})...",
    );
    displayInfo("Please wait...");
    try {
      await fetchProjectDependencies(destDirectory, offline: offline);
    } on TimeoutException {
      displayInfo(
        "Fetching dependencies timed out. Run 'pub get' in your project directory.",
      );
    }

    displayProgress("Success.");
    displayInfo("project '$projectName' successfully created.");
    displayProgress("Project is located at ${destDirectory.path}");
    displayProgress("Open this directory in IntelliJ IDEA, Atom or VS Code.");
    displayProgress(
      "See ${destDirectory.path}${path_lib.separator}README.md for more information.",
    );

    return 0;
  }

  Uri _packageUri(Directory conduitLocation, String packageDir) {
    return conduitLocation.uri.resolve('..').resolve(packageDir);
  }

  bool shouldIncludeItem(FileSystemEntity entity) {
    final ignoreFiles = [
      "packages",
      "pubspec.lock",
      "Dart_Packages.xml",
      "workspace.xml",
      "tasks.xml",
      "vcs.xml",
    ];

    final hiddenFilesToKeep = [
      ".gitignore",
      ".travis.yml",
      "analysis_options.yaml"
    ];

    var lastComponent = entity.uri.pathSegments.last;
    if (lastComponent.isEmpty) {
      lastComponent =
          entity.uri.pathSegments[entity.uri.pathSegments.length - 2];
    }

    if (lastComponent.startsWith(".") &&
        !hiddenFilesToKeep.contains(lastComponent)) {
      return false;
    }

    if (ignoreFiles.contains(lastComponent)) {
      return false;
    }

    return true;
  }

  void interpretContentFile(
    String? projectName,
    Directory destinationDirectory,
    FileSystemEntity sourceFileEntity,
  ) {
    if (shouldIncludeItem(sourceFileEntity)) {
      if (sourceFileEntity is Directory) {
        copyDirectory(projectName, destinationDirectory, sourceFileEntity);
      } else if (sourceFileEntity is File) {
        copyFile(projectName!, destinationDirectory, sourceFileEntity);
      }
    }
  }

  void copyDirectory(
    String? projectName,
    Directory destinationParentDirectory,
    Directory sourceDirectory,
  ) {
    final sourceDirectoryName = sourceDirectory
        .uri.pathSegments[sourceDirectory.uri.pathSegments.length - 2];
    final destDir = Directory(
      path_lib.join(destinationParentDirectory.path, sourceDirectoryName),
    );

    destDir.createSync();

    sourceDirectory.listSync().forEach((f) {
      interpretContentFile(projectName, destDir, f);
    });
  }

  void copyFile(
    String projectName,
    Directory destinationDirectory,
    File sourceFile,
  ) {
    final path = path_lib.join(
      destinationDirectory.path,
      fileNameForFile(projectName, sourceFile),
    );
    var contents = sourceFile.readAsStringSync();

    contents = contents.replaceAll("wildfire", projectName);
    contents =
        contents.replaceAll("Wildfire", camelCaseFromSnakeCase(projectName));

    final outputFile = File(path);
    outputFile.createSync();
    outputFile.writeAsStringSync(contents);
  }

  String fileNameForFile(String projectName, File sourceFile) {
    return sourceFile.uri.pathSegments.last
        .replaceFirst("wildfire", projectName);
  }

  Directory destinationDirectoryFromPath(String pathString) {
    if (pathString.startsWith("/")) {
      return Directory(pathString);
    }
    final currentDirPath = join(Directory.current.path, pathString);

    return Directory(currentDirPath);
  }

  void createProjectSpecificFiles(String directoryPath) {
    displayProgress("Generating config.yaml from config.src.yaml.");
    final configSrcPath = File(path_lib.join(directoryPath, "config.src.yaml"));
    configSrcPath
        .copySync(File(path_lib.join(directoryPath, "config.yaml")).path);
  }

  bool addDependencyOverridesToPackage(
    String packageDirectoryPath,
    Map<String, Uri> overrides,
  ) {
    final overridesFile =
        File(path_lib.join(packageDirectoryPath, "pubspec_overrides.yaml"));

    bool valid = true;

    final overrideBuffer = StringBuffer();
    overrideBuffer.writeln("dependency_overrides:");
    overrides.forEach((packageName, location) {
      final path = location.toFilePath(windows: Platform.isWindows);
      valid &= _testPackagePath(path, packageName);
      overrideBuffer.writeln("  $packageName:");
      overrideBuffer.writeln(
        "    path:  ${_truepath(path)}",
      );
    });

    overridesFile.writeAsStringSync("$overrideBuffer");

    return valid;
  }

  void copyProjectFiles(
    Directory destinationDirectory,
    Directory sourceDirectory,
    String? projectName,
  ) {
    displayInfo(
      "Copying template files to project directory (${destinationDirectory.path})...",
    );
    try {
      destinationDirectory.createSync();

      Directory(sourceDirectory.path).listSync().forEach((f) {
        displayProgress("Copying contents of ${f.path}");
        interpretContentFile(projectName, destinationDirectory, f);
      });
    } catch (e) {
      destinationDirectory.deleteSync(recursive: true);
      displayError("$e");
      rethrow;
    }
  }

  bool isSnakeCase(String string) {
    final expr = RegExp("^[a-z][a-z0-9_]*\$");
    return expr.hasMatch(string);
  }

  String camelCaseFromSnakeCase(String string) {
    return string.split("_").map((str) {
      final firstChar = str.substring(0, 1);
      final remainingString = str.substring(1, str.length);
      return firstChar.toUpperCase() + remainingString;
    }).join();
  }

  Future<int> fetchProjectDependencies(
    Directory workingDirectory, {
    bool offline = false,
  }) async {
    final args = ["pub", "get"];
    if (offline) {
      args.add("--offline");
    }

    try {
      const cmd = "dart";
      final process = await Process.start(
        cmd,
        args,
        workingDirectory: workingDirectory.absolute.path,
        runInShell: true,
      ).timeout(const Duration(seconds: 60));
      process.stdout
          .transform(utf8.decoder)
          .listen((output) => outputSink.write(output));
      process.stderr
          .transform(utf8.decoder)
          .listen((output) => outputSink.write(output));

      final exitCode = await process.exitCode;

      if (exitCode != 0) {
        throw CLIException(
          "If you are offline, try using `pub get --offline`.",
        );
      }

      return exitCode;
    } on TimeoutException {
      displayError(
        "Timed out fetching dependencies. Reconnect to the internet or use `pub get --offline`.",
      );
      rethrow;
    }
  }

  @override
  String get usage {
    return "${super.usage} <project_name>";
  }

  @override
  String get name {
    return "create";
  }

  @override
  String get detailedDescription {
    return "This command will use a template from the conduit package determined by either "
        "git-url (and git-ref), path-source or version. If none of these "
        "are specified, the most recent version on pub.dartlang.org is used.";
  }

  @override
  String get description {
    return "Creates Conduit applications from templates.";
  }

  /// check if a path exists sync.
  bool _exists(String path) {
    return Directory(path).existsSync();
  }

  /// test if the given package dir exists in the test path
  bool _testPackagePath(String testPath, String packageName) {
    final String packagePath = _truepath(testPath);
    if (!_exists(packagePath)) {
      displayError(
        "The source for path '$packageName' doesn't exists. Expected to find it at '$packagePath'",
      );
      return false;
    }
    return true;
  }

  String _truepath(String path) =>
      Uri.parse(path).toFilePath(windows: Platform.isWindows);
}

class CLITemplateList extends CLICommand {
  @override
  Future<int> handle() async {
    final templateRootDirectory =
        (await templateDirectory((await toolVersion).toString()))!;
    final templateDirectories = await templateRootDirectory
        .list()
        .where((fse) => fse is Directory)
        .map((fse) => fse as Directory)
        .toList();
    final templateDescriptions =
        await Future.wait(templateDirectories.map(_templateDescription));
    displayInfo("Available templates:");
    displayProgress("");

    templateDescriptions.forEach(displayProgress);

    return 0;
  }

  @override
  String get name {
    return "list-templates";
  }

  @override
  String get description {
    return "List Conduit application templates.";
  }

  Future<String> _templateDescription(Directory templateDirectory) async {
    final name = templateDirectory
        .uri.pathSegments[templateDirectory.uri.pathSegments.length - 2];
    final pubspecContents =
        await File.fromUri(templateDirectory.uri.resolve("pubspec.yaml"))
            .readAsString();
    final pubspecDefinition = loadYaml(pubspecContents);

    return "$name | ${pubspecDefinition["description"]}";
  }
}

Future<Directory?> templateDirectory(String toolVersion) async {
  const String cmd = "dart";

  try {
    final res = await Process.run(
      cmd,
      ["pub", "cache", "list"],
      runInShell: true,
    );
    final packageDir = Uri.directory(
        jsonDecode(res.stdout)['packages']['conduit'][toolVersion]['location'],
        windows: Platform.isWindows);
    return Directory.fromUri(packageDir.resolve('templates'));
  } catch (_) {
    return null;
  }
}

Future<Uri?> getTemplateLocation(
    String templateName, String toolVersion) async {
  final dirUri = await templateDirectory(toolVersion);
  return dirUri?.uri.resolve("$templateName/");
}
