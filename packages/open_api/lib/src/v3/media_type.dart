import 'package:conduit_codable/conduit_codable.dart';
import 'package:conduit_open_api/src/object.dart';
import 'package:conduit_open_api/src/v3/encoding.dart';
import 'package:conduit_open_api/src/v3/schema.dart';

/// Each [APIMediaType] provides schema and examples for the media type identified by its key.
class APIMediaType extends APIObject {
  APIMediaType({this.schema, this.encoding});
  APIMediaType.empty();

  /// The schema defining the type used for the request body.
  APISchemaObject? schema;

  /// A map between a property name and its encoding information.
  ///
  /// The key, being the property name, MUST exist in the schema as a property. The encoding object SHALL only apply to requestBody objects when the media type is multipart or application/x-www-form-urlencoded.
  Map<String, APIEncoding?>? encoding;

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    schema = object.decodeObject("schema", APISchemaObject.new);
    encoding = object.decodeObjectMap("encoding", APIEncoding.new);
  }

  @override
  void encode(KeyedArchive object) {
    super.encode(object);

    object.encodeObject("schema", schema);
    object.encodeObjectMap("encoding", encoding);
  }
}
