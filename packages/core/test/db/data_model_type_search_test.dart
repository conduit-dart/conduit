import 'package:conduit_core/conduit_core.dart';
import 'package:test/test.dart';

void main() {
  test(
      "Mixed in properties with @Serialize() are transient properties fromCurrentMirrorSystem",
      () {
    final dm = ManagedDataModel.fromCurrentMirrorSystem();
    final store = PostgreSQLPersistentStore.fromConnectionInfo(
      "dart_app",
      "dart",
      "localhost",
      5432,
      "my_database_name",
    );
    final ctx = ManagedContext(dm, store);
    final m = ctx.dataModel!.entityForType(Mixin);
    expect(m.attributes["serialized"]!.isTransient, true);

    final o = Mixin();
    o.serialized = "a";
    expect(o.serialized, "a");
    o.readFromMap({"serialized": "b"});
    expect(o.serialized, "b");
    expect(o.asMap(), {"serialized": "b"});
  });

  test(
      "Mixed in properties with @Serialize() are transient properties from list of types",
      () {
    final dm = ManagedDataModel([Mixin]);
    final store = PostgreSQLPersistentStore.fromConnectionInfo(
      "dart_app",
      "dart",
      "localhost",
      5432,
      "my_database_name",
    );
    final ctx = ManagedContext(dm, store);
    final m = ctx.dataModel!.entityForType(Mixin);
    expect(m.properties.length, 3);
    expect(m.attributes["serialized"]!.isTransient, true);
    expect(m.attributes["y"]!.isTransient, true);
    expect(m.attributes["x"], isNull);

    final o = Mixin();
    o.serialized = "a";
    expect(o.serialized, "a");
    o.readFromMap({"serialized": "b", "y": 1});
    expect(o.serialized, "b");
    expect(o.y, 1);
    expect(o.asMap(), {"serialized": "b", "y": 1});
  });
}

class Mixin extends ManagedObject<_Mixin> with MixinEntity implements _Mixin {
  @Serialize()
  int? y;
}

class _Mixin {
  @primaryKey
  int? id;
}

abstract class MixinEntity {
  @Serialize()
  String? serialized;

  int? x;
}
