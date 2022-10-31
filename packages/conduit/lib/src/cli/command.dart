// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';

import 'package:args/args.dart' as args;
import 'package:collection/collection.dart' show IterableExtension;
import 'package:conduit/src/cli/metadata.dart';
import 'package:conduit/src/cli/running_process.dart';
import 'package:conduit_runtime/runtime.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

/// Exceptions thrown by command line interfaces.
class CLIException implements Exception {
  CLIException(this.message, {this.instructions});

  final List<String>? instructions;
  final String? message;

  @override
  String toString() => message!;
}

enum CLIColor { red, green, blue, boldRed, boldGreen, boldBlue, boldNone, none }

/// A command line interface command.
abstract class CLICommand {
  CLICommand() {
    final arguments = reflect(this).type.instanceMembers.values.where(
          (m) => m.metadata
              .any((im) => im.type.isAssignableTo(reflectType(Argument))),
        );

    for (final arg in arguments) {
      if (!arg.isGetter) {
        throw StateError("Declaration "
            "${MirrorSystem.getName(arg.owner!.simpleName)}.${MirrorSystem.getName(arg.simpleName)} "
            "has CLI annotation, but is not a getter.");
      }

      final Argument? argType = firstMetadataOfType<Argument>(arg);
      argType!.addToParser(options);
    }
  }

  /// Options for this command.
  args.ArgParser options = args.ArgParser();

  late args.ArgResults _argumentValues;

  List<String> get remainingArguments => _argumentValues.rest;

  args.ArgResults? get command => _argumentValues.command;

  StoppableProcess? get runningProcess {
    return _commandMap.values
        .firstWhereOrNull((cmd) => cmd.runningProcess != null)
        ?.runningProcess;
  }

  @Flag(
    "version",
    help: "Prints version of this tool",
    negatable: false,
    defaultsTo: false,
  )
  bool get showVersion => decode<bool>("version");

  @Flag("color", help: "Toggles ANSI color", negatable: true, defaultsTo: true)
  bool get showColors => decode<bool>("color");

  @Flag(
    "help",
    abbr: "h",
    help: "Shows this",
    negatable: false,
    defaultsTo: false,
  )
  bool get helpMeItsScary => decode<bool>("help");

  @Flag(
    "stacktrace",
    help: "Shows the stacktrace if an error occurs",
    defaultsTo: false,
  )
  bool get showStacktrace => decode<bool>("stacktrace");

  @Flag(
    "machine",
    help:
        "Output is machine-readable, usable for creating tools on top of this CLI. Behavior varies by command.",
    defaultsTo: false,
  )
  bool get isMachineOutput => decode<bool>("machine");

  final Map<String, CLICommand> _commandMap = {};

  StringSink _outputSink = stdout;

  StringSink get outputSink => _outputSink;

  set outputSink(StringSink sink) {
    _outputSink = sink;
    for (final cmd in _commandMap.values) {
      cmd.outputSink = sink;
    }
  }

  Version? get toolVersion => _toolVersion;
  Version? _toolVersion;

  static const _delimiter = "-- ";
  static const _tabs = "    ";
  static const _errorDelimiter = "*** ";

  /// Use this method to extract a required value for the command line argument for [key].
  /// If the command line argument uses defaultsTo to set a default value that will
  /// satisfy the requirements.
  ///
  /// Extracts the value from an command argument for the
  /// given [key]. If the command argument [key] was not passed
  /// on the cli and does not have a default value then a
  /// CLIException is thrown.
  ///
  /// If the argument cannot be coerced to the expected type [T] then
  /// a [CLIException] is thrown.
  T decode<T extends Object>(
    String key,
  ) {
    final T? val = decodeOptional(key);

    if (val != null) {
      return val;
    }
    throw CLIException('The required argument "$key" was not passed.');
  }

  /// Use this method to extract an optional value for the command line argument for [key].
  /// If the command argument [key] was not passed
  /// then null is returned unless [orElse] is passed.
  ///
  /// If the value for [key] is null and [orElse] is passed then
  /// [orElse] is called and the resulting value returned.
  ///
  /// If the argument is passed but cannot be coerced to the expected type [T] then
  /// a [CLIException] is thrown.
  T? decodeOptional<T>(String key, {T? Function()? orElse}) {
    dynamic val;
    try {
      if (!_argumentValues.options.contains(key)) {
        return _orElse(orElse);
      }
      val = _argumentValues[key];

      if (val == null) {
        return _orElse(orElse);
      }

      if (T == int && val is String) {
        final t = int.tryParse(val);
        if (t != null) {
          return t as T;
        }
        throw CLIException('Invalid integer value "$val" for argument "$key".');
      }
      return RuntimeContext.current.coerce<T>(val);
    } on TypeCoercionException catch (_) {
      throw CLIException(
        'The value "$val" for argument "$key" could not be coerced to a $T.',
      );
    }
  }

  T? _orElse<T>(T? Function()? orElse) {
    return (orElse != null) ? orElse() : null;
  }

  void registerCommand(CLICommand cmd) {
    _commandMap[cmd.name] = cmd;
    options.addCommand(cmd.name, cmd.options);
  }

  /// Handles the command input.
  ///
  /// Override this method to perform actions for this command.
  ///
  /// Return value is the value returned to the command line operation. Return 0 for success.
  Future<int> handle();

