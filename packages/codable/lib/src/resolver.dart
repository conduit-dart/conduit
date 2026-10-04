import 'package:conduit_codable/src/keyed_archive.dart';

class ReferenceResolver {
  ReferenceResolver(this.document);

  final KeyedArchive document;

  /// resolves a reference of the form '#/yyy/xxx'
  /// To the value stored in a document
  ///
  /// e.g.
  /// if [ref] == '#/definitions/child' then we would
  /// return a [KeyedArchive] with the child named Sally.
  ///
  /// ```
  /// {
  ///   "definitions": {
  ///           "child": {"name": "Sally"}
  ///   },
  ///   "root": {
  ///       "name": "Bob",
  ///       "child": {"\$ref": "#/definitions/child"}
  ///}
  /// ```
  KeyedArchive? resolve(Uri ref) {
    final folded = ref.pathSegments.fold<KeyedArchive?>(document, (
      KeyedArchive? objectPtr,
      pathSegment,
    ) {
      if (objectPtr != null) {
        return objectPtr[pathSegment] as KeyedArchive?;
      } else {
        return null;
      }
    });

    return folded;
  }
}
