import 'package:conduit_codable/conduit_codable.dart';
import 'package:conduit_open_api/src/object.dart';
import 'package:conduit_open_api/src/v2/operation.dart';
import 'package:conduit_open_api/src/v2/parameter.dart';

/// Represents a path (also known as a route) in the OpenAPI specification.
class APIPath extends APIObject {
  APIPath();

  List<APIParameter?> parameters = [];
  Map<String, APIOperation?> operations = {};

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    for (final k in object.keys) {
      if (k == r"$ref") {
        // todo: reference
      } else if (k == "parameters") {
        parameters = object.decodeObjects(k, APIParameter.new)!;
      } else {
        operations[k] = object.decodeObject(k, APIOperation.new);
      }
    }
  }

  @override
  void encode(KeyedArchive object) {
    super.encode(object);

    object.encodeObjects("parameters", parameters);
    operations.forEach((opName, op) {
      object.encodeObject(opName, op);
    });
  }
}
