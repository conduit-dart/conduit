import 'package:conduit_runtime/src/mirror_fallback_stub.dart'
    if (dart.library.mirrors) 'package:conduit_runtime/src/mirror_fallback_real.dart'
    as fallback;

/// Contextual values used during runtime.
///
/// Conditional import on `dart.library.mirrors` keeps `dart:mirrors` out
/// of any AOT-compiled binary's import graph: the stub is selected when
/// mirrors are unavailable (`dart compile exe`), the real fallback when
/// they are (`dart run`, `dart test`). AOT users still must call
/// `bootstrap()` from the build_runner-generated `conduit.g.dart`
/// before any code reads [current], or they'll hit a clear `StateError`.
abstract class RuntimeContext {
  /// Override slot installed by the build_runner-generated `bootstrap()`.
  static RuntimeContext? _installed;

  /// The current [RuntimeContext] available to the executing application.
  ///
  /// Resolution order:
  /// 1. Whatever was installed via [install] (typically the
  ///    build_runner-generated `bootstrap()`).
  /// 2. Whatever was registered via [registerDefaultContextFactory].
  /// 3. The mirror-based `MirrorContext` if `dart:mirrors` is available
  ///    (JIT execution); otherwise a `StateError` (AOT execution).
  static RuntimeContext get current =>
      _installed ??= _resolveDefaultContext();

  /// Installs a pre-populated [RuntimeContext]. Intended to be called from
  /// generated code at the top of `main()` so that no mirror code is ever
  /// executed under `dart compile exe`.
  static void install(RuntimeContext ctx) {
    _installed = ctx;
  }

  /// The runtimes available to the executing application.
  late RuntimeCollection runtimes;

  /// Gets a runtime object for [type].
  ///
  /// Callers typically invoke this method, passing their [runtimeType]
  /// in order to retrieve their runtime object.
  ///
  /// It is important to note that a runtime object must exist for every
  /// class that extends a class that has a runtime. Use `MirrorContext.getSubclassesOf` when compiling.
  ///
  /// In other words, if the type `Base` has a runtime and the type `Subclass` extends `Base`,
  /// `Subclass` must also have a runtime. The runtime objects for both `Subclass` and `Base`
  /// must be the same type.
  dynamic operator [](Type type) => runtimes[type];

  T coerce<T>(dynamic input);
}

/// Optional override hook for the default context factory. Set this from
/// generated code or test setup to bypass the conditional-import path.
RuntimeContext Function()? _defaultContextFactory;

void registerDefaultContextFactory(RuntimeContext Function() factory) {
  _defaultContextFactory = factory;
}

RuntimeContext _resolveDefaultContext() {
  final factory = _defaultContextFactory;
  if (factory != null) return factory();
  return fallback.resolveMirrorFallback();
}

class RuntimeCollection {
  RuntimeCollection(this.map);

  final Map<String, Object> map;

  Iterable<Object> get iterable => map.values;

  final Map<Type, Object> _cache = {};

  Object operator [](Type t) {
    if (_cache.containsKey(t)) {
      return _cache[t]!;
    }

    final typeName = t.toString();
    final r = map[typeName];
    if (r != null) {
      _cache[t] = r;
      return r;
    }

    final genericIndex = typeName.indexOf("<");
    if (genericIndex == -1) {
      throw ArgumentError("Runtime not found for type '$t'.");
    }

    final genericTypeName = typeName.substring(0, genericIndex);
    final out = map[genericTypeName];
    if (out == null) {
      throw ArgumentError("Runtime not found for type '$t'.");
    }

    _cache[t] = out;
    return out;
  }
}

/// Prevents a type from being compiled when it otherwise would be.
///
/// Annotate a type with the const instance of this type to prevent its
/// compilation.
class PreventCompilation {
  const PreventCompilation();
}
