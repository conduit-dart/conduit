import 'package:conduit_codable/conduit_codable.dart';
import 'package:conduit_open_api/src/v3/parameter.dart';

/// [APIHeader] follows the structure of the [APIParameter] with the following changes:
///
/// name MUST NOT be specified, it is given in the corresponding headers map.
/// in MUST NOT be specified, it is implicitly in header.
/// All traits that are affected by the location MUST be applicable to a location of header (for example, style).
class APIHeader extends APIParameter {
  APIHeader({super.schema}) : super.header(null);
  APIHeader.empty() : super.header(null);

  @override
  void encode(KeyedArchive object) {
    name = "temporary";
    super.encode(object);
    object.remove("name");
    object.remove("in");
    name = null;
  }
}
