import 'dart:async';

import 'package:conduit/conduit.dart';
import 'package:conduit/src/dev/helpers.dart';
import 'package:conduit_common/conduit_common.dart';
import 'package:conduit_common_test/conduit_common_test.dart';
import 'package:conduit_open_api/v3.dart';
import 'package:test/test.dart';

void main() {
  group("Documentation", () {
    Map<String, APIOperation>? collectionOperations;
    Map<String, APIOperation>? idOperations;
    setUpAll(() async {
      final context = APIDocumentContext(APIDocument()
        ..info = APIInfo("x", "1.0.0")
        ..paths = {}
        ..components = APIComponents());

      final dataModel = ManagedDataModel([TestModel]);
      final ctx = ManagedContext(dataModel, DefaultPersistentStore());
      final c = ManagedObjectController<TestModel>(ctx);
      c.restore(c.recycledState);
      c.didAddToChannel();
      collectionOperations = c.documentOperations(context, "/", APIPath());
      idOperations = c.documentOperations(
          context, "/", APIPath(parameters: [APIParameter.path("id")]));

      ctx.documentComponents(context);

      await context.finalize();
    });

    test("getObject", () {
      final op = idOperations!["get"]!;
      expect(op.id, "getTestModel");

      expect(op.responses!.length, 2);

      expect(op.responses!["404"], isNotNull);
      expect(
          op.responses!["200"]!.content!["application/json"]!.schema!
              .referenceURI!.path,
          "/components/schemas/TestModel");
    });

    test("createObject", () {
      final op = collectionOperations!["post"]!;
      expect(op.id, "createTestModel");

      expect(op.responses!.length, 3);

      expect(op.responses!["409"], isNotNull);
      expect(op.responses!["400"], isNotNull);
      expect(
          op.responses!["200"]!.content!["application/json"]!.schema!
              .referenceURI!.path,
          "/components/schemas/TestModel");
      expect(
          op.requestBody!.content!["application/json"]!.schema!.referenceURI!
              .path,
          "/components/schemas/TestModel");
    });

    test("updateObject", () {
      final op = idOperations!["put"]!;
      expect(op.id, "updateTestModel");

      expect(op.responses!.length, 4);

      expect(op.responses!["404"], isNotNull);
      expect(op.responses!["409"], isNotNull);
      expect(op.responses!["400"], isNotNull);
      expect(
          op.responses!["200"]!.content!["application/json"]!.schema!
              .referenceURI!.path,
          "/components/schemas/TestModel");
      expect(
          op.requestBody!.content!["application/json"]!.schema!.referenceURI!
              .path,
          "/components/schemas/TestModel");
    });

    test("deleteObject", () {
      final op = idOperations!["delete"]!;
      expect(op.id, "deleteTestModel");

      expect(op.responses!.length, 2);

      expect(op.responses!["404"], isNotNull);
      expect(op.responses!["200"]!.content, isNull);
    });

    test("getObjects", () {
      final op = collectionOperations!["get"]!;
      expect(op.id, "getTestModels");

      expect(op.responses!.length, 2);
      expect(op.parameters!.length, 6);
      expect(op.parameters!.every((p) => p!.isRequired == false), true);

      expect(op.responses!["400"], isNotNull);
      expect(op.responses!["200"]!.content!["application/json"]!.schema!.type,
          APIType.array);
      expect(
          op.responses!["200"]!.content!["application/json"]!.schema!.items!
              .referenceURI!.path,
          "/components/schemas/TestModel");
    });
  });
}

class TestChannel extends ApplicationChannel {
  ManagedContext? context;

  @override
  Future prepare() async {
    final dataModel = ManagedDataModel([TestModel]);
    final persistentStore = PostgresTestConfig().persistentStore;
    context = ManagedContext(dataModel, persistentStore());

    final targetSchema = Schema.fromDataModel(context!.dataModel!);
    final schemaBuilder = SchemaBuilder.toSchema(
        context!.persistentStore, targetSchema,
        isTemporary: true);

    final commands = schemaBuilder.commands;
    for (var cmd in commands) {
      await context!.persistentStore!.execute(cmd);
    }
  }

  @override
  Controller get entryPoint {
    final router = Router();
    router
        .route("/controller/[:id]")
        .link(() => ManagedObjectController<TestModel>(context!));

    router.route("/dynamic/[:id]").link(() => ManagedObjectController.forEntity(
        context!.dataModel!.entityForType(TestModel), context!));
    return router;
  }
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {}

class _TestModel {
  @primaryKey
  int? id;

  String? name;
  DateTime? createdAt;
}
