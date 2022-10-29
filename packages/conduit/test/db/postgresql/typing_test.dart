import 'package:conduit/conduit.dart';
import 'package:conduit/src/db/postgresql/postgresql_query.dart';
import 'package:conduit/src/db/postgresql/query_builder.dart';
import 'package:conduit_common_test/conduit_common_test.dart';
import 'package:test/test.dart';

void main() {
  ManagedContext? context;
  tearDown(() async {
    await context?.close();
    context = null;
  });

  test("Values get typed when used in predicate", () async {
    context = await PostgresTestConfig().contextWithModels([TestModel]);

    final q = Query<TestModel>(context!)
      ..where((o) => o.id).equalTo(1)
      ..where((o) => o.n).equalTo("a")
      ..where((o) => o.t).equalTo(DateTime.now())
      ..where((o) => o.l).equalTo(1)
      ..where((o) => o.b).equalTo(true)
      ..where((o) => o.d).equalTo(1.0)
      ..where((o) => o.doc).equalTo(Document({"k": "v"}));

    final builder = (q as PostgresQuery).createFetchBuilder();
    expect(builder.predicate!.format, contains("id:int8"));
    expect(builder.predicate!.format, contains("n:text"));
    expect(builder.predicate!.format, contains("t:timestamp"));
    expect(builder.predicate!.format, contains("l:int4"));
    expect(builder.predicate!.format, contains("b:boolean"));
    expect(builder.predicate!.format, contains("d:float8"));
    expect(builder.predicate!.format, contains("doc:jsonb"));
  });

  test("Values get typed when used as insertion values", () async {
    context = await PostgresTestConfig().contextWithModels([TestModel]);

    final q = Query<TestModel>(context!)
      ..values.id = 1
      ..values.n = "a"
      ..values.t = DateTime.now()
      ..values.l = 1
      ..values.b = true
      ..values.d = 1.0
      ..values.doc = Document({"k": "v"});

    final builder = PostgresQueryBuilder(q as PostgresQuery);
    final insertString = builder.sqlValuesToInsert;
    expect(insertString, contains("id:int8"));
    expect(insertString, contains("n:text"));
    expect(insertString, contains("t:timestamp"));
    expect(insertString, contains("l:int4"));
    expect(insertString, contains("b:boolean"));
    expect(insertString, contains("d:float8"));
    expect(insertString, contains("doc:jsonb"));
  });
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {}

class _TestModel {
  @primaryKey
  int? id;

  String? n;
  DateTime? t;
  int? l;
  bool? b;
  double? d;
  Document? doc;
}

class TypeRepo {
  Map<String, int>? mapOfInts;
  List<Map<String, int>>? listOfIntMaps;

  Map<int, String>? invalidMapKey;
  Map<String, Uri>? invalidMapValue;

  List<Uri>? invalidList;

  Uri? uri;
}
