import 'dart:convert';

import 'package:build/build.dart';
import 'package:glob/glob.dart';

/// Aggregates the per-source `.channel.conduit.json` /
/// `.controller.conduit.json` / `.serializable.conduit.json` manifests of
/// the root package into a single `lib/conduit.g.dart` whose `bootstrap()`
/// function populates `RuntimeContext.current.runtimes`.
///
/// Runs once per package via the synthetic `$package$` input. Wired
/// `auto_apply: root_package` so only the user's application package gets
/// a registry — library packages don't need one.
///
/// The manifest format each per-source builder writes is:
///   {"channels": ["MyAppChannel"]}
///   {"serializables": ["UserPayload"]}
///   {"controllers": ["HealthController"]}
class RegistryBuilder implements Builder {
  static final _libGlob = Glob('lib/**');

  static const _manifestKinds = <_ManifestKind>[
    _ManifestKind(
      manifestKey: 'channels',
      runtimeSuffix: 'ChannelRuntime',
      manifestExtension: '.channel.conduit.json',
      libraryExtension: '.channel.conduit.dart',
    ),
    _ManifestKind(
      manifestKey: 'serializables',
      runtimeSuffix: 'SerializableRuntime',
      manifestExtension: '.serializable.conduit.json',
      libraryExtension: '.serializable.conduit.dart',
    ),
    _ManifestKind(
      manifestKey: 'controllers',
      runtimeSuffix: 'ControllerRuntime',
      manifestExtension: '.controller.conduit.json',
      libraryExtension: '.controller.conduit.dart',
    ),
  ];

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$package$': ['lib/conduit.g.dart'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final pkg = buildStep.inputId.package;

    final bindings = <_RuntimeBinding>[];

    await for (final id in buildStep.findAssets(_libGlob)) {
      final kind = _kindFor(id.path);
      if (kind == null) continue;
      final manifest =
          json.decode(await buildStep.readAsString(id)) as Map<String, dynamic>;
      final classes = (manifest[kind.manifestKey] as List).cast<String>();
      final libraryPath = id.path.substring(
              0, id.path.length - kind.manifestExtension.length) +
          kind.libraryExtension;
      for (final cls in classes) {
        bindings.add(_RuntimeBinding(
          className: cls,
          runtimeSuffix: kind.runtimeSuffix,
          libraryAssetPath: libraryPath,
        ));
      }
    }

    bindings.sort((a, b) => a.className.compareTo(b.className));

    final buf = StringBuffer()
      ..writeln(
        '// GENERATED CODE - DO NOT MODIFY BY HAND. '
        'conduit_build_runner registry.',
      )
      ..writeln(
        '// ignore_for_file: type=lint, directives_ordering, '
        'no_leading_underscores_for_local_identifiers',
      )
      ..writeln()
      ..writeln("import 'package:conduit_runtime/runtime.dart';")
      ..writeln(
        "import 'package:conduit_runtime/slow_coerce.dart' as _coerce;",
      );

    for (var i = 0; i < bindings.length; i++) {
      final relative = bindings[i].libraryAssetPath.replaceFirst('lib/', '');
      buf.writeln("import 'package:$pkg/$relative' as _r$i;");
    }
    buf.writeln();

    buf.writeln('class _\$ConduitGeneratedContext extends RuntimeContext {');
    buf.writeln('  _\$ConduitGeneratedContext() {');
    buf.writeln('    final map = <String, Object>{};');
    for (var i = 0; i < bindings.length; i++) {
      final b = bindings[i];
      buf.writeln(
        "    map['${b.className}'] = _r$i.\$${b.className}${b.runtimeSuffix}();",
      );
    }
    buf.writeln('    runtimes = RuntimeCollection(map);');
    buf.writeln('  }');
    buf.writeln();
    buf.writeln('  @override');
    buf.writeln('  T coerce<T>(dynamic input) => _coerce.cast<T>(input);');
    buf.writeln('}');
    buf.writeln();

    buf.writeln('/// Installs the build_runner-generated runtime registry');
    buf.writeln(
      '/// into `RuntimeContext.current`. Call once at the top of `main`',
    );
    buf.writeln('/// before constructing `Application<T>`.');
    buf.writeln('void bootstrap() {');
    buf.writeln(
      '  RuntimeContext.install(_\$ConduitGeneratedContext());',
    );
    buf.writeln('}');

    final outputId = AssetId(pkg, 'lib/conduit.g.dart');
    await buildStep.writeAsString(outputId, buf.toString());
  }

  static _ManifestKind? _kindFor(String path) {
    for (final kind in _manifestKinds) {
      if (path.endsWith(kind.manifestExtension)) return kind;
    }
    return null;
  }
}

class _ManifestKind {
  const _ManifestKind({
    required this.manifestKey,
    required this.runtimeSuffix,
    required this.manifestExtension,
    required this.libraryExtension,
  });
  final String manifestKey;
  final String runtimeSuffix;
  final String manifestExtension;
  final String libraryExtension;
}

class _RuntimeBinding {
  _RuntimeBinding({
    required this.className,
    required this.runtimeSuffix,
    required this.libraryAssetPath,
  });
  final String className;
  final String runtimeSuffix;
  final String libraryAssetPath;
}
