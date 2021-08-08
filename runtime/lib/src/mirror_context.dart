import 'context.dart';
import 'compiler.dart';
import 'mirror_coerce.dart';
import 'package:reflectable/reflectable.dart';

import 'reflector.dart';

RuntimeContext instance = MirrorContext._();

class MirrorContext extends RuntimeContext {
  MirrorContext._() {
    final m = <String, dynamic>{};
    for (final c in compilers) {
      final compiledRuntimes = c.compile(this);
      if (m.keys.any((k) => compiledRuntimes.keys.contains(k))) {
        final matching = m.keys.where((k) => compiledRuntimes.keys.contains(k));
        throw StateError(
            'Could not compile. Type conflict for the following types: ${matching.join(", ")}.');
      }
      m.addAll(compiledRuntimes);
    }

    runtimes = RuntimeCollection(m);
  }

  final List<ClassMirror> types = runtimeReflector.libraries.values
      .where((lib) =>
          lib.uri.scheme == "package" ||
          lib.uri.scheme == "file" ||
          lib.uri.scheme == "reflectable")
      .expand((lib) => lib.declarations.values)
      .whereType<ClassMirror>()
      .where((cm) => firstMetadataOfType<PreventCompilation>(cm) == null)
      .toList();

  List<Compiler> get compilers {
    return types
        .where((b) =>
            b.isSubclassOf(
                runtimeReflector.reflectType(Compiler) as ClassMirror) &&
            !b.isAbstract)
        .map((b) => b.newInstance("", []) as Compiler)
        .toList();
  }

  List<ClassMirror> getSubclassesOf(Type type) {
    final mirror = runtimeReflector.reflectType(type);
    return types.where((decl) {
      if (decl.isAbstract) {
        return false;
      }

      if (!decl.isSubclassOf(mirror as ClassMirror)) {
        return false;
      }

      if (decl.hasReflectedType) {
        if (decl.reflectedType == type) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  T coerce<T>(dynamic input) {
    return runtimeCast(input, T) as T;
  }
}

T? firstMetadataOfType<T>(DeclarationMirror dm, {TypeMirror? dynamicType}) {
  final tMirror = dynamicType ?? runtimeReflector.reflectType(T);
  try {
    return dm.metadata.firstWhere(
        (im) => runtimeReflector.reflect(im).type.isSubtypeOf(tMirror)) as T?;
    // ignore: avoid_catching_errors
  } on StateError catch (_) {
    return null;
  }
}
