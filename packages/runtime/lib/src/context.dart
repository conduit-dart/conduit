import 'package:conduit_runtime/src/mirror_context.dart' as context;

/// Contextual values used during runtime.
abstract class RuntimeContext {
  /// The current [RuntimeContext] available to the executing application.
  ///
  /// Is either a `MirrorContext` or a `GeneratedContext`,
  /// depending on the execution type.
  static final RuntimeContext current = context.instance;

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

class RuntimeCollection {
  RuntimeCollection(this.map);

  final Map<String, dynamic> map;

  Iterable<dynamic> get iterable => map.values;

  dynamic operator [](Type t) {
    //todo: optimize by keeping a cache where keys are of type [Type] to avoid the
    // expensive indexOf and substring calls in this method
    final typeName = t.toString();
    final r = map[typeName];
    if (r != null) {
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
