import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';

/// Generates a `ChannelRuntime` subclass per `ApplicationChannel` class in
/// the input library.
///
/// Emits two siblings per source library:
///  - `<src>.channel.conduit.dart` — runtime code with one
///    `$<Class>ChannelRuntime` per channel.
///  - `<src>.channel.conduit.json` — manifest the registry builder reads
///    to discover runtime classes without parsing Dart source. Schema:
///    `{"channels": ["MyAppChannel", ...]}`.
///
/// Replaces the mirror-based `ChannelRuntimeImpl` in
/// `packages/core/lib/src/runtime/impl.dart`.
class ChannelBuilder implements Builder {
  static const _appChannelTypeName = 'ApplicationChannel';
  static const _conduitCorePackagePrefix = 'package:conduit_core/';

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.channel.conduit.dart', '.channel.conduit.json'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    if (!await buildStep.resolver.isLibrary(input)) return;
    final lib = await buildStep.inputLibrary;

    final classes = lib.classes
        .where((c) => !c.isAbstract && _extendsApplicationChannel(c))
        .toList();

    if (classes.isEmpty) return;

    final manifest = {
      'channels': classes.map((c) => c.name).toList(),
    };
    await buildStep.writeAsString(
      input.changeExtension('.channel.conduit.json'),
      json.encode(manifest),
    );

    final inputUri = input.uri.toString();
    final buf = StringBuffer()
      ..writeln(
        '// GENERATED CODE - DO NOT MODIFY BY HAND. '
        'conduit_build_runner ChannelBuilder.',
      )
      ..writeln(
        '// ignore_for_file: type=lint, directives_ordering, '
        'no_leading_underscores_for_local_identifiers',
      )
      ..writeln()
      ..writeln("import 'dart:async';")
      ..writeln("import 'package:conduit_common/conduit_common.dart';")
      ..writeln("import 'package:conduit_core/aot.dart';")
      ..writeln(
        "import 'package:conduit_core/src/application/isolate_application_server.dart';",
      )
      ..writeln("import '$inputUri';")
      ..writeln();

    for (final klass in classes) {
      buf.writeln(_generateRuntimeFor(klass));
    }

    await buildStep.writeAsString(
      input.changeExtension('.channel.conduit.dart'),
      buf.toString(),
    );
  }

  bool _extendsApplicationChannel(ClassElement element) {
    bool isAppChannel(InterfaceType t) {
      final el = t.element;
      if (el.name != _appChannelTypeName) return false;
      final libUri = el.library.identifier;
      return libUri.startsWith(_conduitCorePackagePrefix);
    }

    return element.allSupertypes.any(isAppChannel);
  }

  bool _hasInitializeApplication(ClassElement klass) {
    return klass.methods.any(
      (m) => m.isStatic && m.name == 'initializeApplication',
    );
  }

  String _generateRuntimeFor(ClassElement klass) {
    final className = klass.name;
    final globalInitBody = _hasInitializeApplication(klass)
        ? 'await $className.initializeApplication(config);'
        : '';

    return '''
void _\$${className}EntryPoint(ApplicationInitialServerMessage params) {
  final runtime = \$${className}ChannelRuntime();
  final server = ApplicationIsolateServer(
    runtime.channelType,
    params.configuration,
    params.identifier,
    params.parentMessagePort,
    logToConsole: params.logToConsole,
  );
  server.start(shareHttpServer: true);
}

class \$${className}ChannelRuntime extends ChannelRuntime {
  \$${className}ChannelRuntime();

  @override
  String get name => '$className';

  @override
  IsolateEntryFunction get isolateEntryPoint => _\$${className}EntryPoint;

  @override
  Uri get libraryUri => Uri();

  @override
  Type get channelType => $className;

  @override
  ApplicationChannel instantiateChannel() => $className();

  @override
  Future<void> runGlobalInitialization(ApplicationOptions config) async {
    $globalInitBody
  }

  @override
  Iterable<APIComponentDocumenter> getDocumentableChannelComponents(
    ApplicationChannel channel,
  ) {
    throw UnsupportedError(
      'getDocumentableChannelComponents is not implemented for AOT-compiled channels yet.',
    );
  }
}
''';
  }
}

Builder channelBuilder(BuilderOptions options) => ChannelBuilder();
