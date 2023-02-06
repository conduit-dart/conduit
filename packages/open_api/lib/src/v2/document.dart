import 'package:conduit_codable/cast.dart' as cast;
import 'package:conduit_codable/conduit_codable.dart';
import 'package:conduit_open_api/src/object.dart';
import 'package:conduit_open_api/src/util/list_helper.dart';
import 'package:conduit_open_api/src/v2/metadata.dart';
import 'package:conduit_open_api/src/v2/parameter.dart';
import 'package:conduit_open_api/src/v2/path.dart';
import 'package:conduit_open_api/src/v2/response.dart';
import 'package:conduit_open_api/src/v2/schema.dart';
import 'package:conduit_open_api/src/v2/security.dart';

/// Represents an OpenAPI 2.0 specification.
class APIDocument extends APIObject {
  /// Creates an empty specification.
  APIDocument();

  /// Creates a specification from decoded JSON or YAML document object.
  APIDocument.fromMap(Map<String, dynamic> map) {
    decode(KeyedArchive.unarchive(map, allowReferences: true));
  }

  String version = "2.0";
  APIInfo? info = APIInfo();
  String? host;
  String? basePath;

  List<APITag?>? tags = [];
  List<String>? schemes = [];
  List<String>? consumes = [];
  List<String>? produces = [];
  List<Map<String, List<String?>>?>? security = [];

  Map<String, APIPath?>? paths = {};
  Map<String, APIResponse?>? responses = {};
  Map<String, APIParameter?>? parameters = {};
  Map<String, APISchemaObject?>? definitions = {};
  Map<String, APISecurityScheme?>? securityDefinitions = {};

  Map<String, dynamic> asMap() {
    return KeyedArchive.archive(this, allowReferences: true);
  }

  @override
  Map<String, cast.Cast> get castMap => {
        "schemes": const cast.List(cast.string),
        "consumes": const cast.List(cast.string),
        "produces": const cast.List(cast.string),
        "security":
            const cast.List(cast.Map(cast.string, cast.List(cast.string)))
      };

  @override
  void decode(KeyedArchive object) {
    super.decode(object);

    version = object["swagger"] as String;
    host = object["host"] as String?;
    basePath = object["basePath"] as String?;
    schemes = removeNullsFromList(object["schemes"] as List<String?>?);

    /// remove
    consumes = removeNullsFromList(object["consumes"] as List<String?>?);
    produces = removeNullsFromList(object["produces"] as List<String?>?);
    security = object["security"] as List<Map<String, List<String?>>?>;

    info = object.decodeObject("info", () => APIInfo());
    tags = object.decodeObjects("tags", () => APITag());
    paths = object.decodeObjectMap("paths", () => APIPath());
    responses = object.decodeObjectMap("responses", () => APIResponse());
    parameters = object.decodeObjectMap("parameters", () => APIParameter());
    definitions =
        object.decodeObjectMap("definitions", () => APISchemaObject());
    securityDefinitions = object.decodeObjectMap(
      "securityDefinitions",
      () => APISecurityScheme(),
    );
  }

  @override
  void encode(KeyedArchive object) {
    super.encode(object);

    object.encode("swagger", version);
    object.encode("host", host);
    object.encode("basePath", basePath);
    object.encode("schemes", schemes);
    object.encode("consumes", consumes);
    object.encode("produces", produces);
    object.encodeObjectMap("paths", paths);
    object.encodeObject("info", info);
    object.encodeObjectMap("parameters", parameters);
    object.encodeObjectMap("responses", responses);
    object.encodeObjectMap("securityDefinitions", securityDefinitions);
    object.encode("security", security);
    object.encodeObjects("tags", tags);
    object.encodeObjectMap("definitions", definitions);
  }
}
