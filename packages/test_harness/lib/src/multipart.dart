part of 'agent.dart';

/// Represents a file value in a `multipart/form-data` request body.
///
/// Pass instances of this class as values in the [Map] body of a
/// [TestRequest] when sending a request whose [TestRequest.contentType]
/// has the MIME type `multipart/form-data`. Non-file fields can be passed
/// alongside files as plain values (e.g. [String], [num], [bool], [List]).
///
/// Example:
///
///         await agent.post("/upload", body: {
///           "name": "alice",
///           "avatar": MultipartFormFile.fromBytes(
///             bytes,
///             filename: "a.png",
///             contentType: ContentType("image", "png"),
///           ),
///         }, contentType: ContentType.parse("multipart/form-data"));
class MultipartFormFile {
  /// Creates a multipart file part from raw [bytes].
  ///
  /// [filename] is the value of the `filename` parameter in the
  /// `Content-Disposition` header of the part. If omitted, no filename is
  /// emitted, which matches the behavior of an `<input type="file">` element
  /// when no file has been chosen.
  ///
  /// [contentType] is the value of the part's `Content-Type` header. When
  /// omitted, no `Content-Type` header is emitted for the part, and the
  /// server is free to interpret the bytes per RFC 7578.
  MultipartFormFile.fromBytes(
    List<int> bytes, {
    this.filename,
    this.contentType,
  }) : bytes = List<int>.unmodifiable(bytes);

  /// Creates a multipart file part from a [String].
  ///
  /// The string is encoded as UTF-8 unless [contentType] specifies a
  /// different charset. See [MultipartFormFile.fromBytes] for details on
  /// [filename] and [contentType].
  MultipartFormFile.fromString(
    String value, {
    this.filename,
    ContentType? contentType,
  })  : bytes = List<int>.unmodifiable(
            (contentType?.charset != null
                    ? Encoding.getByName(contentType!.charset) ?? utf8
                    : utf8)
                .encode(value)),
        contentType = contentType ??
            ContentType("text", "plain", charset: "utf-8");

  /// The raw bytes of this part's body.
  final List<int> bytes;

  /// The filename to send in the part's `Content-Disposition` header, or null.
  final String? filename;

  /// The `Content-Type` of this part, or null to omit the header.
  final ContentType? contentType;
}

/// Encodes a map of fields and files as a `multipart/form-data` body.
///
/// The returned bytes use [boundary] as the part separator. Per RFC 7578 the
/// boundary must not appear anywhere in the encoded part bodies; callers are
/// responsible for choosing one (see [_generateMultipartBoundary]).
///
/// Each entry in [fields] becomes one part:
///   - [MultipartFormFile] values are emitted with their `filename` /
///     `Content-Type` headers if set.
///   - [Iterable] values are flattened: one part is emitted per element,
///     all with the same field name (matching how HTML forms encode
///     repeated inputs).
///   - All other values are converted via `toString()` and sent as
///     `text/plain` parts with no filename.
List<int> _encodeMultipartFormData(
  Map<String, dynamic> fields,
  String boundary,
) {
  final builder = BytesBuilder(copy: false);
  final dashBoundary = utf8.encode("--$boundary\r\n");
  const crlf = [0x0d, 0x0a];

  void writePart(String name, dynamic value) {
    builder.add(dashBoundary);
    if (value is MultipartFormFile) {
      final disposition = StringBuffer(
        'content-disposition: form-data; name="${_escapeQuoted(name)}"',
      );
      if (value.filename != null) {
        disposition.write('; filename="${_escapeQuoted(value.filename!)}"');
      }
      disposition.write("\r\n");
      builder.add(utf8.encode(disposition.toString()));
      if (value.contentType != null) {
        builder
            .add(utf8.encode("content-type: ${value.contentType}\r\n"));
      }
      builder.add(crlf);
      builder.add(value.bytes);
      builder.add(crlf);
    } else {
      builder.add(
        utf8.encode(
          'content-disposition: form-data; name="${_escapeQuoted(name)}"\r\n\r\n',
        ),
      );
      builder.add(utf8.encode("$value"));
      builder.add(crlf);
    }
  }

  fields.forEach((name, value) {
    if (value is Iterable && value is! List<int>) {
      for (final inner in value) {
        writePart(name, inner);
      }
    } else {
      writePart(name, value);
    }
  });

  builder.add(utf8.encode("--$boundary--\r\n"));
  return builder.takeBytes();
}

/// Escapes the characters that are not allowed in a `Content-Disposition`
/// `name` or `filename` parameter (RFC 7578 § 4.2 references RFC 2388 which
/// allows percent-encoding of CR, LF and double quote).
String _escapeQuoted(String value) {
  return value
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\r', '%0D')
      .replaceAll('\n', '%0A');
}

/// Generates a random ASCII multipart boundary.
///
/// The shape `dart-conduit-<48 random hex chars>` keeps the boundary inside
/// the RFC 2046 `bcharsnospace` set and is unlikely to collide with any
/// real payload bytes.
String _generateMultipartBoundary([math.Random? random]) {
  final rng = random ?? math.Random.secure();
  final buffer = StringBuffer("dart-conduit-");
  for (var i = 0; i < 24; i++) {
    buffer.write(rng.nextInt(256).toRadixString(16).padLeft(2, "0"));
  }
  return buffer.toString();
}
