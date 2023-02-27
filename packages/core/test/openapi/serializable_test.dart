import 'dart:async';
import 'dart:io';

import 'package:conduit_common/conduit_common.dart';
import 'package:conduit_core/conduit_core.dart';
import 'package:conduit_open_api/v3.dart';
import 'package:test/test.dart';

void main() {
  late APIDocumentContext ctx;
  setUp(() {
    ctx = APIDocumentContext(
      APIDocument()
        ..info = APIInfo("x", "1.0.0")
        ..paths = {}
        ..components = APIComponents(),
    );
  });

  tearDown(() async {
    // Just in case the test didn't clear these
    await ctx.finalize();
  });

  test("Serializable contains properties for each declared field", () async {
    final doc = A().documentSchema(ctx);
    await ctx.finalize();

    expect(doc.properties!.length, 2);

    expect(doc.properties!["x"]!.type, APIType.integer);
    expect(doc.properties!["x"]!.title, "x");

    expect(doc.properties!["b"]!.type, APIType.object);
    expect(doc.properties!["b"]!.title, "b");
  });

  test("Nested serializable is documented", () async {
    final doc = A().documentSchema(ctx);
    expect(doc.properties!["b"]!.properties!.length, 1);
    expect(doc.properties!["b"]!.properties!["y"]!.type, APIType.string);
  });

  test(
      "If Serializable cannot be documented, it still allows doc generation but shows error in document",
      () async {
    final doc = FailsToDocument().documentSchema(ctx);
    await ctx.finalize();

    expect(doc.title, "FailsToDocument");
    expect(doc.description, contains("HttpServer"));
    expect(
      doc.additionalPropertyPolicy,
      APISchemaAdditionalPropertyPolicy.freeForm,
    );
  });

  test("Serializable can override static document method", () async {
    final doc = OverrideDocument().documentSchema(ctx);
    await ctx.finalize();

    expect(doc.properties!["k"], isNotNull);
  });

  test(
      "Can bind a Serializable implementor to a resource controller method and it auto-documents",
      () async {
    final c = BoundBodyController();
    c.didAddToChannel();
    c.restore(c.recycledState);

    c.documentComponents(ctx);
    final op = c.documentOperations(ctx, "/", APIPath.empty());
    await ctx.finalize();

    expect(
      op["post"]!
          .requestBody!
          .content!["application/json"]!
          .schema!
          .referenceURI!
          .pathSegments
          .last,
      "BoundBody",
    );
  });
}

class A extends Serializable {
  int? x;

  B? b;

  @override
  void readFromMap(Map<String, dynamic> requestBody) {}

  @override
  Map<String, dynamic> asMap() {
    return {};
  }
}

class B extends Serializable {
  String? y;

  @override
  void readFromMap(Map<String, dynamic> requestBody) {}

  @override
  Map<String, dynamic> asMap() {
    return {};
  }
}

class FailsToDocument extends Serializable {
  HttpServer? nonsenseProperty;

  @override
  Map<String, dynamic> asMap() => {};

  @override
  void readFromMap(Map<String, dynamic> requestBody) {}
}

class OverrideDocument extends Serializable {
  @override
  APISchemaObject documentSchema(APIDocumentContext context) {
    return APISchemaObject.object({"k": APISchemaObject.string()});
  }

  @override
  Map<String, dynamic> asMap() => {};

  @override
  void readFromMap(Map<String, dynamic> requestBody) {}
}

class BoundBody extends Serializable {
  int? x;

  @override
  Map<String, dynamic> asMap() => {};

  @override
  void readFromMap(Map<String, dynamic> requestBody) {}
}

class BoundBodyController extends ResourceController {
  @Operation.post()
  Future<Response> post(@Bind.body() BoundBody a) async {
    return Response.ok(null);
  }
}