  /// Cleans up any resources used during this command.
  ///
  /// Delete temporary files or close down any [Stream]s.
  Future? cleanup() async {}

  /// Invoked on this instance when this command is executed from the command line.
  ///
  /// Do not override this method. This method invokes [handle] within a try-catch block
  /// and will invoke [cleanup] when complete.
  Future<int> process(
    args.ArgResults results, {
    List<String>? commandPath,
  }) async {
    final parentCommandNames = commandPath ?? <String>[];

    if (results.command != null) {
      parentCommandNames.add(name);
      return _commandMap[results.command!.name!]!
          .process(results.command!, commandPath: parentCommandNames);
    }

    try {
      _argumentValues = results;

      await determineToolVersion();

      if (showVersion) {
        outputSink.writeln("Conduit CLI version: $toolVersion");
        return 0;
      }

      if (!isMachineOutput) {
        displayInfo("Conduit CLI Version: $toolVersion");
      }

      preProcess();

      if (helpMeItsScary) {
        printHelp(parentCommandName: parentCommandNames.join(" "));
        return 0;
      }

      return await handle();
    } on CLIException catch (e, st) {
      displayError(e.message);
      e.instructions?.forEach(displayProgress);

      if (showStacktrace) {
        printStackTrace(st);
      }
    } catch (e, st) {
      displayError("Uncaught error");
      displayProgress("$e");
      printStackTrace(st);
    } finally {
      await cleanup();
    }
    return 1;
  }

  Future determineToolVersion() async {
    try {
      final toolLibraryFilePath = (await Isolate.resolvePackageUri(
        currentMirrorSystem().findLibrary(#conduit).uri,
      ))!
          .toFilePath(windows: Platform.isWindows);
      final conduitDirectory = Directory(
        FileSystemEntity.parentOf(
          FileSystemEntity.parentOf(toolLibraryFilePath),
        ),
      );
      final toolPubspecFile =
          File.fromUri(conduitDirectory.absolute.uri.resolve("pubspec.yaml"));

      final toolPubspecContents =
          loadYaml(toolPubspecFile.readAsStringSync()) as Map;
      final toolVersion = toolPubspecContents["version"] as String;
      _toolVersion = Version.parse(toolVersion);
    } catch (e) {
      print(e);
    }
  }

  void preProcess() {}

  void displayError(
    String? errorMessage, {
    bool showUsage = false,
    CLIColor color = CLIColor.boldRed,
  }) {
    outputSink.writeln(
      "${colorSymbol(color)}$_errorDelimiter$errorMessage$defaultColorSymbol",
    );
    if (showUsage) {
      outputSink.writeln("\n${options.usage}");
    }
  }

  void displayInfo(String infoMessage, {CLIColor color = CLIColor.boldNone}) {
    outputSink.writeln(
      "${colorSymbol(color)}$_delimiter$infoMessage$defaultColorSymbol",
    );
  }

  void displayProgress(
    String progressMessage, {
    CLIColor color = CLIColor.none,
  }) {
    outputSink.writeln(
      "${colorSymbol(color)}$_tabs$progressMessage$defaultColorSymbol",
    );
  }

  String? colorSymbol(CLIColor color) {
    if (!showColors) {
      return "";
    }
    return _lookupTable[color];
  }

  String get name;

  String get detailedDescription => "";

  String get usage {
    final buf = StringBuffer(name);
    if (_commandMap.isNotEmpty) {
      buf.write(" <command>");
    }
    buf.write(" [arguments]");
    return buf.toString();
  }

  String get description;

  String get defaultColorSymbol {
    if (!showColors) {
      return "";
    }
    return "\u001b[0m";
  }

  static const Map<CLIColor, String> _lookupTable = {
    CLIColor.red: "\u001b[31m",
    CLIColor.green: "\u001b[32m",
    CLIColor.blue: "\u001b[34m",
    CLIColor.boldRed: "\u001b[31;1m",
    CLIColor.boldGreen: "\u001b[32;1m",
    CLIColor.boldBlue: "\u001b[34;1m",
    CLIColor.boldNone: "\u001b[0;1m",
    CLIColor.none: "\u001b[0m",
  };

  void printHelp({String? parentCommandName}) {
    print(description);
    print(detailedDescription);
    print("");
    if (parentCommandName == null) {
      print("Usage: $usage");
    } else {
      print("Usage: $parentCommandName $usage");
    }
    print("");
    print("Options:");
    print(options.usage);

    if (options.commands.isNotEmpty) {
      print("Available sub-commands:");

      final commandNames = options.commands.keys.toList();
      commandNames.sort((a, b) => b.length.compareTo(a.length));
      final length = commandNames.first.length + 3;
      for (final command in commandNames) {
        final desc = _commandMap[command]?.description;
        print("  ${command.padRight(length)}$desc");
      }
    }
  }

  bool isExecutableInShellPath(String name) {
    final String locator = Platform.isWindows ? "where" : "which";
    final ProcessResult results =
        Process.runSync(locator, [name], runInShell: true);

    return results.exitCode == 0;
  }

  void printStackTrace(StackTrace st) {
    outputSink.writeln("  **** Stacktrace");
    st.toString().split("\n").forEach((line) {
      if (line.isEmpty) {
        outputSink.writeln("  ****");
      } else {
        outputSink.writeln("  * $line");
      }
    });
  }
}
