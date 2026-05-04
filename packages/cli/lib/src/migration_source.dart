import 'dart:io';

import 'package:conduit_runtime/dev.dart';
import 'package:crypto/crypto.dart';

class MigrationSource {
  MigrationSource(this.source, this.uri, int nameStartIndex, int nameEndIndex) {
    originalName = source!.substring(nameStartIndex, nameEndIndex);
    name = "M${md5.convert(source!.codeUnits)}";
    source = source!.replaceRange(nameStartIndex, nameEndIndex, name);
  }

  MigrationSource.fromMap(Map<String, dynamic> map) {
    originalName = map["originalName"] as String;
    source = map["source"] as String?;
    name = map["name"] as String;
    uri = map["uri"] as String?;
  }

  factory MigrationSource.fromFile(Uri uri) {
    final analyzer = CodeAnalyzer(uri);
    final migrationTypes = analyzer.getSubclassesFromFile("Migration", uri);
    if (migrationTypes.length != 1) {
      throw StateError(
        "Invalid migration file. Must contain exactly one 'Migration' subclass. File: '$uri'.",
      );
    }

    final klass = migrationTypes.first;
    final source = klass.toSource();
    final originalName = klass.namePart.typeName.toString();
    // Locate the class name within `klass.toSource()` directly rather than
    // computing `namePart.offset - klass.offset`. Those two offsets do not
    // share a frame when the class has a leading doc-comment: `klass.offset`
    // is the file offset where the AST node begins (excluding the comment),
    // but `klass.toSource()` echoes the same range — so the diff is right
    // in that case. Where it goes wrong is the *opposite* direction: a
    // doc-comment shifts `klass.namePart.offset` further into the file,
    // and on some analyzer versions the substring math overshoots
    // `source.length`. `indexOf` is bullet-proof against either framing.
    // Regression: github.com/conduit-dart/conduit/issues/213.
    final start = source.indexOf(originalName);
    if (start < 0) {
      throw StateError(
        "Could not locate the migration class name '$originalName' in "
        "the parsed source for file '$uri'. This is an internal error "
        "in conduit's migration loader; please file an issue.",
      );
    }
    return MigrationSource(
      source,
      uri.toFilePath(windows: Platform.isWindows),
      start,
      start + originalName.length,
    );
  }

  Map<String, dynamic> asMap() {
    return {
      "originalName": originalName,
      "name": name,
      "source": source,
      "uri": uri,
    };
  }

  static String combine(List<MigrationSource> sources) {
    return sources.map((s) => s.source).join("\n");
  }

  static int versionNumberFromUri(Uri uri) {
    final fileName = uri.pathSegments.last;
    final migrationName = fileName.split(".").first;
    return int.parse(migrationName.split("_").first);
  }

  String? source;

  late final String originalName;

  late final String name;

  String? uri;

  int get versionNumber => versionNumberFromUri(Uri.parse(uri!));
}
