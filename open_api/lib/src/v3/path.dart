import 'package:conduit_codable/conduit_codable.dart';
import 'package:conduit_open_api/src/object.dart';
import 'package:conduit_open_api/src/v3/operation.dart';
import 'package:conduit_open_api/src/v3/parameter.dart';

/// Describes the operations available on a single path.
///
/// An [APIPath] MAY be empty, due to ACL constraints. The path itself is still exposed to the documentation viewer but they will not know which operations and parameters are available.
class APIPath extends APIObject {
  APIPath({
    this.summary,
    this.description,
    List<APIParameter?>? parameters,
    Map<String, APIOperation?>? operations,
  }) {
    this.parameters = parameters ?? [];
    this.operations = operations ?? {};
  }
  APIPath.empty()
      : parameters = <APIParameter?>[],
        operations = <String, APIOperation?>{};

  /// An optional, string summary, intended to apply to all operations in this path.
  String? summary;

  /// An optional, string description, intended to apply to all operations in this path.
  ///
  /// CommonMark syntax MAY be used for rich text representation.
  String? description;

  /// A list of parameters that are applicable for all the operations described under this path.
  ///
  /// These parameters can be overridden at the operation level, but cannot be removed there. The list MUST NOT include duplicated parameters. A unique parameter is defined by a combination of a name and location. The list can use the Reference Object to link to parameters that are defined at the OpenAPI Object's components/parameters.
  late List<APIParameter?> parameters;

  /// Definitions of operations on this path.
  ///
  /// Keys are lowercased HTTP methods, e.g. get, put, delete, post, etc.
  late Map<String, APIOperation?> operations;

  /// Returns true if this path has path parameters [parameterNames].
  ///
  /// Returns true if [parameters] contains path parameters with names that match [parameterNames] and
  /// both lists have the same number of elements.
  bool containsPathParameters(List<String> parameterNames) {
    final pathParams = parameters
        .where((p) => p?.location == APIParameterLocation.path)
        .map((p) => p?.name)
        .toList();
    if (pathParams.length != parameterNames.length) {
      return false;
    }

    return parameterNames.every((check) => pathParams.contains(check));
  }

  // todo (joeconwaystk): alternative servers not yet implemented

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    summary = object.decode("summary");
    description = object.decode("description");
    parameters =
        object.decodeObjects("parameters", () => APIParameter.empty()) ??
            <APIParameter?>[];

    final methodNames = [
      "get",
      "put",
      "post",
      "delete",
      "options",
      "head",
      "patch",
      "trace"
    ];
    for (final methodName in methodNames) {
      if (object.containsKey(methodName)) {
        operations[methodName] =
            object.decodeObject(methodName, () => APIOperation.empty());
      }
    }
  }

  @override
  void encode(KeyedArchive object) {
    super.encode(object);

    object.encode("summary", summary);
    object.encode("description", description);
    if (parameters.isNotEmpty) {
      object.encodeObjects("parameters", parameters);
    }

    operations.forEach((opName, op) {
      object.encodeObject(opName.toLowerCase(), op);
    });
  }
}
