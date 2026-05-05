/// Mirror-free side-channel for per-type compile errors collected by
/// [DataModelCompiler] during the tolerant eager-compile pass.
///
/// Lives in its own file (no `dart:mirrors` import) so the AOT path —
/// which transitively imports `data_model.dart` — can read this cache
/// without dragging in the JIT/mirror machinery from
/// `data_model_compiler.dart`.
///
/// Populated by `DataModelCompiler.compile`; consumed by the
/// `ManagedDataModel` constructor when a user-requested type is
/// missing from the runtime registry.
final Map<Type, Object> dataModelCompileErrors = {};
