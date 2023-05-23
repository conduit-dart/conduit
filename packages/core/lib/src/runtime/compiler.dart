import 'dart:convert';
import 'dart:io';
import 'dart:mirrors';

import 'package:conduit_core/src/application/channel.dart';
import 'package:conduit_core/src/db/managed/object.dart';
import 'package:conduit_core/src/http/controller.dart';
import 'package:conduit_core/src/http/serializable.dart';
import 'package:conduit_core/src/runtime/impl.dart';
import 'package:conduit_core/src/runtime/orm/data_model_compiler.dart';
import 'package:conduit_runtime/runtime.dart';
import 'package:io/io.dart';
import 'package:yaml/yaml.dart';

class ConduitCompiler extends Compiler {
  @override
  Map<String, dynamic> compile(MirrorContext context) {
    final m = <String, dynamic>{};

    m.addEntries(
      context
          .getSubclassesOf(ApplicationChannel)
          .map((t) => MapEntry(_getClassName(t), ChannelRuntimeImpl(t))),
    );
    m.addEntries(
      context
          .getSubclassesOf(Serializable)
          .map((t) => MapEntry(_getClassName(t), SerializableRuntimeImpl(t))),
    );
    m.addEntries(
      context
          .getSubclassesOf(Controller)
          .map((t) => MapEntry(_getClassName(t), ControllerRuntimeImpl(t))),
    );

    m.addAll(DataModelCompiler().compile(context));

    return m;
  }

  String _getClassName(ClassMirror mirror) {
    return MirrorSystem.getName(mirror.simpleName);
  }

  @override
  List<Uri> getUrisToResolve(BuildContext context) {
    return context.context
        .getSubclassesOf(ManagedObject)
        .map((c) => c.location!.sourceUri)
        .toList();
  }

  @override
  void deflectPackage(Directory destinationDirectory) {
    final libFile = File.fromUri(
      destinationDirectory.uri.resolve("lib/").resolve("conduit_core.dart"),
    );
    final contents = libFile.readAsStringSync();
    libFile.writeAsStringSync(
      contents.replaceFirst(
        "export 'package:conduit_core/src/runtime/compiler.dart';",
        "",
      ),
    );
  }

  @override
  void didFinishPackageGeneration(BuildContext context) {
    if (context.forTests) {
      final devPackages = [
        {'name': 'fs_test_agent', 'path': 'fs_test_agent'},
        {'name': 'conduit_test', 'path': 'test_harness'},
      ];
      final targetPubspecFile =
          File.fromUri(context.buildDirectoryUri.resolve("pubspec.yaml"));
      final pubspecContents = json.decode(targetPubspecFile.readAsStringSync());
      for (final package in devPackages) {
        pubspecContents["dev_dependencies"]
            [package['name']!] = {"path": "packages/${package['path']!}"};

        copyPathSync(
          context.sourceApplicationDirectory.uri
              .resolve("../")
              .resolve(package['path']!)
              .toFilePath(windows: Platform.isWindows),
          context.buildPackagesDirectory.uri
              .resolve(package['path']!)
              .toFilePath(windows: Platform.isWindows),
        );
      }

      pubspecContents["dependency_overrides"]["conduit_core"] =
          pubspecContents["dependencies"]["conduit_core"];
      targetPubspecFile.writeAsStringSync(json.encode(pubspecContents));

      final conduitPackages = [
        {'name': 'conduit_codable', 'path': 'codable'},
        {'name': 'conduit_common', 'path': 'common'},
        {'name': 'conduit_config', 'path': 'config'},
        {'name': 'conduit_isolate_exec', 'path': 'isolate_exec'},
        {'name': 'conduit_open_api', 'path': 'open_api'},
        {'name': 'conduit_password_hash', 'path': 'password_hash'},
        {'name': 'conduit_runtime', 'path': 'runtime'},
      ];
      _overwritePackageDependency(context, 'conduit_core', conduitPackages);

      final runtimePackages = [
        {'name': 'conduit_isolate_exec', 'path': 'isolate_exec'},
      ];
      _overwritePackageDependency(context, 'conduit_runtime', runtimePackages);

      final commonPackages = [
        {'name': 'conduit_open_api', 'path': 'open_api'},
      ];
      _overwritePackageDependency(context, 'common', commonPackages);

      final oapiPackages = [
        {'name': 'conduit_codable', 'path': 'codable'},
      ];
      _overwritePackageDependency(context, 'open_api', oapiPackages);
    }
  }

  void _overwritePackageDependency(
    BuildContext context,
    String packageName,
    List<Map<String, String>> packages,
  ) {
    final pubspecFile = File.fromUri(
      context.buildDirectoryUri
          .resolve('packages/')
          .resolve('$packageName/')
          .resolve("pubspec.yaml"),
    );
    final pubspecContents = loadYaml(pubspecFile.readAsStringSync());
    final jsonContents = json.decode(json.encode(pubspecContents));
    for (final package in packages) {
      jsonContents["dependencies"]
          [package['name']!] = {"path": "../${package['path']!}"};
      copyPathSync(
        context.sourceApplicationDirectory.uri
            .resolve("../")
            .resolve(package['path']!)
            .toFilePath(windows: Platform.isWindows),
        context.buildPackagesDirectory.uri
            .resolve(package['path']!)
            .toFilePath(windows: Platform.isWindows),
      );
    }
    pubspecFile.writeAsStringSync(json.encode(jsonContents));
  }
}
